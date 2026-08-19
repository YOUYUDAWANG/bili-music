import Foundation

actor VocaDBLyricsProvider {
    private let session: URLSession
    private var documents: [String: LyricsDocument] = [:]
    private var queryCache: [String: [LyricsExternalHit]] = [:]
    private var fetchedAt: [String: Date] = [:]
    private let ttl: TimeInterval = 6 * 60 * 60

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 16
            configuration.httpAdditionalHeaders = [
                "User-Agent": "BiliMusic/iOS (personal lyrics client)",
                "Accept": "application/json",
            ]
            self.session = URLSession(configuration: configuration)
        }
    }

    func lyrics(for track: Track, metadata: NormalizedTrackMetadata?) async -> LyricsDocument? {
        let title = LyricsAutoMatchGate.searchTitle(track: track, metadata: metadata)
            ?? metadata?.canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? track.title
        return await lookup(title: title, artist: metadata?.originalArtists.first, duration: track.duration)
            .first(where: { $0.document.hasLyrics })?
            .document
    }

    func lookup(title: String, artist: String?, duration: Int?) async -> [LyricsExternalHit] {
        let query = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let key = query.lowercased()
        if let cached = queryCache[key], let date = fetchedAt[key], Date().timeIntervalSince(date) < ttl {
            return cached
        }
        guard var components = URLComponents(string: "https://vocadb.net/api/songs") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "maxResults", value: "8"),
            URLQueryItem(name: "fields", value: "Lyrics,Names"),
            URLQueryItem(name: "lang", value: "Default"),
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("BiliMusic/iOS (personal lyrics client)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = payload["items"] as? [[String: Any]] else { return [] }

        var hits: [LyricsExternalHit] = []
        for item in items {
            guard let lyrics = item["lyrics"] as? [[String: Any]] else { continue }
            let original = firstLyric(lyrics, cultures: ["Japanese", "Romaji", "English", ""])
            guard let original, !original.isEmpty else { continue }
            let translation = firstLyric(lyrics, cultures: ["Chinese", "English"])
            let romanization = firstLyric(lyrics, cultures: ["Romaji"])
            let songTitle = (item["name"] as? String) ?? query
            let songArtist = ((item["artistString"] as? String) ?? artist) ?? ""
            let length = (item["lengthSeconds"] as? Int) ?? (item["length"] as? Int)
            if let duration, duration > 0, let length, abs(length - duration) > 40 { continue }
            let result = LyricsSearchResult(
                provider: .vocadb,
                id: String(describing: item["id"] ?? query),
                title: songTitle,
                artist: songArtist,
                album: nil,
                duration: length,
                artworkID: nil)
            let document = LyricsDocument(
                result: result,
                lyric: original,
                translatedLyric: translation,
                romanizedLyric: romanization == original ? nil : romanization,
                karaokeLyric: nil,
                karaokeTranslatedLyric: nil)
            documents[result.stableID] = document
            hits.append(LyricsExternalHit(result: result, document: document))
        }
        queryCache[key] = hits
        fetchedAt[key] = Date()
        return hits
    }

    func search(keyword: String) async -> [LyricsSearchResult] {
        await lookup(title: keyword, artist: nil, duration: nil).map(\.result)
    }

    func fetch(for result: LyricsSearchResult) -> LyricsDocument? {
        documents[result.stableID]
    }

    private func firstLyric(_ lyrics: [[String: Any]], cultures: [String]) -> String? {
        for culture in cultures {
            if let match = lyrics.first(where: {
                let value = ($0["cultureCode"] as? String ?? $0["translationType"] as? String ?? "")
                return culture.isEmpty || value.localizedCaseInsensitiveContains(culture)
            }), let value = match["value"] as? String {
                let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return (lyrics.first?["value"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
