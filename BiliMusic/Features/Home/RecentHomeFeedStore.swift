import Foundation

/// 首页「最近推荐过」的曲目记录,带时效。让首页短时间内不再重复推荐同一首,
/// 且跨 app 重启、跨切 tab 都生效(HomeView 的 @State shownKeys 做不到)。
/// 存的是 bvid → 最近一次展示时间,JSON 落盘,防抖写。
@MainActor
final class RecentHomeFeedStore {
    static let shared = RecentHomeFeedStore()

    private var shown: [String: Date] = [:]
    private var loaded = false
    private var saveTask: Task<Void, Never>?

    /// 多久之内不重复推荐同一首。
    private let ttl: TimeInterval = 3 * 3600
    private let maxEntries = 400

    private let fileURL: URL

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("home-recent.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            shown = decoded
        }
        prune()
    }

    /// TTL 内仍算「最近推荐过」的 key 集合,用作首页推荐的排除集。
    /// cid 置 nil → 按 bvid 整体匹配(TrackKey.matches 把 nil 当通配)。
    func recentKeys() -> Set<TrackKey> {
        loadIfNeeded()
        let cutoff = Date().addingTimeInterval(-ttl)
        return Set(shown.filter { $0.value >= cutoff }.keys.map { TrackKey(bvid: $0, cid: nil) })
    }

    /// 记录本次首页展示过的曲目。
    func record(_ bvids: [String]) {
        loadIfNeeded()
        let now = Date()
        for bvid in bvids { shown[bvid] = now }
        prune()
        save()
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
        let url = fileURL
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .background) {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                try? data.write(to: url, options: .atomic)
            }.value
            self?.saveTask = nil
        }
    }
}
