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
    private(set) var contentRevision = 0
    private let fileURL: URL
    private(set) var isLoaded = false
    private var loadTask: Task<[PlaybackHistoryEntry], Never>?
    private var loadStartVersion = 0
    private var mutationVersion = 0
    private var discardPendingLoad = false

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playback-history.json")
    }

    /// 记录一次播放：已存在则次数 +1 并置顶，否则新增；超出 300 条裁掉最旧的。
    func record(_ track: Track) {
        mutationVersion += 1
        var updated = entries
        if let index = updated.firstIndex(where: { $0.key.matches(track) }) {
            updated[index].playCount += 1
            updated[index].lastPlayedAt = Date()
            updated[index].track = track
            let entry = updated.remove(at: index)
            updated.insert(entry, at: 0)
        } else {
            updated.insert(PlaybackHistoryEntry(track: track, playCount: 1, lastPlayedAt: Date()), at: 0)
        }
        if updated.count > 300 {
            updated.removeLast(updated.count - 300)
        }
        setEntries(updated)
        save()
    }

    /// 清空全部播放历史。
    func clear() {
        mutationVersion += 1
        if loadTask != nil, !isLoaded {
            discardPendingLoad = true
        }
        setEntries([])
        save(immediate: true)
    }

    /// 从磁盘异步读历史，并按最近播放时间排序。
    func loadIfNeeded() async {
        guard !isLoaded else { return }
        if let loadTask {
            let loaded = await loadTask.value
            applyLoadedEntries(loaded, startedAt: loadStartVersion)
            return
        }

        let fileURL = fileURL
        loadStartVersion = mutationVersion
        let task = Task<[PlaybackHistoryEntry], Never>.detached(priority: .utility) {
            let start = CFAbsoluteTimeGetCurrent()
            guard let data = try? Data(contentsOf: fileURL),
                  let decoded = try? JSONDecoder().decode([PlaybackHistoryEntry].self, from: data) else {
                return []
            }
            let entries = decoded.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            log.debug("load() \(elapsed, format: .fixed(precision: 1))ms entries=\(entries.count)")
            return entries
        }
        loadTask = task
        let loaded = await task.value
        applyLoadedEntries(loaded, startedAt: loadStartVersion)
    }

    private var saveTask: Task<Void, Never>?

    /// 防抖写盘:record() 每播一首都会调,连续切歌时只在停下来后写一次,
    /// encode 也挪到后台,不再每次都在主线程全量序列化 300 条历史。
    func flush() async {
        saveTask?.cancel()
        await write(entries)
        saveTask = nil
    }

    private func save(immediate: Bool = false) {
        let snapshot = entries
        saveTask?.cancel()
        if immediate {
            saveTask = Task { [weak self] in
                await self?.write(snapshot)
                self?.saveTask = nil
            }
            return
        }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.write(snapshot)
            self?.saveTask = nil
        }
    }

    private func write(_ snapshot: [PlaybackHistoryEntry]) async {
        let url = fileURL
        await Task.detached(priority: .background) {
            let start = CFAbsoluteTimeGetCurrent()
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            log.debug("save() \(elapsed, format: .fixed(precision: 1))ms entries=\(snapshot.count)")
        }.value
    }

    private func applyLoadedEntries(_ loaded: [PlaybackHistoryEntry], startedAt version: Int) {
        guard !isLoaded else { return }
        let changedWhileLoading = mutationVersion != version
        if discardPendingLoad {
            isLoaded = true
        } else if changedWhileLoading {
            let merged = Self.merge(current: entries, loaded: loaded)
            let didChange = merged != entries
            setEntries(merged)
            if didChange {
                save()
            }
            isLoaded = true
        } else {
            setEntries(loaded)
            isLoaded = true
        }
        loadTask = nil
        discardPendingLoad = false
    }

    private func setEntries(_ newEntries: [PlaybackHistoryEntry]) {
        guard entries != newEntries else { return }
        entries = newEntries
        contentRevision += 1
    }

    private static func merge(
        current: [PlaybackHistoryEntry],
        loaded: [PlaybackHistoryEntry]
    ) -> [PlaybackHistoryEntry] {
        var result = current
        for entry in loaded {
            if let index = result.firstIndex(where: { $0.key.matches(entry.track) }) {
                result[index].playCount += entry.playCount
                if entry.lastPlayedAt > result[index].lastPlayedAt {
                    result[index].lastPlayedAt = entry.lastPlayedAt
                    result[index].track = entry.track
                }
            } else {
                result.append(entry)
            }
        }
        return Array(result.sorted { $0.lastPlayedAt > $1.lastPlayedAt }.prefix(300))
    }
}

/// 单条播放历史：曲目 + 播放次数 + 最近播放时间。
struct PlaybackHistoryEntry: Identifiable, Codable, Equatable {
    var track: Track
    var playCount: Int
    var lastPlayedAt: Date

    var id: String { track.id }
    var key: TrackKey { track.key }
    var bvid: String { track.bvid }
}
