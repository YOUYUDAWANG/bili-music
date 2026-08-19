import Foundation

/// 国际歌词库。只用标题/歌手/时长做匹配，不用 LRCLIB 的评分字段。
actor LRCLibLyricsProvider {
    private let session: URLSession
    private var documents: [String: LyricsDocument] = [:]

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

    func lookup(title: String, artist: String?, duration: Int?) async -> [LyricsExternalHit] {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard var components = URLComponents(string: "https://lrclib.net/api/search") else { return [] }
        // 只用歌名搜。带上翻唱者/UP 当 artist_name 时，原唱条目会变成 0 条。
        components.queryItems = Self.searchQueryItems(title: trimmed)
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("BiliMusic/iOS (personal lyrics client)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return [] }
        return ingest(Self.parseSearch(data), artist: artist)
    }

    func search(keyword: String) async -> [LyricsSearchResult] {
        await lookup(title: keyword, artist: nil, duration: nil).map(\.result)
    }

    static func searchQueryItems(title: String) -> [URLQueryItem] {
        [URLQueryItem(name: "q", value: title)]
    }

    func fetch(for result: LyricsSearchResult) -> LyricsDocument? {
        documents[result.stableID]
    }

    static func parseSearch(_ data: Data) -> [LyricsExternalHit] {
        let root: Any
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            root = array
        } else if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = [object]
        } else {
            return []
        }
        guard let rows = root as? [[String: Any]] else { return [] }
        return rows.compactMap(parseHit)
    }

    private func ingest(_ hits: [LyricsExternalHit], artist: String?) -> [LyricsExternalHit] {
        var kept: [LyricsExternalHit] = []
        for hit in hits {
            documents[hit.result.stableID] = hit.document
            kept.append(hit)
        }
        guard let artist, !artist.isEmpty else { return kept }
        let preferred = kept.filter {
            LyricsVersionClassifier.namesOverlap($0.result.artist, [artist])
        }
        return preferred.isEmpty ? kept : preferred
    }

    private static func parseHit(_ row: [String: Any]) -> LyricsExternalHit? {
        if row["instrumental"] as? Bool == true { return nil }
        let id = string(row["id"]) ?? UUID().uuidString
        let title = string(row["trackName"]) ?? string(row["name"]) ?? ""
        guard !title.isEmpty else { return nil }
        let synced = nonEmpty(row["syncedLyrics"] as? String)
        let plain = nonEmpty(row["plainLyrics"] as? String)
        guard synced != nil || plain != nil else { return nil }
        let result = LyricsSearchResult(
            provider: .lrclib,
            id: id,
            title: title,
            artist: string(row["artistName"]) ?? "",
            album: nonEmpty(row["albumName"] as? String),
            duration: seconds(row["duration"]),
            artworkID: nil)
        let document = LyricsDocument(
            result: result,
            lyric: synced ?? plain,
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil)
        return LyricsExternalHit(result: result, document: document)
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String: value
        case let value as NSNumber: value.stringValue
        default: nil
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func seconds(_ value: Any?) -> Int? {
        switch value {
        case let value as Int: value
        case let value as Double: Int(value.rounded())
        case let value as NSNumber: Int(value.doubleValue.rounded())
        case let value as String:
            Double(value).map { Int($0.rounded()) }
        default: nil
        }
    }
}
