import Foundation

enum LyricStageRequestDegradationV4: String, Equatable, Sendable {
    case none
    case fewerLineDetails
    case fewerMoments
    case noContours
    case outlineOnly
    case outlineOnlyOverSoftBudget
}

struct PreparedLyricStageRequestV4 {
    let request: URLRequest
    let audioScore: AudioStructureScoreV4
    let bodyByteCount: Int
    let degradation: LyricStageRequestDegradationV4
}

struct LyricStageGenerationResultV4: Equatable, Sendable {
    let direction: LyricStageDirectionV4
    let audioScore: AudioStructureScoreV4
    let requestBodyByteCount: Int
    let degradation: LyricStageRequestDegradationV4
}

actor LyricStageClientV4 {
    static let shared = LyricStageClientV4()

    static let softRequestBudgetBytes = 88 * 1_024
    static let workerHardRequestLimitBytes = 98_304

    enum ClientError: LocalizedError, Equatable {
        case unconfigured
        case noLyrics
        case tooManyLines
        case invalidLyrics
        case invalidAudioScore
        case completeLyricsExceedHardLimit(Int)
        case invalidResponse
        case unauthorized
        case server(Int)
        case degraded(String?)

        var errorDescription: String? {
            switch self {
            case .unconfigured: "Gemini V4 歌词导演尚未配置"
            case .noLyrics: "当前歌曲没有可编排的同步歌词"
            case .tooManyLines: "完整歌词超过 V4 的 180 行合同上限，已保留本地舞台"
            case .invalidLyrics: "歌词正文或时间未通过 V4 请求门禁"
            case .invalidAudioScore: "V4 音频结构事实未通过本地门禁"
            case .completeLyricsExceedHardLimit:
                "完整歌词超过 V4 请求大小上限，已保留本地舞台"
            case .invalidResponse: "Gemini V4 场景配方未通过本地门禁"
            case .unauthorized: "Gemini V4 认证失效，请重新注入访问令牌"
            case .server(let status): "Gemini V4 歌词导演暂时不可用（\(status)）"
            case .degraded(let reason):
                reason == "upstream_timeout" ? "Gemini V4 编排超时，请稍后重试" : "Gemini V4 本次没有生成有效场景配方"
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
            configuration.timeoutIntervalForRequest = 90
            configuration.timeoutIntervalForResource = 120
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    func direct(
        track: Track,
        lines: [PlayerEngine.LyricLine],
        audioScore: AudioStructureScoreV4
    ) async throws -> LyricStageGenerationResultV4 {
        let prepared = try prepareRequest(track: track, lines: lines, audioScore: audioScore)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: prepared.request)
        } catch let error as URLError where error.code == .timedOut {
            throw ClientError.degraded("upstream_timeout")
        }
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        if http.statusCode == 401 { throw ClientError.unauthorized }
        if http.statusCode == 413 {
            throw ClientError.completeLyricsExceedHardLimit(prepared.bodyByteCount)
        }
        guard (200..<300).contains(http.statusCode) else { throw ClientError.server(http.statusCode) }
        guard let wire = try? JSONDecoder().decode(LyricStageResponseWireV4.self, from: data) else {
            throw ClientError.invalidResponse
        }
        if wire.degraded == true { throw ClientError.degraded(wire.degradedReason) }
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(lines)
        guard let direction = LyricStageDirectorV4.validateWire(
            wire,
            trackID: track.key.description,
            lyricsHash: lyricsHash,
            lines: lines,
            audioScore: prepared.audioScore) else { throw ClientError.invalidResponse }
        return LyricStageGenerationResultV4(
            direction: direction,
            audioScore: prepared.audioScore,
            requestBodyByteCount: prepared.bodyByteCount,
            degradation: prepared.degradation)
    }

    func prepareRequest(
        track: Track,
        lines: [PlayerEngine.LyricLine],
        audioScore: AudioStructureScoreV4
    ) throws -> PreparedLyricStageRequestV4 {
        guard let endpoint, !apiKey.isEmpty else { throw ClientError.unconfigured }
        guard !lines.isEmpty else { throw ClientError.noLyrics }
        guard lines.count <= 180 else { throw ClientError.tooManyLines }
        guard lines.allSatisfy({ line in
            line.from.isFinite
                && line.to.isFinite
                && line.from >= 0
                && line.to > line.from
                && !line.text.isEmpty
        }) else { throw ClientError.invalidLyrics }
        guard audioScore.validated(lineCount: lines.count) != nil else { throw ClientError.invalidAudioScore }

        let candidates: [(Int, Int, Bool, LyricStageRequestDegradationV4)] = [
            (64, 32, true, .none),
            (48, 32, true, .fewerLineDetails),
            (32, 32, true, .fewerLineDetails),
            (16, 32, true, .fewerLineDetails),
            (16, 24, true, .fewerMoments),
            (16, 16, true, .fewerMoments),
            (16, 8, true, .fewerMoments),
            (16, 0, true, .fewerMoments),
            (16, 0, false, .noContours),
            (8, 0, false, .noContours),
            (0, 0, false, .outlineOnly),
        ]
        var smallest: (Data, AudioStructureScoreV4, LyricStageRequestDegradationV4)?
        for candidate in candidates {
            let score = audioScore.deterministicallyLimited(
                lineDetailCount: candidate.0,
                momentCount: candidate.1,
                includeContours: candidate.2)
            let body = try requestBody(track: track, lines: lines, audioScore: score)
            if smallest == nil || body.count < smallest!.0.count {
                smallest = (body, score, candidate.3)
            }
            if body.count <= Self.softRequestBudgetBytes {
                return preparedRequest(
                    endpoint: endpoint,
                    body: body,
                    audioScore: score,
                    degradation: candidate.3)
            }
        }
        guard let smallest else { throw ClientError.invalidAudioScore }
        guard smallest.0.count <= Self.workerHardRequestLimitBytes else {
            throw ClientError.completeLyricsExceedHardLimit(smallest.0.count)
        }
        return preparedRequest(
            endpoint: endpoint,
            body: smallest.0,
            audioScore: smallest.1,
            degradation: .outlineOnlyOverSoftBudget)
    }

    private func preparedRequest(
        endpoint: URL,
        body: Data,
        audioScore: AudioStructureScoreV4,
        degradation: LyricStageRequestDegradationV4
    ) -> PreparedLyricStageRequestV4 {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("BiliMusic/iOS-Director-V4", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120
        request.httpBody = body
        return PreparedLyricStageRequestV4(
            request: request,
            audioScore: audioScore,
            bodyByteCount: body.count,
            degradation: degradation)
    }

    private func requestBody(
        track: Track,
        lines: [PlayerEngine.LyricLine],
        audioScore: AudioStructureScoreV4
    ) throws -> Data {
        let detailedLines = Set(audioScore.lineDetails.map(\.lineIndex))
        let payload = RequestPayload(
            version: LyricStagePlanV4Version.current,
            trackID: track.key.description,
            title: track.title,
            artist: track.artist,
            duration: track.duration,
            lyricsHash: LyricPerformanceFingerprint.lyricsHash(lines),
            audioScoreHash: audioScore.fingerprint,
            audioScore: audioScore,
            lines: lines.enumerated().map { index, line in
                RequestLine(
                    index: index,
                    from: line.from,
                    to: line.to,
                    text: line.text,
                    voiceRole: line.voiceRole.rawValue,
                    overlapGroup: line.overlapGroup,
                    hasRealWordTiming: !line.words.isEmpty,
                    tokens: detailedLines.contains(index)
                        ? LyricStageTokenizer.tokens(for: line).map {
                            RequestToken(
                                index: $0.id,
                                glyphFrom: $0.glyphRange.lowerBound,
                                glyphTo: $0.glyphRange.upperBound)
                        }
                        : [] )
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    private static var configuredEndpoint: URL? {
        if let explicit = bundleString(for: "BiliMusicLyricDirectorAPIURL"),
           var components = URLComponents(string: explicit) {
            components.path = "/v4/lyrics/direct"
            components.query = nil
            components.fragment = nil
            return components.url
        }
        guard let raw = bundleString(for: "BiliMusicMetadataAPIURL"),
              var components = URLComponents(string: raw) else { return nil }
        components.path = "/v4/lyrics/direct"
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
        let version: String
        let trackID: String
        let title: String
        let artist: String
        let duration: Int
        let lyricsHash: String
        let audioScoreHash: String
        let audioScore: AudioStructureScoreV4
        let lines: [RequestLine]
    }

    private struct RequestLine: Encodable {
        let index: Int
        let from: Double
        let to: Double
        let text: String
        let voiceRole: String
        let overlapGroup: String?
        let hasRealWordTiming: Bool
        let tokens: [RequestToken]
    }

    private struct RequestToken: Encodable {
        let index: Int
        let glyphFrom: Int
        let glyphTo: Int

        func encode(to encoder: Encoder) throws {
            var values = encoder.unkeyedContainer()
            try values.encode(index)
            try values.encode(glyphFrom)
            try values.encode(glyphTo)
        }
    }
}
