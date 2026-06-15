import Foundation
import OSLog
import Observation

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "history")


@Observable
@MainActor
final class PlaybackHistoryStore {
    static let shared = PlaybackHistoryStore()

    private(set) var entries: [PlaybackHistoryEntry] = []
    private let fileURL: URL

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playback-history.json")
        load()
    }

    func record(_ track: Track) {
        if let index = entries.firstIndex(where: { $0.bvid == track.bvid }) {
            entries[index].playCount += 1
            entries[index].lastPlayedAt = Date()
            entries[index].track = track
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
        } else {
            entries.insert(PlaybackHistoryEntry(track: track, playCount: 1, lastPlayedAt: Date()), at: 0)
        }
        if entries.count > 300 {
            entries.removeLast(entries.count - 300)
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([PlaybackHistoryEntry].self, from: data) else { return }
        entries = decoded.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    private var saveTask: Task<Void, Never>?

    /// 防抖写盘:record() 每播一首都会调,连续切歌时只在停下来后写一次,
    /// encode 也挪到后台,不再每次都在主线程全量序列化 300 条历史。
    private func save() {
        let snapshot = entries
        let url = fileURL
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

struct PlaybackHistoryEntry: Identifiable, Codable, Equatable {
    var track: Track
    var playCount: Int
    var lastPlayedAt: Date

    var id: String { track.bvid }
    var bvid: String { track.bvid }
}
