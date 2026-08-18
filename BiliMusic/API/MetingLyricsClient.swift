import CommonCrypto
import Compression
import CryptoKit
import Foundation

enum LyricsProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case netease
    case kugou
    case tencent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .netease: "网易云"
        case .kugou: "酷狗"
        case .tencent: "QQ 音乐"
        }
    }
}

struct LyricsSearchResult: Codable, Hashable, Identifiable, Sendable {
    let provider: LyricsProvider
    let id: String
    let title: String
    let artist: String
    let album: String?
    let duration: Int?
    let artworkID: String?

    var stableID: String { "\(provider.rawValue):\(id)" }
}

struct LyricsDocument: Codable, Equatable, Sendable {
    let result: LyricsSearchResult
    let lyric: String?
    let translatedLyric: String?
    let romanizedLyric: String?
    let karaokeLyric: String?
    let karaokeTranslatedLyric: String?

    var preferredMainLyric: String? {
        Self.firstText(karaokeLyric, lyric)
    }

    var preferredTranslationLyric: String? {
        Self.firstText(karaokeTranslatedLyric, translatedLyric)
    }

    var hasLyrics: Bool { preferredMainLyric != nil }

    private static func firstText(_ values: String?...) -> String? {
        values.lazy.compactMap { value in
            let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }.first
    }
}

struct LyricsWordPayload: Equatable, Sendable {
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
}

struct AutomaticLyricsMatch: Sendable {
    let keyword: String
    let provider: LyricsProvider
    let candidates: [LyricsSearchResult]
    let document: LyricsDocument?
}

actor MetingLyricsClient {
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

    /// 清洗服务返回的关键词通常是「歌名-歌手」。这里只做一致性排序，避免 Meting
    /// 搜索结果第一项属于同歌手的另一首歌；不恢复 LRCLIB 的时长/相似度评分系统。
    static func rankedCandidates(
        _ candidates: [LyricsSearchResult],
        keyword: String
    ) -> [LyricsSearchResult] {
        let intent = searchIntent(from: keyword)
        return candidates.enumerated().sorted { lhs, rhs in
            let leftScore = candidateScore(lhs.element, intent: intent)
            let rightScore = candidateScore(rhs.element, intent: intent)
            return leftScore == rightScore ? lhs.offset < rhs.offset : leftScore > rightScore
        }.map(\.element)
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
        }
    }

    func fetchLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        switch result.provider {
        case .netease: return try await fetchNeteaseLyrics(for: result)
        case .kugou: return try await fetchKugouLyrics(for: result)
        case .tencent: return try await fetchTencentLyrics(for: result)
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
        let json = try await neteaseEAPI(path: "/api/song/lyric/v1", body: [
            "id": result.id,
            "cp": false,
            "tv": 0,
            "lv": 0,
            "rv": 0,
            "kv": 0,
            "yv": 0,
            "ytv": 0,
            "yrv": 0,
        ])
        let document = LyricsDocument(
            result: result,
            lyric: Self.lyricText(json["lrc"]),
            translatedLyric: Self.lyricText(json["tlyric"]),
            romanizedLyric: Self.lyricText(json["romalrc"]),
            karaokeLyric: Self.lyricText(json["yrc"]),
            karaokeTranslatedLyric: Self.lyricText(json["ytlrc"]))
        guard document.hasLyrics else { throw ClientError.noLyrics }
        return document
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
        intent: (title: String, artist: String?)
    ) -> Int {
        let wantedTitle = comparable(intent.title)
        let title = comparable(candidate.title)
        var score = 0
        if !wantedTitle.isEmpty, title == wantedTitle {
            score += 100
        } else if !wantedTitle.isEmpty, title.contains(wantedTitle) || wantedTitle.contains(title) {
            score += 60
        }
        if let wantedArtist = intent.artist.map(comparable), !wantedArtist.isEmpty {
            let artist = comparable(candidate.artist)
            if artist == wantedArtist {
                score += 30
            } else if artist.contains(wantedArtist) || wantedArtist.contains(artist) {
                score += 20
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
        guard let main = document.preferredMainLyric else { return [] }
        var rawLines = timedLines(main)
        if rawLines.isEmpty {
            rawLines = plainLines(main, duration: duration)
        }
        var translations: [Int: String] = [:]
        for line in timedLines(document.preferredTranslationLyric ?? "") {
            translations[Int((line.from * 100).rounded())] = line.text
        }
        return rawLines.enumerated().map { index, line in
            let next = index + 1 < rawLines.count ? rawLines[index + 1].from : line.from + 5
            let end = line.duration.map { line.from + $0 } ?? max(next, line.from + 1)
            return LyricsLinePayload(
                from: line.from,
                to: end,
                text: line.text,
                translation: translations[Int((line.from * 100).rounded())],
                words: line.words)
        }
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
