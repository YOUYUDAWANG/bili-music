import Foundation

enum LDDCLyricsBackendConfiguration {
    static let overrideURLKey = "lddcLyricsBackendURL"

    static var baseURL: URL? {
        let override = UserDefaults.standard.string(forKey: overrideURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundled = Bundle.main.object(forInfoDictionaryKey: "BiliMusicLDDCLyricsAPIURL") as? String ?? ""
        let raw = override.isEmpty ? bundled : override
        guard !raw.isEmpty, !raw.contains("$("), let url = URL(string: raw) else { return nil }
        return url
    }

    static var accessToken: String? {
        let infoToken = Bundle.main.object(forInfoDictionaryKey: "BiliMusicLDDCLyricsAPIKey") as? String
        let resourceToken = bundledSecrets?["AccessToken"] as? String
        return infoToken.flatMap(validToken) ?? resourceToken.flatMap(validToken)
    }

    static var isConfigured: Bool { baseURL != nil && accessToken != nil }

    private static var bundledSecrets: [String: Any]? {
        guard let url = Bundle.main.url(
            forResource: "BiliMusicLDDCLyrics",
            withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return nil }
        return plist as? [String: Any]
    }

    private static func validToken(_ token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.contains("$(") ? nil : trimmed
    }
}

protocol LDDCLyricsBackendSearching: Sendable {
    func lookup(
        track: Track,
        metadata: NormalizedTrackMetadata?,
        preferCover: Bool
    ) async throws -> [LyricsExternalHit]
}

enum LDDCLyricsBackendError: LocalizedError, Equatable {
    case notConfigured
    case invalidResponse
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "LDDC 歌词后端尚未配置"
        case .invalidResponse:
            "LDDC 歌词后端返回了无效时间轴"
        case let .server(status):
            "LDDC 歌词后端暂时不可用（\(status)）"
        }
    }
}

actor LDDCLyricsBackendClient: LDDCLyricsBackendSearching {
    static let schema = "bilimusic-lddc-lyrics-v1"

    private let baseURL: URL?
    private let accessToken: String?
    private let session: URLSession

    init(baseURL: URL? = nil, accessToken: String? = nil, session: URLSession? = nil) {
        self.baseURL = baseURL ?? LDDCLyricsBackendConfiguration.baseURL
        self.accessToken = accessToken ?? LDDCLyricsBackendConfiguration.accessToken
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 25
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func lookup(
        track: Track,
        metadata: NormalizedTrackMetadata?,
        preferCover: Bool
    ) async throws -> [LyricsExternalHit] {
        let title = LyricsAutoMatchGate.searchTitle(track: track, metadata: metadata)
            ?? metadata?.canonicalTitle
            ?? track.title
        let artists = expectedArtists(track: track, metadata: metadata, preferCover: preferCover)
        return try await resolve(
            title: title,
            artists: artists,
            aliases: metadata?.aliases ?? [],
            track: track,
            requestScope: preferCover ? "cover" : "original",
            requireDurationMatch: preferCover || metadata?.isCover != true)
    }

    /// Manual search keeps the backend's strict title/artist gate but allows duration mismatches
    /// to remain visible. The App ranks only duration-compatible word timing as reliable; an
    /// explicit user may still inspect an extended-video or medley candidate without weakening
    /// automatic adoption.
    func search(
        keyword: String,
        track: Track,
        metadata: NormalizedTrackMetadata?
    ) async throws -> [LyricsExternalHit] {
        let intent = Self.manualSearchIntent(keyword)
        var artists = intent.artist.map { [$0] } ?? []
        if artists.isEmpty {
            artists.append(contentsOf: metadata?.coverPerformers ?? [])
            artists.append(contentsOf: metadata?.originalArtists ?? [])
            artists.append(track.artist)
        }
        return try await resolve(
            title: intent.title,
            artists: Self.uniqueArtists(artists),
            aliases: metadata?.aliases ?? [],
            track: track,
            requestScope: "manual",
            requireDurationMatch: false)
    }

    private func resolve(
        title: String,
        artists: [String],
        aliases: [String],
        track: Track,
        requestScope: String,
        requireDurationMatch: Bool
    ) async throws -> [LyricsExternalHit] {
        guard let baseURL, let accessToken else { throw LDDCLyricsBackendError.notConfigured }
        guard !title.isEmpty, !artists.isEmpty else { return [] }

        let requestID = "\(track.bvid):\(track.cid.map(String.init) ?? "-"):\(requestScope)"
        let payload = ResolveRequest(
            schema: Self.schema,
            requestID: requestID,
            title: title,
            artists: artists,
            aliases: aliases,
            durationMilliseconds: track.duration > 0 ? track.duration * 1_000 : nil,
            requireDurationMatch: requireDurationMatch,
            maxCandidates: 6)
        var request = URLRequest(
            url: baseURL
                .appendingPathComponent("v1")
                .appendingPathComponent("lyrics")
                .appendingPathComponent("resolve"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("BiliMusic/iOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LDDCLyricsBackendError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LDDCLyricsBackendError.server(http.statusCode)
        }
        let envelope: ResolveResponse
        do {
            envelope = try JSONDecoder().decode(ResolveResponse.self, from: data)
        } catch {
            throw LDDCLyricsBackendError.invalidResponse
        }
        guard envelope.schema == Self.schema,
              envelope.requestID == requestID,
              envelope.candidates.count <= 12 else {
            throw LDDCLyricsBackendError.invalidResponse
        }
        return try envelope.candidates.compactMap(Self.hit(from:))
    }

    private static func manualSearchIntent(_ keyword: String) -> (title: String, artist: String?) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.lastIndex(of: "-") else { return (trimmed, nil) }
        let title = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = String(trimmed[trimmed.index(after: separator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artist.isEmpty else { return (trimmed, nil) }
        return (title.isEmpty ? trimmed : title, artist)
    }

    private static func uniqueArtists(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = LyricsVersionClassifier.comparable(trimmed)
            return seen.insert(key).inserted ? trimmed : nil
        }
    }

    private func expectedArtists(
        track: Track,
        metadata: NormalizedTrackMetadata?,
        preferCover: Bool
    ) -> [String] {
        var values = preferCover ? (metadata?.coverPerformers ?? []) : (metadata?.originalArtists ?? [])
        if preferCover, let uploader = metadata?.uploader {
            values.append(uploader)
        }
        if values.isEmpty {
            values.append(track.artist)
        }
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = LyricsVersionClassifier.comparable(trimmed)
            return seen.insert(key).inserted ? trimmed : nil
        }
    }

    private static func hit(from candidate: Candidate) throws -> LyricsExternalHit? {
        guard let provider = provider(for: candidate.source),
              !candidate.id.isEmpty,
              !candidate.title.isEmpty,
              !candidate.artist.isEmpty,
              candidate.lyricLines.count <= 500 else { return nil }
        let lines = try validatedLines(candidate.lyricLines, requiresWords: candidate.timingKind == "word")
        guard !lines.isEmpty else { return nil }
        let translations = try validatedLines(candidate.translationLines, requiresWords: false)
        let romanizations = try validatedLines(candidate.romanizationLines, requiresWords: false)
        let result = LyricsSearchResult(
            provider: provider,
            id: candidate.id,
            title: candidate.title,
            artist: candidate.artist,
            album: candidate.album,
            duration: candidate.durationSeconds,
            artworkID: nil,
            timingKindHint: candidate.timingKind == "word" ? .word : .line)
        let lyric = lrc(from: lines)
        let karaoke = candidate.timingKind == "word" ? qrc(from: lines) : nil
        let document = LyricsDocument(
            result: result,
            lyric: lyric,
            translatedLyric: translations.isEmpty ? nil : lrc(from: translations),
            romanizedLyric: romanizations.isEmpty ? nil : lrc(from: romanizations),
            karaokeLyric: karaoke,
            karaokeTranslatedLyric: nil,
            timingKind: karaoke == nil ? .line : .word,
            vocalLines: vocalLines(from: lines, translations: translations))
        guard document.hasLyrics else { return nil }
        return LyricsExternalHit(result: result, document: document)
    }

    private static func provider(for value: String) -> LyricsProvider? {
        switch value {
        case "kugou": .kugou
        case "tencent": .tencent
        case "netease": .netease
        default: nil
        }
    }

    private static func validatedLines(
        _ source: [Line],
        requiresWords: Bool
    ) throws -> [Line] {
        var previousStart = -1
        var totalWords = 0
        var output: [Line] = []
        for line in source.sorted(by: { $0.startMilliseconds < $1.startMilliseconds }) {
            guard line.startMilliseconds >= previousStart,
                  line.endMilliseconds > line.startMilliseconds,
                  !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LDDCLyricsBackendError.invalidResponse
            }
            var previousWordStart = line.startMilliseconds
            for word in line.words {
                guard word.startMilliseconds >= line.startMilliseconds,
                      word.startMilliseconds >= previousWordStart,
                      word.endMilliseconds > word.startMilliseconds,
                      word.endMilliseconds <= line.endMilliseconds + 250,
                      !word.text.isEmpty else {
                    throw LDDCLyricsBackendError.invalidResponse
                }
                previousWordStart = word.startMilliseconds
            }
            totalWords += line.words.count
            guard totalWords <= 5_000, !requiresWords || !line.words.isEmpty else {
                throw LDDCLyricsBackendError.invalidResponse
            }
            previousStart = line.startMilliseconds
            output.append(line)
        }
        return output
    }

    private static func lrc(from lines: [Line]) -> String {
        lines.map { line in
            "[\(timestamp(line.startMilliseconds))]\(line.text)"
        }.joined(separator: "\n")
    }

    private static func qrc(from lines: [Line]) -> String? {
        let rows = lines.compactMap { line -> String? in
            guard !line.words.isEmpty else { return nil }
            let duration = max(line.endMilliseconds - line.startMilliseconds, 1)
            let words = line.words.map { word in
                let offset = max(0, word.startMilliseconds - line.startMilliseconds)
                let length = max(1, word.endMilliseconds - word.startMilliseconds)
                return "<\(offset),\(length),0>\(word.text)"
            }.joined()
            return "[\(line.startMilliseconds),\(duration)]\(words)"
        }
        return rows.isEmpty ? nil : rows.joined(separator: "\n")
    }

    private static func vocalLines(from lines: [Line], translations: [Line]) -> [LyricsVocalLine] {
        let translationByStart = Dictionary(
            translations.map { ($0.startMilliseconds, $0.text) },
            uniquingKeysWith: { first, _ in first })
        return lines.enumerated().map { index, line in
            let translation = translationByStart[line.startMilliseconds]
                ?? translations.first(where: { abs($0.startMilliseconds - line.startMilliseconds) <= 80 })?.text
            return LyricsVocalLine(
                from: Double(line.startMilliseconds) / 1_000,
                to: Double(line.endMilliseconds) / 1_000,
                text: line.text,
                translation: translation,
                words: line.words.map {
                    LyricsWordPayload(
                        from: Double($0.startMilliseconds) / 1_000,
                        to: Double($0.endMilliseconds) / 1_000,
                        text: $0.text)
                },
                voiceRole: .lead,
                layerID: "lddc-line-\(index)",
                overlapGroup: nil)
        }
    }

    private static func timestamp(_ milliseconds: Int) -> String {
        let minutes = milliseconds / 60_000
        let seconds = (milliseconds % 60_000) / 1_000
        let fraction = milliseconds % 1_000
        return String(format: "%02d:%02d.%03d", minutes, seconds, fraction)
    }
}

private extension LDDCLyricsBackendClient {
    struct ResolveRequest: Encodable {
        let schema: String
        let requestID: String
        let title: String
        let artists: [String]
        let aliases: [String]
        let durationMilliseconds: Int?
        let requireDurationMatch: Bool
        let maxCandidates: Int
    }

    struct ResolveResponse: Decodable {
        let schema: String
        let requestID: String
        let candidates: [Candidate]
    }

    struct Candidate: Decodable {
        let source: String
        let id: String
        let title: String
        let artist: String
        let album: String?
        let durationSeconds: Int?
        let timingKind: String
        let lyricLines: [Line]
        let translationLines: [Line]
        let romanizationLines: [Line]
    }

    struct Line: Decodable {
        let startMilliseconds: Int
        let endMilliseconds: Int
        let text: String
        let words: [Word]
    }

    struct Word: Decodable {
        let startMilliseconds: Int
        let endMilliseconds: Int
        let text: String
    }
}
