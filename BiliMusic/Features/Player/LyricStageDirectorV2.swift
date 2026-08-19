import Foundation

enum LyricStageDirectorV2 {
    static func compose(
        trackID: String,
        lines: [PlayerEngine.LyricLine]
    ) -> LyricStageScoreV2 {
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(lines)
        let tokens = lines.map(LyricStageTokenizer.tokens(for:))
        let sections = sections(for: lines)
        let repeats = repeatedTexts(in: lines)
        var scenes: [StageScene] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if let group = line.overlapGroup {
                let clustered = cluster(startingAt: index, group: group, lines: lines)
                scenes.append(duetScene(indices: clustered, lines: lines))
                index = clustered.max().map { $0 + 1 } ?? (index + 1)
                continue
            }
            scenes.append(
                lineScene(
                    index: index,
                    line: line,
                    tokens: tokens[safe: index] ?? [],
                    sections: sections,
                    isRepeat: repeats.contains(normalized(line.text))))
            index += 1
        }
        return LyricStageScoreV2(
            version: LyricStageScoreV2Version.current,
            trackID: trackID,
            lyricsHash: lyricsHash,
            styleSheet: StageStyleSheet(
                concept: "quiet local stage",
                paletteStrategy: .coverAnalogous,
                typeSystem: .iPhone17Pro,
                motifs: [
                    StageMotif(id: "echo-repeat", verb: .echo, note: "reprise uses the same echo motif"),
                ]),
            sections: sections,
            scenes: scenes)
    }

    static func sections(for lines: [PlayerEngine.LyricLine]) -> [StageSection] {
        guard !lines.isEmpty else { return [] }
        let last = lines.count - 1
        let introEnd = max(0, Int((Double(lines.count) * 0.12).rounded(.down)))
        let outroStart = min(last, max(introEnd + 1, Int((Double(lines.count) * 0.88).rounded(.down))))
        let repeats = repeatedTexts(in: lines)
        let chorusHits = lines.enumerated().compactMap { index, line -> Int? in
            repeats.contains(normalized(line.text)) ? index : nil
        }
        let chorusFrom = chorusHits.min() ?? min(last, introEnd + 1)
        let chorusTo = chorusHits.max() ?? chorusFrom
        var result: [StageSection] = [
            StageSection(
                id: "intro",
                lineFrom: 0,
                lineTo: introEnd,
                kind: .intro,
                density: 0.10,
                heroBudget: 0,
                accentBudget: 0.08,
                preferredMotifs: []),
        ]
        if chorusFrom > introEnd + 1 {
            result.append(
                StageSection(
                    id: "verse-a",
                    lineFrom: min(last, introEnd + 1),
                    lineTo: max(introEnd + 1, chorusFrom - 1),
                    kind: .verse,
                    density: 0.20,
                    heroBudget: 0,
                    accentBudget: 0.12,
                    preferredMotifs: []))
        }
        result.append(
            StageSection(
                id: "chorus",
                lineFrom: chorusFrom,
                lineTo: max(chorusFrom, min(outroStart, chorusTo)),
                kind: chorusHits.isEmpty ? .verse : .chorus,
                density: chorusHits.isEmpty ? 0.20 : 0.85,
                heroBudget: chorusHits.isEmpty ? 0 : 1,
                accentBudget: chorusHits.isEmpty ? 0.12 : 0.20,
                preferredMotifs: chorusHits.isEmpty ? [] : ["echo-repeat"]))
        if outroStart > (result.last?.lineTo ?? 0) + 1 {
            result.append(
                StageSection(
                    id: "verse-b",
                    lineFrom: (result.last?.lineTo ?? 0) + 1,
                    lineTo: max((result.last?.lineTo ?? 0) + 1, outroStart - 1),
                    kind: .verse,
                    density: 0.20,
                    heroBudget: 0,
                    accentBudget: 0.12,
                    preferredMotifs: []))
        }
        result.append(
            StageSection(
                id: "outro",
                lineFrom: outroStart,
                lineTo: last,
                kind: .outro,
                density: 0.15,
                heroBudget: 0,
                accentBudget: 0.08,
                preferredMotifs: []))
        return result
    }

    static func fillMissingScenes(
        in score: LyricStageScoreV2,
        lines: [PlayerEngine.LyricLine]
    ) -> LyricStageScoreV2 {
        let covered = Set(score.scenes.flatMap(\.lineIndices))
        guard covered.count < lines.count else { return score }
        let local = compose(trackID: score.trackID, lines: lines)
        let extras = local.scenes.compactMap { scene -> StageScene? in
            trimmedFallbackScene(scene, uncovered: scene.lineIndices.filter { !covered.contains($0) })
        }
        return LyricStageScoreV2(
            version: score.version,
            trackID: score.trackID,
            lyricsHash: score.lyricsHash,
            styleSheet: score.styleSheet,
            sections: score.sections.isEmpty ? local.sections : score.sections,
            scenes: score.scenes + extras,
            droppedEvents: score.droppedEvents)
    }

    private static func trimmedFallbackScene(_ scene: StageScene, uncovered: [Int]) -> StageScene? {
        guard !uncovered.isEmpty else { return nil }
        if uncovered == scene.lineIndices { return scene }
        let actors = scene.actors.filter { uncovered.contains($0.target.lineIndex) }
        guard !actors.isEmpty else { return nil }
        let actorIDs = Set(actors.map(\.id))
        let composition: StageComposition
        if uncovered.count == 1 {
            composition = .singleAnchor
        } else if scene.composition == .splitVoices {
            composition = .splitVoices
        } else {
            composition = scene.composition
        }
        return StageScene(
            id: scene.id + "-gap",
            lineIndices: uncovered,
            composition: composition,
            actors: actors,
            events: scene.events.filter { actorIDs.contains($0.actorID) },
            handoffOut: scene.handoffOut)
    }

    private static func lineScene(
        index: Int,
        line: PlayerEngine.LyricLine,
        tokens: [StageToken],
        sections: [StageSection],
        isRepeat: Bool
    ) -> StageScene {
        let section = sections.first { $0.lineRange.contains(index) }
        let isQuiet = (section?.kind == .verse || section?.kind == .intro || section?.kind == .outro)
            && !isRepeat
        let baseID = "local-\(index)-base"
        var actors = [
            StageActor(
                id: baseID,
                target: .line(lineIndex: index),
                role: .base,
                anchor: .center,
                typeRole: .normal,
                paletteRole: .primary),
        ]
        var events = [
            StageEvent(
                actorID: baseID,
                phase: .entrance,
                verb: .appear,
                start: 0,
                duration: 0.35,
                intensity: 0.45,
                reason: .structuralTransition),
            StageEvent(
                actorID: baseID,
                phase: .exit,
                verb: .dissolve,
                start: 0.80,
                duration: 0.20,
                intensity: 0.6,
                reason: .structuralTransition),
            StageEvent(
                actorID: baseID,
                phase: .hold,
                verb: .pulse,
                start: 0.35,
                duration: 0.45,
                intensity: 0.32,
                reason: .sustainedPhrase),
        ]
        if isRepeat {
            events.append(
                StageEvent(
                    actorID: baseID,
                    phase: .performance,
                    verb: .echo,
                    start: 0.38,
                    duration: 0.36,
                    intensity: 0.7,
                    motifRef: "echo-repeat",
                    reason: .hookRepeat,
                    priority: 1))
        } else if !isQuiet, containsImpact(line.text), let token = emphasisToken(in: tokens) {
            let cueID = "local-\(index)-word"
            actors.append(
                StageActor(
                    id: cueID,
                    target: .tokens(lineIndex: index, tokenIndices: [token.id]),
                    role: .supporting,
                    anchor: .center,
                    typeRole: .emphasis,
                    paletteRole: .accent))
            events.append(
                StageEvent(
                    actorID: cueID,
                    phase: .performance,
                    verb: .pulse,
                    start: 0.40,
                    duration: 0.30,
                    intensity: 0.8,
                    reason: .actionWord,
                    priority: 1))
        }
        return StageScene(
            id: "local-scene-\(index)",
            lineIndices: [index],
            composition: .singleAnchor,
            actors: actors,
            events: events,
            handoffOut: .dissolve)
    }

    private static func duetScene(indices: [Int], lines: [PlayerEngine.LyricLine]) -> StageScene {
        let actors: [StageActor] = indices.enumerated().map { offset, lineIndex in
            let line = lines[lineIndex]
            let isB = line.voiceRole == .duetB || offset.isMultiple(of: 2) == false
            return StageActor(
                id: "local-\(lineIndex)-voice",
                target: .line(lineIndex: lineIndex),
                role: isB ? .vocalB : .vocalA,
                anchor: isB ? .trailing : .leading,
                typeRole: .normal,
                paletteRole: isB ? .warm : .accent)
        }
        let peer = actors.last?.id ?? actors[0].id
        let events = actors.flatMap { actor -> [StageEvent] in
            [
                StageEvent(
                    actorID: actor.id,
                    phase: .entrance,
                    verb: .appear,
                    start: 0,
                    duration: 0.35,
                    intensity: 0.7,
                    reason: .vocalOverlap,
                    relation: .mirrorWith(actorID: peer)),
                StageEvent(
                    actorID: actor.id,
                    phase: .exit,
                    verb: .dissolve,
                    start: 0.80,
                    duration: 0.20,
                    intensity: 0.6,
                    reason: .vocalOverlap),
                StageEvent(
                    actorID: actor.id,
                    phase: .hold,
                    verb: .pulse,
                    start: 0.35,
                    duration: 0.45,
                    intensity: 0.32,
                    reason: .sustainedPhrase),
            ]
        }
        return StageScene(
            id: "local-duet-\(indices.first ?? 0)",
            lineIndices: Array(indices.prefix(3)),
            composition: .splitVoices,
            actors: actors,
            events: events,
            handoffOut: .dissolve)
    }

    private static func cluster(startingAt index: Int, group: String, lines: [PlayerEngine.LyricLine]) -> [Int] {
        var result = [index]
        var cursor = index + 1
        while cursor < lines.count, lines[cursor].overlapGroup == group, result.count < 3 {
            result.append(cursor)
            cursor += 1
        }
        return result
    }

    private static func repeatedTexts(in lines: [PlayerEngine.LyricLine]) -> Set<String> {
        var seen: [String: Int] = [:]
        for line in lines {
            let key = normalized(line.text)
            guard key.count >= 2 else { continue }
            seen[key, default: 0] += 1
        }
        return Set(seen.compactMap { $0.value > 1 ? $0.key : nil })
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    private static func containsImpact(_ text: String) -> Bool {
        text.contains("!") || text.contains("！")
    }

    private static func emphasisToken(in tokens: [StageToken]) -> StageToken? {
        tokens.last { $0.kind == .word }
    }
}
