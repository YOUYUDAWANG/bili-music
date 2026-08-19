import Foundation

enum LyricStageBudget {
    static let maxVisibleLines = 3
    static let maxActiveGlyphs = 120
    static let maxPrimaryEventsPerScene = 2
    static let maxHeroGlyphs = 3
    static let maxHeroActorsPerScene = 1
    static let minHeroSeparation: Double = 8
    static let maxEchoLayers = 2
    static let maxSectionAccentRatio = 0.20
    static let minVerseQuietRatio = 0.60
    static let majorVerbs: Set<StageVerb> = [.drop, .pulse, .scatter]

    struct Outcome: Equatable, Sendable {
        var score: LyricStageScoreV2
        var dropped: [DroppedStageEvent]
    }

    static func apply(
        _ score: LyricStageScoreV2,
        lines: [PlayerEngine.LyricLine],
        tokens: [[StageToken]]
    ) -> Outcome {
        var dropped = score.droppedEvents
        var scenes = score.scenes
        var lastHeroEnd: Double = -100

        scenes = applyMotifs(scenes, styleSheet: score.styleSheet)
        scenes = scenes.map { scene in
            pruneScene(
                scene,
                lines: lines,
                tokens: tokens,
                lastHeroEnd: &lastHeroEnd,
                dropped: &dropped)
        }
        scenes = enforceSectionHeroBudget(scenes, sections: score.sections, lines: lines, dropped: &dropped)
        scenes = enforceAccentBudget(scenes, sections: score.sections, lines: lines, tokens: tokens, dropped: &dropped)
        let quieted = enforceSectionDensity(scenes, sections: score.sections, dropped: &dropped)
        return Outcome(
            score: LyricStageScoreV2(
                version: score.version,
                trackID: score.trackID,
                lyricsHash: score.lyricsHash,
                styleSheet: score.styleSheet,
                sections: score.sections,
                scenes: quieted,
                droppedEvents: dropped),
            dropped: dropped)
    }

    static func trimConcurrent(_ glyphs: [ResolvedStageGlyph]) -> [ResolvedStageGlyph] {
        guard peakConcurrent(glyphs) > maxActiveGlyphs else { return glyphs }
        return glyphs.filter { !$0.isBackdrop }.map { glyph in
            ResolvedStageGlyph(
                id: glyph.id,
                text: glyph.text,
                lineIndex: glyph.lineIndex,
                tokenID: glyph.tokenID,
                actorID: glyph.actorID,
                origin: glyph.origin,
                size: glyph.size,
                fontSize: glyph.fontSize,
                isBold: glyph.isBold,
                paletteRole: glyph.paletteRole,
                syncWindow: glyph.syncWindow,
                performanceWindow: glyph.performanceWindow,
                visibleWindow: glyph.visibleWindow,
                events: glyph.events.filter { $0.verb != .echo },
                handoffs: [],
                echoLayers: 0,
                isBackdrop: false,
                seed: glyph.seed)
        }
    }

    static func peakConcurrent(_ glyphs: [ResolvedStageGlyph]) -> Int {
        var points: [(Double, Int)] = []
        points.reserveCapacity(glyphs.count * 2)
        for glyph in glyphs {
            points.append((glyph.visibleWindow.lowerBound, 1))
            points.append((glyph.visibleWindow.upperBound, -1))
        }
        points.sort { lhs, rhs in
            if lhs.0 == rhs.0 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }
        var current = 0
        var peak = 0
        for point in points {
            current += point.1
            peak = max(peak, current)
        }
        return peak
    }

    private static func pruneScene(
        _ scene: StageScene,
        lines: [PlayerEngine.LyricLine],
        tokens: [[StageToken]],
        lastHeroEnd: inout Double,
        dropped: inout [DroppedStageEvent]
    ) -> StageScene {
        var actors = Array(scene.actors.prefix(8))
        let heroActors = actors.filter { $0.typeRole == .hero || $0.role == .protagonist }
        if heroActors.count > maxHeroActorsPerScene {
            for extra in heroActors.dropFirst() {
                if let index = actors.firstIndex(where: { $0.id == extra.id }) {
                    actors[index] = StageActor(
                        id: extra.id,
                        target: extra.target,
                        role: extra.role == .protagonist ? .supporting : extra.role,
                        anchor: extra.anchor,
                        typeRole: .emphasis,
                        paletteRole: extra.paletteRole)
                    dropped.append(DroppedStageEvent(
                        sceneID: scene.id,
                        actorID: extra.id,
                        verb: .pulse,
                        reason: "hero-actor-limit"))
                }
            }
        }

        actors = actors.map { actor in
            guard actor.typeRole == .hero else { return actor }
            let count = resolvedGlyphCount(actor.target, tokens: tokens)
            if count > maxHeroGlyphs {
                dropped.append(DroppedStageEvent(
                    sceneID: scene.id,
                    actorID: actor.id,
                    verb: .pulse,
                    reason: "hero-glyph-limit"))
                return StageActor(
                    id: actor.id,
                    target: trimmedHeroTarget(actor.target, tokens: tokens),
                    role: actor.role,
                    anchor: actor.anchor,
                    typeRole: .hero,
                    paletteRole: actor.paletteRole)
            }
            return actor
        }

        let sceneStart = sceneStartTime(scene, lines: lines)
        if actors.contains(where: { $0.typeRole == .hero }),
           sceneStart - lastHeroEnd < minHeroSeparation {
            actors = actors.map { actor in
                guard actor.typeRole == .hero else { return actor }
                dropped.append(DroppedStageEvent(
                    sceneID: scene.id,
                    actorID: actor.id,
                    verb: .pulse,
                    reason: "hero-spacing"))
                return StageActor(
                    id: actor.id,
                    target: actor.target,
                    role: .supporting,
                    anchor: actor.anchor,
                    typeRole: .emphasis,
                    paletteRole: actor.paletteRole)
            }
        } else if actors.contains(where: { $0.typeRole == .hero }) {
            lastHeroEnd = sceneEndTime(scene, lines: lines)
        }

        var events = scene.events.sorted { lhs, rhs in
            if lhs.priority == rhs.priority { return lhs.intensity > rhs.intensity }
            return lhs.priority > rhs.priority
        }

        let majorCount = Set(events.map(\.verb)).intersection(majorVerbs).count
        if majorCount >= 3 {
            if let scatter = events.last(where: { $0.verb == .scatter }) {
                events.removeAll { $0.actorID == scatter.actorID && $0.verb == .scatter && $0.phase == scatter.phase }
                dropped.append(DroppedStageEvent(
                    sceneID: scene.id,
                    actorID: scatter.actorID,
                    verb: .scatter,
                    reason: "major-verb-stack"))
            }
        }

        var echoEvents = events.filter { $0.verb == .echo }
        if echoEvents.count > 1 {
            let extra = echoEvents.dropFirst()
            events.removeAll { event in extra.contains(where: { $0.actorID == event.actorID && $0.verb == .echo && $0.phase == event.phase }) }
            for event in extra {
                dropped.append(DroppedStageEvent(
                    sceneID: scene.id,
                    actorID: event.actorID,
                    verb: .echo,
                    reason: "echo-layer-limit"))
            }
        }

        let primary = events.filter { $0.phase == .entrance || $0.phase == .performance }
        if primary.count > maxPrimaryEventsPerScene {
            let extras = primary.dropFirst(maxPrimaryEventsPerScene)
            events.removeAll { event in
                extras.contains(where: {
                    $0.actorID == event.actorID && $0.phase == event.phase && $0.verb == event.verb
                })
            }
            for event in extras {
                dropped.append(DroppedStageEvent(
                    sceneID: scene.id,
                    actorID: event.actorID,
                    verb: event.verb,
                    reason: "scene-event-budget"))
            }
        }

        return StageScene(
            id: scene.id,
            lineIndices: Array(scene.lineIndices.prefix(maxVisibleLines)),
            composition: scene.composition,
            actors: actors,
            events: events,
            handoffOut: simplifiedHandoff(scene.handoffOut))
    }

    private static func applyMotifs(
        _ scenes: [StageScene],
        styleSheet: StageStyleSheet
    ) -> [StageScene] {
        let motifs = Dictionary(uniqueKeysWithValues: styleSheet.motifs.map { ($0.id, $0) })
        var counts: [String: Int] = [:]
        return scenes.map { scene in
            StageScene(
                id: scene.id,
                lineIndices: scene.lineIndices,
                composition: scene.composition,
                actors: scene.actors,
                events: scene.events.map { event in
                    guard let ref = event.motifRef, let motif = motifs[ref] else { return event }
                    let seen = counts[ref, default: 0]
                    counts[ref] = seen + 1
                    let verb = StageChoreography.allows(motif.verb, in: event.phase) ? motif.verb : event.verb
                    return StageEvent(
                        actorID: event.actorID,
                        phase: event.phase,
                        verb: verb,
                        start: event.start,
                        duration: event.duration,
                        intensity: min(1.25, event.intensity + Double(seen) * 0.08),
                        motifRef: ref,
                        reason: event.reason,
                        relation: event.relation,
                        priority: event.priority)
                },
                handoffOut: scene.handoffOut)
        }
    }

    private static func enforceSectionHeroBudget(
        _ scenes: [StageScene],
        sections: [StageSection],
        lines: [PlayerEngine.LyricLine],
        dropped: inout [DroppedStageEvent]
    ) -> [StageScene] {
        var result = scenes
        for section in sections {
            let indices = result.enumerated().filter { _, scene in
                scene.lineIndices.contains(where: { section.lineRange.contains($0) })
            }
            var remaining = section.heroBudget
            for (offset, scene) in indices.sorted(by: { lhs, rhs in
                sceneStartTime(lhs.element, lines: lines) < sceneStartTime(rhs.element, lines: lines)
            }) {
                let heroes = scene.actors.filter { $0.typeRole == .hero }
                guard !heroes.isEmpty else { continue }
                if remaining <= 0 {
                    result[offset] = demoteHeroes(scene, reason: "section-hero-budget", dropped: &dropped)
                } else {
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func enforceAccentBudget(
        _ scenes: [StageScene],
        sections: [StageSection],
        lines: [PlayerEngine.LyricLine],
        tokens: [[StageToken]],
        dropped: inout [DroppedStageEvent]
    ) -> [StageScene] {
        var result = scenes
        let accentVerbs: Set<StageVerb> = [.drop, .pulse, .stretch, .echo, .scatter, .assemble]
        for section in sections {
            let cap = min(section.accentBudget, maxSectionAccentRatio)
            let sectionScenes = result.enumerated().filter { _, scene in
                scene.lineIndices.contains(where: { section.lineRange.contains($0) })
            }
            let lineIndices = Set(sectionScenes.flatMap { $0.element.lineIndices })
            let totalGlyphTime = lineIndices.reduce(0.0) { partial, index in
                let duration = max(0.12, (lines[safe: index]?.to ?? 0) - (lines[safe: index]?.from ?? 0))
                let glyphs = tokens[safe: index]?.reduce(0) { $0 + $1.glyphRange.count } ?? 0
                return partial + duration * Double(max(1, glyphs))
            }
            guard totalGlyphTime > 0 else { continue }
            var accentEvents: [(Int, StageEvent, Double)] = []
            for (offset, scene) in sectionScenes {
                let span = max(0.12, sceneEndTime(scene, lines: lines) - sceneStartTime(scene, lines: lines))
                for event in scene.events where accentVerbs.contains(event.verb) && !isBaselineBreath(event) {
                    let actor = scene.actors.first { $0.id == event.actorID }
                    let count = actor.map { resolvedGlyphCount($0.target, tokens: tokens) } ?? 1
                    accentEvents.append((offset, event, event.duration * span * Double(max(1, count))))
                }
            }
            var used = accentEvents.reduce(0.0) { $0 + $1.2 }
            let sorted = accentEvents.sorted { lhs, rhs in
                if lhs.1.priority == rhs.1.priority { return lhs.1.intensity < rhs.1.intensity }
                return lhs.1.priority < rhs.1.priority
            }
            for item in sorted {
                guard used / totalGlyphTime > cap else { break }
                let scene = result[item.0]
                result[item.0] = StageScene(
                    id: scene.id,
                    lineIndices: scene.lineIndices,
                    composition: scene.composition,
                    actors: scene.actors,
                    events: scene.events.filter {
                        !($0.actorID == item.1.actorID && $0.phase == item.1.phase && $0.verb == item.1.verb)
                    },
                    handoffOut: scene.handoffOut)
                dropped.append(DroppedStageEvent(
                    sceneID: scene.id,
                    actorID: item.1.actorID,
                    verb: item.1.verb,
                    reason: "section-accent-budget"))
                used -= item.2
            }
        }
        return result
    }

    private static func enforceSectionDensity(
        _ scenes: [StageScene],
        sections: [StageSection],
        dropped: inout [DroppedStageEvent]
    ) -> [StageScene] {
        var result = scenes
        for section in sections {
            let maxDecorative = section.kind == .verse
                ? min(section.density, 1 - minVerseQuietRatio)
                : section.density
            let matches = result.enumerated().filter { _, scene in
                scene.lineIndices.contains { section.lineRange.contains($0) }
            }
            let decorative = matches.filter { _, scene in
                scene.events.contains {
                    $0.verb != .appear && $0.verb != .dissolve && !isBaselineBreath($0)
                }
            }
            let ratio = Double(decorative.count) / Double(max(1, matches.count))
            guard ratio > maxDecorative else { continue }
            let allowed = Int((maxDecorative * Double(matches.count)).rounded(.down))
            var extra = max(0, decorative.count - allowed)
            for (offset, scene) in decorative.reversed() {
                guard extra > 0 else { break }
                for event in scene.events where event.verb != .appear && event.verb != .dissolve {
                    dropped.append(DroppedStageEvent(
                        sceneID: scene.id,
                        actorID: event.actorID,
                        verb: event.verb,
                        reason: "section-density"))
                }
                result[offset] = StageScene(
                    id: scene.id,
                    lineIndices: scene.lineIndices,
                    composition: scene.composition == .heroBackdrop ? .singleAnchor : scene.composition,
                    actors: scene.actors.map {
                        $0.typeRole == .hero
                            ? StageActor(
                                id: $0.id,
                                target: $0.target,
                                role: .base,
                                anchor: $0.anchor,
                                typeRole: .normal,
                                paletteRole: $0.paletteRole)
                            : $0
                    },
                    events: scene.events.filter {
                        $0.verb == .appear || $0.verb == .dissolve || isBaselineBreath($0)
                    },
                    handoffOut: .dissolve)
                extra -= 1
            }
        }
        return result
    }

    private static func isBaselineBreath(_ event: StageEvent) -> Bool {
        event.phase == .hold
            && event.verb == .pulse
            && event.reason == .sustainedPhrase
            && event.intensity <= 0.35
    }

    private static func demoteHeroes(
        _ scene: StageScene,
        reason: String,
        dropped: inout [DroppedStageEvent]
    ) -> StageScene {
        StageScene(
            id: scene.id,
            lineIndices: scene.lineIndices,
            composition: scene.composition == .heroBackdrop ? .stacked : scene.composition,
            actors: scene.actors.map { actor in
                guard actor.typeRole == .hero else { return actor }
                dropped.append(DroppedStageEvent(
                    sceneID: scene.id,
                    actorID: actor.id,
                    verb: .pulse,
                    reason: reason))
                return StageActor(
                    id: actor.id,
                    target: actor.target,
                    role: .supporting,
                    anchor: actor.anchor,
                    typeRole: .emphasis,
                    paletteRole: actor.paletteRole)
            },
            events: scene.events,
            handoffOut: scene.handoffOut)
    }

    private static func simplifiedHandoff(_ handoff: StageHandoff?) -> StageHandoff? {
        switch handoff {
        case .residue:
            return .dissolve
        default:
            return handoff
        }
    }

    private static func resolvedGlyphCount(_ target: StageActorTarget, tokens: [[StageToken]]) -> Int {
        switch target {
        case .line(let lineIndex):
            return tokens[safe: lineIndex]?.reduce(0) { $0 + $1.glyphRange.count } ?? 0
        case .tokens(let lineIndex, let tokenIndices):
            guard let lineTokens = tokens[safe: lineIndex] else { return 0 }
            return tokenIndices.reduce(0) { partial, index in
                partial + (lineTokens[safe: index]?.glyphRange.count ?? 0)
            }
        case .glyphs(_, let from, let to):
            return max(0, to - from + 1)
        }
    }

    private static func trimmedHeroTarget(_ target: StageActorTarget, tokens: [[StageToken]]) -> StageActorTarget {
        switch target {
        case .line(let lineIndex):
            return .glyphs(lineIndex: lineIndex, glyphFrom: 0, glyphTo: maxHeroGlyphs - 1)
        case .tokens(let lineIndex, let tokenIndices):
            return .tokens(lineIndex: lineIndex, tokenIndices: Array(tokenIndices.prefix(1)))
        case .glyphs(let lineIndex, let from, _):
            return .glyphs(lineIndex: lineIndex, glyphFrom: from, glyphTo: from + maxHeroGlyphs - 1)
        }
    }

    private static func sceneStartTime(_ scene: StageScene, lines: [PlayerEngine.LyricLine]) -> Double {
        scene.lineIndices.compactMap { lines[safe: $0]?.from }.min() ?? 0
    }

    private static func sceneEndTime(_ scene: StageScene, lines: [PlayerEngine.LyricLine]) -> Double {
        scene.lineIndices.compactMap { lines[safe: $0]?.to }.max() ?? 0
    }
}
