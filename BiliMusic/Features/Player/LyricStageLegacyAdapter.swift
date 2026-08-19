import Foundation

enum LyricStageLegacyAdapter {
    static func adapt(
        trackID: String,
        lines: [PlayerEngine.LyricLine],
        performanceScore: LyricPerformanceScore?
    ) -> LyricStageScoreV2 {
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(lines)
        let tokens = lines.map(LyricStageTokenizer.tokens(for:))
        var scenes: [StageScene] = []

        for (index, line) in lines.enumerated() {
            let fallback = LyricMotionDirector.cue(
                text: line.text,
                lineDuration: line.to - line.from,
                trackID: trackID,
                lineIndex: index,
                reduceMotion: false)
            let cue = performanceScore?.cue(for: index, fallback: fallback) ?? fallback
            let native = performanceScore?.stageDirective(for: index)
            let lunaScene = performanceScore?.scene(for: index)
            let wordCue = performanceScore?.wordCue(for: index)
            let overlap = line.overlapGroup != nil || line.voiceRole == .duetA || line.voiceRole == .duetB
            let composition: StageComposition = overlap ? .splitVoices : .singleAnchor
            let verb = verb(
                for: native?.behavior,
                effect: cue.effect,
                overlap: overlap)
            let baseID = "legacy-\(index)-base"
            let cueID = "legacy-\(index)-cue"
            var actors = [
                StageActor(
                    id: baseID,
                    target: .line(lineIndex: index),
                    role: overlap ? (line.voiceRole == .duetB ? .vocalB : .vocalA) : .base,
                    anchor: overlap
                        ? (line.voiceRole == .duetB ? .trailing : .leading)
                        : .center,
                    typeRole: .normal,
                    paletteRole: paletteRole(for: line.voiceRole)),
            ]
            var events = [
                StageEvent(
                    actorID: baseID,
                    phase: .entrance,
                    verb: verb,
                    start: 0,
                    duration: 0.35,
                    intensity: native?.intensity ?? cue.intensity,
                    reason: overlap ? .vocalOverlap : .structuralTransition,
                    relation: overlap ? .mirrorWith(actorID: "legacy-peer") : nil),
                StageEvent(
                    actorID: baseID,
                    phase: .exit,
                    verb: .dissolve,
                    start: 0.80,
                    duration: 0.20,
                    intensity: 0.7,
                    reason: .structuralTransition),
            ]

            if let wordCue, wordCue.effect != .sweep {
                let tokenIndices = tokenIndices(
                    in: tokens[safe: index] ?? [],
                    coveringWords: wordCue.startWordIndex...wordCue.endWordIndex,
                    line: line)
                if !tokenIndices.isEmpty {
                    actors.append(
                        StageActor(
                            id: cueID,
                            target: .tokens(lineIndex: index, tokenIndices: tokenIndices),
                            role: .protagonist,
                            anchor: .center,
                            typeRole: tokenIndices.count <= 3 ? .emphasis : .normal,
                            paletteRole: .accent))
                    events.append(
                        StageEvent(
                            actorID: cueID,
                            phase: .performance,
                            verb: wordVerb(wordCue.effect),
                            start: 0.35,
                            duration: 0.45,
                            intensity: wordCue.intensity,
                            reason: reason(for: wordCue.effect),
                            priority: 1))
                }
            }

            scenes.append(
                StageScene(
                    id: "legacy-scene-\(index)",
                    lineIndices: performanceScore?.textLineIndices(for: index) ?? [index],
                    composition: composition,
                    actors: actors,
                    events: events,
                    handoffOut: .dissolve))
        }

        return LyricStageScoreV2(
            version: LyricStageScoreV2Version.current,
            trackID: trackID,
            lyricsHash: lyricsHash,
            styleSheet: StageStyleSheet(
                concept: performanceScore?.stageBible?.concept ?? "legacy-stage",
                paletteStrategy: .coverAnalogous,
                typeSystem: .iPhone17Pro,
                motifs: [
                    StageMotif(id: "echo-repeat", verb: .echo, note: "legacy echoTrail / repeat"),
                ]),
            sections: LyricStageDirectorV2.sections(for: lines),
            scenes: scenes)
    }

    static func verb(
        for behavior: LyricStageBehavior?,
        effect: LyricMotionEffect,
        overlap: Bool
    ) -> StageVerb {
        if overlap { return .appear }
        if let behavior {
            switch behavior {
            case .assemble: return .assemble
            case .gravityDrop: return .drop
            case .ripple: return .drift
            case .stretch: return .stretch
            case .echo: return .echo
            case .drift: return .drift
            case .focus: return .appear
            case .converge: return .appear
            }
        }
        switch effect {
        case .rise, .cascade: return .assemble
        case .impact, .drop: return .drop
        case .drift: return .drift
        case .breathe: return .appear
        case .echo: return .echo
        case .focus: return .appear
        case .stretch: return .stretch
        }
    }

    private static func wordVerb(_ effect: LyricWordEffect) -> StageVerb {
        switch effect {
        case .impact: return .pulse
        case .stretch: return .stretch
        case .echoTrail: return .echo
        case .sweep: return .appear
        }
    }

    private static func reason(for effect: LyricWordEffect) -> StageEventReason {
        switch effect {
        case .impact: return .actionWord
        case .stretch: return .sustainedPhrase
        case .echoTrail: return .hookRepeat
        case .sweep: return .structuralTransition
        }
    }

    private static func paletteRole(for role: LyricVoiceRole) -> StagePaletteRole {
        switch role {
        case .backing: return .secondary
        case .duetA: return .accent
        case .duetB: return .warm
        case .lead, .together: return .primary
        }
    }

    private static func tokenIndices(
        in tokens: [StageToken],
        coveringWords wordRange: ClosedRange<Int>,
        line: PlayerEngine.LyricLine
    ) -> [Int] {
        let words = line.words.sorted { $0.from < $1.from }
        guard words.indices.contains(wordRange.lowerBound) else { return [] }
        let texts = wordRange.compactMap { words[safe: $0]?.text }
        var cursor = 0
        var matches: [Int] = []
        for text in texts {
            if let index = tokens[cursor...].firstIndex(where: { $0.text == text && $0.kind != .whitespace }) {
                matches.append(index)
                cursor = index + 1
            }
        }
        return matches
    }
}
