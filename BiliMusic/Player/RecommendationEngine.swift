import Foundation
import OSLog

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "recommend")

/// 统一推荐引擎（无状态）。融合相关视频、收藏夹种子、历史、歌单相邻、歌手搜索等多来源，
/// 确定性打分 + 随机扰动后排序。供首页、电台自动选歌、播放器相关面板共用。
@MainActor
struct RecommendationEngine {
    /// 推荐场景：首页发现 / 电台连播 / 播放器相关面板。
    enum Mode {
        case home
        case radio
        case relatedPanel
    }

    /// 一次推荐的上下文：当前曲目、队列、歌单曲目、跨调用排除集。
    struct Context {
        var current: Track?
        var queue: [Track] = []
        var playlistTracks: [Track] = []
        var excludedBVIDs: Set<String> = []
    }

    /// 候选来源，决定基础分。
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

    private let client = BiliClient()

    /// 按场景汇集候选并排序。首页按质量分层短路，够用就停止补源。
    func recommendations(mode: Mode, context: Context, limit: Int = 24) async -> [Track] {
        var candidates: [Candidate] = []

        switch mode {
        case .home:
            // 首页刷新必须快:旧逻辑会串行请求收藏/历史/缓存/当前歌曲十几个 related,
            // 真机上点击"换一批"会明显变慢。这里按质量分层短路,够用就停止补源。
            let favorites = await favoriteSeeds(maxCount: 5)
            candidates += await relatedCandidates(from: favorites, source: .favoriteSeed, perSeedLimit: 10)

            if candidates.count < 12, let current = context.current {
                candidates += await relatedCandidates(from: [current], source: .relatedCurrent, perSeedLimit: 12)
            }
            if candidates.count < 12 {
                let history = PlaybackHistoryStore.shared.entries.prefix(2).map(\.track)
                candidates += await relatedCandidates(from: Array(history), source: .relatedHistory, perSeedLimit: 8)
            }
            if candidates.count < 12 {
                let cache = CacheStore.shared.entries.prefix(2).map(\.track)
                candidates += await relatedCandidates(from: Array(cache), source: .relatedHistory, perSeedLimit: 8)
            }
            if candidates.isEmpty {
                candidates += await fallbackSearchCandidates(keywordLimit: 1)
            }

        case .radio:
            if let current = context.current {
                candidates += await relatedCandidates(from: [current], source: .relatedCurrent)
                candidates += await artistSearchCandidates(for: current)
            }
            candidates += playlistNeighborCandidates(current: context.current, playlistTracks: context.playlistTracks)

        case .relatedPanel:
            if let current = context.current {
                candidates += await relatedCandidates(from: [current], source: .relatedCurrent)
                candidates += await artistSearchCandidates(for: current)
            }
            candidates += playlistNeighborCandidates(current: context.current, playlistTracks: context.playlistTracks)
            candidates += await relatedCandidates(from: PlaybackHistoryStore.shared.entries.prefix(2).map(\.track), source: .relatedHistory)
        }

        return ranked(candidates, mode: mode, context: context, limit: limit)
    }

    /// 电台模式取下一首：用 .radio 场景跑一遍取第一名。
    func nextRadioTrack(after current: Track?, excludedBVIDs: Set<String>) async -> Track? {
        guard let current else { return nil }
        let tracks = await recommendations(
            mode: .radio,
            context: Context(current: current, excludedBVIDs: excludedBVIDs),
            limit: 8)
        return tracks.first
    }

    /// 并发拉取多个种子的相关视频，过滤出音乐后作候选。
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

    /// 用歌手/歌名搜索补充候选。
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

    /// 兜底：用泛音乐关键词搜索（无任何种子时）。
    private func fallbackSearchCandidates(keywordLimit: Int = 2) async -> [Candidate] {
        let keywords = [
            "华语音乐 MV",
            "日语歌 翻唱",
            "粤语歌 live",
            "动漫 OST 音乐",
        ].shuffled().prefix(keywordLimit)
        return await withTaskGroup(of: [Candidate].self) { group in
            for keyword in keywords {
                group.addTask {
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

    /// 取当前曲目在歌单里的相邻曲目作候选。
    private func playlistNeighborCandidates(current: Track?, playlistTracks: [Track]) -> [Candidate] {
        guard let current, let index = playlistTracks.firstIndex(where: { $0.bvid == current.bvid }) else { return [] }
        let bounds = max(0, index - 3)..<min(playlistTracks.count, index + 4)
        return playlistTracks[bounds]
            .filter { $0.bvid != current.bvid }
            .map { Candidate(track: $0, source: .playlistNeighbor, seed: current) }
    }

    /// 从收藏夹随机页抽取种子曲目（需登录）。
    private func favoriteSeeds(maxCount: Int = 4) async -> [Track] {
        guard CookieStore.isLoggedIn else { return [] }
        let manager = FavoriteManager.shared
        if manager.folders.isEmpty {
            await manager.loadFolders()
        }
        let chosenId = UserDefaults.standard.integer(forKey: "recommendFolderId")
        let folder = manager.folders.first(where: { $0.id == chosenId && $0.media_count > 0 })
            ?? manager.folders.first(where: { $0.title.contains("默认") && $0.media_count > 0 })
            ?? manager.folders.first(where: { $0.media_count > 0 })
        guard let folder else { return [] }
        let pageCount = max(1, Int(ceil(Double(folder.media_count) / 40.0)))
        var pageNums: Set<Int> = [Int.random(in: 1...pageCount)]
        if pageCount > 1 {
            while pageNums.count < 2 { pageNums.insert(Int.random(in: 1...pageCount)) }
        }
        var allItems: [Track] = []
        await withTaskGroup(of: [Track].self) { group in
            for pageNum in pageNums {
                group.addTask {
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

    /// 打分、去重、排序，并对非电台场景的尾部做随机化。
    private func ranked(_ candidates: [Candidate], mode: Mode, context: Context, limit: Int) -> [Track] {
        let recent = Set(PlaybackHistoryStore.shared.entries.prefix(mode == .radio ? 20 : 8).map(\.bvid))
        let queueSet = Set(context.queue.map(\.bvid))
        let current = context.current

        let scored = candidates
            .filter { $0.track.bvid != current?.bvid }
            .filter { !context.excludedBVIDs.contains($0.track.bvid) }
            .map { candidate in
                (candidate.track, score(candidate, current: current, recent: recent, queueSet: queueSet, mode: mode))
            }
            .filter { $0.1 > 0 }

        var best: [String: (track: Track, score: Int)] = [:]
        for item in scored {
            let previous = best[item.0.bvid]
            if previous == nil || item.1 > previous!.score {
                best[item.0.bvid] = (item.0, item.1)
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

    /// 单个候选的综合打分：来源 + 音乐度 + 时长 + 歌手/歌名相关 + 收藏/缓存信号 − 最近/重复/非音乐惩罚。
    private func score(_ candidate: Candidate, current: Track?, recent: Set<String>, queueSet: Set<String>, mode: Mode) -> Int {
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

        if FavoriteManager.shared.favoriteBVIDs.contains(track.bvid) {
            score += 12
        }
        if CacheStore.shared.entry(bvid: track.bvid) != nil {
            score += 6
        }
        if recent.contains(track.bvid) {
            score -= mode == .radio ? 80 : 24
        }
        if queueSet.contains(track.bvid) {
            score -= 18
        }
        if hasBadRecommendationHint(text) {
            score -= 48
        }
        score += Int.random(in: -10...10)
        return score
    }

    /// 为某曲目生成搜索词（歌手 + 解析出的歌名）。
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

    /// 从标题里抽出《》内或「 - 」前的歌名。
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

    /// 标题是否含解说/切片/鬼畜等明显非音乐信号。
    private func hasBadRecommendationHint(_ text: String) -> Bool {
        [
            "解说", "评论", "reaction", "clip", "切片", "教程", "中字", "字幕组",
            "耐久", "作业用", "排行", "top", "合集剪辑", "鬼畜", "mad", "amv",
        ].contains { text.contains($0) }
    }

    /// 取标题里有意义的关键词（用于相关性加分）。
    private func importantTokens(_ text: String) -> [String] {
        normalized(text)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 && !["official", "music", "video", "mv", "live", "cover"].contains($0) }
    }

    /// 归一化文本，便于包含匹配。
    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\p{P}\p{S}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
