import CommonCrypto
import Compression
import CryptoKit
import Foundation

enum LyricsProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case netease
    case kugou
    case tencent
    case biliSubtitle
    case amll
    case vocadb
    case lrclib
    case imported
    case precisionHost

    var id: String { rawValue }

    static var catalogCases: [LyricsProvider] { [.netease, .kugou, .tencent, .lrclib, .vocadb] }

    var displayName: String {
        switch self {
        case .netease: "网易云"
        case .kugou: "酷狗"
        case .tencent: "QQ 音乐"
        case .biliSubtitle: "B 站字幕"
        case .amll: "AMLL 逐字"
        case .vocadb: "VocaDB"
        case .lrclib: "LRCLIB"
        case .imported: "本地导入"
        case .precisionHost: "高精度主机"
        }
    }

    /// 已停用，仅用于识别并丢弃旧缓存。
    var isRetired: Bool { self == .biliSubtitle }
}

enum LyricsVersionScope: String, Codable, Sendable {
    case exactCover
    case sameRecording
    case canonicalOriginal
    case textOnlyFallback
    case manual
}

enum LyricsTimingKind: String, Codable, Sendable {
    case word
    case line
    case none
}

enum LyricVoiceRole: String, Codable, Sendable {
    case lead
    case backing
    case duetA
    case duetB
    case together

    var isSecondary: Bool {
        self == .backing
    }
}

enum LyricsSearchScope: String, Sendable {
    case automatic
    case coverVersion
    case originalRecording
}

struct LyricsSearchResult: Codable, Hashable, Identifiable, Sendable {
    let provider: LyricsProvider
    let id: String
    let title: String
    let artist: String
    let album: String?
    let duration: Int?
    let artworkID: String?
    var timingKindHint: LyricsTimingKind? = nil

    var stableID: String { "\(provider.rawValue):\(id)" }
}

struct LyricsExternalHit: Sendable {
    var result: LyricsSearchResult
    var document: LyricsDocument
}

struct LyricsDocument: Equatable, Sendable {
    let result: LyricsSearchResult
    let lyric: String?
    let translatedLyric: String?
    let romanizedLyric: String?
    let karaokeLyric: String?
    let karaokeTranslatedLyric: String?
    var versionScope: LyricsVersionScope
    var timingKind: LyricsTimingKind
    var timingNeedsConfirmation: Bool
    var appliesToCurrentCover: Bool
    var followsPlayback: Bool
    var vocalLines: [LyricsVocalLine]?

    init(
        result: LyricsSearchResult,
        lyric: String?,
        translatedLyric: String?,
        romanizedLyric: String?,
        karaokeLyric: String?,
        karaokeTranslatedLyric: String?,
        versionScope: LyricsVersionScope = .sameRecording,
        timingKind: LyricsTimingKind? = nil,
        timingNeedsConfirmation: Bool = false,
        appliesToCurrentCover: Bool = true,
        followsPlayback: Bool? = nil,
        vocalLines: [LyricsVocalLine]? = nil
    ) {
        self.result = result
        self.lyric = lyric
        self.translatedLyric = translatedLyric
        self.romanizedLyric = romanizedLyric
        self.karaokeLyric = karaokeLyric
        self.karaokeTranslatedLyric = karaokeTranslatedLyric
        self.versionScope = versionScope
        self.timingKind = timingKind ?? Self.inferredTimingKind(
            karaokeLyric: karaokeLyric,
            lyric: lyric)
        self.timingNeedsConfirmation = timingNeedsConfirmation
        self.appliesToCurrentCover = appliesToCurrentCover
        self.followsPlayback = followsPlayback ?? (self.timingKind != .none)
        self.vocalLines = vocalLines
    }

    var preferredMainLyric: String? {
        Self.firstText(karaokeLyric, lyric)
    }

    var preferredTranslationLyric: String? {
        Self.firstText(karaokeTranslatedLyric, translatedLyric)
    }

    var hasLyrics: Bool { preferredMainLyric != nil }

    var hasWordSync: Bool { Self.firstText(karaokeLyric) != nil }
    var hasLineSync: Bool { lyric.map(Self.containsLRCTimestamps) ?? false }
    var hasTranslation: Bool { Self.firstText(translatedLyric, karaokeTranslatedLyric) != nil }
    var hasRomanization: Bool { Self.firstText(romanizedLyric) != nil }

    var bannerText: String? {
        switch versionScope {
        case .exactCover:
            return timingKind == .none ? "翻唱版 · 纯文本" : "翻唱版 · 精确同步"
        case .sameRecording:
            return nil
        case .canonicalOriginal:
            return timingNeedsConfirmation ? "原唱歌词 · 时间轴待确认" : "原唱歌词"
        case .textOnlyFallback:
            if timingKind == .none { return "纯文本歌词" }
            return followsPlayback ? "歌词 · 待确认" : "歌词 · 不跟随播放"
        case .manual:
            return result.provider == .imported ? "本地手动歌词" : nil
        }
    }

    func applying(policy: LyricsTimingPolicy) -> LyricsDocument {
        var copy = self
        copy.versionScope = policy.scope
        copy.timingKind = policy.timingKind
        copy.timingNeedsConfirmation = policy.needsConfirmation
        copy.appliesToCurrentCover = policy.appliesToCurrentCover
        copy.followsPlayback = policy.followsPlayback
        return copy
    }

    func restoringPlaybackTiming(as scope: LyricsVersionScope = .manual) -> LyricsDocument {
        var copy = self
        copy.versionScope = scope
        copy.timingKind = Self.inferredTimingKind(karaokeLyric: karaokeLyric, lyric: lyric)
        copy.timingNeedsConfirmation = false
        copy.appliesToCurrentCover = true
        copy.followsPlayback = copy.timingKind != .none
        return copy
    }

    static func containsLRCTimestamps(_ text: String) -> Bool {
        text.range(of: #"\[\d{1,2}:\d{2}"#, options: .regularExpression) != nil
    }

    private static func inferredTimingKind(karaokeLyric: String?, lyric: String?) -> LyricsTimingKind {
        if firstText(karaokeLyric) != nil { return .word }
        if let lyric, containsLRCTimestamps(lyric) { return .line }
        return .none
    }

    private static func firstText(_ values: String?...) -> String? {
        values.lazy.compactMap { value in
            let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }.first
    }
}

extension LyricsDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case result, lyric, translatedLyric, romanizedLyric, karaokeLyric, karaokeTranslatedLyric
        case versionScope, timingKind, timingNeedsConfirmation, appliesToCurrentCover, followsPlayback, vocalLines
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        result = try container.decode(LyricsSearchResult.self, forKey: .result)
        lyric = try container.decodeIfPresent(String.self, forKey: .lyric)
        translatedLyric = try container.decodeIfPresent(String.self, forKey: .translatedLyric)
        romanizedLyric = try container.decodeIfPresent(String.self, forKey: .romanizedLyric)
        karaokeLyric = try container.decodeIfPresent(String.self, forKey: .karaokeLyric)
        karaokeTranslatedLyric = try container.decodeIfPresent(String.self, forKey: .karaokeTranslatedLyric)
        versionScope = try container.decodeIfPresent(LyricsVersionScope.self, forKey: .versionScope) ?? .sameRecording
        timingKind = try container.decodeIfPresent(LyricsTimingKind.self, forKey: .timingKind)
            ?? Self.inferredTimingKind(karaokeLyric: karaokeLyric, lyric: lyric)
        timingNeedsConfirmation = try container.decodeIfPresent(Bool.self, forKey: .timingNeedsConfirmation) ?? false
        appliesToCurrentCover = try container.decodeIfPresent(Bool.self, forKey: .appliesToCurrentCover) ?? true
        followsPlayback = try container.decodeIfPresent(Bool.self, forKey: .followsPlayback)
            ?? (timingKind != .none)
        vocalLines = try container.decodeIfPresent([LyricsVocalLine].self, forKey: .vocalLines)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(result, forKey: .result)
        try container.encodeIfPresent(lyric, forKey: .lyric)
        try container.encodeIfPresent(translatedLyric, forKey: .translatedLyric)
        try container.encodeIfPresent(romanizedLyric, forKey: .romanizedLyric)
        try container.encodeIfPresent(karaokeLyric, forKey: .karaokeLyric)
        try container.encodeIfPresent(karaokeTranslatedLyric, forKey: .karaokeTranslatedLyric)
        try container.encode(versionScope, forKey: .versionScope)
        try container.encode(timingKind, forKey: .timingKind)
        try container.encode(timingNeedsConfirmation, forKey: .timingNeedsConfirmation)
        try container.encode(appliesToCurrentCover, forKey: .appliesToCurrentCover)
        try container.encode(followsPlayback, forKey: .followsPlayback)
        try container.encodeIfPresent(vocalLines, forKey: .vocalLines)
    }
}

struct LyricsWordPayload: Codable, Equatable, Sendable {
    let from: Double
    let to: Double
    let text: String
}

struct LyricsLinePayload: Equatable, Sendable {
    let from: Double
    let to: Double
    let text: String
    let translation: String?
    let words: [LyricsWordPayload]
    let voiceRole: LyricVoiceRole
    let layerID: String
    let overlapGroup: String?

    init(
        from: Double,
        to: Double,
        text: String,
        translation: String?,
        words: [LyricsWordPayload],
        voiceRole: LyricVoiceRole = .lead,
        layerID: String = "lead",
        overlapGroup: String? = nil
    ) {
        self.from = from
        self.to = to
        self.text = text
        self.translation = translation
        self.words = words
        self.voiceRole = voiceRole
        self.layerID = layerID
        self.overlapGroup = overlapGroup
    }
}

struct LyricsVocalLine: Codable, Equatable, Sendable {
    let from: Double
    let to: Double
    let text: String
    let translation: String?
    let words: [LyricsWordPayload]
    let voiceRole: LyricVoiceRole
    let layerID: String
    let overlapGroup: String?
}

struct AutomaticLyricsMatch: Sendable {
    let keyword: String
    let provider: LyricsProvider
    let candidates: [LyricsSearchResult]
    let document: LyricsDocument?
}

protocol LyricsCatalogSearching: Sendable {
    func search(keyword: String, provider: LyricsProvider) async throws -> [LyricsSearchResult]
    func fetchLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument
}

actor MetingLyricsClient: LyricsCatalogSearching {
    enum ClientError: LocalizedError {
        case invalidResponse
        case server(String)
        case noLyrics

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "歌词服务返回格式异常"
            case .server(let message): message
            case .noLyrics: "没有找到可用歌词"
            }
        }
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    static func preferredProvider(for title: String) -> LyricsProvider {
        let lower = title.lowercased()
        return lower.contains("周杰伦") || lower.contains("jay") ? .kugou : .netease
    }

    /// 只在同一版本范围内比较标题/歌手/时长，不把翻唱和原唱混成一个模糊分。
    static func rankedCandidates(
        _ candidates: [LyricsSearchResult],
        keyword: String,
        originalArtists: [String] = [],
        coverPerformers: [String] = [],
        duration: Int? = nil,
        preferCover: Bool = false
    ) -> [LyricsSearchResult] {
        let intent = searchIntent(from: keyword)
        return candidates.enumerated().sorted { lhs, rhs in
            let leftScope = LyricsVersionClassifier.scope(
                for: lhs.element,
                originalArtists: originalArtists,
                coverPerformers: coverPerformers,
                isCoverSearch: preferCover)
            let rightScope = LyricsVersionClassifier.scope(
                for: rhs.element,
                originalArtists: originalArtists,
                coverPerformers: coverPerformers,
                isCoverSearch: preferCover)
            let leftRank = LyricsVersionClassifier.rank(leftScope, preferCover: preferCover)
            let rightRank = LyricsVersionClassifier.rank(rightScope, preferCover: preferCover)
            if leftRank != rightRank { return leftRank < rightRank }
            let leftHasVerifiedWords = hasReliableWordTiming(
                lhs.element,
                expectedDuration: duration)
            let rightHasVerifiedWords = hasReliableWordTiming(
                rhs.element,
                expectedDuration: duration)
            if leftHasVerifiedWords != rightHasVerifiedWords { return leftHasVerifiedWords }
            let leftScore = candidateScore(
                lhs.element,
                intent: intent,
                focusArtists: preferCover ? coverPerformers : originalArtists,
                duration: duration)
            let rightScore = candidateScore(
                rhs.element,
                intent: intent,
                focusArtists: preferCover ? coverPerformers : originalArtists,
                duration: duration)
            return leftScore == rightScore ? lhs.offset < rhs.offset : leftScore > rightScore
        }.map(\.element)
    }

    /// A word-timed catalog entry is reliable for priority only when its recording duration is
    /// compatible with the current track. Unknown durations retain the existing word preference;
    /// a known large mismatch remains visible in manual search without being promoted as exact.
    static func hasReliableWordTiming(
        _ candidate: LyricsSearchResult,
        expectedDuration: Int?
    ) -> Bool {
        guard candidate.timingKindHint == .word else { return false }
        guard let expectedDuration, expectedDuration > 0,
              let candidateDuration = candidate.duration, candidateDuration > 0 else {
            return true
        }
        return abs(candidateDuration - expectedDuration) <= 4
    }

    /// 手动搜索：多源去重后按同一套标题/歌手/时长规则排序，保留各平台条目。
    static func aggregatedCandidates(
        _ batches: [[LyricsSearchResult]],
        keyword: String,
        originalArtists: [String] = [],
        coverPerformers: [String] = [],
        duration: Int? = nil,
        preferCover: Bool = false
    ) -> [LyricsSearchResult] {
        var seen = Set<String>()
        let pooled = batches.flatMap { $0 }.filter { seen.insert($0.stableID).inserted }
        return rankedCandidates(
            pooled,
            keyword: keyword,
            originalArtists: originalArtists,
            coverPerformers: coverPerformers,
            duration: duration,
            preferCover: preferCover)
    }

    func resolveSearchKeyword(for track: Track) async -> String {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, !artist.isEmpty { return "\(title)-\(artist)" }
        if !title.isEmpty { return title }

        let parsed = TrackTitleParser.parseSongDetailed(from: track.title, fallbackArtist: track.artist)
        return parsed.title.isEmpty ? track.title : parsed.title
    }

    func automaticLyrics(for track: Track) async throws -> AutomaticLyricsMatch {
        let keyword = await resolveSearchKeyword(for: track)
        let provider = Self.preferredProvider(for: track.title + " " + keyword)
        let candidates = Self.rankedCandidates(
            try await search(keyword: keyword, provider: provider),
            keyword: keyword)
        for candidate in candidates {
            if let document = try? await fetchLyrics(for: candidate), document.hasLyrics {
                return AutomaticLyricsMatch(
                    keyword: keyword,
                    provider: provider,
                    candidates: candidates,
                    document: document)
            }
        }
        return AutomaticLyricsMatch(
            keyword: keyword,
            provider: provider,
            candidates: candidates,
            document: nil)
    }

    func search(keyword: String, provider: LyricsProvider) async throws -> [LyricsSearchResult] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        switch provider {
        case .netease: return try await searchNetease(trimmed)
        case .kugou: return try await searchKugou(trimmed)
        case .tencent: return try await searchTencent(trimmed)
        case .biliSubtitle, .amll, .vocadb, .lrclib, .imported, .precisionHost:
            return []
        }
    }

    func fetchLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        switch result.provider {
        case .netease: return try await fetchNeteaseLyrics(for: result)
        case .kugou: return try await fetchKugouLyrics(for: result)
        case .tencent: return try await fetchTencentLyrics(for: result)
        case .biliSubtitle, .amll, .vocadb, .lrclib, .imported, .precisionHost:
            throw ClientError.noLyrics
        }
    }

    // MARK: - NetEase

    private func searchNetease(_ keyword: String) async throws -> [LyricsSearchResult] {
        let json = try await neteaseEAPI(path: "/api/cloudsearch/pc", body: [
            "s": keyword,
            "type": 1,
            "limit": 10,
            "offset": 0,
            "total": "true",
        ])
        let songs = ((json["result"] as? [String: Any])?["songs"] as? [[String: Any]]) ?? []
        return songs.compactMap { song in
            guard let id = Self.string(song["id"]), !id.isEmpty else { return nil }
            let album = song["al"] as? [String: Any] ?? song["album"] as? [String: Any]
            let artists = song["ar"] as? [[String: Any]] ?? song["artists"] as? [[String: Any]] ?? []
            return LyricsSearchResult(
                provider: .netease,
                id: id,
                title: Self.string(song["name"]) ?? "",
                artist: artists.compactMap { Self.string($0["name"]) }.joined(separator: " / "),
                album: Self.nonEmpty(Self.string(album?["name"])),
                duration: Self.millisecondsToSeconds(song["dt"]),
                artworkID: Self.string(album?["pic_str"] ?? album?["pic"] ?? album?["picId"]))
        }
    }

    private func fetchNeteaseLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        let v1 = try await neteaseLyricPayload(path: "/api/song/lyric/v1", id: result.id, extra: [
            "cp": false,
            "tv": 0,
            "lv": 0,
            "rv": 0,
            "kv": 0,
            "yv": 0,
            "ytv": 0,
            "yrv": 0,
        ])
        if let document = neteaseDocument(result: result, json: v1) {
            return document
        }
        let legacy = try await neteaseLyricPayload(path: "/api/song/lyric", id: result.id, extra: [
            "lv": -1,
            "tv": -1,
            "rv": -1,
            "kv": -1,
        ])
        if let document = neteaseDocument(result: result, json: legacy) {
            return document
        }
        throw ClientError.noLyrics
    }

    private func neteaseLyricPayload(path: String, id: String, extra: [String: Any]) async throws -> [String: Any] {
        var body: [String: Any] = extra
        body["id"] = id
        return try await neteaseEAPI(path: path, body: body)
    }

    private func neteaseDocument(result: LyricsSearchResult, json: [String: Any]) -> LyricsDocument? {
        let document = LyricsDocument(
            result: result,
            lyric: Self.lyricText(json["lrc"]),
            translatedLyric: Self.lyricText(json["tlyric"]),
            romanizedLyric: Self.lyricText(json["romalrc"]),
            karaokeLyric: Self.lyricText(json["yrc"]),
            karaokeTranslatedLyric: Self.lyricText(json["ytlrc"]))
        return document.hasLyrics ? document : nil
    }

    private func neteaseEAPI(path: String, body: [String: Any]) async throws -> [String: Any] {
        let encrypted = try Self.neteaseEncryptedParameters(path: path, body: body)
        let eapiPath = path.replacingOccurrences(of: "/api/", with: "/eapi/")
        var request = URLRequest(url: URL(string: "https://interface.music.163.com\(eapiPath)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("os=pc; appver=8.9.70;", forHTTPHeaderField: "Cookie")
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("params=\(encrypted)".utf8)
        return try await responseJSON(for: request)
    }

    static func neteaseEncryptedParameters(path: String, body: [String: Any]) throws -> String {
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        guard let json = String(data: bodyData, encoding: .utf8) else { throw ClientError.invalidResponse }
        let message = "nobody\(path)use\(json)md5forencrypt"
        let digest = Insecure.MD5.hash(data: Data(message.utf8)).map { String(format: "%02x", $0) }.joined()
        let payload = "\(path)-36cd479b6b5-\(json)-36cd479b6b5-\(digest)"
        return try aesECBEncrypt(Data(payload.utf8), key: Data("e82ckenh8dichen8".utf8))
            .map { String(format: "%02X", $0) }
            .joined()
    }

    private static func aesECBEncrypt(_ data: Data, key: Data) throws -> Data {
        var output = Data(count: data.count + kCCBlockSizeAES128)
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { dataBuffer in
                key.withUnsafeBytes { keyBuffer in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBuffer.baseAddress,
                        key.count,
                        nil,
                        dataBuffer.baseAddress,
                        data.count,
                        outputBuffer.baseAddress,
                        outputBuffer.count,
                        &outputLength)
                }
            }
        }
        guard status == kCCSuccess else { throw ClientError.server("网易云请求加密失败") }
        output.removeSubrange(outputLength..<output.count)
        return output
    }

    // MARK: - Tencent

    private func searchTencent(_ keyword: String) async throws -> [LyricsSearchResult] {
        let dataPayload: [String: Any] = [
            "comm": ["ct": "19", "cv": "1859", "uin": "0"],
            "req": [
                "method": "DoSearchForQQMusicDesktop",
                "module": "music.search.SearchCgiService",
                "param": ["grp": 1, "num_per_page": 10, "page_num": 1, "query": keyword, "search_type": 0],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: dataPayload)
        var components = URLComponents(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "data", value: String(decoding: data, as: UTF8.self)),
        ]
        var request = URLRequest(url: components.url!)
        Self.applyTencentHeaders(to: &request)
        let json = try await responseJSON(for: request)
        let req = json["req"] as? [String: Any]
        let body = (req?["data"] as? [String: Any])?["body"] as? [String: Any]
        let song = body?["song"] as? [String: Any]
        let list = song?["list"] as? [[String: Any]] ?? []
        return list.compactMap { item in
            let value = item["musicData"] as? [String: Any] ?? item
            guard let id = Self.string(value["mid"] ?? value["songmid"]), !id.isEmpty else { return nil }
            let album = value["album"] as? [String: Any]
            let singers = value["singer"] as? [[String: Any]] ?? []
            return LyricsSearchResult(
                provider: .tencent,
                id: id,
                title: Self.string(value["name"] ?? value["songname"]) ?? "",
                artist: singers.compactMap { Self.string($0["name"]) }.joined(separator: " / "),
                album: Self.nonEmpty(Self.string(album?["title"] ?? album?["name"] ?? value["albumname"])),
                duration: Self.seconds(value["interval"]),
                artworkID: Self.string(album?["mid"] ?? value["albummid"]))
        }
    }

    private func fetchTencentLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        var components = URLComponents(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")!
        components.queryItems = [
            URLQueryItem(name: "songmid", value: result.id),
            URLQueryItem(name: "g_tk", value: "5381"),
        ]
        var request = URLRequest(url: components.url!)
        Self.applyTencentHeaders(to: &request)
        let data = try await responseData(for: request)
        var text = String(decoding: data, as: UTF8.self)
        if let start = text.firstIndex(of: "("), let end = text.lastIndex(of: ")"), start < end {
            text = String(text[text.index(after: start)..<end])
        }
        guard let jsonData = text.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ClientError.invalidResponse
        }
        let lyric = Self.decodeTencentLyric(json["lyric"])
        let translation = Self.decodeTencentLyric(json["trans"])
        let document = LyricsDocument(
            result: result,
            lyric: Self.nonEmpty(lyric),
            translatedLyric: Self.nonEmpty(translation),
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil)
        guard document.hasLyrics else { throw ClientError.noLyrics }
        return document
    }

    private static func applyTencentHeaders(to request: inout URLRequest) {
        request.setValue("http://y.qq.com", forHTTPHeaderField: "Referer")
        request.setValue("QQ%E9%9F%B3%E4%B9%90/54409 CFNetwork/901.1 Darwin/17.6.0 (x86_64)", forHTTPHeaderField: "User-Agent")
        request.setValue("pgv_pvi=22038528; pgv_si=s3156287488; pgv_pvid=5535248600; yplayer_open=1; qqmusic_fromtag=66; player_exist=1", forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
    }

    private static func decodeTencentLyric(_ value: Any?) -> String? {
        guard let encoded = value as? String,
              let data = Data(base64Encoded: encoded),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return decodeHTMLEntities(text)
    }

    // MARK: - Kugou

    private func searchKugou(_ keyword: String) async throws -> [LyricsSearchResult] {
        var components = URLComponents(string: "http://mobilecdn.kugou.com/api/v3/search/song")!
        components.queryItems = [
            URLQueryItem(name: "api_ver", value: "1"),
            URLQueryItem(name: "area_code", value: "1"),
            URLQueryItem(name: "correct", value: "1"),
            URLQueryItem(name: "pagesize", value: "10"),
            URLQueryItem(name: "plat", value: "2"),
            URLQueryItem(name: "tag", value: "1"),
            URLQueryItem(name: "sver", value: "5"),
            URLQueryItem(name: "showtype", value: "10"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "version", value: "8990"),
        ]
        var request = URLRequest(url: components.url!)
        Self.applyKugouHeaders(to: &request)
        let json = try await responseJSON(for: request)
        let info = (json["data"] as? [String: Any])?["info"] as? [[String: Any]] ?? []
        return info.compactMap { item in
            guard let id = Self.string(item["hash"] ?? item["audio_id"] ?? item["id"]), !id.isEmpty else { return nil }
            let filename = Self.string(item["filename"] ?? item["fileName"]) ?? ""
            let parsed = Self.parseKugouFilename(filename)
            return LyricsSearchResult(
                provider: .kugou,
                id: id,
                title: Self.string(item["songName"] ?? item["songname"] ?? item["song_name"]) ?? parsed.title,
                artist: Self.string(item["singername"] ?? item["singerName"] ?? item["author_name"]) ?? parsed.artist,
                album: Self.nonEmpty(Self.string(item["album_name"] ?? item["albumName"])),
                duration: Self.seconds(item["duration"]),
                artworkID: nil)
        }
    }

    private func fetchKugouLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        var searchComponents = URLComponents(string: "http://krcs.kugou.com/search")!
        searchComponents.queryItems = [
            URLQueryItem(name: "keyword", value: " - "),
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "hash", value: result.id),
            URLQueryItem(name: "client", value: "mobi"),
            URLQueryItem(name: "man", value: "yes"),
        ]
        var request = URLRequest(url: searchComponents.url!)
        Self.applyKugouHeaders(to: &request)
        let json = try await responseJSON(for: request)
        guard let candidate = (json["candidates"] as? [[String: Any]])?.first,
              let accessKey = Self.string(candidate["accesskey"]),
              let lyricID = Self.string(candidate["id"]),
              !accessKey.isEmpty,
              !lyricID.isEmpty else { throw ClientError.noLyrics }

        let lyric = try await downloadKugouLyric(accessKey: accessKey, lyricID: lyricID, format: "lrc")
        let karaoke = try? await downloadKugouLyric(accessKey: accessKey, lyricID: lyricID, format: "krc")
        let document = LyricsDocument(
            result: result,
            lyric: Self.nonEmpty(lyric),
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: Self.nonEmpty(karaoke),
            karaokeTranslatedLyric: nil)
        guard document.hasLyrics else { throw ClientError.noLyrics }
        return document
    }

    private func downloadKugouLyric(accessKey: String, lyricID: String, format: String) async throws -> String {
        var components = URLComponents(string: "http://lyrics.kugou.com/download")!
        components.queryItems = [
            URLQueryItem(name: "charset", value: "utf8"),
            URLQueryItem(name: "accesskey", value: accessKey),
            URLQueryItem(name: "id", value: lyricID),
            URLQueryItem(name: "client", value: "android"),
            URLQueryItem(name: "fmt", value: format),
            URLQueryItem(name: "ver", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        Self.applyKugouHeaders(to: &request)
        let json = try await responseJSON(for: request)
        guard let encoded = json["content"] as? String,
              let bytes = Data(base64Encoded: encoded) else { throw ClientError.noLyrics }
        if format == "krc", bytes.starts(with: Data([0x6b, 0x72, 0x63, 0x31])) {
            let encrypted = bytes.dropFirst(4)
            let key: [UInt8] = [0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47, 0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69]
            let decoded = Data(encrypted.enumerated().map { index, byte in byte ^ key[index % key.count] })
            guard let inflated = Self.inflateZlib(decoded),
                  let text = String(data: inflated, encoding: .utf8) else { throw ClientError.invalidResponse }
            return text
        }
        guard let text = String(data: bytes, encoding: .utf8) else { throw ClientError.invalidResponse }
        return text
    }

    private static func applyKugouHeaders(to request: inout URLRequest) {
        request.setValue("IPhone-8990-searchSong", forHTTPHeaderField: "User-Agent")
        request.setValue("iOS11.4-Phone8990-1009-0-WiFi", forHTTPHeaderField: "UNI-UserAgent")
    }

    private static func inflateZlib(_ data: Data) -> Data? {
        var capacity = max(data.count * 8, 64 * 1024)
        for _ in 0..<5 {
            var output = Data(count: capacity)
            let decodedSize = output.withUnsafeMutableBytes { outputBuffer in
                data.withUnsafeBytes { inputBuffer in
                    compression_decode_buffer(
                        outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        capacity,
                        inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        data.count,
                        nil,
                        COMPRESSION_ZLIB)
                }
            }
            if decodedSize > 0, decodedSize < capacity {
                output.removeSubrange(decodedSize..<output.count)
                return output
            }
            capacity *= 2
        }
        return nil
    }

    // MARK: - Shared helpers

    private func responseData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw ClientError.server("歌词服务暂时不可用")
        }
        return data
    }

    private func responseJSON(for request: URLRequest) async throws -> [String: Any] {
        let data = try await responseData(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.invalidResponse
        }
        return json
    }

    private static let browserUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36"

    private static func searchIntent(from keyword: String) -> (title: String, artist: String?) {
        guard let separator = keyword.lastIndex(of: "-") else {
            return (keyword, nil)
        }
        let title = String(keyword[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = String(keyword[keyword.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (title.isEmpty ? keyword : title, artist.isEmpty ? nil : artist)
    }

    private static func candidateScore(
        _ candidate: LyricsSearchResult,
        intent: (title: String, artist: String?),
        focusArtists: [String] = [],
        duration: Int? = nil
    ) -> Int {
        let wantedTitle = comparable(intent.title)
        let title = comparable(candidate.title)
        var score = 0
        if !wantedTitle.isEmpty, title == wantedTitle {
            score += 100
        } else if !wantedTitle.isEmpty, title.contains(wantedTitle) || wantedTitle.contains(title) {
            score += 60
        }
        let wantedArtists = focusArtists.isEmpty
            ? [intent.artist].compactMap { $0 }
            : focusArtists
        let artist = comparable(candidate.artist)
        for wanted in wantedArtists.map(comparable) where !wanted.isEmpty {
            if artist == wanted {
                score += 40
                break
            }
            if artist.contains(wanted) || wanted.contains(artist) {
                score += 25
                break
            }
        }
        if let wantedDuration = duration, wantedDuration > 0, let candidateDuration = candidate.duration {
            let delta = abs(candidateDuration - wantedDuration)
            if delta <= 3 {
                score += 50
            } else if delta <= 8 {
                score += 25
            } else if delta <= 15 {
                score += 8
            } else if delta > 30 {
                score -= 50
            }
        }
        return score
    }

    private static func comparable(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\s\-_/·・.,，。:：'\"“”‘’()\[\]【】（）《》「」『』!！?？]"#, with: "", options: .regularExpression)
            .lowercased()
    }

    private static func lyricText(_ value: Any?) -> String? {
        nonEmpty((value as? [String: Any])?["lyric"] as? String)
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String: value
        case let value as NSNumber: value.stringValue
        default: nil
        }
    }

    private static func seconds(_ value: Any?) -> Int? {
        guard let raw = string(value), let number = Double(raw) else { return nil }
        return Int(number.rounded())
    }

    private static func millisecondsToSeconds(_ value: Any?) -> Int? {
        guard let raw = string(value), let number = Double(raw) else { return nil }
        return Int((number / 1000).rounded())
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func parseKugouFilename(_ value: String) -> (artist: String, title: String) {
        let parts = value.components(separatedBy: " - ")
        guard parts.count > 1 else { return ("", value) }
        return (parts[0].trimmingCharacters(in: .whitespaces), parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces))
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        var text = value
        let replacements = ["&apos;": "'", "&quot;": "\"", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for (source, target) in replacements { text = text.replacingOccurrences(of: source, with: target) }
        return text
    }
}

enum LyricsParser {
    private struct RawLine {
        let from: Double
        let duration: Double?
        let text: String
        let words: [LyricsWordPayload]
    }

    static func lines(from document: LyricsDocument, duration: Int) -> [LyricsLinePayload] {
        if let vocalLines = document.vocalLines, !vocalLines.isEmpty {
            return vocalLines.map { line in
                LyricsLinePayload(
                    from: line.from,
                    to: line.to,
                    text: line.text,
                    translation: line.translation,
                    words: line.words,
                    voiceRole: line.voiceRole,
                    layerID: line.layerID,
                    overlapGroup: line.overlapGroup)
            }
        }
        guard let main = document.preferredMainLyric else { return [] }
        var rawLines = timedLines(main)
        if rawLines.isEmpty {
            rawLines = plainLines(main, duration: duration)
        }
        var translations: [Int: String] = [:]
        for line in timedLines(document.preferredTranslationLyric ?? "") {
            translations[Int((line.from * 100).rounded())] = line.text
        }
        let parsed = rawLines.enumerated().map { index, line in
            let next = rawLines.dropFirst(index + 1).first(where: { $0.from > line.from + 0.08 })?.from
                ?? line.from + 5
            let end = line.duration.map { line.from + $0 } ?? max(next, line.from + 1)
            return LyricsLinePayload(
                from: line.from,
                to: end,
                text: line.text,
                translation: translations[Int((line.from * 100).rounded())],
                words: line.words)
        }
        return LyricVocalArrangement.arrange(parsed)
    }

    private static func timedLines(_ text: String) -> [RawLine] {
        var result: [RawLine] = []
        for sourceLine in text.split(whereSeparator: \.isNewline) {
            let line = String(sourceLine)
            if let qrc = parseMillisecondLine(line) {
                result.append(qrc)
            } else {
                result.append(contentsOf: parseLRCLine(line))
            }
        }
        return result.sorted { $0.from < $1.from }
    }

    private static func parseMillisecondLine(_ line: String) -> RawLine? {
        let pattern = #"^\[(\d+),(\d+)\](.*)$"#
        guard let match = firstMatch(pattern, in: line),
              let start = number(match, group: 1, text: line),
              let duration = number(match, group: 2, text: line),
              let bodyRange = Range(match.range(at: 3), in: line) else { return nil }
        let body = String(line[bodyRange])
        let words = parseWords(body, lineStartMilliseconds: start)
        let stripped = body.replacingOccurrences(
            of: #"[<(]\d+,\d+(?:,\d+)?[>)]"#,
            with: "",
            options: .regularExpression)
        let text = words.isEmpty ? stripped : words.map(\.text).joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return RawLine(
            from: start / 1000,
            duration: duration / 1000,
            text: text,
            words: words)
    }

    private static func parseWords(_ body: String, lineStartMilliseconds: Double) -> [LyricsWordPayload] {
        guard let regex = try? NSRegularExpression(pattern: #"[<(](\d+),(\d+)(?:,\d+)?[>)]([^<(]+)"#) else { return [] }
        return regex.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap { match in
            guard let offset = number(match, group: 1, text: body),
                  let duration = number(match, group: 2, text: body),
                  let textRange = Range(match.range(at: 3), in: body) else { return nil }
            let start = (lineStartMilliseconds + offset) / 1000
            return LyricsWordPayload(from: start, to: start + duration / 1000, text: String(body[textRange]))
        }
    }

    private static func parseLRCLine(_ source: String) -> [RawLine] {
        let pattern = #"^\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var line = source
        var times: [Double] = []
        while let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let minute = number(match, group: 1, text: line),
              let second = number(match, group: 2, text: line),
              let fullRange = Range(match.range, in: line) {
            var fraction = 0.0
            if let range = Range(match.range(at: 3), in: line) {
                let raw = String(line[range])
                fraction = (Double(raw) ?? 0) / pow(10, Double(raw.count))
            }
            times.append(minute * 60 + second + fraction)
            line.removeSubrange(fullRange)
        }
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return times.map { RawLine(from: $0, duration: nil, text: text, words: []) }
    }

    private static func plainLines(_ text: String, duration: Int) -> [RawLine] {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }
        let total = Double(max(duration, lines.count * 4))
        let step = max(2, total / Double(lines.count))
        return lines.enumerated().map { index, text in
            RawLine(from: Double(index) * step, duration: step, text: text, words: [])
        }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        try? NSRegularExpression(pattern: pattern).firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func number(_ match: NSTextCheckingResult, group: Int, text: String) -> Double? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return Double(text[range])
    }
}

enum LyricVocalArrangement {
    private struct LabeledText {
        let text: String
        let role: LyricVoiceRole
        let isExplicit: Bool
    }

    static func arrange(_ source: [LyricsLinePayload]) -> [LyricsLinePayload] {
        var arranged: [LyricsLinePayload] = []
        arranged.reserveCapacity(source.count + source.count / 4)

        for (index, line) in source.enumerated() {
            let labeled = labeledText(line.text)
            if let split = splitInlineBacking(labeled.text) {
                let group = groupID(for: line, index: index)
                arranged.append(copy(
                    line,
                    text: split.lead,
                    words: words(matching: split.lead, in: line.words),
                    role: labeled.isExplicit ? labeled.role : .lead,
                    layerID: "\(group)-lead",
                    overlapGroup: group))
                arranged.append(copy(
                    line,
                    text: split.backing,
                    translation: .some(nil),
                    words: words(matching: split.backing, in: line.words),
                    role: split.role,
                    layerID: "\(group)-backing",
                    overlapGroup: group))
            } else {
                arranged.append(copy(
                    line,
                    text: labeled.text,
                    role: labeled.role,
                    layerID: "line-\(index)-\(labeled.role.rawValue)"))
            }
        }

        // Repeated LRC timestamps are the only unlabeled multi-line form we
        // can safely treat as simultaneous. Mere tail overlap is common in
        // ordinary karaoke files and must not be promoted to a duet.
        var cursor = 0
        while cursor < arranged.count {
            let start = arranged[cursor].from
            var end = cursor + 1
            while end < arranged.count, abs(arranged[end].from - start) <= 0.08 {
                end += 1
            }
            if end - cursor > 1 {
                let group = "timestamp-\(Int((start * 1_000).rounded()))-\(cursor)"
                for offset in cursor..<end where arranged[offset].overlapGroup == nil {
                    let role: LyricVoiceRole
                    switch offset - cursor {
                    case 0: role = arranged[offset].voiceRole == .lead ? .duetA : arranged[offset].voiceRole
                    case 1: role = arranged[offset].voiceRole == .lead ? .duetB : arranged[offset].voiceRole
                    default: role = arranged[offset].voiceRole == .lead ? .backing : arranged[offset].voiceRole
                    }
                    arranged[offset] = copy(
                        arranged[offset],
                        role: role,
                        layerID: "\(group)-\(offset - cursor)",
                        overlapGroup: group)
                }
            }
            cursor = end
        }
        return arranged
    }

    private static func labeledText(_ source: String) -> LabeledText {
        let labels: [(String, LyricVoiceRole)] = [
            (#"^(?:和声|伴唱|Backing|B\.?V\.?)\s*[:：]\s*(.+)$"#, .backing),
            (#"^(?:主唱|Lead)\s*[:：]\s*(.+)$"#, .lead),
            (#"^(?:男声?|A)\s*[:：]\s*(.+)$"#, .duetA),
            (#"^(?:女声?|B)\s*[:：]\s*(.+)$"#, .duetB),
            (#"^(?:合|合唱|Together|All)\s*[:：]\s*(.+)$"#, .together),
        ]
        for (pattern, role) in labels {
            guard let match = firstMatch(pattern, in: source),
                  let range = Range(match.range(at: 1), in: source) else { continue }
            let text = source[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return LabeledText(text: text, role: role, isExplicit: true)
            }
        }
        return LabeledText(text: source, role: .lead, isExplicit: false)
    }

    private static func splitInlineBacking(
        _ source: String
    ) -> (lead: String, backing: String, role: LyricVoiceRole)? {
        let pattern = #"^(.+?)[（(]\s*((?:(?:和声|伴唱|Backing|B\.?V\.?)\s*[:：]\s*)?[^()（）]+)[）)]\s*$"#
        guard let match = firstMatch(pattern, in: source),
              let leadRange = Range(match.range(at: 1), in: source),
              let backingRange = Range(match.range(at: 2), in: source) else { return nil }
        let lead = source[leadRange].trimmingCharacters(in: .whitespacesAndNewlines)
        var backing = source[backingRange].trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitPattern = #"^(?:和声|伴唱|Backing|B\.?V\.?)\s*[:：]\s*"#
        let explicitlyLabeled = backing.range(of: explicitPattern, options: .regularExpression) != nil
        backing = backing.replacingOccurrences(of: explicitPattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lead.isEmpty,
              !backing.isEmpty,
              explicitlyLabeled || isPlausibleBackingText(backing) else { return nil }
        return (lead, backing, .backing)
    }

    private static func isPlausibleBackingText(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let stageDirections = ["前奏", "间奏", "尾奏", "伴奏", "重复", "music", "instrumental", "repeat"]
        guard !stageDirections.contains(where: normalized.contains) else { return false }
        let meaningful = normalized.unicodeScalars.filter {
            CharacterSet.letters.union(.decimalDigits).contains($0)
        }
        return meaningful.count >= 2 && meaningful.count <= 48
    }

    private static func words(
        matching text: String,
        in source: [LyricsWordPayload]
    ) -> [LyricsWordPayload] {
        guard !source.isEmpty else { return [] }
        let target = normalized(text)
        guard !target.isEmpty else { return [] }
        for lower in source.indices {
            var candidate = ""
            for upper in lower..<source.endIndex {
                candidate += normalized(source[upper].text)
                if candidate == target {
                    return Array(source[lower...upper])
                }
                if candidate.count > target.count { break }
            }
        }
        return []
    }

    private static func normalized(_ text: String) -> String {
        String(text.unicodeScalars.filter {
            CharacterSet.letters.union(.decimalDigits).contains($0)
        }).lowercased()
    }

    private static func groupID(for line: LyricsLinePayload, index: Int) -> String {
        "inline-\(Int((line.from * 1_000).rounded()))-\(index)"
    }

    private static func copy(
        _ line: LyricsLinePayload,
        text: String? = nil,
        translation: String?? = nil,
        words: [LyricsWordPayload]? = nil,
        role: LyricVoiceRole? = nil,
        layerID: String? = nil,
        overlapGroup: String?? = nil
    ) -> LyricsLinePayload {
        LyricsLinePayload(
            from: line.from,
            to: line.to,
            text: text ?? line.text,
            translation: translation ?? line.translation,
            words: words ?? line.words,
            voiceRole: role ?? line.voiceRole,
            layerID: layerID ?? line.layerID,
            overlapGroup: overlapGroup ?? line.overlapGroup)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            .firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
