import Foundation

struct LyricWordDisplayToken: Identifiable, Equatable, Sendable {
    let id: Int
    var text: String
    let wordIndex: Int?
    let from: Double
    let to: Double
}

enum LyricWordPlaybackState: Equatable, Sendable {
    case unsung
    case current(progress: Double)
    case sung
}

enum LyricWordPerformanceModel {
    static func displayTokens(for line: PlayerEngine.LyricLine) -> [LyricWordDisplayToken] {
        let words = line.words.sorted { lhs, rhs in
            if lhs.from == rhs.from { return lhs.to < rhs.to }
            return lhs.from < rhs.from
        }
        guard !words.isEmpty else {
            return [LyricWordDisplayToken(
                id: 0,
                text: line.text,
                wordIndex: nil,
                from: line.from,
                to: line.to)]
        }

        var cursor = line.text.startIndex
        var tokens: [LyricWordDisplayToken] = []
        for (index, word) in words.enumerated() {
            guard cursor <= line.text.endIndex,
                  let range = line.text.range(
                    of: word.text,
                    options: [],
                    range: cursor..<line.text.endIndex) else {
                return [LyricWordDisplayToken(
                    id: 0,
                    text: line.text,
                    wordIndex: nil,
                    from: line.from,
                    to: line.to)]
            }
            let prefix = String(line.text[cursor..<range.lowerBound])
            tokens.append(LyricWordDisplayToken(
                id: index,
                text: prefix + String(line.text[range]),
                wordIndex: index,
                from: word.from,
                to: word.to))
            cursor = range.upperBound
        }
        if cursor < line.text.endIndex, !tokens.isEmpty {
            tokens[tokens.count - 1].text += String(line.text[cursor...])
        }
        return tokens
    }

    static func playbackState(
        for token: LyricWordDisplayToken,
        at time: Double
    ) -> LyricWordPlaybackState {
        guard token.wordIndex != nil else { return .unsung }
        if time >= token.to { return .sung }
        guard time >= token.from else { return .unsung }
        let duration = max(token.to - token.from, 0.04)
        return .current(progress: min(max((time - token.from) / duration, 0), 1))
    }
}
