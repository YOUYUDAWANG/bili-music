import Foundation
import OSLog

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "playback-queue")

/// 冷启动恢复用的播放队列快照。只持久化曲目元数据，不保存会过期的流 URL。
struct PersistedPlaybackQueue: Codable, Equatable, Sendable {
    var version: Int
    var queue: [Track]
    var queueIndex: Int
    var queueMode: PlayerEngine.QueueMode
    var resumePosition: Double
    var savedAt: Date
}

enum PlaybackQueueWindow {
    static let maxCount = 200

    /// 队列过长时保留当前曲附近的窗口，避免 `prefix` 把正在播的歌裁掉。
    static func capped(queue: [Track], index: Int, limit: Int = maxCount) -> (queue: [Track], index: Int) {
        guard !queue.isEmpty else { return ([], 0) }
        let safeIndex = min(max(index, 0), queue.count - 1)
        if queue.count <= limit {
            return (queue, safeIndex)
        }
        let leading = min(safeIndex, 50)
        var start = safeIndex - leading
        var end = min(queue.count, start + limit)
        start = max(0, end - limit)
        end = min(queue.count, start + limit)
        return (Array(queue[start..<end]), safeIndex - start)
    }
}

@MainActor
final class PlaybackQueueStore {
    static let shared = PlaybackQueueStore()

    private(set) var snapshot: PersistedPlaybackQueue?
    private let fileURL: URL
    private let fileWriter = VersionedAtomicFileWriter()
    private var isLoaded = false
    private var writeRevision = 0
    private var saveTask: Task<Void, Never>?

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playback-queue.json")
    }

#if DEBUG
    init(fileURLForTesting: URL) {
        fileURL = fileURLForTesting
    }
#endif

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        let url = fileURL
        snapshot = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(PersistedPlaybackQueue.self, from: data),
                  decoded.version >= 1,
                  !decoded.queue.isEmpty,
                  decoded.queue.indices.contains(decoded.queueIndex) else {
                return nil
            }
            return decoded
        }.value
        isLoaded = true
    }

    func replace(_ snapshot: PersistedPlaybackQueue?) {
        self.snapshot = snapshot
        isLoaded = true
        scheduleSave()
    }

    func flush() async {
        await loadIfNeeded()
        saveTask?.cancel()
        let revision = nextRevision()
        do {
            try await write(snapshot, revision: revision)
        } catch {
            log.error("flush failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleSave() {
        let snapshot = snapshot
        saveTask?.cancel()
        let revision = nextRevision()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            do {
                try await self.write(snapshot, revision: revision)
            } catch {
                log.error("save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func write(_ snapshot: PersistedPlaybackQueue?, revision: Int) async throws {
        let url = fileURL
        if let snapshot {
            let data = try await Task.detached(priority: .background) {
                try JSONEncoder().encode(snapshot)
            }.value
            try await fileWriter.write(data, revision: revision, to: url)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func nextRevision() -> Int {
        writeRevision += 1
        return writeRevision
    }
}
