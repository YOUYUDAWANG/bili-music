import Foundation
import OSLog

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "recommend")

private actor RecommendationResultCache {
    static let shared = RecommendationResultCache()

    private var values: [String: (date: Date, tracks: [Track])] = [:]
    private let ttl: TimeInterval = 8 * 60

    func tracks(for key: String) -> [Track]? {
        guard let cached = values[key],
              Date().timeIntervalSince(cached.date) < ttl else {
            values[key] = nil
            return nil
        }
        return cached.tracks
    }

    func store(_ tracks: [Track], for key: String) {
        values[key] = (Date(), tracks)
        if values.count > 24 {
            values.removeValue(forKey: values.keys.sorted().first ?? key)
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
        case homeFeed          // B 站官方推荐流
        case upWorks           // 同 UP 主更多作品 (通过收藏夹 UP 主空间获取)
        case historyArtist     // 播放历史中提取艺人名搜索

        var baseScore: Int {
            switch self {
            case .relatedCurrent: 65
            case .relatedHistory: 42
            case .favoriteSeed: 50
            case .playlistNeighbor: 70
            case .artistSearch: 46
            case .fallbackSearch: 30
            case .homeFeed: 48
            case .upWorks: 55
            case .historyArtist: 44
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

    func recommendations(mode: Mode, context: Context, limit: Int = 24, offset: Int = 0) async -> [Track] {
        let snapshot = await Self.makeSnapshot(mode: mode)
        let cacheKey = Self.cacheKey(mode: mode, context: context, snapshot: snapshot)

        // 缓存策略:
        // - 翻页(offset>0):直接从缓存池取,按 offset 切片
        // - 初始加载(offset=0,无排除):直接取缓存池的前 limit 首
        // - 换一批(offset=0,有排除):跳过缓存,重建池子(否则越换越少)
        if let cached = await RecommendationResultCache.shared.tracks(for: cacheKey) {
            if offset > 0 || context.excludedKeys.isEmpty {
                let available = cached.dropFirst(offset)
                if !available.isEmpty {
                    return Array(available.prefix(limit))
                }
                // 翻页到底了,返回空(没有更多了)
                if offset > 0 { return [] }
            }
        }

        var candidates: [Candidate] = []

        switch mode {
        case .home:
            // 关键修复:不用阈值短路,改用并行 all-sources 各自贡献。
            // 旧逻辑「第一个源够了就跳过所有后面的」→ 候选全来自同一源 → 大量重复 → dedup 只剩个位数。
            // 现在 8 个源并发跑,每源贡献固定量 → diversity 大幅提升。
            let favorites = await favoriteSeeds(maxCount: 6, snapshot: snapshot)
            await withTaskGroup(of: [Candidate].self) { group in
                // 1. 收藏夹 related（最多产,优先放,但限制 perSeed）
                group.addTask {
                    await relatedCandidates(from: favorites, source: .favoriteSeed, perSeedLimit: 10)
                }
                // 2. B 站官方推荐流（外部新鲜血液）
                group.addTask {
                    await homeFeedCandidates(count: 2, limit: 10)
                }
                // 3. UP 主作品（同风格深度扩展）
                group.addTask {
                    await upWorksCandidates(from: favorites, maxCandidates: 20)
                }
                // 4. 播放历史艺人搜索（更多同艺人作品）
                group.addTask {
                    await historyArtistCandidates(snapshot: snapshot, maxCandidates: 10)
                }
                // 5. 当前曲 related
                if let current = context.current {
                    group.addTask {
                        await relatedCandidates(from: [current], source: .relatedCurrent, perSeedLimit: 10)
                    }
                }
                // 6. 播放历史 related
                if !snapshot.historyTracks.isEmpty {
                    group.addTask {
                        await relatedCandidates(from: Array(snapshot.historyTracks.prefix(2)), source: .relatedHistory, perSeedLimit: 8)
                    }
                }
                // 7. 缓存曲目 related
                if !snapshot.cachedTracks.isEmpty {
                    group.addTask {
                        await relatedCandidates(from: Array(snapshot.cachedTracks.prefix(2)), source: .relatedHistory, perSeedLimit: 8)
                    }
                }
                // 8. 兜底搜索（最兜底,keywords 少一些但覆盖面广）
                group.addTask {
                    await fallbackSearchCandidates(keywordLimit: 3)
                }

                for await batch in group {
                    candidates.append(contentsOf: batch)
                }
            }

        case .radio:
            if let current = context.current {
                candidates += await relatedCandidates(from: [current], source: .relatedCurrent)
                candidates += await artistSearchCandidates(for: current)
            }
            candidates += playlistNeighborCandidates(current: context.current, playlistTracks: context.playlistTracks)

        case .relatedPanel:
            if let current = context.current {
                candidates += await relatedCandidates(from: [current], source: .relatedCurrent, perSeedLimit: 14)
                if candidates.count < 10 {
                    candidates += await artistSearchCandidates(for: current)
                }
            }
            candidates += playlistNeighborCandidates(current: context.current, playlistTracks: context.playlistTracks)
            if candidates.count < 12 {
                candidates += await relatedCandidates(from: Array(snapshot.historyTracks.prefix(1)), source: .relatedHistory, perSeedLimit: 8)
            }
        }

        // 首页用 150 首的大缓存池,支持后续翻页;其他模式按需取 limit 首
        let poolSize = mode == .home ? 150 : limit
        let pool = await Task.detached(priority: .userInitiated) {
            Self.ranked(candidates, mode: mode, context: context, snapshot: snapshot, limit: poolSize)
        }.value
        if mode != .radio {
            await RecommendationResultCache.shared.store(pool, for: cacheKey)
        }

        return Array(pool.dropFirst(offset).prefix(limit))
    }

    func nextRadioTrack(after current: Track?, excludedKeys: Set<TrackKey>) async -> Track? {
        guard let current else { return nil }
        let tracks = await recommendations(
            mode: .radio,
            context: Context(current: current, excludedKeys: excludedKeys),
            limit: 8)
        return tracks.first
    }

    private func relatedCandidates(from seeds: [Track], source: Source, perSeedLimit: Int = 18) async -> [Candidate] {
        await withTaskGroup(of: [Candidate].self) { group in
            for seed in seeds {
                group.addTask {
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

    /// B 站官方推荐流作为数据源。用多个随机 fresh_idx 并行获取不同内容,
    /// 引入收藏夹之外的新歌,从根本上突破「一两百首循环」。
    private func homeFeedCandidates(count: Int = 1, limit: Int = 15) async -> [Candidate] {
        let indices = (0..<count).map { _ in Int.random(in: 0...10) }
        return await withTaskGroup(of: [Candidate].self) { group in
            for idx in indices {
                group.addTask {
                    guard let items = try? await self.client.homeFeed(freshIdx: idx) else { return [] }
                    return items
                        .filter { $0.bvid != nil && $0.duration != nil }
                        .map { item in
                            Track(bvid: item.bvid!, title: item.title ?? "", artist: item.owner?.name ?? "",
                                  coverURL: item.pic.flatMap(URL.init(string:)), duration: item.duration!)
                        }
                        .filter(MusicFilter.isMusic)
                        .prefix(limit)
                        .map { Candidate(track: $0, source: .homeFeed, seed: nil) }
                }
            }
            var all: [Candidate] = []
            for await batch in group { all.append(contentsOf: batch) }
            return all
        }
    }

    /// 从收藏夹种子的 UP 主空间获取更多作品,深度扩展同风格内容。
    /// 取最多 2 个 UP 主,每个取前 2 个合集/系列,大幅拓宽同风格曲库。
    private func upWorksCandidates(from seeds: [Track], maxCandidates: Int = 30) async -> [Candidate] {
        let seedsToCheck = seeds.prefix(3)
        return await withTaskGroup(of: [Candidate].self) { group in
            for seed in seedsToCheck {
                group.addTask {
                    guard let info = try? await self.client.videoInfo(bvid: seed.bvid) else { return [] }
                    let mid = info.owner.mid
                    guard let playlists = try? await self.client.upPlaylists(mid: mid) else { return [] }
                    var candidates: [Candidate] = []
                    for playlist in playlists.prefix(2) {
                        guard let page = try? await self.client.upPlaylistItems(mid: mid, playlist: playlist, page: 1) else { continue }
                        for item in page.items.prefix(15) {
                            let track = Track(playlist: item, artist: info.owner.name, ownerMid: mid)
                            guard MusicFilter.isMusic(track) else { continue }
                            candidates.append(Candidate(track: track, source: .upWorks, seed: seed))
                        }
                    }
                    return candidates
                }
            }
            var all: [Candidate] = []
            for await batch in group { all.append(contentsOf: batch) }
            return Array(all.prefix(maxCandidates))
        }
    }

    /// 从播放历史提取艺人名做搜索,发现更多同艺人但未曾相遇的作品。
    /// 取最多 3 个艺人,每人搜 1 页,覆盖更多同风格内容。
    private func historyArtistCandidates(snapshot: Snapshot, maxCandidates: Int = 20) async -> [Candidate] {
        let artists = Set(snapshot.historyTracks.map(\.artist).filter { !$0.isEmpty })
        let selected = Array(artists).shuffled().prefix(3)
        return await withTaskGroup(of: [Candidate].self) { group in
            for artist in selected {
                group.addTask {
                    guard let items = try? await self.client.search(keyword: "\(artist) 音乐", musicOnly: true) else { return [] }
                    return items
                        .map(Track.init(search:))
                        .filter { MusicFilter.isSearchResultMusic($0, query: artist) }
                        .prefix(10)
                        .map { Candidate(track: $0, source: .historyArtist, seed: nil) }
                }
            }
            var all: [Candidate] = []
            for await batch in group { all.append(contentsOf: batch) }
            return Array(all.prefix(maxCandidates))
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

    /// 兜底搜索：32 个关键词按 8 个风格分组 + 翻页取 page 2,大幅提升兜底多样性。
    private func fallbackSearchCandidates(keywordLimit: Int = 2) async -> [Candidate] {
        let keywordGroups: [[String]] = [
            ["华语音乐 MV", "华语经典 老歌", "周杰伦 合集", "林俊杰 音乐"],
            ["日语歌 翻唱", "日语流行 歌单", "YOASOBI 音楽", "米津玄师 MV"],
            ["粤语歌 live", "Beyond 经典", "陈奕迅 演唱会", "粤语金曲 串烧"],
            ["动漫 OST 音乐", "ACG 歌曲 合集", "动画 主题曲", "游戏音乐 BGM"],
            ["欧美流行 音乐", "K-pop 随机播放", "kpop 韩语歌", "JPOP 日音"],
            ["纯音乐 钢琴", "吉他 指弹 翻弹", "国风 古风 音乐", "说唱 rap 中文"],
            ["乐队 livehouse 现场", "电音 EDM 混音", "R&B 灵魂乐 歌单", "民谣 吉他 弹唱"],
            ["citypop 日系", "蒸汽波 vaporwave", "lo-fi 自习 音乐", "爵士 jazz 即兴"],
        ]
        let selectedGroups = keywordGroups.shuffled().prefix(keywordLimit)
        let keywords = selectedGroups.flatMap { $0 }.shuffled().prefix(keywordLimit * 2)
        return await withTaskGroup(of: [Candidate].self) { group in
            for keyword in keywords {
                // 每关键词取 page 1 + page 2,扩大搜索覆盖面
                for page in 1...2 {
                    group.addTask {
                        guard let items = try? await self.client.search(keyword: keyword, page: page, musicOnly: true) else { return [] }
                        return items
                            .map(Track.init(search:))
                            .filter { MusicFilter.isSearchResultMusic($0, query: keyword) }
                            .prefix(8)
                            .map { Candidate(track: $0, source: .fallbackSearch, seed: nil) }
                    }
                }
            }
            var candidates: [Candidate] = []
            for await batch in group {
                candidates.append(contentsOf: batch)
            }
            return candidates
        }
    }

    private func playlistNeighborCandidates(current: Track?, playlistTracks: [Track]) -> [Candidate] {
        guard let current, let index = playlistTracks.firstIndex(where: { $0.bvid == current.bvid }) else { return [] }
        let bounds = max(0, index - 3)..<min(playlistTracks.count, index + 4)
        return playlistTracks[bounds]
            .filter { $0.bvid != current.bvid }
            .map { Candidate(track: $0, source: .playlistNeighbor, seed: current) }
    }

    /// 全量扫描收藏夹,构建更大的种子池。最多取 2 个收藏夹 × 12 页(约 960 首),
    /// 分批并行拉取。从全量池中随机抽 maxCount 个种子 → 每个种子调 related → 候选大幅拓宽。
    private func favoriteSeeds(maxCount: Int = 4, snapshot: Snapshot) async -> [Track] {
        // 确定要扫描的收藏夹(主推荐夹 + 次选夹)
        let folderIDs = await resolveFavoriteFolderIDs()
        guard !folderIDs.isEmpty else { return [] }
        var allItems: [Track] = []
        for folderId in folderIDs {
            guard let totalPages = await totalPages(for: folderId) else { continue }
            // 分批并行:每批 4 页,避免瞬间太多请求
            for batchStart in stride(from: 1, through: totalPages, by: 4) {
                let batchEnd = min(batchStart + 3, totalPages)
                await withTaskGroup(of: [Track].self) { group in
                    for pageNum in batchStart...batchEnd {
                        group.addTask {
                            guard let result = try? await self.client.favItems(folderId: folderId, page: pageNum) else { return [] }
                            return (result.medias ?? [])
                                .filter { $0.attr == 0 }
                                .map { Track(bvid: $0.bvid, title: $0.title, artist: $0.upper.name,
                                             coverURL: URL(string: $0.cover), duration: $0.duration) }
                                .filter(MusicFilter.isStrictMusic)
                        }
                    }
                    for await tracks in group { allItems.append(contentsOf: tracks) }
                }
            }
        }
        return Array(allItems.shuffled().prefix(maxCount))
    }

    /// 解析收藏夹列表:主推荐夹(用户指定/默认) + 另一个有内容的文件夹
    @MainActor
    private func resolveFavoriteFolderIDs() async -> [Int] {
        guard CookieStore.isLoggedIn else { return [] }
        let manager = FavoriteManager.shared
        if manager.folders.isEmpty { await manager.loadFolders() }
        let chosenId = UserDefaults.standard.integer(forKey: "recommendFolderId")
        let folders = manager.folders.filter { $0.media_count > 0 }
        // 按 media_count 降序排列,优先选大的
        let sorted = folders.sorted { $0.media_count > $1.media_count }
        // 主夹 = 用户指定的或默认尺最大的
        let primary = sorted.first { $0.id == chosenId }
            ?? sorted.first { $0.title.contains("默认") }
            ?? sorted.first
        guard let primary else { return [] }
        // 次夹 = 与主夹不同且有内容的另一个
        let secondary = sorted.first { $0.id != primary.id && $0.media_count > 0 }
        return secondary.map { [primary.id, $0.id] } ?? [primary.id]
    }

    private func totalPages(for folderId: Int) async -> Int? {
        let folders = await FavoriteManager.shared.folders
        guard let folder = folders.first(where: { $0.id == folderId }) else { return nil }
        return min(max(1, Int(ceil(Double(folder.media_count) / 40.0))), 12)
    }

    @MainActor
    private static func makeSnapshot(mode: Mode) async -> Snapshot {
        await CacheStore.shared.loadIfNeeded()
        await PlaybackHistoryStore.shared.loadIfNeeded()
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

    private static func ranked(_ candidates: [Candidate], mode: Mode, context: Context, snapshot: Snapshot, limit: Int) -> [Track] {
        let current = context.current

        let scored = candidates
            .filter { candidate in
                guard let current else { return true }
                return !candidate.track.key.matches(current)
            }
            .filter { !Self.contains(context.excludedKeys, matching: $0.track) }
            .map { candidate in
                (candidate.track, score(candidate, current: current, queue: context.queue, mode: mode, snapshot: snapshot))
            }
            .filter { $0.1 > 0 }

        var best: [TrackKey: (track: Track, score: Int)] = [:]
        for item in scored {
            let key = best.keys.first { $0.matches(item.0) } ?? item.0.key
            let previous = best[key]
            if previous == nil || item.1 > previous!.score {
                best[key] = (item.0, item.1)
            }
        }

        let sorted = best.values
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.track.title < rhs.track.title
                }
                return lhs.score > rhs.score
            }
            .map(\.track)

        if mode == .radio {
            return Array(sorted.prefix(limit))
        }

        let head = sorted.prefix(8)
        let tail = sorted.dropFirst(8).shuffled()
        return Array((head + tail).prefix(limit))
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
