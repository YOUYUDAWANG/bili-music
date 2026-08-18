import Foundation

/// B 站标题只在结构足够明确时转换成歌名/歌手；普通列表不会展示低置信清洗结果。
enum TrackTitleParser {
    struct ParsedSong: Equatable {
        enum Confidence: Int {
            case low
            case medium
            case high
        }

        let title: String
        let artist: String?
        let confidence: Confidence

        var isDisplaySafe: Bool { confidence == .high }
    }

    private static let noiseTokens = [
        "4k", "8k", "1080p", "2160p", "60fps", "60帧", "hi-res", "hires", "无损", "flac",
        "dolby", "杜比", "修复", "重制", "高清", "超清", "official", "官方", "mv", "完整版",
        "纯享", "字幕", "歌词", "cd音轨", "臻彩", "收录", "原版", "超高清",
        "lyrics", "lyric", "remastered", "hd",
    ]

    static func parseSong(from rawTitle: String) -> (title: String, artist: String?) {
        let parsed = parseSongDetailed(from: rawTitle)
        return (parsed.title, parsed.artist)
    }

    static func parseSongForDisplay(from rawTitle: String, fallbackArtist: String) -> ParsedSong {
        let parsed = parseSongDetailed(from: rawTitle, fallbackArtist: fallbackArtist)
        guard parsed.isDisplaySafe else {
            return ParsedSong(title: rawTitle, artist: nil, confidence: .low)
        }
        return parsed
    }

    static func parseSongDetailed(from rawTitle: String, fallbackArtist: String? = nil) -> ParsedSong {
        let normalized = normalizeRawTitle(rawTitle)
        guard !normalized.isEmpty else {
            return ParsedSong(title: rawTitle, artist: nil, confidence: .low)
        }
        let text = removeNoiseBlocks(normalized)

        if let quoted = parseQuotedSong(text) {
            return quoted
        }
        if let separated = parseSeparatedSong(text) {
            return ParsedSong(title: separated.title, artist: separated.artist, confidence: .high)
        }
        if let bracketed = parseLeadingBracketSong(text, fallbackArtist: fallbackArtist) {
            return bracketed
        }

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
        let artist = [before, after].first { !$0.isEmpty && isLikelyArtist($0) }
        return ParsedSong(title: song, artist: artist, confidence: .high)
    }

    private static func parseSeparatedSong(_ text: String) -> (title: String, artist: String?)? {
        for separator in [" - ", " – ", " — ", " | ", "｜", " / "] where text.contains(separator) {
            let parts = text.components(separatedBy: separator)
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
        let pattern = #"^[【\[（(]([^】\]）)]{1,40})[】\]）)]\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let blockRange = Range(match.range(at: 1), in: text),
              let restRange = Range(match.range(at: 2), in: text) else { return nil }

        let block = cleanupTitleCandidate(String(text[blockRange]))
        let rest = cleanupTitleCandidate(String(text[restRange]))
        guard !block.isEmpty, !rest.isEmpty, !isNoiseBlock(block) else { return nil }

        let fallback = fallbackArtist.map(cleanupArtistCandidate) ?? ""
        let comparableBlock = comparableKey(block)
        let comparableRest = comparableKey(rest)
        let comparableFallback = comparableKey(fallback)
        if !comparableFallback.isEmpty,
           comparableBlock == comparableFallback,
           isSafeStandaloneTitle(rest) {
            return ParsedSong(title: rest, artist: block, confidence: .high)
        }
        if !comparableFallback.isEmpty,
           comparableRest == comparableFallback,
           isSafeStandaloneTitle(block) {
            return ParsedSong(title: block, artist: fallback, confidence: .high)
        }
        return nil
    }

    private static func isLikelyArtist(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 40 else { return false }
        let lower = value.lowercased()
        return !["cover", "翻唱", "合集", "歌单", "playlist", "reaction"].contains {
            lower.localizedCaseInsensitiveContains($0)
        }
    }

    private static func normalizeRawTitle(_ rawTitle: String) -> String {
        rawTitle
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeNoiseBlocks(_ text: String) -> String {
        let pattern = #"[【\[（(]([^】\]）)]*)[】\]）)]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = ""
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let fullRange = Range(match.range(at: 0), in: text),
                  let contentRange = Range(match.range(at: 1), in: text) else { continue }
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
        removeNoiseTokens(from: removeNoiseBlocks(value))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -—_/|｜·・:：,，.。"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeNoiseTokens(from value: String) -> String {
        var text = value
        for token in noiseTokens {
            if token.unicodeScalars.allSatisfy(\.isASCII) {
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
            "mv", "musicvideo", "字幕", "中字", "lyrics", "lyric", "完整版", "纯享", "remastered", "hd",
        ]
        return noise.contains {
            lower.localizedCaseInsensitiveContains($0) || compact.contains(comparableKey($0))
        }
    }

    private static func isSafeStandaloneTitle(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...32).contains(text.count) else { return false }
        let lower = text.lowercased()
        return !["reaction", "解析", "盘点", "合集", "歌单", "playlist", "教程", "鉴赏", "排行", "推荐"].contains {
            lower.localizedCaseInsensitiveContains($0)
        }
    }

    private static func comparableKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\s\-_/·・.,，。:：'\"“”‘’()\[\]【】（）《》「」『』!！?？]"#, with: "", options: .regularExpression)
            .lowercased()
    }
}
