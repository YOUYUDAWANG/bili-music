import Foundation

/// 从「我喜欢」、音乐收藏夹和播放历史里抽出常听歌手，供推荐去搜同类歌。
struct ListeningTaste: Equatable, Sendable {
    struct Artist: Equatable, Sendable {
        var name: String
        var weight: Int
    }

    var artists: [Artist]
    var titles: [Artist]
    var seedTracks: [Track]

    static let empty = ListeningTaste(artists: [], titles: [], seedTracks: [])

    var isEmpty: Bool { artists.isEmpty && titles.isEmpty }

    init(artists: [Artist], titles: [Artist] = [], seedTracks: [Track]) {
        self.artists = artists
        self.titles = titles
        self.seedTracks = seedTracks
    }

    static func build(
        liked: [Track],
        library: [Track],
        history: [(track: Track, playCount: Int)],
        metadataFor: (Track) -> NormalizedTrackMetadata?
    ) -> ListeningTaste {
        var weights: [String: Int] = [:]
        var names: [String: String] = [:]
        var titleWeights: [String: Int] = [:]
        var titleNames: [String: String] = [:]
        var seedWeights: [String: (track: Track, weight: Int)] = [:]

        func add(_ track: Track, weight: Int) {
            guard weight > 0 else { return }
            let metadata = metadataFor(track)
            let extracted = Self.artists(in: track, metadata: metadata)
            for artist in extracted {
                let key = normalized(artist)
                weights[key, default: 0] += weight
                if names[key] == nil {
                    names[key] = artist
                }
            }
            for title in Self.titles(in: track, metadata: metadata) {
                let key = normalized(title)
                guard weights[key] == nil else { continue }
                titleWeights[key, default: 0] += weight
                if titleNames[key] == nil {
                    titleNames[key] = title
                }
            }
            let seedKey = track.bvid
            if let previous = seedWeights[seedKey] {
                if weight > previous.weight {
                    seedWeights[seedKey] = (track, weight)
                } else {
                    seedWeights[seedKey] = (previous.track, previous.weight + weight)
                }
            } else {
                seedWeights[seedKey] = (track, weight)
            }
        }

        for track in liked {
            add(track, weight: 8)
        }
        for track in library {
            add(track, weight: 4)
        }
        for item in history {
            add(item.track, weight: min(max(item.playCount, 1), 8))
        }

        let artists = weights
            .compactMap { key, weight -> Artist? in
                guard let name = names[key] else { return nil }
                return Artist(name: name, weight: weight)
            }
            .sorted { lhs, rhs in
                if lhs.weight == rhs.weight { return lhs.name < rhs.name }
                return lhs.weight > rhs.weight
            }

        let titles = titleWeights
            .compactMap { key, weight -> Artist? in
                guard let name = titleNames[key] else { return nil }
                return Artist(name: name, weight: weight)
            }
            .sorted { lhs, rhs in
                if lhs.weight == rhs.weight { return lhs.name < rhs.name }
                return lhs.weight > rhs.weight
            }

        let seeds = seedWeights.values
            .sorted { lhs, rhs in
                if lhs.weight == rhs.weight { return lhs.track.title < rhs.track.title }
                return lhs.weight > rhs.weight
            }
            .prefix(6)
            .map(\.track)

        return ListeningTaste(artists: artists, titles: titles, seedTracks: Array(seeds))
    }

    static func artists(in track: Track, metadata: NormalizedTrackMetadata?) -> [String] {
        if let metadata {
            var names = metadata.originalArtists
            if metadata.isCover {
                names.append(contentsOf: metadata.coverPerformers)
            }
            let usable = uniqued(names.filter(isUsableArtist))
            if !usable.isEmpty { return usable }
        }

        let parsed = TrackTitleParser.parseSongDetailed(from: track.title, fallbackArtist: track.artist)
        if parsed.confidence == .high, let artist = parsed.artist, isUsableArtist(artist) {
            return [artist]
        }
        return []
    }

    static func titles(in track: Track, metadata: NormalizedTrackMetadata?) -> [String] {
        var found: [String] = []
        if let title = metadata?.canonicalTitle, isUsableTitle(title) {
            found.append(title)
        }
        let parsed = TrackTitleParser.parseSongDetailed(from: track.title, fallbackArtist: track.artist)
        if parsed.confidence == .high, isUsableTitle(parsed.title) {
            found.append(parsed.title)
        }
        return uniqued(found)
    }

    static func isUsableTitle(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...32).contains(trimmed.count) else { return false }
        if trimmed.uppercased().hasPrefix("BV") { return false }
        let lower = normalized(trimmed)
        let rejected = [
            "official", "mv", "合集", "歌单", "高音质", "无损", "live全集", "纯享",
        ]
        return !rejected.contains { lower == normalized($0) || lower.contains(normalized($0)) }
    }

    static func isUsableArtist(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...24).contains(trimmed.count) else { return false }
        if trimmed.uppercased().hasPrefix("BV") { return false }
        if trimmed.allSatisfy(\.isNumber) { return false }
        let lower = normalized(trimmed)
        let rejected = [
            "音乐", "歌曲", "高音质", "无损", "official", "官方", "bilibili", "哔哩哔哩",
            "搬运", "剪辑", "合集", "歌单", "未知", "unknown", "various", "cover", "翻唱",
            "投稿", "音源", "纯音乐合集",
        ]
        return !rejected.contains { lower.contains(normalized($0)) }
    }

    func matches(title: String, artist: String) -> Bool {
        let haystack = Self.normalized(title + " " + artist)
        if artists.prefix(8).contains(where: { item in
            let key = Self.normalized(item.name)
            return key.count >= 2 && haystack.contains(key)
        }) {
            return true
        }
        return titles.prefix(8).contains { item in
            let key = Self.normalized(item.name)
            return key.count >= 2 && haystack.contains(key)
        }
    }

    struct Query: Equatable, Sendable {
        var keyword: String
        var page: Int
    }

    static func searchPlan(
        artists: [Artist],
        titles: [Artist],
        artistLimit: Int,
        titleLimit: Int,
        page: Int
    ) -> [Query] {
        let basePage = min(max(page, 1), 3)
        let artistNames = pickSearchNames(from: artists, limit: artistLimit)
        let titleNames = pickSearchNames(from: titles, limit: titleLimit)
        var queries: [Query] = []
        var seen = Set<String>()
        for (offset, name) in artistNames.enumerated() {
            let key = normalized(name)
            guard seen.insert("a:\(key)").inserted else { continue }
            queries.append(Query(keyword: name, page: ((basePage - 1 + offset) % 3) + 1))
        }
        for (offset, name) in titleNames.enumerated() {
            let key = normalized(name)
            guard seen.insert("t:\(key)").inserted else { continue }
            queries.append(Query(keyword: name, page: ((basePage - 1 + offset) % 3) + 1))
        }
        return queries
    }

    static func pickSearchNames(from artists: [Artist], limit: Int) -> [String] {
        let ranked = artists.sorted { lhs, rhs in
            if lhs.weight == rhs.weight { return lhs.name < rhs.name }
            return lhs.weight > rhs.weight
        }
        guard limit > 0, !ranked.isEmpty else { return [] }
        if ranked.count <= limit { return ranked.map(\.name) }
        let pool = Array(ranked.prefix(max(limit, min(12, ranked.count))))
        return weightedSample(pool, count: limit).map(\.name)
    }

    private static func weightedSample(_ items: [Artist], count: Int) -> [Artist] {
        items
            .map { item -> (Artist, Double) in
                let weight = Double(max(1, item.weight))
                let u = Double.random(in: 1e-9 ..< 1)
                return (item, pow(u, 1.0 / weight))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(count)
            .map(\.0)
    }

    private static func uniqued(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert(normalized($0)).inserted }
    }

    static func normalized(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
