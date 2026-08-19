import Foundation

enum LyricStageTokenizer {
    private static let japaneseParticles: Set<String> = [
        "は", "が", "を", "に", "で", "と", "も", "の", "か", "ね", "よ", "な", "わ", "へ", "や", "て",
        "だ", "です", "ます",
    ]
    private static let chineseParticles: Set<String> = [
        "的", "了", "着", "过", "吗", "呢", "吧", "啊", "呀", "嘛",
    ]

    static func tokens(for line: PlayerEngine.LyricLine) -> [StageToken] {
        if !line.words.isEmpty {
            return tokensFromWords(line)
        }
        return tokensFromText(line.text)
    }

    static func glyphCount(for text: String) -> Int {
        Array(text).count
    }

    static func tokenCounts(for lines: [PlayerEngine.LyricLine]) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: lines.enumerated().map { index, line in
            (index, tokens(for: line).count)
        })
    }

    static func glyphCounts(for lines: [PlayerEngine.LyricLine]) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: lines.enumerated().map { index, line in
            (index, glyphCount(for: line.text))
        })
    }

    static func payloads(for lines: [PlayerEngine.LyricLine]) -> [StageTokenPayload] {
        lines.enumerated().flatMap { lineIndex, line in
            tokens(for: line).map { token in
                StageTokenPayload(
                    lineIndex: lineIndex,
                    id: token.id,
                    text: String(token.text.prefix(80)),
                    glyphFrom: token.glyphRange.lowerBound,
                    glyphTo: token.glyphRange.upperBound,
                    kind: token.kind)
            }
        }
    }

    private static func tokensFromWords(_ line: PlayerEngine.LyricLine) -> [StageToken] {
        let characters = Array(line.text)
        guard !characters.isEmpty else { return [] }
        let sortedWords = line.words.sorted { lhs, rhs in
            lhs.from == rhs.from ? lhs.to < rhs.to : lhs.from < rhs.from
        }
        var tokens: [StageToken] = []
        var cursor = line.text.startIndex
        var glyphCursor = 0

        for word in sortedWords {
            guard let range = line.text.range(of: word.text, range: cursor..<line.text.endIndex) else {
                return tokensFromText(line.text)
            }
            appendInterstitial(
                Array(line.text[cursor..<range.lowerBound]),
                glyphCursor: &glyphCursor,
                into: &tokens)
            let glyphLength = Array(line.text[range]).count
            tokens.append(
                StageToken(
                    id: tokens.count,
                    text: String(line.text[range]),
                    glyphRange: glyphCursor..<(glyphCursor + glyphLength),
                    kind: classifyToken(String(line.text[range])),
                    realTiming: word.from...max(word.from + 0.04, word.to)))
            glyphCursor += glyphLength
            cursor = range.upperBound
        }
        appendInterstitial(
            Array(line.text[cursor..<line.text.endIndex]),
            glyphCursor: &glyphCursor,
            into: &tokens)
        _ = characters
        return tokens
    }

    private static func appendInterstitial(
        _ characters: [Character],
        glyphCursor: inout Int,
        into tokens: inout [StageToken]
    ) {
        guard !characters.isEmpty else { return }
        var buffer = ""
        var bufferKind: StageTokenKind?
        var bufferStart = glyphCursor

        func flush() {
            guard let kind = bufferKind, !buffer.isEmpty else { return }
            tokens.append(
                StageToken(
                    id: tokens.count,
                    text: buffer,
                    glyphRange: bufferStart..<glyphCursor,
                    kind: kind,
                    realTiming: nil))
            buffer = ""
            bufferKind = nil
            bufferStart = glyphCursor
        }

        for character in characters {
            let piece = String(character)
            let kind = classifyToken(piece)
            if bufferKind == nil {
                bufferKind = kind
                bufferStart = glyphCursor
                buffer = piece
            } else if bufferKind == kind, kind == .whitespace {
                buffer.append(character)
            } else {
                flush()
                bufferKind = kind
                bufferStart = glyphCursor
                buffer = piece
            }
            glyphCursor += 1
            if kind != .whitespace { flush() }
        }
        flush()
    }

    private static func tokensFromText(_ text: String) -> [StageToken] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }
        var tokens: [StageToken] = []
        var index = 0
        while index < characters.count {
            let start = index
            let character = characters[index]
            let piece = String(character)
            if character.isWhitespace {
                while index < characters.count, characters[index].isWhitespace {
                    index += 1
                }
                tokens.append(
                    StageToken(
                        id: tokens.count,
                        text: String(characters[start..<index]),
                        glyphRange: start..<index,
                        kind: .whitespace,
                        realTiming: nil))
                continue
            }
            if isEmoji(piece) {
                index += 1
                tokens.append(
                    StageToken(
                        id: tokens.count,
                        text: piece,
                        glyphRange: start..<index,
                        kind: .emoji,
                        realTiming: nil))
                continue
            }
            if isPunctuation(character) {
                index += 1
                tokens.append(
                    StageToken(
                        id: tokens.count,
                        text: piece,
                        glyphRange: start..<index,
                        kind: .punctuation,
                        realTiming: nil))
                continue
            }
            if isCJK(character) {
                if let particle = multiCharacterParticle(in: characters, at: index) {
                    let end = index + particle.count
                    tokens.append(
                        StageToken(
                            id: tokens.count,
                            text: particle,
                            glyphRange: index..<end,
                            kind: .particle,
                            realTiming: nil))
                    index = end
                    continue
                }
                if particleKind(piece) == .particle {
                    index += 1
                    tokens.append(
                        StageToken(
                            id: tokens.count,
                            text: piece,
                            glyphRange: start..<index,
                            kind: .particle,
                            realTiming: nil))
                    continue
                }
                var end = index + 1
                while end < characters.count, end - index < 2 {
                    let next = String(characters[end])
                    if !isCJK(characters[end])
                        || isPunctuation(characters[end])
                        || particleKind(next) == .particle
                        || multiCharacterParticle(in: characters, at: end) != nil {
                        break
                    }
                    end += 1
                }
                tokens.append(
                    StageToken(
                        id: tokens.count,
                        text: String(characters[start..<end]),
                        glyphRange: start..<end,
                        kind: .word,
                        realTiming: nil))
                index = end
                continue
            }
            while index < characters.count {
                let next = characters[index]
                if next.isWhitespace || isPunctuation(next) || isCJK(next) || isEmoji(String(next)) {
                    break
                }
                index += 1
            }
            tokens.append(
                StageToken(
                    id: tokens.count,
                    text: String(characters[start..<index]),
                    glyphRange: start..<index,
                    kind: .word,
                    realTiming: nil))
        }
        return tokens
    }

    private static func classifyToken(_ text: String) -> StageTokenKind {
        if text.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
            return .whitespace
        }
        if isEmoji(text) { return .emoji }
        if text.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) }) {
            return .punctuation
        }
        if text.count == 1, let character = text.first, isCJK(character) {
            return particleKind(text)
        }
        return .word
    }

    private static func particleKind(_ text: String) -> StageTokenKind {
        japaneseParticles.contains(text) || chineseParticles.contains(text) ? .particle : .word
    }

    private static let multiCharacterParticles = ["です", "ます"]

    private static func multiCharacterParticle(in characters: [Character], at index: Int) -> String? {
        for particle in multiCharacterParticles {
            let end = index + particle.count
            guard end <= characters.count else { continue }
            if String(characters[index..<end]) == particle {
                return particle
            }
        }
        return nil
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)
                || (0x3400...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
        }
    }

    private static func isEmoji(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.properties.isEmoji && (scalar.properties.isEmojiPresentation || scalar.value > 0x238C)
        }
    }
}
