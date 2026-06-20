import Foundation
import OSLog
import Observation

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "history")


/// 播放历史。JSON 持久化、上限 300 条，供推荐去重与「最近播放」展示。
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

    /// 记录一次播放：已存在则次数 +1 并置顶，否则新增；超出 300 条裁掉最旧的。
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

    /// 清空全部播放历史。
    func clear() {
        entries = []
        save()
    }

    /// 从磁盘读历史，并按最近播放时间排序。
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

/// 单条播放历史：曲目 + 播放次数 + 最近播放时间。
struct PlaybackHistoryEntry: Identifiable, Codable, Equatable {
    var track: Track
    var playCount: Int
    var lastPlayedAt: Date

    var id: String { track.bvid }
    var bvid: String { track.bvid }
}
