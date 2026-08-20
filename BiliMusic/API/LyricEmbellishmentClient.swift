import Foundation

private struct LyricEmbellishmentResponse: Decodable {
    let version: String
    let trackID: String
    let lyricsHash: String
    let mood: String
    let cues: [LyricEmbellishmentCue]
    let degraded: Bool?
    let degradedReason: String?

    var score: LyricEmbellishmentScore {
        LyricEmbellishmentScore(
            version: version,
            trackID: trackID,
            lyricsHash: lyricsHash,
            mood: mood,
            cues: cues
        )
    }
}

/// 露娜（Luna）微巧思演出客户端
actor LyricEmbellishmentClient {
    static let shared = LyricEmbellishmentClient()

    enum ClientError: LocalizedError {
        case unconfigured
        case noLyrics
        case invalidResponse
        case server(Int)
        case degraded(String?)

        var errorDescription: String? {
            switch self {
            case .unconfigured: "Luna 微巧思导演尚未配置"
            case .noLyrics: "当前歌曲没有可编排的逐行歌词"
            case .invalidResponse: "Luna 返回的微巧思格式异常"
            case .server(let status): "Luna 导演暂时不可用（\(status)）"
            case .degraded(let reason):
                switch reason {
                case "upstream_timeout": "Luna 编排超时，请稍后重试"
                case "upstream_error": "Luna 上游请求失败，请稍后重试"
                default: "Luna 本次没有生成有效微巧思"
                }
            }
        }
    }

    private let endpoint: URL?
    private let apiKey: String
    private let session: URLSession

    init(endpoint: URL? = nil, apiKey: String? = nil, session: URLSession? = nil) {
        self.endpoint = endpoint ?? Self.configuredEndpoint
        self.apiKey = apiKey ?? Self.bundleString(for: "BiliMusicMetadataAPIKey") ?? ""
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 30
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    /// 请求 Luna 对当前歌词进行智能微装帧编排
    func embellish(track: Track, lines: [PlayerEngine.LyricLine]) async throws -> LyricEmbellishmentScore {
        guard let endpoint, !apiKey.isEmpty else { throw ClientError.unconfigured }
        guard !lines.isEmpty else { throw ClientError.noLyrics }

        let selectedLines = Array(lines.prefix(120))
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(lines)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("BiliMusic/iOS-Embellisher", forHTTPHeaderField: "User-Agent")

        let payload = RequestPayload(
            trackID: track.key.description,
            title: track.title,
            artist: track.artist,
            duration: Double(track.duration),
            lyricsHash: lyricsHash,
            lines: selectedLines.enumerated().map { index, line in
                .init(
                    index: index,
                    text: line.text,
                    words: line.words.enumerated().map { wordIdx, word in
                        .init(index: wordIdx, text: word.text)
                    }
                )
            }
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw ClientError.server(http.statusCode)
        }

        let decoded: LyricEmbellishmentResponse
        do {
            decoded = try JSONDecoder().decode(LyricEmbellishmentResponse.self, from: data)
        } catch {
            throw ClientError.invalidResponse
        }

        if decoded.degraded == true {
            throw ClientError.degraded(decoded.degradedReason)
        }

        return decoded.score
    }

    private static var configuredEndpoint: URL? {
        if let raw = bundleString(for: "BILIMUSIC_LYRIC_EMBELLISH_API_URL"),
           let url = URL(string: raw) {
            return url
        }
        if let metadata = bundleString(for: "BiliMusicMetadataAPIURL"),
           let url = URL(string: metadata) {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.path = "/v1/lyrics/embellish"
            return components?.url
        }
        return URL(string: "https://bilimusic-metadata.mercari-email-sale-worker.workers.dev/v1/lyrics/embellish")
    }

    private static func bundleString(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct RequestPayload: Encodable {
        let trackID: String
        let title: String
        let artist: String
        let duration: Double
        let lyricsHash: String
        let lines: [LinePayload]

        struct LinePayload: Encodable {
            let index: Int
            let text: String
            let words: [WordPayload]
        }

        struct WordPayload: Encodable {
            let index: Int
            let text: String
        }
    }
}
