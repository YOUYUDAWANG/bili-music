import Foundation

/// 记住最近展示或选中过的推荐 BV，避免 related 图里那批固定热门歌反复出现。
actor RecommendationMemory {
    static let shared = RecommendationMemory()

    static let ttl: TimeInterval = 6 * 60 * 60
    static let maxEntries = 400

    private let fileURL: URL
    private var entries: [String: Date] = [:]
    private var feedIndex = 1
    private var isLoaded = false
    private var saveTask: Task<Void, Never>?

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("recommendation-memory.json")
    }

#if DEBUG
    init(fileURLForTesting: URL) {
        fileURL = fileURLForTesting
    }
#endif

    func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            entries = snapshot.entries
            feedIndex = max(1, snapshot.feedIndex)
        } else if let legacy = try? JSONDecoder().decode([String: Date].self, from: data) {
            entries = legacy
        }
        pruneLocked()
    }

    func recentBVIDs(now: Date = Date()) -> Set<String> {
        loadIfNeeded()
        pruneLocked(now: now)
        return Set(entries.keys)
    }

    func recentKeys(now: Date = Date()) -> Set<TrackKey> {
        Set(recentBVIDs(now: now).map { TrackKey(bvid: $0, cid: nil) })
    }

    func record(_ bvids: [String], at date: Date = Date()) {
        loadIfNeeded()
        for bvid in bvids where !bvid.isEmpty {
            entries[bvid] = date
        }
        pruneLocked(now: date)
        scheduleSave()
    }

    func nextFeedIndices(count: Int) -> [Int] {
        loadIfNeeded()
        let pageCount = max(count, 0)
        let start = max(1, feedIndex)
        feedIndex = start + pageCount
        scheduleSave()
        return Array(start..<feedIndex)
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        saveLocked()
    }

    private func pruneLocked(now: Date = Date()) {
        entries = entries.filter { now.timeIntervalSince($0.value) < Self.ttl }
        if entries.count > Self.maxEntries {
            let trimmed = entries.sorted { $0.value > $1.value }.prefix(Self.maxEntries)
            entries = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.key, $0.value) })
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveLocked()
        }
    }

    private func saveLocked() {
        let snapshot = Snapshot(entries: entries, feedIndex: feedIndex)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private struct Snapshot: Codable {
        var entries: [String: Date]
        var feedIndex: Int
    }
}
