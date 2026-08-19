import Foundation

enum PrecisionLyricsHostConfiguration {
    static let overrideURLKey = "precisionLyricsHostURL"

    static var baseURL: URL? {
        candidateBaseURLs.first
    }

    static var candidateBaseURLs: [URL] {
        let override = UserDefaults.standard.string(forKey: overrideURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !override.isEmpty {
            return validURL(override).map { [$0] } ?? []
        }
        let keys = [
            "BiliMusicPrecisionLyricsHostURL",
            "BiliMusicPrecisionLyricsHostFallbackURL",
        ]
        var seen = Set<String>()
        return keys.compactMap { key in
            guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
                  let url = validURL(raw),
                  seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }
    }

    static var accessToken: String? {
        let infoToken = Bundle.main.object(forInfoDictionaryKey: "BiliMusicPrecisionLyricsHostToken") as? String
        let resourceToken = bundledSecrets?["AccessToken"] as? String
        let raw = (infoToken.flatMap(validToken) ?? resourceToken.flatMap(validToken)) ?? ""
        return raw.isEmpty ? nil : raw
    }

    static var isConfigured: Bool { baseURL != nil && accessToken != nil }

    private static var bundledSecrets: [String: Any]? {
        guard let url = Bundle.main.url(
            forResource: "BiliMusicPrecisionLyricsHost",
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

    private static func validURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return URL(string: trimmed)
    }
}

struct PrecisionLyricsHostQuality: Codable, Equatable, Sendable {
    let lineCount: Int
    let characterCount: Int
    let modelConsensusLines: Int
    let globalAnchorLines: Int
    let rhythmFallbackLines: Int
    let whisperXCharacterLines: Int
    let globalSampleCount: Int
    let globalCandidateCount: Int
    let globalMedianAbsoluteDeviation: Double
    let globalOffsetSeconds: Double
    let minimumCharacterSeconds: Double
    let medianCharacterSeconds: Double
    let elapsedSeconds: Double
    let qrcBytes: Int
}

struct PrecisionLyricsHostAlignment: Equatable, Sendable {
    let jobID: String
    let document: LyricsDocument
    let quality: PrecisionLyricsHostQuality
}

enum PrecisionLyricsHostError: LocalizedError, Equatable {
    case notConfigured
    case noLineSyncedLyrics
    case overlappingVocalsUnsupported
    case invalidResponse
    case hostUnreachable
    case server(String)
    case timedOut
    case qualityRejected(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "请先在设置里配置高精度歌词主机"
        case .noLineSyncedLyrics:
            "高精度主机目前需要已有逐行时间轴"
        case .overlappingVocalsUnsupported:
            "当前歌词包含并行声部，暂不允许主机结果覆盖"
        case .invalidResponse:
            "高精度主机返回了无法识别的结果"
        case .hostUnreachable:
            "无法连接高精度主机，请确认手机已开启 Tailscale 或连接家中 Wi-Fi"
        case let .server(message):
            "高精度主机生成失败：\(Self.conciseServerMessage(message))"
        case .timedOut:
            "高精度主机处理超时，任务仍可能在电脑上继续"
        case let .qualityRejected(reason):
            "主机结果未通过质量门禁：\(reason)"
        }
    }

    private static func conciseServerMessage(_ message: String) -> String {
        let lines = message
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let preferred = lines.reversed().first { line in
            ["ValueError:", "RuntimeError:", "OSError:", "TimeoutError:"]
                .contains { line.hasPrefix($0) }
        }
        let fallback = lines.last { line in
            !line.contains("FullyQualifiedErrorId") && !line.contains("CategoryInfo")
        }
        let summary = preferred ?? fallback ?? "未知错误"
        return String(summary.prefix(180))
    }
}

actor PrecisionLyricsHostClient {
    static let shared = PrecisionLyricsHostClient()
    static let schema = "bilimusic-precision-host-v1"
    typealias ProgressHandler = @Sendable (Double, String) -> Void

    private let session: URLSession
    private let configuredBaseURLs: [URL]?

    init(session: URLSession? = nil, baseURLs: [URL]? = nil) {
        configuredBaseURLs = baseURLs
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 90
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func healthCheck() async throws -> Int {
        (try await reachableBaseURL()).latencyMilliseconds
    }

    func align(
        audioURL: URL,
        track: Track,
        document: LyricsDocument,
        language: String,
        progress: @escaping ProgressHandler
    ) async throws -> PrecisionLyricsHostAlignment {
        guard PrecisionLyricsHostConfiguration.baseURL != nil,
              let token = PrecisionLyricsHostConfiguration.accessToken else {
            throw PrecisionLyricsHostError.notConfigured
        }
        guard document.hasLineSync, let lyric = document.lyric else {
            throw PrecisionLyricsHostError.noLineSyncedLyrics
        }
        if document.vocalLines?.isEmpty == false {
            throw PrecisionLyricsHostError.overlappingVocalsUnsupported
        }

        progress(0.01, "正在检查电脑连接")
        let baseURL = (try await reachableBaseURL()).url
        progress(0.02, "电脑已连接，正在提交任务")
        let payload = CreateJobRequest(
            schema: Self.schema,
            bvid: track.bvid,
            cid: track.cid,
            title: track.title,
            artist: track.artist,
            language: language,
            duration: track.duration,
            lyric: lyric,
            karaokeLyric: document.karaokeLyric)
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/jobs"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.authorize(&request, token: token)
        let (createData, createResponse) = try await session.data(for: request)
        try Self.validateHTTP(response: createResponse, data: createData)
        var status = try Self.decodeStatus(createData)

        if status.uploadRequired == true {
            progress(0.08, "正在上传本地音频")
            var upload = URLRequest(
                url: baseURL
                    .appendingPathComponent("v1/jobs")
                    .appendingPathComponent(status.jobID)
                    .appendingPathComponent("audio"))
            upload.httpMethod = "PUT"
            upload.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            Self.authorize(&upload, token: token)
            let (uploadData, uploadResponse) = try await session.upload(for: upload, fromFile: audioURL)
            try Self.validateHTTP(response: uploadResponse, data: uploadData)
            status = try Self.decodeStatus(uploadData)
        }

        let statusURL = baseURL
            .appendingPathComponent("v1/jobs")
            .appendingPathComponent(status.jobID)
        for attempt in 0..<150 {
            try Task.checkCancellation()
            if status.state == "completed", let result = status.result {
                progress(1, "高精度逐字歌词已生成")
                return try Self.alignment(
                    result: result,
                    source: document,
                    track: track)
            }
            if status.state == "failed" {
                throw PrecisionLyricsHostError.server(status.error ?? status.message)
            }
            let phaseProgress = min(0.95, 0.12 + Double(attempt) / 700)
            progress(phaseProgress, status.message)
            try await Task.sleep(for: .seconds(2))
            var poll = URLRequest(url: statusURL)
            Self.authorize(&poll, token: token)
            let (data, response) = try await session.data(for: poll)
            try Self.validateHTTP(response: response, data: data)
            status = try Self.decodeStatus(data)
        }
        throw PrecisionLyricsHostError.timedOut
    }

    private func reachableBaseURL() async throws -> (url: URL, latencyMilliseconds: Int) {
        let baseURLs = configuredBaseURLs ?? PrecisionLyricsHostConfiguration.candidateBaseURLs
        guard !baseURLs.isEmpty else { throw PrecisionLyricsHostError.notConfigured }
        for baseURL in baseURLs {
            var request = URLRequest(url: baseURL.appendingPathComponent("health"))
            request.timeoutInterval = 5
            let started = Date()
            do {
                let (data, response) = try await session.data(for: request)
                try Self.validateHTTP(response: response, data: data)
                let health = try JSONDecoder().decode(HealthResponse.self, from: data)
                guard health.schema == Self.schema, health.status == "ok" else { continue }
                return (baseURL, Int(Date().timeIntervalSince(started) * 1_000))
            } catch {
                continue
            }
        }
        throw PrecisionLyricsHostError.hostUnreachable
    }

    static func alignment(
        result: JobResult,
        source: LyricsDocument,
        track: Track
    ) throws -> PrecisionLyricsHostAlignment {
        guard result.schema == schema, result.bvid == track.bvid, !result.karaokeLyric.isEmpty else {
            throw PrecisionLyricsHostError.invalidResponse
        }
        let sourceResult = source.result
        let hostResult = LyricsSearchResult(
            provider: .precisionHost,
            id: result.jobID,
            title: sourceResult.title,
            artist: sourceResult.artist,
            album: sourceResult.album,
            duration: sourceResult.duration,
            artworkID: sourceResult.artworkID)
        let candidate = LyricsDocument(
            result: hostResult,
            lyric: source.lyric,
            translatedLyric: source.translatedLyric,
            romanizedLyric: source.romanizedLyric,
            karaokeLyric: result.karaokeLyric,
            karaokeTranslatedLyric: source.karaokeTranslatedLyric,
            versionScope: source.versionScope,
            timingKind: .word,
            timingNeedsConfirmation: source.timingNeedsConfirmation
                || result.quality.rhythmFallbackLines * 4 > result.quality.lineCount
                || result.quality.whisperXCharacterLines * 5 < result.quality.lineCount * 4,
            appliesToCurrentCover: true,
            followsPlayback: true,
            vocalLines: nil)
        try validateQuality(
            source: source,
            candidate: candidate,
            quality: result.quality,
            duration: track.duration)
        return PrecisionLyricsHostAlignment(
            jobID: result.jobID,
            document: candidate,
            quality: result.quality)
    }

    static func validateQuality(
        source: LyricsDocument,
        candidate: LyricsDocument,
        quality: PrecisionLyricsHostQuality,
        duration: Int
    ) throws {
        let sourceForLines = LyricsDocument(
            result: source.result,
            lyric: source.lyric,
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil,
            versionScope: source.versionScope,
            timingKind: .line,
            timingNeedsConfirmation: source.timingNeedsConfirmation,
            appliesToCurrentCover: source.appliesToCurrentCover,
            followsPlayback: true,
            vocalLines: nil)
        let sourceLines = LyricsParser.lines(from: sourceForLines, duration: duration)
        let candidateLines = LyricsParser.lines(from: candidate, duration: duration)
        let sourceRawLineCount = timestampedLRCLineCount(source.lyric)
        let candidateRawLineCount = millisecondQRCLineCount(candidate.karaokeLyric)
        guard sourceRawLineCount > 0,
              sourceRawLineCount == candidateRawLineCount,
              quality.lineCount == candidateRawLineCount else {
            throw PrecisionLyricsHostError.qualityRejected(
                "原始时间轴行数不一致（原词 \(sourceRawLineCount) / QRC \(candidateRawLineCount) / 主机 \(quality.lineCount)）")
        }
        guard !sourceLines.isEmpty, sourceLines.count == candidateLines.count else {
            throw PrecisionLyricsHostError.qualityRejected(
                "显示行数不一致（原词 \(sourceLines.count) / 结果 \(candidateLines.count)）")
        }
        guard zip(sourceLines, candidateLines).allSatisfy({ $0.text == $1.text }) else {
            throw PrecisionLyricsHostError.qualityRejected("歌词全文没有被完整保留")
        }
        guard quality.characterCount > 0,
              quality.whisperXCharacterLines * 2 >= quality.lineCount else {
            throw PrecisionLyricsHostError.qualityRejected("独立字符复核覆盖不足")
        }
        guard quality.globalSampleCount >= 6,
              quality.globalCandidateCount >= quality.globalSampleCount,
              quality.globalMedianAbsoluteDeviation.isFinite,
              quality.globalMedianAbsoluteDeviation <= 1 else {
            throw PrecisionLyricsHostError.qualityRejected("整曲位移共识不稳定")
        }
        guard quality.rhythmFallbackLines * 100 <= quality.lineCount * 35 else {
            throw PrecisionLyricsHostError.qualityRejected("逐行模型回退过多")
        }
        var previousLine: LyricsLinePayload?
        for line in candidateLines {
            let sharesOverlapGroup = previousLine?.overlapGroup != nil
                && previousLine?.overlapGroup == line.overlapGroup
                && abs((previousLine?.from ?? 0) - line.from) <= 0.08
            guard line.from.isFinite, line.to.isFinite,
                  previousLine == nil || line.from > (previousLine?.from ?? -Double.infinity) || sharesOverlapGroup,
                  line.to > line.from,
                  !line.words.isEmpty else {
                throw PrecisionLyricsHostError.qualityRejected("时间轴不连续")
            }
            var previousWordStart = line.from - 0.001
            for word in line.words {
                guard word.from.isFinite, word.to.isFinite,
                      word.from >= previousWordStart,
                      word.to > word.from,
                      word.from >= line.from - 0.02,
                      word.to <= line.to + 0.02 else {
                    throw PrecisionLyricsHostError.qualityRejected("逐字时间不单调")
                }
                previousWordStart = word.from
            }
            previousLine = line
        }
    }

    private static func timestampedLRCLineCount(_ lyric: String?) -> Int {
        guard let lyric else { return 0 }
        let timestamp = #"^\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]"#
        return lyric.split(whereSeparator: { $0.isNewline }).reduce(into: 0) { count, rawLine in
            let line = String(rawLine)
            guard let range = line.range(of: timestamp, options: .regularExpression) else { return }
            let body = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { count += 1 }
        }
    }

    private static func millisecondQRCLineCount(_ lyric: String?) -> Int {
        guard let lyric else { return 0 }
        let timestamp = #"^\[\d+,\d+\]"#
        return lyric.split(whereSeparator: { $0.isNewline }).reduce(into: 0) { count, rawLine in
            if String(rawLine).range(of: timestamp, options: .regularExpression) != nil {
                count += 1
            }
        }
    }

    private static func authorize(_ request: inout URLRequest, token: String) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    }

    private static func decodeStatus(_ data: Data) throws -> JobStatus {
        do {
            let status = try JSONDecoder().decode(JobStatus.self, from: data)
            guard status.schema == schema, !status.jobID.isEmpty else {
                throw PrecisionLyricsHostError.invalidResponse
            }
            return status
        } catch let error as PrecisionLyricsHostError {
            throw error
        } catch {
            throw PrecisionLyricsHostError.invalidResponse
        }
    }

    private static func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PrecisionLyricsHostError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw PrecisionLyricsHostError.server(envelope?.error ?? "HTTP \(http.statusCode)")
        }
    }

    private struct CreateJobRequest: Encodable {
        let schema: String
        let bvid: String
        let cid: Int?
        let title: String
        let artist: String
        let language: String
        let duration: Int
        let lyric: String
        let karaokeLyric: String?
    }

    struct JobResult: Codable, Equatable, Sendable {
        let schema: String
        let jobID: String
        let bvid: String
        let karaokeLyric: String
        let quality: PrecisionLyricsHostQuality

        private enum CodingKeys: String, CodingKey {
            case schema, bvid, karaokeLyric, quality
            case jobID = "jobId"
        }
    }

    private struct JobStatus: Decodable {
        let schema: String
        let jobID: String
        let state: String
        let message: String
        let error: String?
        let uploadRequired: Bool?
        let result: JobResult?

        private enum CodingKeys: String, CodingKey {
            case schema, state, message, error, uploadRequired, result
            case jobID = "jobId"
        }
    }

    private struct HealthResponse: Decodable {
        let schema: String
        let status: String
    }

    private struct ErrorEnvelope: Decodable {
        let error: String
    }
}
