import Foundation
import OSLog

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "recommend")

/// 已打分的候选。
private struct ScoredTrack {
    let track: Track
    let score: Int
}

/// 缓存的是「打分后的候选池」而非最终列表:网络开销 8 分钟付一次,
/// 但每次调用都在池子上重新加权随机抽样,所以「换一批」每次结果不同。
private actor RecommendationPoolCache {
    static let shared = RecommendationPoolCache()

    private var values: [String: (date: Date, pool: [ScoredTrack])] = [:]
    private let ttl: TimeInterval = 8 * 60

    func pool(for key: String) -> [ScoredTrack]? {
        guard let cached = values[key],
              Date().timeIntervalSince(cached.date) < ttl else {
            values[key] = nil
            return nil
        }
        return cached.pool
    }

    func store(_ pool: [ScoredTrack], for key: String) {
        values[key] = (Date(), pool)
        if values.count > 24, let oldest = values.min(by: { $0.value.date < $1.value.date })?.key {
            values.removeValue(forKey: oldest)
        }
    }
}

struct RecommendationSchedulingPolicy: Equatable {
    enum Trigger: Equatable {
        case initialHomeLoad
        case manualRefresh
    }

    var trigger: Trigger?
    var favoriteSeedLimit: Int
    var relatedPerFavoriteSeedLimit: Int
    var historySeedLimit: Int
    var cachedSeedLimit: Int
    var fallbackKeywordLimit: Int
    var scoringPriority: TaskPriority

    static func home(trigger: Trigger) -> RecommendationSchedulingPolicy {
        RecommendationSchedulingPolicy(
            trigger: trigger,
            favoriteSeedLimit: 5,
            relatedPerFavoriteSeedLimit: 10,
            historySeedLimit: 2,
            cachedSeedLimit: 2,
            fallbackKeywordLimit: 1,
            scoringPriority: .utility)
    }

    static func `default`(for mode: RecommendationEngine.Mode) -> RecommendationSchedulingPolicy {
        switch mode {
        case .home:
            return home(trigger: .manualRefresh)
        case .radio, .relatedPanel:
            return RecommendationSchedulingPolicy(
                trigger: nil,
                favoriteSeedLimit: 4,
                relatedPerFavoriteSeedLimit: 18,
                historySeedLimit: 1,
                cachedSeedLimit: 1,
                fallbackKeywordLimit: 2,
                scoringPriority: .userInitiated)
        }
    }
}

struct RecommendationEngine {
    enum Mode {
        case home
        case radio
        case relatedPanel
    }

    struct Context {
        var current: Track?
        var queue: [Track] = []
        var playlistTracks: [Track] = []
        var excludedKeys: Set<TrackKey> = []
    }

    private enum Source {
        case relatedCurrent
        case relatedHistory
        case favoriteSeed
        case playlistNeighbor
        case artistSearch
        case fallbackSearch

        var baseScore: Int {
            switch self {
            case .relatedCurrent: 65
            case .relatedHistory: 42
            case .favoriteSeed: 50
            case .playlistNeighbor: 70
            case .artistSearch: 46
            case .fallbackSearch: 30
            }
        }
    }

    private struct Candidate {
        let track: Track
        let source: Source
        let seed: Track?
    }

    private struct FavoriteFolderSnapshot {
        let id: Int
        let mediaCount: Int
    }

    private struct Snapshot {
        let historyTracks: [Track]
        let recentKeys: Set<TrackKey>
        let cachedTracks: [Track]
        let cachedKeys: Set<TrackKey>
        let favoriteBVIDs: Set<String>
        let favoriteFolder: FavoriteFolderSnapshot?
    }

    private let client = BiliClient()

    func recommendations(
        mode: Mode,
        context: Context,
        limit: Int = 24,
        policy: RecommendationSchedulingPolicy? = nil
    ) async -> [Track] {
        let schedulingPolicy = policy ?? RecommendationSchedulingPolicy.default(for: mode)
        let snapshot = await Self.makeSnapshot(mode: mode)
        let cacheKey = Self.cacheKey(mode: mode, context: context, snapshot: snapshot)

        // 电台要的是「最佳下一首」,需要实时最高分,不缓存、不随机。其余模式缓存候选池。
        if mode != .radio, let cached = await RecommendationPoolCache.shared.pool(for: cacheKey) {
            let usable = Self.usable(cached, mode: mode, snapshot: snapshot)
            let available = usable.filter { !Self.contains(context.excludedKeys, matching: $0.track) }
            // 池子还够抽 / 或首次加载(无排除集)就直接用;被排除集掏空了才重建。
            if available.count >= limit || (context.excludedKeys.isEmpty && !available.isEmpty) {
                return Self.select(from: usable, mode: mode, excluded: context.excludedKeys, limit: limit)
            }
        }

        let candidates = await buildCandidates(
            mode: mode,
            context: context,
            snapshot: snapshot,
            policy: schedulingPolicy)
        let pool = await Task.detached(priority: schedulingPolicy.scoringPriority) {
            Self.scoredPool(candidates, mode: mode, context: context, snapshot: snapshot)
        }.value
        if mode != .radio {
            await RecommendationPoolCache.shared.store(pool, for: cacheKey)
        }
        let usable = Self.usable(pool, mode: mode, snapshot: snapshot)
        return Self.select(from: usable, mode: mode, excluded: context.excludedKeys, limit: limit)
    }

    /// 发现类推荐(首页 / 播放器推荐面板)不展示已收藏的歌——你都收藏了不需要再推。
    /// 用实时收藏集过滤,所以即便命中的是几分钟前的缓存池,刚收藏的也会立刻消失。
    /// 电台连播保留收藏曲(否则电台永远不放你喜欢的歌)。
    private static func usable(_ pool: [ScoredTrack], mode: Mode, snapshot: Snapshot) -> [ScoredTrack] {
        let musicOnly = pool.filter { isDisplayableRecommendation($0.track, mode: mode) }
        guard mode != .radio else { return musicOnly }
        return musicOnly.filter { !snapshot.favoriteBVIDs.contains($0.track.bvid) }
    }

    private func buildCandidates(
        mode: Mode,
        context: Context,
        snapshot: Snapshot,
        policy: RecommendationSchedulingPolicy
    ) async -> [Candidate] {
        var candidates: [Candidate] = []

        switch mode {
        case .home:
            // 首页刷新必须快:旧逻辑会串行请求收藏/历史/缓存/当前歌曲十几个 related,
            // 真机上点击"换一批"会明显变慢。这里按质量分层短路,够用就停止补源。
            let favorites = await favoriteSeeds(
                maxCount: policy.favoriteSeedLimit,
                snapshot: snapshot,
                priority: policy.scoringPriority)
            candidates += await relatedCandidates(
                from: favorites,
                source: .favoriteSeed,
                perSeedLimit: policy.relatedPerFavoriteSeedLimit,
                priority: policy.scoringPriority)

            if candidates.count < 16, let current = context.current {
                candidates += await relatedCandidates(
                    from: [current],
                    source: .relatedCurrent,
                    perSeedLimit: 12,
                    priority: policy.scoringPriority)
            }
            if candidates.count < 16 {
                candidates += await relatedCandidates(
                    from: Array(snapshot.historyTracks.prefix(policy.historySeedLimit)),
                    source: .relatedHistory,
                    perSeedLimit: 8,
                    priority: policy.scoringPriority)
            }
            if candidates.count < 16 {
                candidates += await relatedCandidates(
                    from: Array(snapshot.cachedTracks.prefix(policy.cachedSeedLimit)),
                    source: .relatedHistory,
                    perSeedLimit: 8,
                    priority: policy.scoringPriority)
            }
            if candidates.isEmpty {
                candidates += await fallbackSearchCandidates(
                    keywordLimit: policy.fallbackKeywordLimit,
                    priority: policy.scoringPriority)
            }

        case .radio:
            if let current = context.current {
                candidates += await relatedCandidates(from: [current], source: .relatedCurrent)
                candidates += await artistSearchCandidates(for: current)
            }
            candidates += playlistNeighborCandidates(current: context.current, playlistTracks: context.playlistTracks, mode: mode)

        case .relatedPanel:
            if let current = context.current {
                candidates += await relatedCandidates(from: [current], source: .relatedCurrent, perSeedLimit: 24)
                if candidates.count < 10 {
                    candidates += await artistSearchCandidates(for: current)
                }
            }
            candidates += playlistNeighborCandidates(current: context.current, playlistTracks: context.playlistTracks, mode: mode)
        }

        return candidates
    }

    func nextRadioTrack(after current: Track?, excludedKeys: Set<TrackKey>) async -> Track? {
        guard let current else { return nil }
        let tracks = await recommendations(
            mode: .radio,
            context: Context(current: current, excludedKeys: excludedKeys),
            limit: 8)
        return tracks.first
    }

    private func relatedCandidates(
        from seeds: [Track],
        source: Source,
        perSeedLimit: Int = 18,
        priority: TaskPriority? = nil
    ) async -> [Candidate] {
        await withTaskGroup(of: [Candidate].self) { group in
            for seed in seeds {
                group.addTask(priority: priority) {
                    guard let items = try? await client.related(bvid: seed.bvid) else { return [] }
                    return items
                        .map(Track.init(related:))
                        .filter(MusicFilter.isMusic)
                        .prefix(perSeedLimit)
                        .map { Candidate(track: $0, source: source, seed: seed) }
                }
            }
            var candidates: [Candidate] = []
            for await batch in group {
                candidates.append(contentsOf: batch)
            }
            return candidates
        }
    }

    private func artistSearchCandidates(for track: Track) async -> [Candidate] {
        let terms = searchTerms(for: track)
        guard !terms.isEmpty else { return [] }
        return await withTaskGroup(of: [Candidate].self) { group in
            for term in terms.prefix(2) {
                group.addTask {
                    guard let items = try? await client.search(keyword: term, musicOnly: true) else { return [] }
                    return items
                        .map(Track.init(search:))
                        .filter { MusicFilter.isSearchResultMusic($0, query: term) }
                        .prefix(10)
                        .map { Candidate(track: $0, source: .artistSearch, seed: track) }
                }
            }
            var candidates: [Candidate] = []
            for await batch in group {
                candidates.append(contentsOf: batch)
            }
            return candidates
        }
    }

    private func fallbackSearchCandidates(keywordLimit: Int = 2, priority: TaskPriority? = nil) async -> [Candidate] {
        let keywords = [
            "华语音乐 MV",
            "日语歌 翻唱",
            "粤语歌 live",
            "动漫 OST 音乐",
        ].shuffled().prefix(keywordLimit)
        return await withTaskGroup(of: [Candidate].self) { group in
            for keyword in keywords {
                group.addTask(priority: priority) {
                    guard let items = try? await client.search(keyword: keyword, musicOnly: true) else { return [] }
                    return items
                        .map(Track.init(search:))
                        .filter { MusicFilter.isSearchResultMusic($0, query: keyword) }
                        .prefix(12)
                        .map { Candidate(track: $0, source: .fallbackSearch, seed: nil) }
                }
            }
            var candidates: [Candidate] = []
            for await batch in group {
                candidates.append(contentsOf: batch)
            }
            return candidates
        }
    }

    private func playlistNeighborCandidates(current: Track?, playlistTracks: [Track], mode: Mode) -> [Candidate] {
        guard let current, let index = playlistTracks.firstIndex(where: { $0.bvid == current.bvid }) else { return [] }
        let bounds = max(0, index - 3)..<min(playlistTracks.count, index + 4)
        return playlistTracks[bounds]
            .filter { $0.bvid != current.bvid }
            .filter { Self.isDisplayableRecommendation($0, mode: mode) }
            .map { Candidate(track: $0, source: .playlistNeighbor, seed: current) }
    }

    private func favoriteSeeds(maxCount: Int = 4, snapshot: Snapshot, priority: TaskPriority? = nil) async -> [Track] {
        guard let folder = snapshot.favoriteFolder else { return [] }
        let pageCount = max(1, Int(ceil(Double(folder.mediaCount) / 40.0)))
        var pageNums: Set<Int> = [Int.random(in: 1...pageCount)]
        if pageCount > 1 {
            while pageNums.count < 2 { pageNums.insert(Int.random(in: 1...pageCount)) }
        }
        var allItems: [Track] = []
        await withTaskGroup(of: [Track].self) { group in
            for pageNum in pageNums {
                group.addTask(priority: priority) {
                    guard let result = try? await self.client.favItems(folderId: folder.id, page: pageNum) else { return [] }
                    return (result.medias ?? [])
                        .filter { $0.attr == 0 }
                        .map { Track(bvid: $0.bvid, title: $0.title, artist: $0.upper.name,
                                     coverURL: URL(string: $0.cover), duration: $0.duration) }
                        .filter(MusicFilter.isStrictMusic)
                }
            }
            for await tracks in group { allItems.append(contentsOf: tracks) }
        }
        return Array(allItems.shuffled().prefix(maxCount))
    }

    @MainActor
    private static func makeSnapshot(mode: Mode) async -> Snapshot {
        await CacheStore.shared.loadIfNeeded()
        await PlaybackHistoryStore.shared.loadIfNeeded()
        // 发现类推荐要排除已收藏的歌,先补全收藏全集(缓存 10 分钟,绝大多数调用是命中)。
        if mode != .radio {
            await FavoriteManager.shared.syncAllFavoriteIDs()
        }
        let historyEntries = PlaybackHistoryStore.shared.entries
        let cacheEntries = CacheStore.shared.entries
        let favoriteBVIDs = FavoriteManager.shared.favoriteBVIDs
        let favoriteFolder = await favoriteFolderSnapshot(mode: mode)
        return Snapshot(
            historyTracks: historyEntries.map(\.track),
            recentKeys: Set(historyEntries.prefix(mode == .radio ? 20 : 8).map(\.key)),
            cachedTracks: cacheEntries.map(\.track),
            cachedKeys: Set(cacheEntries.map(\.key)),
            favoriteBVIDs: favoriteBVIDs,
            favoriteFolder: favoriteFolder)
    }

    @MainActor
    private static func favoriteFolderSnapshot(mode: Mode) async -> FavoriteFolderSnapshot? {
        guard mode == .home, CookieStore.isLoggedIn else { return nil }
        let manager = FavoriteManager.shared
        if manager.folders.isEmpty {
            await manager.loadFolders()
        }
        let chosenId = UserDefaults.standard.integer(forKey: "recommendFolderId")
        let folder = manager.folders.first(where: { $0.id == chosenId && $0.media_count > 0 })
            ?? manager.folders.first(where: { $0.title.contains("默认") && $0.media_count > 0 })
            ?? manager.folders.first(where: { $0.media_count > 0 })
        guard let folder else { return nil }
        return FavoriteFolderSnapshot(id: folder.id, mediaCount: folder.media_count)
    }

    /// 打分 + 按 key 去重(保留最高分),得到一个降序候选池。注意:这里**不**做
    /// excludedKeys 过滤——排除集是「本次会话已展示」的动态信息,要在抽样阶段实时过滤,
    /// 不能烘进缓存的池子里,否则会把池子越缩越小。
    private static func scoredPool(_ candidates: [Candidate], mode: Mode, context: Context, snapshot: Snapshot) -> [ScoredTrack] {
        let current = context.current

        let scored = candidates
            .filter { isDisplayableRecommendation($0.track, mode: mode) }
            .filter { candidate in
                guard let current else { return true }
                return !candidate.track.key.matches(current)
            }
            .map { candidate in
                (candidate.track, score(candidate, current: current, queue: context.queue, mode: mode, snapshot: snapshot))
            }
            .filter { $0.1 > 0 }

        var best: [TrackKey: ScoredTrack] = [:]
        for item in scored {
            let key = best.keys.first { $0.matches(item.0) } ?? item.0.key
            if let previous = best[key], previous.score >= item.1 { continue }
            best[key] = ScoredTrack(track: item.0, score: item.1)
        }

        return best.values.sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.track.title < rhs.track.title }
            return lhs.score > rhs.score
        }
    }

    static func isDisplayableRecommendation(_ track: Track, mode: Mode) -> Bool {
        switch mode {
        case .home, .relatedPanel:
            MusicFilter.isSearchResultMusic(track)
        case .radio:
            MusicFilter.isMusic(track)
        }
    }

    /// 从候选池里选出本次要展示的曲目。
    /// 电台:要最佳下一首,实时排除后取最高分。其余:加权随机抽样,高分更可能被选中
    /// 但每次都不同,从根本上解决「换一批总是那几首」。
    private static func select(from pool: [ScoredTrack], mode: Mode, excluded: Set<TrackKey>, limit: Int) -> [Track] {
        let available = pool.filter { !Self.contains(excluded, matching: $0.track) }
        if mode == .radio {
            return Array(available.prefix(limit).map(\.track))
        }
        return weightedSample(available, count: limit).map(\.track)
    }

    /// 加权随机抽样(无放回,Efraimidis–Spirakis):key = U^(1/weight),取 key 最大的若干个。
    /// weight 用分数,分数越高越可能靠前,但仍有随机性,保证每次刷新结果轮换。
    private static func weightedSample(_ items: [ScoredTrack], count: Int) -> [ScoredTrack] {
        items
            .map { item -> (ScoredTrack, Double) in
                let weight = Double(max(1, item.score))
                let u = Double.random(in: 1e-9 ..< 1)
                return (item, pow(u, 1.0 / weight))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(count)
            .map(\.0)
    }

    private static func score(_ candidate: Candidate, current: Track?, queue: [Track], mode: Mode, snapshot: Snapshot) -> Int {
        let track = candidate.track
        let text = normalized(track.title + " " + track.artist)
        var score = candidate.source.baseScore

        if MusicFilter.isStrictMusic(track) {
            score += 18
        } else if MusicFilter.isMusic(track) {
            score += 8
        } else {
            score -= 60
        }

        switch track.duration {
        case 120...420: score += 18
        case 60..<120, 421...600: score += 5
        default: score -= 18
        }

        if let current {
            let currentArtist = normalized(current.artist)
            let currentTitle = normalized(current.title)
            if !currentArtist.isEmpty, text.contains(currentArtist) {
                score += mode == .radio ? 35 : 18
            }
            for token in importantTokens(currentTitle).prefix(3) where text.contains(token) {
                score += mode == .radio ? 8 : 4
            }
        }

        if snapshot.favoriteBVIDs.contains(track.bvid) {
            score += 12
        }
        if contains(snapshot.cachedKeys, matching: track) {
            score += 6
        }
        if contains(snapshot.recentKeys, matching: track) {
            score -= mode == .radio ? 80 : 24
        }
        if queue.contains(where: { $0.key.matches(track) }) {
            score -= 18
        }
        if hasBadRecommendationHint(text) {
            score -= 48
        }
        score += Int.random(in: -10...10)
        return score
    }

    private static func contains(_ keys: Set<TrackKey>, matching track: Track) -> Bool {
        keys.contains(track.key) || keys.contains { $0.matches(track) }
    }

    private static func cacheKey(mode: Mode, context: Context, snapshot: Snapshot) -> String {
        let current = context.current?.key.description ?? "none"
        let playlist = context.playlistTracks.prefix(4).map(\.key.description).joined(separator: ",")
        let folder = snapshot.favoriteFolder?.id ?? 0
        switch mode {
        case .home:
            return "home:\(folder):\(current)"
        case .relatedPanel:
            return "related:\(current):\(playlist)"
        case .radio:
            return "radio:\(current):\(playlist)"
        }
    }

    private func searchTerms(for track: Track) -> [String] {
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = parsedTitle(track.title)
        var terms: [String] = []
        if !artist.isEmpty {
            terms.append("\(artist) 音乐")
        }
        if let parsed {
            terms.append(parsed)
        }
        return Array(Set(terms)).filter { !$0.isEmpty }
    }

    private func parsedTitle(_ title: String) -> String? {
        if let start = title.firstIndex(of: "《"),
           let end = title[start...].firstIndex(of: "》"),
           start < end {
            return String(title[title.index(after: start)..<end])
        }
        if let dash = title.range(of: " - ") {
            return String(title[..<dash.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func hasBadRecommendationHint(_ text: String) -> Bool {
        [
            "解说", "评论", "reaction", "clip", "切片", "教程", "中字", "字幕组",
            "耐久", "作业用", "排行", "top", "合集剪辑", "鬼畜", "mad", "amv",
        ].contains { text.contains($0) }
    }

    private static func importantTokens(_ text: String) -> [String] {
        normalized(text)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 && !["official", "music", "video", "mv", "live", "cover"].contains($0) }
    }

    private static func normalized(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\p{P}\p{S}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
