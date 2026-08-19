import Foundation

enum LyricStageBehavior: String, Codable, CaseIterable, Sendable {
    case assemble
    case gravityDrop
    case ripple
    case stretch
    case echo
    case drift
    case focus
    case converge
}

enum LyricStagePaletteRole: String, Codable, Sendable {
    case primary
    case accent
    case warm
    case secondary
}

struct LyricStageBible: Codable, Equatable, Sendable {
    let concept: String
    let motif: String
    let intensityArc: String

    func validated() -> LyricStageBible? {
        let concept = concept.trimmingCharacters(in: .whitespacesAndNewlines)
        let motif = motif.trimmingCharacters(in: .whitespacesAndNewlines)
        let intensityArc = intensityArc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !concept.isEmpty, !motif.isEmpty else { return nil }
        return LyricStageBible(
            concept: String(concept.prefix(160)),
            motif: String(motif.prefix(160)),
            intensityArc: String(intensityArc.prefix(200)))
    }
}

struct LyricStageDirective: Codable, Equatable, Sendable {
    let lineIndex: Int
    let behavior: LyricStageBehavior
    let alignment: LyricMotionAlignment?
    let direction: Int
    let intensity: Double
    let fontScale: Double
    let glyphStagger: Double
    let paletteRole: LyricStagePaletteRole?

    func validated(lineCount: Int) -> LyricStageDirective? {
        guard (0..<lineCount).contains(lineIndex) else { return nil }
        return LyricStageDirective(
            lineIndex: lineIndex,
            behavior: behavior,
            alignment: alignment,
            direction: direction < 0 ? -1 : 1,
            intensity: intensity.clamped(to: 0.35...1.25),
            fontScale: fontScale.clamped(to: 0.78...1.22),
            glyphStagger: glyphStagger.clamped(to: 0...0.14),
            paletteRole: paletteRole)
    }
}

struct LyricStageScene: Codable, Equatable, Sendable, Identifiable {
    var id: Int { lineIndex }

    let lineIndex: Int
    let from: Double
    let to: Double
    let behavior: LyricStageBehavior
    let alignment: LyricMotionAlignment
    let direction: Int
    let intensity: Double
    let fontSize: Double
    let glyphStagger: Double
    let paletteRole: LyricStagePaletteRole

    func validated(lineCount: Int) -> LyricStageScene? {
        guard (0..<lineCount).contains(lineIndex),
              from.isFinite,
              to.isFinite,
              from >= 0,
              to > from else { return nil }
        return LyricStageScene(
            lineIndex: lineIndex,
            from: from,
            to: to,
            behavior: behavior,
            alignment: alignment,
            direction: direction < 0 ? -1 : 1,
            intensity: intensity.clamped(to: 0.35...1.25),
            fontSize: fontSize.clamped(to: 20...38),
            glyphStagger: glyphStagger.clamped(to: 0...0.14),
            paletteRole: paletteRole)
    }
}

struct LyricStageScore: Codable, Equatable, Sendable {
    static let currentVersion = "lyric-performance-v5-stage-local"

    let version: String
    let trackID: String
    let lyricsHash: String
    let mood: String
    let scenes: [LyricStageScene]

    func validated(trackID: String, lyricsHash: String, lineCount: Int) -> LyricStageScore? {
        guard version == Self.currentVersion,
              self.trackID == trackID,
              self.lyricsHash == lyricsHash,
              lineCount > 0 else { return nil }
        var seen = Set<Int>()
        let safe = scenes.compactMap { scene -> LyricStageScene? in
            guard let scene = scene.validated(lineCount: lineCount),
                  seen.insert(scene.lineIndex).inserted else { return nil }
            return scene
        }
        guard safe.count == lineCount else { return nil }
        return LyricStageScore(
            version: version,
            trackID: trackID,
            lyricsHash: lyricsHash,
            mood: String(mood.prefix(80)),
            scenes: safe.sorted { $0.lineIndex < $1.lineIndex })
    }

    func scene(for lineIndex: Int) -> LyricStageScene? {
        scenes.first { $0.lineIndex == lineIndex }
    }
}

struct LyricStageGlyph: Equatable, Sendable, Identifiable {
    let id: Int
    let text: String
    let from: Double
    let to: Double
    let hasRealWordTiming: Bool
    let wordIndex: Int?
    let performanceFrom: Double
    let performanceTo: Double
}

enum LyricStageCompiler {
    static func compile(
        trackID: String,
        lines: [PlayerEngine.LyricLine],
        performanceScore: LyricPerformanceScore?
    ) -> LyricStageScore? {
        guard !lines.isEmpty else { return nil }
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(lines)
        let scenes = lines.enumerated().map { index, line in
            let fallback = LyricMotionDirector.cue(
                text: line.text,
                lineDuration: line.to - line.from,
                trackID: trackID,
                lineIndex: index,
                reduceMotion: false)
            let cue = performanceScore?.cue(for: index, fallback: fallback) ?? fallback
            let native = performanceScore?.stageDirective(for: index)
            let lunaScene = performanceScore?.scene(for: index)
            let isQuietBaseline = native == nil && lunaScene == nil
            let behavior: LyricStageBehavior
            if isQuietBaseline {
                behavior = line.overlapGroup == nil ? .focus : .converge
            } else {
                behavior = native?.behavior ?? mappedBehavior(
                    for: cue.effect,
                    role: line.voiceRole,
                    hasOverlap: line.overlapGroup != nil)
            }
            return LyricStageScene(
                lineIndex: index,
                from: max(0, line.from),
                to: max(line.from + 0.12, line.to),
                behavior: behavior,
                alignment: native?.alignment ?? cue.alignment,
                direction: native?.direction ?? (cue.direction < 0 ? -1 : 1),
                intensity: isQuietBaseline ? 0.4 : (native?.intensity ?? cue.intensity),
                fontSize: cue.fontSize * (native?.fontScale ?? 1),
                glyphStagger: isQuietBaseline ? min(0.04, stagger(for: line)) : (native?.glyphStagger ?? stagger(for: line)),
                paletteRole: native?.paletteRole ?? paletteRole(for: line.voiceRole, behavior: behavior))
        }
        return LyricStageScore(
            version: LyricStageScore.currentVersion,
            trackID: trackID,
            lyricsHash: lyricsHash,
            mood: performanceScore?.mood ?? "local-stage",
            scenes: scenes
        ).validated(trackID: trackID, lyricsHash: lyricsHash, lineCount: lines.count)
    }

    static func glyphs(for line: PlayerEngine.LyricLine) -> [LyricStageGlyph] {
        let characters = Array(line.text)
        guard !characters.isEmpty else { return [] }
        let sortedWords = line.words.sorted { lhs, rhs in
            lhs.from == rhs.from ? lhs.to < rhs.to : lhs.from < rhs.from
        }
        guard !sortedWords.isEmpty else {
            return performanceGlyphs(characters, line: line, wordIndex: nil, startingID: 0)
        }

        var result: [LyricStageGlyph] = []
        var cursor = line.text.startIndex
        for (wordIndex, word) in sortedWords.enumerated() {
            guard let range = line.text.range(of: word.text, range: cursor..<line.text.endIndex) else {
                return performanceGlyphs(characters, line: line, wordIndex: nil, startingID: 0)
            }
            let prefix = Array(line.text[cursor..<range.lowerBound])
            let tokenStart = performanceOrigin(forToken: wordIndex, line: line)
            if !prefix.isEmpty {
                result.append(contentsOf: timedGlyphs(
                    prefix,
                    syncFrom: max(line.from, word.from - 0.08),
                    syncTo: word.from,
                    line: line,
                    wordIndex: nil,
                    startingID: result.count,
                    performanceOrigin: max(line.from, tokenStart - 0.04)))
            }
            result.append(contentsOf: timedGlyphs(
                Array(line.text[range]),
                syncFrom: word.from,
                syncTo: max(word.from + 0.04, word.to),
                line: line,
                wordIndex: wordIndex,
                startingID: result.count,
                performanceOrigin: tokenStart))
            cursor = range.upperBound
        }
        if cursor < line.text.endIndex {
            result.append(contentsOf: timedGlyphs(
                Array(line.text[cursor...]),
                syncFrom: sortedWords.last?.to ?? line.from,
                syncTo: line.to,
                line: line,
                wordIndex: nil,
                startingID: result.count,
                performanceOrigin: performanceOrigin(forToken: sortedWords.count, line: line)))
        }
        return result
    }

    static func visibleLineIndices(
        lines: [PlayerEngine.LyricLine],
        at time: Double,
        performanceScore: LyricPerformanceScore?
    ) -> [Int] {
        let active = LyricHighlightModel.activeLineIndices(lines: lines, at: time)
        if active.count > 1 { return Array(active.prefix(3)) }
        let primary = active.first ?? lines.firstIndex(where: { $0.from > time })
        guard let primary else { return [] }
        let directed = performanceScore?.textLineIndices(for: primary) ?? [primary]
        var seen = Set<Int>()
        return directed.filter {
            lines.indices.contains($0) && seen.insert($0).inserted
        }.prefix(3).map { $0 }
    }

    private static func mappedBehavior(
        for effect: LyricMotionEffect,
        role: LyricVoiceRole,
        hasOverlap: Bool
    ) -> LyricStageBehavior {
        if hasOverlap || role == .duetA || role == .duetB || role == .together {
            return .converge
        }
        if role == .backing { return .echo }
        switch effect {
        case .rise, .cascade: return .assemble
        case .impact, .drop: return .gravityDrop
        case .drift: return .drift
        case .breathe: return .ripple
        case .echo: return .echo
        case .focus: return .focus
        case .stretch: return .stretch
        }
    }

    private static func paletteRole(
        for role: LyricVoiceRole,
        behavior: LyricStageBehavior
    ) -> LyricStagePaletteRole {
        switch role {
        case .backing: return .secondary
        case .duetA: return .accent
        case .duetB: return .warm
        case .lead, .together:
            return behavior == .gravityDrop ? .warm : .primary
        }
    }

    private static func stagger(for line: PlayerEngine.LyricLine) -> Double {
        let count = max(1, line.text.count)
        let available = max(0.4, line.to - line.from)
        return min(0.11, max(0.025, available * 0.35 / Double(count)))
    }

    private static func performanceGlyphs(
        _ characters: [Character],
        line: PlayerEngine.LyricLine,
        wordIndex: Int?,
        startingID: Int
    ) -> [LyricStageGlyph] {
        let tokens = LyricStageTokenizer.tokens(for: line)
        guard !tokens.isEmpty else {
            return timedGlyphs(
                characters,
                syncFrom: line.from,
                syncTo: line.to,
                line: line,
                wordIndex: wordIndex,
                startingID: startingID,
                realTiming: false)
        }
        var result: [LyricStageGlyph] = []
        for token in tokens {
            let slice = Array(token.text)
            result.append(contentsOf: timedGlyphs(
                slice,
                syncFrom: line.from,
                syncTo: line.to,
                line: line,
                wordIndex: token.kind == .word ? token.id : nil,
                startingID: startingID + result.count,
                realTiming: false,
                performanceOrigin: performanceOrigin(forToken: token.id, line: line)))
        }
        return result
    }

    private static func timedGlyphs(
        _ characters: [Character],
        syncFrom: Double,
        syncTo: Double,
        line: PlayerEngine.LyricLine,
        wordIndex: Int?,
        startingID: Int,
        realTiming: Bool = true,
        performanceOrigin: Double? = nil
    ) -> [LyricStageGlyph] {
        guard !characters.isEmpty else { return [] }
        let span = max(0.12, line.to - line.from)
        let entranceEnd = line.from + span * 0.35
        let origin = performanceOrigin ?? line.from
        let innerStagger = min(0.016, span * 0.04 / Double(max(1, characters.count)))
        return characters.enumerated().map { index, character in
            let performanceFrom = min(entranceEnd, origin + Double(index) * innerStagger)
            let performanceTo = max(performanceFrom + 0.08, line.from + span * 0.80)
            return LyricStageGlyph(
                id: startingID + index,
                text: String(character),
                from: realTiming ? max(0, syncFrom) : performanceFrom,
                to: realTiming ? max(syncFrom + 0.04, syncTo) : performanceTo,
                hasRealWordTiming: realTiming,
                wordIndex: wordIndex,
                performanceFrom: performanceFrom,
                performanceTo: performanceTo)
        }
    }

    private static func performanceOrigin(forToken tokenIndex: Int, line: PlayerEngine.LyricLine) -> Double {
        let span = max(0.12, line.to - line.from)
        return min(line.from + span * 0.35, line.from + Double(tokenIndex) * min(0.09, span * 0.14))
    }
}
