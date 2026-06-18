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

    private(set) var entries: [CachedEntry] = [] {
        didSet { rebuildIndex() }
    }

    // TrackKey → entry 的 O(1) 索引。B 站同一个 BV 可以有多个 cid/分P,
    // 缓存身份必须精确到 cid,否则分P歌曲会互相覆盖。
    private var index: [TrackKey: CachedEntry] = [:]

    private func rebuildIndex() {
        index = Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
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
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([CachedEntry].self, from: data) {
            // 索引和实际文件可能不一致(比如 iCloud 清理),只保留文件还在的
            entries = saved.filter {
                FileManager.default.fileExists(atPath: Self.audioDir.appendingPathComponent($0.fileName).path)
            }
        }
        rebuildIndex()   // didSet 在 init 内不触发,手动建一次
    }

    func entry(for track: Track) -> CachedEntry? {
        if let cid = track.cid, let exact = index[TrackKey(bvid: track.bvid, cid: cid)] {
            return exact
        }
        let matches = entries.filter { $0.bvid == track.bvid }
        if matches.count == 1 {
            return matches[0]
        }
        return nil
    }

    func entry(key: TrackKey) -> CachedEntry? {
        if let exact = index[key] {
            return exact
        }
        guard key.cid == nil else { return nil }
        let matches = entries.filter { $0.bvid == key.bvid }
        return matches.count == 1 ? matches[0] : nil
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
        entries.removeAll { $0.key == entry.key }
        entries.insert(entry, at: 0)
        save(immediate: true)
    }

    func remove(_ entry: CachedEntry) {
        try? FileManager.default.removeItem(at: Self.audioDir.appendingPathComponent(entry.fileName))
        entries.removeAll { $0.key == entry.key }
        save(immediate: true)
    }

    func removeAll() {
        entries.forEach {
            try? FileManager.default.removeItem(at: Self.audioDir.appendingPathComponent($0.fileName))
        }
        entries = []
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
}
