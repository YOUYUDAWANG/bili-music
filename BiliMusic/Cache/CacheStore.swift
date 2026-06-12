import Foundation
import Observation

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

    private(set) var entries: [CachedEntry] = []

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
    }

    func entry(bvid: String) -> CachedEntry? {
        entries.first { $0.bvid == bvid }
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

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
