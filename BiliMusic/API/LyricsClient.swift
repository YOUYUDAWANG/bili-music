import Foundation
import OSLog

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "lyrics")

/// 在线歌词:LRCLIB 同步歌词。B 站标题噪声多、artist 是 UP主而非歌手,
/// 所以先从标题解析真实歌名/歌手,再用「标题相似 + 时长门槛」严格匹配,宁可没有也不错配。
struct LyricsClient {
    /// LRCLIB 搜索返回的候选条目。
    struct Candidate: Decodable, Hashable {
        let id: Int?
        let trackName: String
        let artistName: String
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    struct QueryPlan: Hashable {
        enum Kind: Hashable {
            case exactGet(track: String, artist: String, duration: Int)
            case searchFields(track: String, artist: String?)
            case searchText(String)
        }

        let kind: Kind
    }

    struct ParsedSong: Equatable {
        enum Confidence: Int {
            case low
            case medium
            case high
        }

        let title: String
        let artist: String?
        let confidence: Confidence

        var isDisplaySafe: Bool {
            confidence == .high
        }
    }

    /// 匹配不到歌词。
    enum LyricsError: Error { case noMatch }

    /// 为曲目匹配歌词：解析歌名/歌手 → 多路搜索 → 评分筛选 → 解析 LRC 或纯文本歌词。
    func lyrics(for track: Track) async throws -> [PlayerEngine.LyricLine] {
        let parsed = Self.parseSongDetailed(from: track.title, fallbackArtist: track.artist)
        let artists = artistCandidates(parsedArtist: parsed.artist, trackArtist: track.artist)
        let plans = queryPlans(title: parsed.title, rawTitle: track.title, artists: artists, duration: track.duration)
        let candidates = await candidates(for: plans)

        guard let best = bestCandidate(
            candidates,
            songTitle: parsed.title,
            artists: artists,
            duration: track.duration) else {
            throw LyricsError.noMatch
        }
        let lines = lyricLines(from: best, duration: track.duration)
        guard !lines.isEmpty else { throw LyricsError.noMatch }
        return lines
    }

    // MARK: - 请求

    private func candidates(for plans: [QueryPlan]) async -> [Candidate] {
        await withTaskGroup(of: [Candidate].self) { group in
            for plan in plans.prefix(8) {
                group.addTask {
                    switch plan.kind {
                    case .exactGet(let track, let artist, let duration):
                        return (try? await exactGet(track: track, artist: artist, duration: duration)).map { [$0] } ?? []
                    case .searchFields(let track, let artist):
                        return (try? await searchByFields(track: track, artist: artist)) ?? []
                    case .searchText(let query):
                        return (try? await searchFreeText(query)) ?? []
                    }
                }
            }

            var merged: [Candidate] = []
            for await candidates in group {
                merged.append(contentsOf: candidates)
            }
            return dedupe(merged)
        }
    }

    /// 按歌名 + 歌手 + 时长查询。LRCLIB 的 `/api/get` 比 search 更激进,可能访问外部来源。
    private func exactGet(track: String, artist: String, duration: Int) async throws -> Candidate {
        try await requestOne(queryItems: [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: ""),
            URLQueryItem(name: "duration", value: String(duration)),
        ])
    }

    /// 按歌名 + 可选歌手搜索。
    private func searchByFields(track: String, artist: String?) async throws -> [Candidate] {
        var items = [URLQueryItem(name: "track_name", value: track)]
        if let artist, !artist.isEmpty {
            items.append(URLQueryItem(name: "artist_name", value: artist))
        }
        return try await request(queryItems: items)
    }

    /// 自由文本搜索（兜底）。
    private func searchFreeText(_ query: String) async throws -> [Candidate] {
        try await request(queryItems: [URLQueryItem(name: "q", value: query)])
    }

    /// 调 LRCLIB 搜索接口并解码候选列表。
    private func request(queryItems: [URLQueryItem]) async throws -> [Candidate] {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        request.setValue("BiliMusic iOS personal app", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([Candidate].self, from: data)
    }

    /// 调 LRCLIB 精确接口并解码单个候选。
    private func requestOne(queryItems: [URLQueryItem]) async throws -> Candidate {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        request.setValue("BiliMusic iOS personal app", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 404 {
            throw LyricsError.noMatch
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Candidate.self, from: data)
    }

    // MARK: - 匹配

    // MARK: - 查询计划

    func queryPlans(title: String, rawTitle: String, artists: [String], duration: Int) -> [QueryPlan] {
        let titles = titleVariants(title: title, rawTitle: rawTitle)
        var plans: [QueryPlan] = []

        if duration > 0 {
            for artist in artists.prefix(2) {
                plans.append(QueryPlan(kind: .exactGet(track: title, artist: artist, duration: duration)))
            }
        }

        for artist in artists.prefix(3) {
            plans.append(QueryPlan(kind: .searchFields(track: title, artist: artist)))
        }
        plans.append(QueryPlan(kind: .searchFields(track: title, artist: nil)))

        for candidateTitle in titles.prefix(3) {
            plans.append(QueryPlan(kind: .searchText(candidateTitle)))
            for artist in artists.prefix(2) {
                plans.append(QueryPlan(kind: .searchText("\(candidateTitle) \(artist)")))
                plans.append(QueryPlan(kind: .searchText("\(artist) \(candidateTitle)")))
            }
        }

        return dedupe(plans)
    }

    func artistCandidates(parsedArtist: String?, trackArtist: String) -> [String] {
        let raw = [parsedArtist, trackArtist]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return dedupe(raw)
            .filter { isLikelySearchArtist($0) }
    }

    private func titleVariants(title: String, rawTitle: String) -> [String] {
        var variants = [title, Self.parseSong(from: rawTitle).title]
        let cleanedRaw = Self.stripNoise(rawTitle)
        variants.append(cleanedRaw)
        variants.append(contentsOf: splitTitleVariants(title))
        variants.append(contentsOf: splitTitleVariants(cleanedRaw))
        return dedupe(variants.map { compactWhitespace($0) }.filter { !$0.isEmpty })
    }

    private func splitTitleVariants(_ title: String) -> [String] {
        let separators = [" - ", " – ", " — ", "｜", " | ", " / ", "／"]
        for separator in separators where title.contains(separator) {
            let parts = title
                .components(separatedBy: separator)
                .map { compactWhitespace($0) }
                .filter { !$0.isEmpty }
            if parts.count >= 2 {
                return [parts[0], parts[1], parts.suffix(from: 1).joined(separator: " ")]
            }
        }
        return []
    }

    // MARK: - 匹配

    /// 歌名必须足够接近；有歌手信号时允许 MV 片头片尾造成更大的时长差。
    func bestCandidate(_ candidates: [Candidate], songTitle: String, artists: [String], duration: Int) -> Candidate? {
        let wanted = comparable(songTitle)
        guard !wanted.isEmpty else { return nil }
        return candidates
            .filter { $0.instrumental != true }
            .filter { candidateHasLyrics($0) }
            .filter { candidate in
                titleMatchScore(candidate.trackName, wanted: wanted) >= 45
            }
            .filter { candidate in
                guard duration > 0, let cd = candidate.duration else { return true }
                let artistScore = max(
                    artistMatchScore(candidate.artistName, artists: artists),
                    embeddedArtistMatchScore(candidate.artistName, wantedTitle: wanted))
                let maxDelta = artistScore > 0 ? 45.0 : 25.0
                return abs(cd - Double(duration)) <= maxDelta
            }
            .map { ($0, score($0, songTitle: wanted, artists: artists, duration: duration)) }
            .filter { $0.1 >= 50 }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// 给候选打分：歌名相似度 + 时长接近度，压低伴奏/钢琴/卡拉OK 版本。
    private func score(_ candidate: Candidate, songTitle wanted: String, artists: [String], duration: Int) -> Int {
        var value = titleMatchScore(candidate.trackName, wanted: wanted)
        value += max(
            artistMatchScore(candidate.artistName, artists: artists),
            embeddedArtistMatchScore(candidate.artistName, wantedTitle: wanted))

        if duration > 0, let cd = candidate.duration {
            switch abs(cd - Double(duration)) {
            case 0...3: value += 28
            case 3...12: value += 18
            case 12...25: value += 8
            default: value -= 8
            }
        }
        if candidate.syncedLyrics?.isEmpty == false {
            value += 12
        } else if candidate.plainLyrics?.isEmpty == false {
            value += 4
        }
        // 优先正式版本,压低伴奏/钢琴翻弹/卡拉OK
        let album = candidate.albumName ?? ""
        if ["伴奏", "钢琴", "piano", "instrumental", "karaoke"].contains(where: {
            album.localizedCaseInsensitiveContains($0) || candidate.trackName.localizedCaseInsensitiveContains($0)
        }) {
            value -= 25
        }
        return value
    }

    private func titleMatchScore(_ title: String, wanted: String) -> Int {
        let ct = comparable(title)
        guard !ct.isEmpty else { return 0 }
        if ct == wanted { return 70 }
        if ct.contains(wanted) || wanted.contains(ct) {
            // 归一化后只剩 1-2 字符的极短歌名(《光》《海》)contains 太宽,大幅降分不过门槛
            return wanted.count >= 3 ? 56 : 20
        }
        let ratio = similarity(ct, wanted)
        if ratio >= 0.82 { return 52 }
        if ratio >= 0.72 { return 44 }
        return 0
    }

    private func artistMatchScore(_ artistName: String, artists: [String]) -> Int {
        let candidate = comparable(artistName)
        guard !candidate.isEmpty else { return 0 }
        for artist in artists {
            let wanted = comparable(artist)
            guard !wanted.isEmpty else { continue }
            if candidate == wanted { return 28 }
            if candidate.contains(wanted) || wanted.contains(candidate) { return 18 }
            if similarity(candidate, wanted) >= 0.78 { return 12 }
        }
        return 0
    }

    private func embeddedArtistMatchScore(_ artistName: String, wantedTitle: String) -> Int {
        let candidate = comparable(artistName)
        guard candidate.count >= 2 else { return 0 }
        return wantedTitle.contains(candidate) ? 16 : 0
    }

    private func candidateHasLyrics(_ candidate: Candidate) -> Bool {
        candidate.syncedLyrics?.isEmpty == false || candidate.plainLyrics?.isEmpty == false
    }

    // MARK: - 标题解析

    /// 噪声词:画质/音质/修复/官方等,与歌名无关。
    private static let noiseTokens = [
        "4k", "8k", "1080p", "2160p", "60fps", "60帧", "hi-res", "hires", "无损", "flac",
        "dolby", "杜比", "修复", "重制", "高清", "超清", "official", "官方", "mv", "完整版",
        "纯享", "字幕", "歌词", "cd音轨", "臻彩", "收录", "原版", "超高清",
        "lyrics", "lyric", "remastered", "hd",
    ]

    /// 从 B 站标题解析出 (歌名, 歌手?)。供歌词检索使用,会返回低置信清洗结果作为查询候选。
    static func parseSong(from rawTitle: String) -> (title: String, artist: String?) {
        let parsed = parseSongDetailed(from: rawTitle)
        return (parsed.title, parsed.artist)
    }

    /// 供 UI 展示使用。低置信时调用方应保留原标题,避免把评论/合集/搬运说明误清洗成歌名。
    static func parseSongForDisplay(from rawTitle: String, fallbackArtist: String) -> ParsedSong {
        let parsed = parseSongDetailed(from: rawTitle, fallbackArtist: fallbackArtist)
        if parsed.isDisplaySafe {
            return parsed
        }
        return ParsedSong(title: rawTitle, artist: nil, confidence: .low)
    }

    /// 从 B 站标题解析出结构化信息。优先使用明确结构,例如《歌名》或 `Artist - Title`。
    static func parseSongDetailed(from rawTitle: String, fallbackArtist: String? = nil) -> ParsedSong {
        let normalized = normalizeRawTitle(rawTitle)
        guard !normalized.isEmpty else {
            return ParsedSong(title: rawTitle, artist: nil, confidence: .low)
        }
        let text = removeNoiseBlocks(normalized)

        // 《歌名》/「歌名」/『歌名』:括号内是歌名,括号前/后短文本才可能是歌手。
        if let quoted = parseQuotedSong(text) {
            return quoted
        }
        if let separated = parseSeparatedSong(text) {
            return ParsedSong(title: separated.title, artist: separated.artist, confidence: .high)
        }
        if let bracketed = parseLeadingBracketSong(text, fallbackArtist: fallbackArtist) {
            return bracketed
        }

        // 没有可靠结构时,只做很轻的尾部噪声清理。UI 不直接采用 low 结果。
        let cleaned = cleanupTitleCandidate(text)
        let title = cleaned.isEmpty ? normalized : cleaned
        let confidence: ParsedSong.Confidence = (title != normalized && isSafeStandaloneTitle(title)) ? .medium : .low
        return ParsedSong(title: title, artist: nil, confidence: confidence)
    }

    private static func parseQuotedSong(_ text: String) -> ParsedSong? {
        guard let match = text.range(of: #"[《「『][^》」』]+[》」』]"#, options: .regularExpression) else {
            return nil
        }
        let song = cleanupTitleCandidate(String(text[match])
            .trimmingCharacters(in: CharacterSet(charactersIn: "《》「」『』 ")))
        guard !song.isEmpty else { return nil }

        let before = cleanupArtistCandidate(String(text[..<match.lowerBound]))
        let after = cleanupArtistCandidate(String(text[match.upperBound...]))
        let artist = [before, after]
            .first { candidate in
                candidate.isEmpty == false && isLikelyArtist(candidate)
            }
        return ParsedSong(title: song, artist: artist, confidence: .high)
    }

    private static func parseSeparatedSong(_ text: String) -> (title: String, artist: String?)? {
        let separators = [" - ", " – ", " — ", " | ", "｜", " / "]
        for separator in separators where text.contains(separator) {
            let parts = text
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            let artist = cleanupArtistCandidate(parts[0])
            let title = cleanupTitleCandidate(parts.dropFirst().joined(separator: " "))
            guard isLikelyArtist(artist), isSafeStandaloneTitle(title) else { continue }
            return (title, artist)
        }
        return nil
    }

    private static func parseLeadingBracketSong(_ text: String, fallbackArtist: String?) -> ParsedSong? {
        let pattern = #"^[【\[\（(]([^】\]）)]{1,40})[】\]）)]\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let blockRange = Range(match.range(at: 1), in: text),
              let restRange = Range(match.range(at: 2), in: text) else {
            return nil
        }

        let block = cleanupTitleCandidate(String(text[blockRange]))
        let rest = cleanupTitleCandidate(String(text[restRange]))
        guard !block.isEmpty, !rest.isEmpty, !isNoiseBlock(block) else { return nil }

        let fallback = fallbackArtist.map(cleanupArtistCandidate) ?? ""
        let comparableBlock = comparableKey(block)
        let comparableRest = comparableKey(rest)
        let comparableFallback = comparableKey(fallback)

        if !comparableFallback.isEmpty, comparableBlock == comparableFallback, isSafeStandaloneTitle(rest) {
            return ParsedSong(title: rest, artist: block, confidence: .high)
        }
        if !comparableFallback.isEmpty, comparableRest == comparableFallback, isSafeStandaloneTitle(block) {
            return ParsedSong(title: block, artist: fallback, confidence: .high)
        }
        return nil
    }

    private static func isLikelyArtist(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 40 else { return false }
        let lower = value.lowercased()
        let blocked = ["cover", "翻唱", "合集", "歌单", "playlist", "reaction", "reaction"]
        return !blocked.contains { lower.localizedCaseInsensitiveContains($0) }
    }

    private func isLikelySearchArtist(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 48 else { return false }
        let lower = trimmed.lowercased()
        let blocked = [
            "up", "搬运", "字幕", "音乐分享", "音乐频道", "合集", "歌单", "playlist",
            "reaction", "cover", "翻唱", "官方号", "official channel"
        ]
        return !blocked.contains { lower.localizedCaseInsensitiveContains($0) }
    }

    private static func stripNoise(_ rawTitle: String) -> String {
        let text = removeNoiseTokens(from: removeNoiseBlocks(normalizeRawTitle(rawTitle)))
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeRawTitle(_ rawTitle: String) -> String {
        rawTitle
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeNoiseBlocks(_ text: String) -> String {
        let pattern = #"[【\[\（(]([^】\]）)]*)[】\]）)]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = ""
        var cursor = text.startIndex
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        for match in matches {
            guard let fullRange = Range(match.range(at: 0), in: text),
                  let contentRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            result += String(text[cursor..<fullRange.lowerBound])
            let content = String(text[contentRange])
            result += isNoiseBlock(content) ? " " : String(text[fullRange])
            cursor = fullRange.upperBound
        }
        result += String(text[cursor...])
        return result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanupTitleCandidate(_ value: String) -> String {
        let text = removeNoiseTokens(from: removeNoiseBlocks(value))
        return text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -—_/|｜·・:：,，.。"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeNoiseTokens(from value: String) -> String {
        var text = value
        for token in noiseTokens {
            if token.unicodeScalars.allSatisfy({ $0.isASCII }) {
                let escaped = NSRegularExpression.escapedPattern(for: token)
                let boundary = #"[\s\-_·・|｜/\\:：,，.。()\[\]【】（）《》「」『』]"#
                let pattern = #"(?i)(^|"# + boundary + #")"# + escaped + #"(?=$|"# + boundary + #")"#
                text = text.replacingOccurrences(of: pattern, with: "$1 ", options: .regularExpression)
            } else {
                text = text.replacingOccurrences(of: token, with: " ", options: .caseInsensitive)
            }
        }
        return text
    }

    private static func cleanupArtistCandidate(_ value: String) -> String {
        cleanupTitleCandidate(value)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -—_/|｜·・:：,，.。"))
    }

    private static func isNoiseBlock(_ value: String) -> Bool {
        let lower = value.lowercased()
        let compact = comparableKey(value)
        guard !compact.isEmpty else { return true }
        let noise = [
            "4k", "8k", "1080", "2160", "60fps", "60帧", "hires", "hi-res", "flac",
            "dolby", "杜比", "修复", "重制", "高清", "超清", "official", "官方",
            "mv", "musicvideo", "字幕", "中字", "lyrics", "lyric", "完整版", "纯享",
            "remastered", "hd"
        ]
        return noise.contains { lower.localizedCaseInsensitiveContains($0) || compact.contains(comparableKey($0)) }
    }

    private static func isSafeStandaloneTitle(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 1, text.count <= 32 else { return false }
        let lower = text.lowercased()
        let blocked = ["reaction", "解析", "盘点", "合集", "歌单", "playlist", "教程", "鉴赏", "排行", "推荐"]
        return !blocked.contains { lower.localizedCaseInsensitiveContains($0) }
    }

    private static func comparableKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\s\-_/·・.,，。:：'"“”‘’()\[\]【】（）《》「」『』!！?？]"#, with: "", options: .regularExpression)
            .lowercased()
    }

    /// 正则替换的简写。
    private static func regexReplace(_ text: String, _ pattern: String, with replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    // MARK: - LRC 解析

    func lyricLines(from candidate: Candidate, duration: Int) -> [PlayerEngine.LyricLine] {
        if let synced = candidate.syncedLyrics, !synced.isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty { return lines }
        }
        guard let plain = candidate.plainLyrics, !plain.isEmpty else { return [] }
        return parsePlainLyrics(plain, duration: duration)
    }

    /// 解析 LRC 文本为带时间区间的歌词行。支持 `[t1][t2]歌词` 多时间标签行（同一文本多时间点）。
    private func parseLRC(_ text: String) -> [PlayerEngine.LyricLine] {
        let pattern = #"^\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var rawLines: [(time: Double, text: String)] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = String(raw)
            var times: [Double] = []
            // 循环剥离行首所有时间标签
            while true {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard let match = regex.firstMatch(in: line, range: range),
                      let fullRange = Range(match.range, in: line),
                      let minuteRange = Range(match.range(at: 1), in: line),
                      let secondRange = Range(match.range(at: 2), in: line) else { break }
                let minute = Double(line[minuteRange]) ?? 0
                let second = Double(line[secondRange]) ?? 0
                var fraction = 0.0
                if let fractionRange = Range(match.range(at: 3), in: line) {
                    let rawFraction = String(line[fractionRange])
                    fraction = (Double(rawFraction) ?? 0) / pow(10, Double(rawFraction.count))
                }
                times.append(minute * 60 + second + fraction)
                line.removeSubrange(fullRange)
                line = String(line.drop(while: { $0 == " " || $0 == "\t" }))
            }
            let content = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty, !times.isEmpty else { continue }
            for time in times {
                rawLines.append((time, content))
            }
        }
        rawLines.sort { $0.time < $1.time }

        return rawLines.enumerated().map { index, line in
            let nextTime = index + 1 < rawLines.count ? rawLines[index + 1].time : line.time + 5
            return PlayerEngine.LyricLine(from: line.time, to: max(nextTime, line.time + 1), text: line.text)
        }
    }

    /// LRCLIB 有些条目只有纯文本歌词。为了让用户能点开查看,按行生成稳定的弱时间轴。
    private func parsePlainLyrics(_ text: String, duration: Int) -> [PlayerEngine.LyricLine] {
        let contents = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !contents.isEmpty else { return [] }

        let total = Double(max(duration, contents.count * 4))
        let step = max(2, total / Double(contents.count))
        return contents.enumerated().map { index, text in
            let start = Double(index) * step
            return PlayerEngine.LyricLine(
                from: start,
                to: min(total, start + step),
                text: text)
        }
    }

    /// 归一化歌名用于比较（去音调/标点/空白后小写）。
    private func comparable(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\s\-_/·・.,，。:：'"“”‘’()\[\]【】（）《》「」!！?？]"#, with: "", options: .regularExpression)
            .lowercased()
    }

    private func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        let left = Array(lhs)
        let right = Array(rhs)
        let distance = levenshtein(left, right)
        return 1 - Double(distance) / Double(max(left.count, right.count))
    }

    private func levenshtein(_ lhs: [Character], _ rhs: [Character]) -> Int {
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var previous = Array(0...rhs.count)
        var current = Array(repeating: 0, count: rhs.count + 1)
        for (i, left) in lhs.enumerated() {
            current[0] = i + 1
            for (j, right) in rhs.enumerated() {
                let substitution = previous[j] + (left == right ? 0 : 1)
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }

    private func compactWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dedupe<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    private func dedupe(_ candidates: [Candidate]) -> [Candidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = candidate.id.map(String.init)
                ?? [candidate.trackName, candidate.artistName, candidate.albumName ?? ""]
                    .map(comparable)
                    .joined(separator: "|")
            return seen.insert(key).inserted
        }
    }
}
