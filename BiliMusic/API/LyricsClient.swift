import Foundation

/// 在线歌词:LRCLIB 同步歌词。B 站标题噪声多、artist 是 UP主而非歌手,
/// 所以先从标题解析真实歌名/歌手,再用「标题相似 + 时长门槛」严格匹配,宁可没有也不错配。
struct LyricsClient {
    struct Candidate: Decodable {
        let trackName: String
        let artistName: String
        let albumName: String?
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    enum LyricsError: Error { case noMatch }

    func lyrics(for track: Track) async throws -> [PlayerEngine.LyricLine] {
        let parsed = Self.parseSong(from: track.title)

        // 候选来源:① 歌名+歌手精确搜(若解析出歌手)② 自由文本搜兜底
        var candidates: [Candidate] = []
        if let artist = parsed.artist, !artist.isEmpty {
            candidates += (try? await searchByFields(track: parsed.title, artist: artist)) ?? []
        }
        let freeQuery = [parsed.title, parsed.artist].compactMap { $0 }.joined(separator: " ")
        candidates += (try? await searchFreeText(freeQuery)) ?? []

        guard let best = bestCandidate(candidates, songTitle: parsed.title, duration: track.duration),
              let synced = best.syncedLyrics, !synced.isEmpty else {
            throw LyricsError.noMatch
        }
        let lines = parseLRC(synced)
        guard !lines.isEmpty else { throw LyricsError.noMatch }
        return lines
    }

    // MARK: - 请求

    private func searchByFields(track: String, artist: String) async throws -> [Candidate] {
        try await request(queryItems: [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist),
        ])
    }

    private func searchFreeText(_ query: String) async throws -> [Candidate] {
        try await request(queryItems: [URLQueryItem(name: "q", value: query)])
    }

    private func request(queryItems: [URLQueryItem]) async throws -> [Candidate] {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.setValue("BiliMusic iOS personal app", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONDecoder().decode([Candidate].self, from: data)) ?? []
    }

    // MARK: - 匹配

    /// 双重硬门槛:歌名必须相似 + 时长接近(都已知时差 ≤12 秒),再按分数取最高。
    private func bestCandidate(_ candidates: [Candidate], songTitle: String, duration: Int) -> Candidate? {
        let wanted = comparable(songTitle)
        guard !wanted.isEmpty else { return nil }
        return candidates
            .filter { ($0.syncedLyrics?.isEmpty == false) }
            .filter { candidate in
                let ct = comparable(candidate.trackName)
                guard !ct.isEmpty else { return false }
                return ct == wanted || ct.contains(wanted) || wanted.contains(ct)
            }
            .filter { candidate in
                guard duration > 0, let cd = candidate.duration else { return true }
                return abs(cd - Double(duration)) <= 12
            }
            .map { ($0, score($0, songTitle: wanted, duration: duration)) }
            .max { $0.1 < $1.1 }?
            .0
    }

    private func score(_ candidate: Candidate, songTitle wanted: String, duration: Int) -> Int {
        var value = 0
        let ct = comparable(candidate.trackName)
        if ct == wanted { value += 50 }
        else if ct.contains(wanted) || wanted.contains(ct) { value += 30 }

        if duration > 0, let cd = candidate.duration {
            switch abs(cd - Double(duration)) {
            case 0...3: value += 30
            case 3...7: value += 18
            default: value += 6
            }
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

    // MARK: - 标题解析

    /// 噪声词:画质/音质/修复/官方等,与歌名无关。
    private static let noiseTokens = [
        "4k", "8k", "1080p", "2160p", "60fps", "60帧", "hi-res", "hires", "无损", "flac",
        "dolby", "杜比", "修复", "重制", "高清", "超清", "official", "官方", "mv", "完整版",
        "纯享", "现场", "live", "字幕", "歌词", "cd音轨", "臻彩", "收录", "原版", "超高清",
        "lyrics", "lyric", "remastered", "hd",
    ]

    /// 从 B 站标题解析出 (歌名, 歌手?)。优先取《》「」内的歌名,括号外靠前的当歌手。
    static func parseSong(from rawTitle: String) -> (title: String, artist: String?) {
        var text = rawTitle
        // 去掉【】[]()（) 整块噪声
        text = regexReplace(text, #"[【\[（(][^】\]）)]*[】\]）)]"#, with: " ")
        for token in noiseTokens {
            text = text.replacingOccurrences(of: token, with: " ", options: .caseInsensitive)
        }
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 《歌名》/「歌名」:括号内是歌名,括号前残留文字当歌手
        if let match = text.range(of: #"[《「][^》」]+[》」]"#, options: .regularExpression) {
            let song = String(text[match])
                .trimmingCharacters(in: CharacterSet(charactersIn: "《》「」 "))
            let before = text[..<match.lowerBound]
                .trimmingCharacters(in: CharacterSet(charactersIn: " -—_/|"))
            return (song, before.isEmpty ? nil : before)
        }
        // 没有书名号:整串当歌名(可能含"歌手 歌名"),交给时长门槛兜底
        return (text, nil)
    }

    private static func regexReplace(_ text: String, _ pattern: String, with replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    // MARK: - LRC 解析

    private func parseLRC(_ text: String) -> [PlayerEngine.LyricLine] {
        let pattern = #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]\s*(.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let rawLines: [(time: Double, text: String)] = text
            .split(whereSeparator: \.isNewline)
            .compactMap { raw in
                let line = String(raw)
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard let match = regex.firstMatch(in: line, range: range),
                      let minuteRange = Range(match.range(at: 1), in: line),
                      let secondRange = Range(match.range(at: 2), in: line) else {
                    return nil
                }
                let minute = Double(line[minuteRange]) ?? 0
                let second = Double(line[secondRange]) ?? 0
                var fraction = 0.0
                if let fractionRange = Range(match.range(at: 3), in: line) {
                    let rawFraction = String(line[fractionRange])
                    fraction = (Double(rawFraction) ?? 0) / pow(10, Double(rawFraction.count))
                }
                let textRange = Range(match.range(at: 4), in: line)
                let content = textRange.map { String(line[$0]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                guard !content.isEmpty else { return nil }
                return (minute * 60 + second + fraction, content)
            }
            .sorted { $0.time < $1.time }

        return rawLines.enumerated().map { index, line in
            let nextTime = index + 1 < rawLines.count ? rawLines[index + 1].time : line.time + 5
            return PlayerEngine.LyricLine(from: line.time, to: max(nextTime, line.time + 1), text: line.text)
        }
    }

    private func comparable(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\s\-_/·・.,，。:：'"“”‘’()\[\]【】（）《》「」!！?？]"#, with: "", options: .regularExpression)
            .lowercased()
    }
}
