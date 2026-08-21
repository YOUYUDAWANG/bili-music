import Foundation

private struct LyricStageV3Response: Decodable {
    let version: String
    let directorVersion: String
    let trackID: String
    let lyricsHash: String
    let lineCount: Int
    let audioSummaryHash: String
    let stageBible: LyricStageBibleV3
    let sections: [LyricStageSectionV3]
    let scenes: [LyricStageSceneOverrideV3]
    let degraded: Bool?
    let degradedReason: String?
    let partial: Bool?
    let provider: String?
    let model: String?

    var direction: LyricStageDirectionV3 {
        LyricStageDirectionV3(
            version: version,
            directorVersion: directorVersion,
            trackID: trackID,
            lyricsHash: lyricsHash,
            lineCount: lineCount,
            audioSummaryHash: audioSummaryHash,
            stageBible: stageBible,
            sections: sections,
            scenes: scenes,
            partial: partial ?? false,
            provider: provider,
            model: model)
    }
}

actor LyricStageClientV3 {
    static let shared = LyricStageClientV3()

    enum ClientError: LocalizedError {
        case unconfigured
        case noLyrics
        case invalidResponse
        case unauthorized
        case server(Int)
        case degraded(String?)

        var errorDescription: String? {
            switch self {
            case .unconfigured: "Luna V3 歌词导演尚未配置"
            case .noLyrics: "当前歌曲没有可编排的同步歌词"
            case .invalidResponse: "Luna 返回的 V5.3 演出脚本未通过门禁"
            case .unauthorized: "Luna V3 认证失效，请重新注入访问令牌"
            case .server(let status): "Luna V3 歌词导演暂时不可用（\(status)）"
            case .degraded(let reason):
                switch reason {
                case "upstream_timeout": "Luna V3 编排超时，请稍后重试"
                case "upstream_error": "Luna V3 上游请求失败，请稍后重试"
                case "invalid_upstream_json", "invalid_director_output", "empty_or_invalid_scenes":
                    "Luna V3 返回的演出脚本无效"
                default: "Luna V3 本次没有生成有效演出"
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
            configuration.timeoutIntervalForRequest = 90
            configuration.timeoutIntervalForResource = 120
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    func direct(
        track: Track,
        lines: [PlayerEngine.LyricLine],
        audioSummary: LyricStageAudioSummaryV3
    ) async throws -> LyricStageDirectionV3 {
        guard let endpoint, !apiKey.isEmpty else { throw ClientError.unconfigured }
        guard !lines.isEmpty else { throw ClientError.noLyrics }
        let selectedLines = Array(lines.prefix(180))
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(lines)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("BiliMusic/iOS-Director-V3", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(
            RequestPayload(
                trackID: track.key.description,
                title: track.title,
                artist: track.artist,
                duration: track.duration,
                lyricsHash: lyricsHash,
                audioSummaryHash: audioSummary.summaryHash,
                audioSummary: .init(audioSummary),
                target: .init(device: "iPhone 17 Pro", os: "iOS 27"),
                lines: selectedLines.enumerated().map { index, line in
                    .init(
                        index: index,
                        from: line.from,
                        to: line.to,
                        text: line.text,
                        voiceRole: line.voiceRole.rawValue,
                        overlapGroup: line.overlapGroup)
                }))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw ClientError.degraded("upstream_timeout")
        }
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        if http.statusCode == 401 { throw ClientError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw ClientError.server(http.statusCode) }
        guard let result = try? JSONDecoder().decode(LyricStageV3Response.self, from: data) else {
            throw ClientError.invalidResponse
        }
        if result.degraded == true { throw ClientError.degraded(result.degradedReason) }
        guard let safe = result.direction.validated(
            trackID: track.key.description,
            lyricsHash: lyricsHash,
            lines: selectedLines,
            audioSummaryHash: audioSummary.summaryHash) else { throw ClientError.invalidResponse }
        return safe
    }

    private static var configuredEndpoint: URL? {
        if let explicit = bundleString(for: "BiliMusicLyricDirectorAPIURL"),
           var components = URLComponents(string: explicit) {
            components.path = "/v3/lyrics/direct"
            components.query = nil
            components.fragment = nil
            return components.url
        }
        guard let raw = bundleString(for: "BiliMusicMetadataAPIURL"),
              var components = URLComponents(string: raw) else { return nil }
        components.path = "/v3/lyrics/direct"
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
        let audioSummaryHash: String
        let audioSummary: AudioSummary
        let target: Target
        let lines: [Line]

        struct AudioSummary: Encodable {
            private static let maximumLineFeatureCount = 96

            let version: String
            let mapFingerprint: String
            let summaryHash: String
            let duration: Double
            let bpm: Double?
            let confidence: AudioPerformanceConfidence
            let sections: [LyricStageAudioSectionSummaryV3]
            let lines: [LyricStageAudioLineSummaryV3]

            init(_ summary: LyricStageAudioSummaryV3) {
                version = summary.version
                mapFingerprint = summary.mapFingerprint
                summaryHash = summary.summaryHash
                duration = summary.duration
                bpm = summary.bpm
                confidence = summary.confidence
                sections = summary.sections
                lines = Self.selectedLineFeatures(from: summary)
            }

            private static func selectedLineFeatures(
                from summary: LyricStageAudioSummaryV3
            ) -> [LyricStageAudioLineSummaryV3] {
                guard summary.lines.count > maximumLineFeatureCount else {
                    return summary.lines.sorted { $0.lineIndex < $1.lineIndex }
                }
                let boundaryIndices = Set(summary.sections.flatMap { section in
                    [section.lineFrom, section.lineTo].compactMap { $0 }
                })
                return summary.lines
                    .sorted { lhs, rhs in
                        let lhsBoundary = boundaryIndices.contains(lhs.lineIndex)
                        let rhsBoundary = boundaryIndices.contains(rhs.lineIndex)
                        if lhsBoundary != rhsBoundary { return lhsBoundary }
                        let lhsScore = structuralScore(lhs)
                        let rhsScore = structuralScore(rhs)
                        if lhsScore != rhsScore { return lhsScore > rhsScore }
                        return lhs.lineIndex < rhs.lineIndex
                    }
                    .prefix(maximumLineFeatureCount)
                    .sorted { $0.lineIndex < $1.lineIndex }
            }

            private static func structuralScore(_ line: LyricStageAudioLineSummaryV3) -> Double {
                let onset = line.onsetStrength.isFinite ? max(0, line.onsetStrength) : 0
                let energyChange = line.energyDelta.isFinite ? abs(line.energyDelta) : 0
                let longTone = line.longToneRatio.isFinite ? max(0, line.longToneRatio) : 0
                let onsetDensity = min(1, Double(max(0, line.onsetCount)) / 5)
                return onset * 0.42 + energyChange * 0.30 + longTone * 0.20 + onsetDensity * 0.08
            }
        }

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
            let overlapGroup: String?
        }
    }
}
