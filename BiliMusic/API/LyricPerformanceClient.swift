import Foundation

private struct LyricPerformanceResponse: Decodable {
    let version: String
    let directorVersion: String
    let trackID: String
    let lyricsHash: String
    let lineCount: Int
    let mood: String
    let compositions: [LyricTextComposition]
    let scenes: [LyricPerformanceScene]
    let wordCues: [LyricWordCue]?
    let stageBible: LyricStageBible?
    let stageDirectives: [LyricStageDirective]?
    let degraded: Bool
    let degradedReason: String?

    var score: LyricPerformanceScore {
        LyricPerformanceScore(
            version: version,
            directorVersion: directorVersion,
            trackID: trackID,
            lyricsHash: lyricsHash,
            lineCount: lineCount,
            mood: mood,
            compositions: compositions,
            scenes: scenes,
            wordCues: wordCues ?? [],
            stageBible: stageBible,
            stageDirectives: stageDirectives ?? []
        )
    }
}

actor LyricPerformanceClient {
    static let shared = LyricPerformanceClient()

    enum ClientError: LocalizedError {
        case unconfigured
        case noLyrics
        case invalidResponse
        case server(Int)
        case degraded(String?)

        var errorDescription: String? {
            switch self {
            case .unconfigured: "Luna 歌词导演尚未配置"
            case .noLyrics: "当前歌曲没有可编排的逐行歌词"
            case .invalidResponse: "Luna 返回的演出脚本格式异常"
            case .server(let status): "Luna 歌词导演暂时不可用（\(status)）"
            case .degraded(let reason):
                switch reason {
                case "upstream_timeout": "Luna 编排超时，请稍后重试"
                case "upstream_error": "Luna 上游请求失败，请稍后重试"
                case "invalid_upstream_json", "invalid_director_output": "Luna 返回的演出脚本无效"
                default: "Luna 本次没有生成有效演出"
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
            configuration.timeoutIntervalForRequest = 45
            configuration.timeoutIntervalForResource = 55
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    func direct(track: Track, lines: [PlayerEngine.LyricLine]) async throws -> LyricPerformanceScore {
        guard let endpoint, !apiKey.isEmpty else { throw ClientError.unconfigured }
        guard !lines.isEmpty else { throw ClientError.noLyrics }
        let selectedLines = Array(lines.prefix(180))
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(lines)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("BiliMusic/iOS-Director", forHTTPHeaderField: "User-Agent")
        let payload = RequestPayload(
            trackID: track.key.description,
            title: track.title,
            artist: track.artist,
            duration: track.duration,
            lyricsHash: lyricsHash,
            target: .init(device: "iPhone 17 Pro", os: "iOS 27"),
            lines: selectedLines.enumerated().map { index, line in
                .init(
                    index: index,
                    from: line.from,
                    to: line.to,
                    text: line.text,
                    voiceRole: line.voiceRole.rawValue,
                    layerID: line.layerID,
                    overlapGroup: line.overlapGroup,
                    words: line.words.sorted { $0.from < $1.from }.enumerated().map { wordIndex, word in
                        .init(index: wordIndex, from: word.from, to: word.to, text: word.text)
                    })
            }
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ClientError.server(http.statusCode) }
        let result = try JSONDecoder().decode(LyricPerformanceResponse.self, from: data)
        guard !result.degraded else { throw ClientError.degraded(result.degradedReason) }
        guard let safe = result.score.validated(
            trackID: track.key.description,
            lyricsHash: lyricsHash,
            lineCount: lines.count,
            wordCounts: LyricPerformanceFingerprint.wordCounts(lines)
        ) else { throw ClientError.invalidResponse }
        return safe
    }

    private static var configuredEndpoint: URL? {
        if let explicit = bundleString(for: "BiliMusicLyricDirectorAPIURL"),
           let url = URL(string: explicit) {
            return url
        }
        guard let raw = bundleString(for: "BiliMusicMetadataAPIURL"),
              var components = URLComponents(string: raw) else { return nil }
        components.path = "/v1/lyrics/direct"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func bundleString(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private struct RequestPayload: Encodable {
        let trackID: String
        let title: String
        let artist: String
        let duration: Int
        let lyricsHash: String
        let target: Target
        let lines: [Line]

        struct Target: Encodable {
            let device: String
            let os: String
        }

        struct Line: Encodable {
            let index: Int
            let from: Double
            let to: Double
            let text: String
            let voiceRole: String
            let layerID: String
            let overlapGroup: String?
            let words: [Word]

            struct Word: Encodable {
                let index: Int
                let from: Double
                let to: Double
                let text: String
            }
        }
    }
}
