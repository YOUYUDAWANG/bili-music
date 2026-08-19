import Foundation

struct AMLLLyricsProvider: Sendable {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 2.5
            configuration.timeoutIntervalForResource = 3
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func lyrics(for result: LyricsSearchResult) async -> LyricsDocument? {
        guard let folder = folder(for: result.provider) else { return nil }
        for base in Self.endpointBases {
            let url = URL(string: "\(base)/\(folder)/\(result.id).ttml")
            guard let url else { continue }
            var request = URLRequest(url: url)
            request.setValue("BiliMusic/iOS", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let ttml = String(data: data, encoding: .utf8),
                  ttml.contains("<p") else { continue }
            let parsed = AMLLTTMLParser.parse(ttml)
            guard !parsed.lyric.isEmpty else { continue }
            return LyricsDocument(
                result: LyricsSearchResult(
                    provider: .amll,
                    id: result.id,
                    title: result.title,
                    artist: result.artist,
                    album: result.album,
                    duration: result.duration,
                    artworkID: result.artworkID),
                lyric: parsed.lyric,
                translatedLyric: parsed.translation,
                romanizedLyric: parsed.romanization,
                karaokeLyric: parsed.karaoke,
                karaokeTranslatedLyric: nil,
                versionScope: .sameRecording,
                timingKind: parsed.karaoke == nil ? .line : .word)
        }
        return nil
    }

    private static let endpointBases = [
        "https://amlldb.bikonoo.com",
        "https://raw.githubusercontent.com/amll-dev/amll-ttml-db/main",
    ]

    private func folder(for provider: LyricsProvider) -> String? {
        switch provider {
        case .netease: "ncm-lyrics"
        case .tencent: "qq-lyrics"
        default: nil
        }
    }
}

enum AMLLTTMLParser {
    static func parse(_ ttml: String) -> (lyric: String, karaoke: String?, translation: String?, romanization: String?) {
        var lyricLines: [String] = []
        var karaokeLines: [String] = []
        var translationLines: [String] = []
        var romanizationLines: [String] = []
        let paragraphs = ttml.components(separatedBy: "<p").dropFirst()
        for paragraph in paragraphs {
            let begin = attribute(paragraph, name: "begin")
            let end = attribute(paragraph, name: "end")
            guard let beginSeconds = seconds(begin) else { continue }
            let endSeconds = seconds(end) ?? beginSeconds + 2
            let spans = classifiedSpans(in: paragraph)
            let mainSpans = spans.filter { $0.kind == .lyric || $0.kind == .background }
            let text = mainSpans.map(\.text).joined()
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            lyricLines.append("[\(lrcTimestamp(beginSeconds))]\(clean)")
            if mainSpans.count > 1 {
                let durationMS = Int(((endSeconds - beginSeconds) * 1000).rounded())
                let words = mainSpans.map { span in
                    let offset = Int(((span.begin - beginSeconds) * 1000).rounded())
                    let length = Int(((span.end - span.begin) * 1000).rounded())
                    return "(\(max(offset, 0)),\(max(length, 80)),0)\(span.text)"
                }.joined()
                karaokeLines.append("[\(Int((beginSeconds * 1000).rounded())),\(max(durationMS, 80))]\(words)")
            }
            if let translation = spans.first(where: { $0.kind == .translation })?.text {
                translationLines.append("[\(lrcTimestamp(beginSeconds))]\(translation)")
            }
            if let romanization = spans.first(where: { $0.kind == .romanization })?.text {
                romanizationLines.append("[\(lrcTimestamp(beginSeconds))]\(romanization)")
            }
        }
        return (
            lyricLines.joined(separator: "\n"),
            karaokeLines.isEmpty ? nil : karaokeLines.joined(separator: "\n"),
            translationLines.isEmpty ? nil : translationLines.joined(separator: "\n"),
            romanizationLines.isEmpty ? nil : romanizationLines.joined(separator: "\n")
        )
    }

    private static func attribute(_ text: String, name: String) -> String? {
        let pattern = #"\#(name)="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private enum SpanKind {
        case lyric, background, translation, romanization
    }

    private static func classifiedSpans(
        in paragraph: String
    ) -> [(begin: Double, end: Double, text: String, kind: SpanKind)] {
        let chunks = paragraph.components(separatedBy: "<span").dropFirst()
        var spans: [(begin: Double, end: Double, text: String, kind: SpanKind)] = []
        for chunk in chunks {
            let role = (attribute(chunk, name: "ttm:role") ?? attribute(chunk, name: "role") ?? "").lowercased()
            let lang = (attribute(chunk, name: "xml:lang") ?? attribute(chunk, name: "lang") ?? "").lowercased()
            let kind: SpanKind
            if role.contains("translation") || lang.hasPrefix("zh") {
                kind = .translation
            } else if role.contains("roman") || lang.contains("latn") {
                kind = .romanization
            } else if role.contains("bg") || role.contains("background") {
                kind = .background
            } else {
                kind = .lyric
            }
            let begin = seconds(attribute(chunk, name: "begin")) ?? 0
            let end = seconds(attribute(chunk, name: "end")) ?? begin
            let text = stripTags(chunk.components(separatedBy: ">").dropFirst().joined(separator: ">"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                spans.append((begin, end, text, kind))
            }
        }
        if spans.filter({ $0.kind == .lyric || $0.kind == .background }).isEmpty,
           spans.isEmpty {
            let body = stripTags(paragraph.components(separatedBy: ">").dropFirst().joined(separator: ">"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                spans.append((0, 0, body, .lyric))
            }
        }
        return spans
    }

    private static func stripTags(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    private static func seconds(_ value: String?) -> Double? {
        guard let value, !value.isEmpty else { return nil }
        let parts = value.split(separator: ":").map(String.init)
        if parts.count == 3, let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(parts[2]) {
            return hours * 3600 + minutes * 60 + seconds
        }
        if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) {
            return minutes * 60 + seconds
        }
        return Double(value)
    }

    private static func lrcTimestamp(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let rest = seconds - Double(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, rest)
    }
}
