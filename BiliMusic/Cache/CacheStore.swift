import Foundation
import OSLog
import Observation

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "cache")

actor VersionedAtomicFileWriter {
    private var latestRevision = 0

    func write(_ data: Data, revision: Int, to url: URL) throws {
        guard revision >= latestRevision else { return }
        latestRevision = revision
        try data.write(to: url, options: .atomic)
    }
}

struct CachedEntry: Codable, Identifiable, Equatable, Sendable {
    let bvid: String
    let cid: Int
    let title: String
    let artist: String
    let coverURL: String?
    let duration: Int
    let fileName: String
    let fileSize: Int64
    let downloadedAt: Date
    let quality: Int?    // 音质 id,旧索引没有该字段
    var accessedAt: Date?

    var key: TrackKey { TrackKey(bvid: bvid, cid: cid) }
    var id: String { key.description }
    var lastAccessedAt: Date { accessedAt ?? downloadedAt }

    var track: Track {
        Track(bvid: bvid, cid: cid, title: title, artist: artist,
              coverURL: coverURL.flatMap(URL.init(string:)), duration: duration)
    }

    init(
        bvid: String,
        cid: Int,
        title: String,
        artist: String,
        coverURL: String?,
        duration: Int,
        fileName: String,
        fileSize: Int64,
        downloadedAt: Date,
        quality: Int?,
        accessedAt: Date? = nil
    ) {
        self.bvid = bvid
        self.cid = cid
        self.title = title
        self.artist = artist
        self.coverURL = coverURL
        self.duration = duration
        self.fileName = fileName
        self.fileSize = fileSize
        self.downloadedAt = downloadedAt
        self.quality = quality
        self.accessedAt = accessedAt ?? downloadedAt
    }
}

/// 已缓存音频的索引。音频文件在 Documents/audio/,索引是 JSON 文件,单表场景不上 SwiftData。
@Observable
@MainActor
final class CacheStore {
    static let shared = CacheStore()
    /// 自动缓存开启后限制本地音频数量；超出后按访问时间淘汰最旧的。
    static let maxEntryCount = 120
    /// Search 的本地缓存投影要覆盖“最近 6 条 + 缓存 6 条”的合并窗口,
    /// 所以比最终渲染出来的缓存行数更宽,避免 recent 排除后第 7-12 条缓存被漏掉。
    private static let searchLocalContentProjectionLimit = 12
    private var playbackProtectedKey: TrackKey?
    private var downloadProtectionCounts: [TrackKey: Int] = [:]

    private(set) var entries: [CachedEntry] = [] {
        didSet { rebuildIndex() }
    }
    private(set) var contentRevision = 0

    // TrackKey → entry 的 O(1) 索引。B 站同一个 BV 可以有多个 cid/分P,
    // 缓存身份必须精确到 cid,否则分P歌曲会互相覆盖。
    private var index: [TrackKey: CachedEntry] = [:]
    private var uniqueBVIDIndex: [String: CachedEntry] = [:]
    private var ambiguousBVIDs: Set<String> = []
    private(set) var isLoaded = false
    private var loadTask: Task<[CachedEntry], Never>?
    private var loadStartVersion = 0
    private var mutationVersion = 0
    private var removedDuringLoad: Set<TrackKey> = []
    private var clearedDuringLoad = false
    private let fileWriter = VersionedAtomicFileWriter()
    private var writeRevision = 0

    private func rebuildIndex() {
        index = Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let grouped = Dictionary(grouping: entries, by: \.bvid)
        uniqueBVIDIndex = grouped.compactMapValues { $0.count == 1 ? $0[0] : nil }
        ambiguousBVIDs = Set(grouped.filter { $0.value.count > 1 }.map(\.key))
    }

    nonisolated static var audioDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio", isDirectory: true)
    }

    // 实例持有的路径:生产环境等同 Documents 索引 + Self.audioDir;测试可注入隔离目录。
    private let indexURL: URL
    private let audioDir: URL

    private init() {
        indexURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cache_index.json")
        audioDir = Self.audioDir
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        rebuildIndex()   // didSet 在 init 内不触发,手动建一次
    }

#if DEBUG
    /// 测试注入:索引文件与音频目录都指向隔离路径,与真实 Documents 完全隔离。
    init(indexURLForTesting: URL, audioDirForTesting: URL) {
        indexURL = indexURLForTesting
        audioDir = audioDirForTesting
        try? FileManager.default.createDirectory(at: audioDirForTesting, withIntermediateDirectories: true)
        rebuildIndex()
    }
#endif

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        if let loadTask {
            let loaded = await loadTask.value
            applyLoadedEntries(loaded, startedAt: loadStartVersion)
            return
        }

        let indexURL = indexURL
        let audioDir = audioDir
        loadStartVersion = mutationVersion
        let task = Task<[CachedEntry], Never>.detached(priority: .utility) {
            let start = CFAbsoluteTimeGetCurrent()
            let fileManager = FileManager.default
            try? fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true)
            let saved: [CachedEntry]
            if let data = try? Data(contentsOf: indexURL) {
                guard let decoded = try? JSONDecoder().decode([CachedEntry].self, from: data) else {
                    // 索引存在但解码失败:跳过孤儿清理,避免把有效音频误当孤儿删掉
                    return []
                }
                saved = decoded
            } else {
                saved = []
            }
            let entries = saved.filter {
                fileManager.fileExists(atPath: audioDir.appendingPathComponent($0.fileName).path)
            }
            // 孤儿清理:删除 audioDir 里不在索引中的文件(下载落盘与写索引之间被杀等场景遗留)。
            // 下载方 download()/addPersisting() 都会先 await loadIfNeeded() 才动 audioDir,
            // 下载中的临时文件也在系统 tmp 而非 audioDir,所以此刻清理不会误删进行中的下载。
            let indexedFileNames = Set(saved.map(\.fileName))
            if let files = try? fileManager.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil) {
                for file in files where !indexedFileNames.contains(file.lastPathComponent) {
                    try? fileManager.removeItem(at: file)
                }
            }
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            log.debug("load() \(elapsed, format: .fixed(precision: 1))ms entries=\(entries.count)")
            return entries
        }
        loadTask = task
        let loaded = await task.value
        applyLoadedEntries(loaded, startedAt: loadStartVersion)
    }

    func entry(for track: Track) -> CachedEntry? {
        if let cid = track.cid {
            return index[TrackKey(bvid: track.bvid, cid: cid)]
        }
        guard !ambiguousBVIDs.contains(track.bvid) else { return nil }
        guard let candidate = uniqueBVIDIndex[track.bvid],
              Self.titlesLikelyMatch(track.title, candidate.title) else {
            return nil
        }
        return candidate
    }

    private static func titlesLikelyMatch(_ lhs: String, _ rhs: String) -> Bool {
        func normalized(_ value: String) -> String {
            value
                .replacingOccurrences(of: "<em class=\"keyword\">", with: "")
                .replacingOccurrences(of: "</em>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }
        let left = normalized(lhs)
        let right = normalized(rhs)
        return !left.isEmpty && left == right
    }

    func addPersisting(_ entry: CachedEntry) async throws {
        await loadIfNeeded()
        saveTask?.cancel()
        mutationVersion += 1
        let previousEntries = entries
        var updated = entries
        updated.removeAll { $0.key == entry.key }
        var stored = entry
        if stored.accessedAt == nil {
            stored.accessedAt = stored.downloadedAt
        }
        updated.insert(stored, at: 0)
        let evicted = Self.evictOverflow(
            &updated,
            protecting: protectedKeys.union([stored.key]),
            limit: Self.maxEntryCount)
        setEntries(updated)
        let revision = nextWriteRevision()
        do {
            try await write(updated, revision: revision)
            finishSave(revision: revision)
            removeAudioFiles(for: evicted)
        } catch {
            mutationVersion += 1
            setEntries(previousEntries)
            let rollbackRevision = nextWriteRevision()
            try? await write(previousEntries, revision: rollbackRevision)
            finishSave(revision: rollbackRevision)
            throw error
        }
    }

    func touch(_ key: TrackKey) {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return }
        var updated = entries
        var entry = updated.remove(at: index)
        entry.accessedAt = Date()
        updated.insert(entry, at: 0)
        setEntries(updated)
        guard isLoaded else { return }
        save()
    }

    func setPlaybackProtectedKey(_ key: TrackKey?) {
        playbackProtectedKey = key
    }

    func beginDownloadProtection(_ key: TrackKey) {
        downloadProtectionCounts[key, default: 0] += 1
    }

    func endDownloadProtection(_ key: TrackKey) {
        if let count = downloadProtectionCounts[key], count > 1 {
            downloadProtectionCounts[key] = count - 1
        } else {
            downloadProtectionCounts[key] = nil
        }
    }

    func enforceRetentionLimit() async {
        await loadIfNeeded()
        var updated = entries
        let evicted = Self.evictOverflow(
            &updated,
            protecting: protectedKeys,
            limit: Self.maxEntryCount)
        guard !evicted.isEmpty else { return }
        mutationVersion += 1
        setEntries(updated)
        saveTask?.cancel()
        let revision = nextWriteRevision()
        do {
            try await write(updated, revision: revision)
            finishSave(revision: revision)
            removeAudioFiles(for: evicted)
        } catch {
            log.error("retention save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

#if DEBUG
    func addForTesting(_ entry: CachedEntry) {
        mutationVersion += 1
        var updated = entries
        updated.removeAll { $0.key == entry.key }
        updated.insert(entry, at: 0)
        _ = Self.evictOverflow(
            &updated,
            protecting: protectedKeys.union([entry.key]),
            limit: Self.maxEntryCount)
        setEntries(updated)
    }
#endif

    func remove(_ entry: CachedEntry) {
        mutationVersion += 1
        if loadTask != nil, !isLoaded {
            removedDuringLoad.insert(entry.key)
        }
        try? FileManager.default.removeItem(at: audioDir.appendingPathComponent(entry.fileName))
        var updated = entries
        updated.removeAll { $0.key == entry.key }
        setEntries(updated)
        // load 未完成时不写盘,避免把不完整的索引落盘;applyLoadedEntries 合并后统一补写
        guard isLoaded else { return }
        save()   // 逐条删除走防抖;scene phase 切后台的 flush() 兜底
    }

    func removeAll() {
        mutationVersion += 1
        if loadTask != nil, !isLoaded {
            clearedDuringLoad = true
        }
        entries.forEach {
            try? FileManager.default.removeItem(at: audioDir.appendingPathComponent($0.fileName))
        }
        setEntries([])
        // load 未完成时推迟写盘,由 applyLoadedEntries 的 clearedDuringLoad 分支补上
        guard isLoaded else { return }
        save(immediate: true)
    }

    var totalSize: Int64 {
        entries.reduce(0) { $0 + $1.fileSize }
    }

    private var saveTask: Task<Void, Never>?

    /// 立即写盘:scene phase 切后台等时机兜底,把防抖中的改动落盘。
    func flush() async throws {
        guard isLoaded || mutationVersion > 0 else { return }
        if !isLoaded {
            // 先等索引加载合并完成,避免把不完整的索引落盘
            await loadIfNeeded()
        }
        saveTask?.cancel()
        let revision = nextWriteRevision()
        try await write(entries, revision: revision)
        finishSave(revision: revision)
    }

    /// 写盘。immediate=false 走 1s 防抖(连续逐条 remove 只在末尾写一次),
    /// removeAll / load 合并等关键路径用 immediate=true 立即写。encode 在后台执行。
    private func save(immediate: Bool = false) {
        let snapshot = entries
        saveTask?.cancel()
        let revision = nextWriteRevision()
        saveTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            do {
                try await self.write(snapshot, revision: revision)
            } catch {
                log.error("save failed: \(error.localizedDescription, privacy: .public)")
            }
            self.finishSave(revision: revision)
        }
    }

    private func write(_ snapshot: [CachedEntry], revision: Int) async throws {
        let url = indexURL
        let data = try await Task.detached(priority: .background) {
            let start = CFAbsoluteTimeGetCurrent()
            let data = try JSONEncoder().encode(snapshot)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            log.debug("encode() \(elapsed, format: .fixed(precision: 1))ms entries=\(snapshot.count)")
            return data
        }.value
        try await fileWriter.write(data, revision: revision, to: url)
    }

    private func nextWriteRevision() -> Int {
        writeRevision += 1
        return writeRevision
    }

    private func finishSave(revision: Int) {
        if writeRevision == revision {
            saveTask = nil
        }
    }

    private func applyLoadedEntries(_ loaded: [CachedEntry], startedAt version: Int) {
        guard !isLoaded else { return }
        let changedWhileLoading = mutationVersion != version
        if clearedDuringLoad {
            isLoaded = true
            // removeAll 在 load 期间推迟的写盘在此补上
            save(immediate: true)
        } else if changedWhileLoading {
            let currentKeys = Set(entries.map(\.key))
            let retainedLoaded = loaded
                .filter { !removedDuringLoad.contains($0.key) }
                .filter { !currentKeys.contains($0.key) }
            let updated = entries + retainedLoaded
            setEntries(updated)
            isLoaded = true
            // load 期间被推迟的写盘,连同 merge 结果一并在此落盘
            save(immediate: true)
        } else {
            setEntries(loaded)
            isLoaded = true
        }
        loadTask = nil
        removedDuringLoad = []
        clearedDuringLoad = false
    }

    private func setEntries(_ newEntries: [CachedEntry]) {
        guard entries != newEntries else { return }
        let previousProjection = searchVisibleTracks(from: entries)
        let nextProjection = searchVisibleTracks(from: newEntries)
        entries = newEntries
        if previousProjection != nextProjection {
            contentRevision += 1
        }
    }

    private func searchVisibleTracks(from entries: [CachedEntry]) -> [Track] {
        Array(entries.prefix(Self.searchLocalContentProjectionLimit).map(\.track))
    }

    private var protectedKeys: Set<TrackKey> {
        var keys = Set(downloadProtectionCounts.keys)
        if let playbackProtectedKey {
            keys.insert(playbackProtectedKey)
        }
        return keys
    }

    private func removeAudioFiles(for entries: [CachedEntry]) {
        for entry in entries {
            try? FileManager.default.removeItem(at: audioDir.appendingPathComponent(entry.fileName))
        }
    }

    static func evictOverflow(
        _ entries: inout [CachedEntry],
        protecting: Set<TrackKey>,
        limit: Int
    ) -> [CachedEntry] {
        var evicted: [CachedEntry] = []
        while entries.count > limit {
            guard let index = entries.indices.reversed().first(where: { !protecting.contains(entries[$0].key) }) else {
                break
            }
            evicted.append(entries.remove(at: index))
        }
        return evicted
    }
}
