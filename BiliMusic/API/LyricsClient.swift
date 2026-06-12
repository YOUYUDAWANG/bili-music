import Foundation

struct LyricsClient {
    struct Candidate: Decodable {
        let trackName: String
        let artistName: String
        let albumName: String?
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    enum LyricsError: Error {
        case noMatch
    }

    func lyrics(for track: Track) async throws -> [PlayerEngine.LyricLine] {
        let queryTitle = normalizedTitle(track.title)
        let queryArtist = normalizedArtist(track.artist)
        let candidates = try await search(title: queryTitle, artist: queryArtist)
        guard let best = bestCandidate(from: candidates, title: queryTitle, artist: queryArtist, duration: track.duration),
              let synced = best.syncedLyrics,
              !synced.isEmpty else {
            throw LyricsError.noMatch
        }
        let lines = parseLRC(synced)
        guard !lines.isEmpty else { throw LyricsError.noMatch }
        return lines
    }

    private func search(title: String, artist: String) async throws -> [Candidate] {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("BiliMusic iOS personal app", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([Candidate].self, from: data)
    }

    private func bestCandidate(from candidates: [Candidate], title: String, artist: String, duration: Int) -> Candidate? {
        candidates
            .filter { ($0.syncedLyrics?.isEmpty == false) }
            .map { candidate in
                (candidate, score(candidate, title: title, artist: artist, duration: duration))
            }
            .filter { $0.1 >= 55 }
            .max { $0.1 < $1.1 }?
            .0
    }

    private func score(_ candidate: Candidate, title: String, artist: String, duration: Int) -> Int {
        let wantedTitle = comparable(title)
        let candidateTitle = comparable(candidate.trackName)
        let wantedArtist = comparable(artist)
        let candidateArtist = comparable(candidate.artistName)
        var value = 0

        if candidateTitle == wantedTitle {
            value += 55
        } else if candidateTitle.contains(wantedTitle) || wantedTitle.contains(candidateTitle) {
            value += 35
        }

        if !wantedArtist.isEmpty {
            if candidateArtist == wantedArtist {
                value += 25
            } else if candidateArtist.contains(wantedArtist) || wantedArtist.contains(candidateArtist) {
                value += 12
            }
        }

        if duration > 0, let candidateDuration = candidate.duration {
            let diff = abs(candidateDuration - Double(duration))
            switch diff {
            case 0...3: value += 25
            case 3...8: value += 15
            case 8...15: value += 5
            default: value -= 20
            }
        }

        if candidate.syncedLyrics != nil {
            value += 10
        }
        if candidate.albumName?.localizedCaseInsensitiveContains("伴奏") == true ||
            candidate.albumName?.localizedCaseInsensitiveContains("钢琴") == true ||
            candidate.albumName?.localizedCaseInsensitiveContains("piano") == true {
            value -= 8
        }
        return value
    }

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

    private func normalizedTitle(_ title: String) -> String {
        var cleaned = title
        let bracketPatterns = [
            #"\s*[\[【（(].*?(cover|翻唱|完整版|MV|官方|字幕|歌词|lyrics|live|现场|伴奏|纯享).*?[\]】）)]"#,
            #"\s*-\s*.*$"#,
        ]
        for pattern in bracketPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedArtist(_ artist: String) -> String {
        artist
            .replacingOccurrences(of: "Official", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "官方", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func comparable(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\s\-_/·・.,，。:：'"“”‘’()\[\]【】（）]"#, with: "", options: .regularExpression)
            .lowercased()
    }
}
