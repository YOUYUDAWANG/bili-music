import Foundation

@MainActor
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
        var excludedBVIDs: Set<String> = []
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

    private let client = BiliClient()

    func recommendations(mode: Mode, context: Context, limit: Int = 24) async -> [Track] {
        var candidates: [Candidate] = []

        switch mode {
        case .home:
            // 首页刷新必须快:旧逻辑会串行请求收藏/历史/缓存/当前歌曲十几个 related,
            // 真机上点击"换一批"会明显变慢。这里按质量分层短路,够用就停止补源。
            let favorites = await favoriteSeeds(maxCount: 3)
            candidates += await relatedCandidates(from: favorites, source: .favoriteSeed, perSeedLimit: 12)

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

    func nextRadioTrack(after current: Track?, excludedBVIDs: Set<String>) async -> Track? {
        guard let current else { return nil }
        let tracks = await recommendations(
            mode: .radio,
            context: Context(current: current, excludedBVIDs: excludedBVIDs),
            limit: 8)
        return tracks.first
    }

    private func relatedCandidates(from seeds: [Track], source: Source, perSeedLimit: Int = 18) async -> [Candidate] {
        var candidates: [Candidate] = []
        for seed in seeds {
            guard let items = try? await client.related(bvid: seed.bvid) else { continue }
            candidates.append(contentsOf: items
                .map(Track.init(related:))
                .filter(MusicFilter.isMusic)
                .prefix(perSeedLimit)
                .map { Candidate(track: $0, source: source, seed: seed) })
        }
        return candidates
    }

    private func artistSearchCandidates(for track: Track) async -> [Candidate] {
        let terms = searchTerms(for: track)
        guard !terms.isEmpty else { return [] }
        var candidates: [Candidate] = []
        for term in terms.prefix(2) {
            guard let items = try? await client.search(keyword: term) else { continue }
            candidates.append(contentsOf: items
                .map(Track.init(search:))
                .filter { MusicFilter.isSearchResultMusic($0, query: term) }
                .prefix(10)
                .map { Candidate(track: $0, source: .artistSearch, seed: track) })
        }
        return candidates
    }

    private func fallbackSearchCandidates(keywordLimit: Int = 2) async -> [Candidate] {
        let keywords = [
            "华语音乐 MV",
            "日语歌 翻唱",
            "粤语歌 live",
            "动漫 OST 音乐",
        ].shuffled().prefix(keywordLimit)
        var candidates: [Candidate] = []
        for keyword in keywords {
            guard let items = try? await client.search(keyword: keyword) else { continue }
            candidates.append(contentsOf: items
                .map(Track.init(search:))
                .filter { MusicFilter.isSearchResultMusic($0, query: keyword) }
                .prefix(12)
                .map { Candidate(track: $0, source: .fallbackSearch, seed: nil) })
        }
        return candidates
    }

    private func playlistNeighborCandidates(current: Track?, playlistTracks: [Track]) -> [Candidate] {
        guard let current, let index = playlistTracks.firstIndex(where: { $0.bvid == current.bvid }) else { return [] }
        let bounds = max(0, index - 3)..<min(playlistTracks.count, index + 4)
        return playlistTracks[bounds]
            .filter { $0.bvid != current.bvid }
            .map { Candidate(track: $0, source: .playlistNeighbor, seed: current) }
    }

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
        let page = Int.random(in: 1...pageCount)
        guard let result = try? await client.favItems(folderId: folder.id, page: page) else { return [] }
        let items = (result.medias ?? [])
            .filter { $0.attr == 0 }
            .map { Track(bvid: $0.bvid, title: $0.title, artist: $0.upper.name,
                         coverURL: URL(string: $0.cover), duration: $0.duration) }
            .filter(MusicFilter.isStrictMusic)
        return Array(items.shuffled().prefix(maxCount))
    }

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
        return score
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

    private func hasBadRecommendationHint(_ text: String) -> Bool {
        [
            "解说", "评论", "reaction", "clip", "切片", "教程", "中字", "字幕组",
            "耐久", "作业用", "排行", "top", "合集剪辑", "鬼畜", "mad", "amv",
        ].contains { text.contains($0) }
    }

    private func importantTokens(_ text: String) -> [String] {
        normalized(text)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 && !["official", "music", "video", "mv", "live", "cover"].contains($0) }
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\p{P}\p{S}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
