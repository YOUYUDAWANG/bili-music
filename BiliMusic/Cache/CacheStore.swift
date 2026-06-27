import Foundation
import OSLog
import Observation

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "cache")


struct CachedEntry: Codable, Identifiable, Equatable {
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

    var key: TrackKey { TrackKey(bvid: bvid, cid: cid) }
    var id: String { key.description }

    var track: Track {
        Track(bvid: bvid, cid: cid, title: title, artist: artist,
              coverURL: coverURL.flatMap(URL.init(string:)), duration: duration)
    }
}

/// 已缓存音频的索引。音频文件在 Documents/audio/,索引是 JSON 文件,单表场景不上 SwiftData。
@Observable
@MainActor
final class CacheStore {
    static let shared = CacheStore()
    /// Search 的本地缓存投影要覆盖“最近 6 条 + 缓存 6 条”的合并窗口,
    /// 所以比最终渲染出来的缓存行数更宽,避免 recent 排除后第 7-12 条缓存被漏掉。
    private static let searchLocalContentProjectionLimit = 12

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

    private var indexURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cache_index.json")
    }

    private init() {
        try? FileManager.default.createDirectory(at: Self.audioDir, withIntermediateDirectories: true)
        rebuildIndex()   // didSet 在 init 内不触发,手动建一次
    }

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        if let loadTask {
            let loaded = await loadTask.value
            applyLoadedEntries(loaded, startedAt: loadStartVersion)
            return
        }

        let indexURL = indexURL
        let audioDir = Self.audioDir
        loadStartVersion = mutationVersion
        let task = Task<[CachedEntry], Never>.detached(priority: .utility) {
            let start = CFAbsoluteTimeGetCurrent()
            try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
            guard let data = try? Data(contentsOf: indexURL),
                  let saved = try? JSONDecoder().decode([CachedEntry].self, from: data) else {
                return []
            }
            let entries = saved.filter {
                FileManager.default.fileExists(atPath: audioDir.appendingPathComponent($0.fileName).path)
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
        if let cid = track.cid, let exact = index[TrackKey(bvid: track.bvid, cid: cid)] {
            return exact
        }
        guard !ambiguousBVIDs.contains(track.bvid) else { return nil }
        return uniqueBVIDIndex[track.bvid]
    }

    func entry(key: TrackKey) -> CachedEntry? {
        if let exact = index[key] {
            return exact
        }
        guard key.cid == nil else { return nil }
        guard !ambiguousBVIDs.contains(key.bvid) else { return nil }
        return uniqueBVIDIndex[key.bvid]
    }

    /// 兼容旧调用:只在该 BV 唯一缓存时返回,避免多分P误命中。
    func entry(bvid: String) -> CachedEntry? {
        entry(key: TrackKey(bvid: bvid, cid: nil))
    }

    func localURL(for track: Track) -> URL? {
        entry(for: track).map { Self.audioDir.appendingPathComponent($0.fileName) }
    }

    func localURL(bvid: String) -> URL? {
        entry(bvid: bvid).map { Self.audioDir.appendingPathComponent($0.fileName) }
    }

    func add(_ entry: CachedEntry) {
        mutationVersion += 1
        var updated = entries
        updated.removeAll { $0.key == entry.key }
        updated.insert(entry, at: 0)
        setEntries(updated)
        save(immediate: true)
    }

    func remove(_ entry: CachedEntry) {
        mutationVersion += 1
        if loadTask != nil, !isLoaded {
            removedDuringLoad.insert(entry.key)
        }
        try? FileManager.default.removeItem(at: Self.audioDir.appendingPathComponent(entry.fileName))
        var updated = entries
        updated.removeAll { $0.key == entry.key }
        setEntries(updated)
        save(immediate: true)
    }

    func removeAll() {
        mutationVersion += 1
        if loadTask != nil, !isLoaded {
            clearedDuringLoad = true
        }
        entries.forEach {
            try? FileManager.default.removeItem(at: Self.audioDir.appendingPathComponent($0.fileName))
        }
        setEntries([])
        save(immediate: true)
    }

    var totalSize: Int64 {
        entries.reduce(0) { $0 + $1.fileSize }
    }

    private var saveTask: Task<Void, Never>?

    /// 防抖写盘:短时间内多次 add/remove 只在末尾写一次,encode 也挪到后台,
    /// 不再每次改动都在主线程全量序列化整张索引。
    func flush() async {
        saveTask?.cancel()
        await write(entries)
        saveTask = nil
    }

    private func save(immediate: Bool = false) {
        let snapshot = entries
        if immediate {
            saveTask?.cancel()
            saveTask = Task { [weak self] in
                await self?.write(snapshot)
                self?.saveTask = nil
            }
            return
        }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.write(snapshot)
            self?.saveTask = nil
        }
    }

    private func write(_ snapshot: [CachedEntry]) async {
        let url = indexURL
        await Task.detached(priority: .background) {
            let start = CFAbsoluteTimeGetCurrent()
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            log.debug("save() \(elapsed, format: .fixed(precision: 1))ms entries=\(snapshot.count)")
        }.value
    }

    private func applyLoadedEntries(_ loaded: [CachedEntry], startedAt version: Int) {
        guard !isLoaded else { return }
        let changedWhileLoading = mutationVersion != version
        if clearedDuringLoad {
            isLoaded = true
        } else if changedWhileLoading {
            let currentKeys = Set(entries.map(\.key))
            let retainedLoaded = loaded
                .filter { !removedDuringLoad.contains($0.key) }
                .filter { !currentKeys.contains($0.key) }
            let updated = entries + retainedLoaded
            let didChange = updated != entries
            setEntries(updated)
            if didChange {
                save(immediate: true)
            }
            isLoaded = true
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
}
