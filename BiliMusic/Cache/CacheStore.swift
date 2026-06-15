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

    var id: String { bvid }

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

    // bvid → entry 的 O(1) 索引。entry(bvid:) 在 body 重渲染时频繁调用,
    // 缓存上百首后线性扫描会拖慢列表/播放页。
    private var index: [String: CachedEntry] = [:]

    private func rebuildIndex() {
        index = Dictionary(entries.map { ($0.bvid, $0) }, uniquingKeysWith: { first, _ in first })
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

    func entry(bvid: String) -> CachedEntry? {
        index[bvid]
    }

    func localURL(bvid: String) -> URL? {
        entry(bvid: bvid).map { Self.audioDir.appendingPathComponent($0.fileName) }
    }

    func add(_ entry: CachedEntry) {
        entries.removeAll { $0.bvid == entry.bvid }
        entries.insert(entry, at: 0)
        save()
    }

    func remove(_ entry: CachedEntry) {
        try? FileManager.default.removeItem(at: Self.audioDir.appendingPathComponent(entry.fileName))
        entries.removeAll { $0.bvid == entry.bvid }
        save()
    }

    func removeAll() {
        entries.forEach {
            try? FileManager.default.removeItem(at: Self.audioDir.appendingPathComponent($0.fileName))
        }
        entries = []
        save()
    }

    var totalSize: Int64 {
        entries.reduce(0) { $0 + $1.fileSize }
    }

    private var saveTask: Task<Void, Never>?

    /// 防抖写盘:短时间内多次 add/remove 只在末尾写一次,encode 也挪到后台,
    /// 不再每次改动都在主线程全量序列化整张索引。
    private func save() {
        let snapshot = entries
        let url = indexURL
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .background) {
                let start = CFAbsoluteTimeGetCurrent()
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                try? data.write(to: url, options: .atomic)
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                log.debug("save() \(elapsed, format: .fixed(precision: 1))ms entries=\(snapshot.count)")
            }.value
            self?.saveTask = nil
        }
    }
}
