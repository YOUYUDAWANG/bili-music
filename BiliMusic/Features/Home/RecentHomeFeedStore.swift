import Foundation

/// 首页「最近推荐过」的曲目记录,带时效。让首页短时间内不再重复推荐同一首,
/// 且跨 app 重启、跨切 tab 都生效(HomeView 的 @State shownKeys 做不到)。
/// 存的是 bvid → 最近一次展示时间,JSON 落盘,防抖写。
@MainActor
final class RecentHomeFeedStore {
    static let shared = RecentHomeFeedStore()

    private var shown: [String: Date] = [:]
    private var isLoaded = false
    private var loadTask: Task<[String: Date], Never>?
    private var loadStartVersion = 0
    private var mutationVersion = 0
    private var saveTask: Task<Void, Never>?
    private let fileWriter = VersionedAtomicFileWriter()
    private var writeRevision = 0

    /// 多久之内不重复推荐同一首。
    private let ttl: TimeInterval = 3 * 3600
    private let maxEntries = 400

    private let fileURL: URL

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("home-recent.json")
    }

    private func loadIfNeeded() async {
        guard !isLoaded else { return }
        if let loadTask {
            let loaded = await loadTask.value
            applyLoaded(loaded, startedAt: loadStartVersion)
            return
        }

        let fileURL = fileURL
        loadStartVersion = mutationVersion
        let task = Task<[String: Date], Never>.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: fileURL),
                  let decoded = try? JSONDecoder().decode([String: Date].self, from: data) else {
                return [:]
            }
            return decoded
        }
        loadTask = task
        let loaded = await task.value
        applyLoaded(loaded, startedAt: loadStartVersion)
    }

    /// TTL 内仍算「最近推荐过」的 key 集合,用作首页推荐的排除集。
    /// cid 置 nil → 按 bvid 整体匹配(TrackKey.matches 把 nil 当通配)。
    func recentKeys() async -> Set<TrackKey> {
        await loadIfNeeded()
        let cutoff = Date().addingTimeInterval(-ttl)
        return Set(shown.filter { $0.value >= cutoff }.keys.map { TrackKey(bvid: $0, cid: nil) })
    }

    /// 记录本次首页展示过的曲目。
    func record(_ bvids: [String]) async {
        await loadIfNeeded()
        mutationVersion += 1
        let now = Date()
        for bvid in bvids { shown[bvid] = now }
        prune()
        save()
    }

    func flush() async {
        guard isLoaded || mutationVersion > 0 else { return }
        saveTask?.cancel()
        let revision = nextWriteRevision()
        do {
            try await write(shown, revision: revision)
        } catch {
            NSLog("Recent home feed flush failed: %@", error.localizedDescription)
        }
        finishSave(revision: revision)
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-ttl)
        shown = shown.filter { $0.value >= cutoff }
        if shown.count > maxEntries {
            let keep = shown.sorted { $0.value > $1.value }.prefix(maxEntries)
            shown = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    private func save() {
        let snapshot = shown
        saveTask?.cancel()
        let revision = nextWriteRevision()
        saveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            do {
                try await self.write(snapshot, revision: revision)
            } catch {
                NSLog("Recent home feed save failed: %@", error.localizedDescription)
            }
            self.finishSave(revision: revision)
        }
    }

    private func write(_ snapshot: [String: Date], revision: Int) async throws {
        let data = try await Task.detached(priority: .background) {
            try JSONEncoder().encode(snapshot)
        }.value
        try await fileWriter.write(data, revision: revision, to: fileURL)
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

    private func applyLoaded(_ loaded: [String: Date], startedAt version: Int) {
        guard !isLoaded else { return }
        if mutationVersion == version {
            shown = loaded
        } else {
            for (bvid, date) in loaded where date > (shown[bvid] ?? .distantPast) {
                shown[bvid] = date
            }
        }
        prune()
        isLoaded = true
        loadTask = nil
    }
}
