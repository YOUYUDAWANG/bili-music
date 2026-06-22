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

    func recommendations(mode: Mode, context: Context, limit: Int = 24) async -> [Track] {
        let snapshot = await Self.makeSnapshot(mode: mode)
        let cacheKey = Self.cacheKey(mode: mode, context: context, snapshot: snapshot)
        if let cached = await RecommendationResultCache.shared.tracks(for: cacheKey) {
            let filtered = cached.filter { !Self.contains(context.excludedKeys, matching: $0) }
            if !filtered.isEmpty {
                return Array(filtered.prefix(limit))
            }
        }

        var candidates: [Candidate] = []

        switch mode {
        case .home:
            // 首页刷新必须快:旧逻辑会串行请求收藏/历史/缓存/当前歌曲十几个 related,
            // 真机上点击"换一批"会明显变慢。这里按质量分层短路,够用就停止补源。
            let favorites = await favoriteSeeds(maxCount: 3, snapshot: snapshot)
            candidates += await relatedCandidates(from: favorites, source: .favoriteSeed, perSeedLimit: 8)

            if candidates.count < 12, let current = context.current {
                candidates += await relatedCandidates(from: [current], source: .relatedCurrent, perSeedLimit: 12)
            }
            if candidates.count < 12 {
                candidates += await relatedCandidates(from: Array(snapshot.historyTracks.prefix(2)), source: .relatedHistory, perSeedLimit: 8)
            }
            if candidates.count < 12 {
                candidates += await relatedCandidates(from: Array(snapshot.cachedTracks.prefix(2)), source: .relatedHistory, perSeedLimit: 8)
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

        let ranked = await Task.detached(priority: .userInitiated) {
            Self.ranked(candidates, mode: mode, context: context, snapshot: snapshot, limit: limit)
        }.value
        if mode != .radio {
            await RecommendationResultCache.shared.store(ranked, for: cacheKey)
        }
        return ranked
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

    private func playlistNeighborCandidates(current: Track?, playlistTracks: [Track]) -> [Candidate] {
        guard let current, let index = playlistTracks.firstIndex(where: { $0.bvid == current.bvid }) else { return [] }
        let bounds = max(0, index - 3)..<min(playlistTracks.count, index + 4)
        return playlistTracks[bounds]
            .filter { $0.bvid != current.bvid }
            .map { Candidate(track: $0, source: .playlistNeighbor, seed: current) }
    }

    private func favoriteSeeds(maxCount: Int = 4, snapshot: Snapshot) async -> [Track] {
        guard let folder = snapshot.favoriteFolder else { return [] }
        let pageCount = max(1, Int(ceil(Double(folder.mediaCount) / 40.0)))
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
