import UIKit

enum LyricStageCompilerV2 {
    private static let maxWidth: CGFloat = 340

    static func compile(
        trackID: String,
        lines: [PlayerEngine.LyricLine],
        score: LyricStageScoreV2? = nil,
        performanceScore: LyricPerformanceScore? = nil,
        canvasSize: CGSize = CGSize(width: 340, height: 280),
        dynamicTypeScale: CGFloat = 1,
        reduceMotion: Bool = false,
        palette: PlayerArtworkPalette = .fallback
    ) -> ResolvedStageScore? {
        guard !lines.isEmpty else { return nil }
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(lines)
        let tokens = lines.map(LyricStageTokenizer.tokens(for:))
        let tokenCounts = Dictionary(uniqueKeysWithValues: tokens.enumerated().map { ($0.offset, $0.element.count) })
        let glyphCounts = LyricStageTokenizer.glyphCounts(for: lines)

        let source = resolvedSource(
            trackID: trackID,
            lyricsHash: lyricsHash,
            lines: lines,
            score: score,
            performanceScore: performanceScore,
            tokenCounts: tokenCounts,
            glyphCounts: glyphCounts)
        let filled = LyricStageDirectorV2.fillMissingScenes(in: source, lines: lines)
        let budgeted = LyricStageBudget.apply(filled, lines: lines, tokens: tokens)
        let prepared = reduceMotion ? reduceMotionScore(budgeted.score) : budgeted.score
        let resolvedPalette = LyricStagePaletteResolver.resolve(
            strategy: prepared.styleSheet.paletteStrategy,
            cover: palette)
        let glyphs = LyricStageBudget.trimConcurrent(
            bakeGlyphs(
                score: prepared,
                lines: lines,
                tokens: tokens,
                canvasSize: canvasSize,
                dynamicTypeScale: dynamicTypeScale,
                reduceMotion: reduceMotion))
        return ResolvedStageScore(
            version: prepared.version,
            trackID: trackID,
            lyricsHash: lyricsHash,
            canvasSize: canvasSize,
            glyphs: glyphs,
            palette: resolvedPalette,
            summary: summary(for: prepared, dropped: budgeted.dropped),
            reduceMotion: reduceMotion)
    }

    static func summary(for score: LyricStageScoreV2, dropped: [DroppedStageEvent]) -> LyricStagePerformanceSummary {
        LyricStagePerformanceSummary(
            concept: score.styleSheet.concept,
            paletteStrategy: score.styleSheet.paletteStrategy,
            sections: score.sections.map { "\($0.kind.rawValue) \($0.lineFrom)–\($0.lineTo) d=\(String(format: "%.2f", $0.density))" },
            motifs: score.styleSheet.motifs.map(\.id),
            heroScenes: score.scenes.filter { scene in scene.actors.contains { $0.typeRole == .hero } }.map(\.id),
            handoffs: score.scenes.compactMap { scene in
                scene.handoffOut.map { "\(scene.id):\($0.label)" }
            },
            droppedEvents: dropped,
            events: score.scenes.flatMap { scene in
                scene.events.map { "\(scene.id)/\($0.actorID) \($0.phase.rawValue) \($0.verb.rawValue) \($0.reason.rawValue)" }
            })
    }

    private static func resolvedSource(
        trackID: String,
        lyricsHash: String,
        lines: [PlayerEngine.LyricLine],
        score: LyricStageScoreV2?,
        performanceScore: LyricPerformanceScore?,
        tokenCounts: [Int: Int],
        glyphCounts: [Int: Int]
    ) -> LyricStageScoreV2 {
        if let score,
           let safe = score.validated(
            trackID: trackID,
            lyricsHash: lyricsHash,
            lineCount: lines.count,
            tokenCounts: tokenCounts,
            glyphCounts: glyphCounts) {
            return safe
        }
        if performanceScore != nil {
            return LyricStageLegacyAdapter.adapt(
                trackID: trackID,
                lines: lines,
                performanceScore: performanceScore)
        }
        return LyricStageDirectorV2.compose(trackID: trackID, lines: lines)
    }

    private static func reduceMotionScore(_ score: LyricStageScoreV2) -> LyricStageScoreV2 {
        LyricStageScoreV2(
            version: score.version,
            trackID: score.trackID,
            lyricsHash: score.lyricsHash,
            styleSheet: score.styleSheet,
            sections: score.sections,
            scenes: score.scenes.map { scene in
                StageScene(
                    id: scene.id,
                    lineIndices: scene.lineIndices,
                    composition: scene.composition == .heroBackdrop ? .stacked : scene.composition,
                    actors: scene.actors,
                    events: scene.events.map { event in
                        StageEvent(
                            actorID: event.actorID,
                            phase: event.phase,
                            verb: reducedVerb(event.verb),
                            start: event.start,
                            duration: event.duration,
                            intensity: min(event.intensity, 0.7),
                            motifRef: event.motifRef,
                            reason: event.reason,
                            relation: nil,
                            priority: event.priority)
                    },
                    handoffOut: scene.handoffOut.map { _ in .dissolve })
            },
            droppedEvents: score.droppedEvents)
    }

    private static func reducedVerb(_ verb: StageVerb) -> StageVerb {
        switch verb {
        case .drop, .assemble, .scatter, .drift: return .appear
        default: return verb
        }
    }

    private static func bakeGlyphs(
        score: LyricStageScoreV2,
        lines: [PlayerEngine.LyricLine],
        tokens: [[StageToken]],
        canvasSize: CGSize,
        dynamicTypeScale: CGFloat,
        reduceMotion: Bool
    ) -> [ResolvedStageGlyph] {
        var glyphs: [ResolvedStageGlyph] = []
        let actorOrigins = actorCenters(
            score: score,
            lines: lines,
            tokens: tokens,
            canvasSize: canvasSize,
            dynamicTypeScale: dynamicTypeScale)

        for (sceneIndex, scene) in score.scenes.enumerated() {
            let times = sceneTimes(scene, lines: lines)
            let previous = sceneIndex > 0 ? score.scenes[sceneIndex - 1] : nil
            let next = score.scenes[safe: sceneIndex + 1]
            let previousTimes = previous.map { sceneTimes($0, lines: lines) }
            let nextTimes = next.map { sceneTimes($0, lines: lines) }
            let layouts = layout(
                scene: scene,
                lines: lines,
                tokens: tokens,
                canvasSize: canvasSize,
                typeSystem: score.styleSheet.typeSystem,
                dynamicTypeScale: dynamicTypeScale)
            let actorGlyphs = Dictionary(uniqueKeysWithValues: scene.actors.map { actor in
                (actor.id, Set(resolveGlyphs(actor.target, tokens: tokens)))
            })
            let incoming = previous.flatMap {
                compiledHandoff($0.handoffOut, times: previousTimes ?? times, nextTimes: times, outgoing: false)
            }
            let outgoing = compiledHandoff(scene.handoffOut, times: times, nextTimes: nextTimes, outgoing: true)

            for layout in layouts {
                let tokenID = tokenID(for: layout.glyphIndex, tokens: tokens[safe: layout.lineIndex] ?? [])
                let key = GlyphKey(lineIndex: layout.lineIndex, glyphIndex: layout.glyphIndex)
                let membership: [StageActor]
                if layout.isBackdrop {
                    membership = scene.actors.filter { $0.id == layout.actorID }
                } else {
                    membership = scene.actors.filter { actor in
                        actor.role != .backdrop
                            && actorGlyphs[actor.id]?.contains(key) == true
                    }
                }
                let events = membership.flatMap { actor -> [ResolvedGlyphEvent] in
                    scene.events.filter { $0.actorID == actor.id }.map { event in
                        resolvedEvent(
                            event,
                            times: times,
                            actor: actor,
                            layout: layout,
                            actorOrigins: actorOrigins,
                            scene: scene)
                    }
                }
                let token = (tokens[safe: layout.lineIndex] ?? []).first { $0.glyphRange.contains(layout.glyphIndex) }
                let performance = performanceWindow(for: token, times: times, glyphIndex: layout.glyphIndex)
                let visibleStart = min(times.start, incoming?.start ?? times.start)
                let visibleEnd = max(times.end, outgoing?.end ?? times.end)
                glyphs.append(
                    ResolvedStageGlyph(
                        id: glyphs.count,
                        text: layout.text,
                        lineIndex: layout.lineIndex,
                        tokenID: tokenID,
                        actorID: layout.actorID,
                        origin: layout.origin,
                        size: layout.size,
                        fontSize: layout.fontSize,
                        isBold: layout.isBold,
                        paletteRole: layout.paletteRole,
                        syncWindow: layout.isBackdrop ? nil : token?.realTiming,
                        performanceWindow: performance,
                        visibleWindow: visibleStart...visibleEnd,
                        events: events,
                        handoffs: layout.isBackdrop ? [] : [incoming, outgoing].compactMap { $0 },
                        echoLayers: events.contains { $0.verb == .echo } ? 2 : 0,
                        isBackdrop: layout.isBackdrop,
                        seed: layout.lineIndex * 97 + layout.glyphIndex * 13))
            }
        }
        return glyphs
    }

    private struct GlyphKey: Hashable {
        let lineIndex: Int
        let glyphIndex: Int
    }

    private struct ActorKey: Hashable {
        let sceneID: String
        let actorID: String
    }

    private struct GlyphLayout {
        let lineIndex: Int
        let glyphIndex: Int
        let text: String
        let origin: CGPoint
        let size: CGSize
        let fontSize: Double
        let isBold: Bool
        let typeRole: StageTypeRole
        let actorID: String
        let isBackdrop: Bool
        let paletteRole: StagePaletteRole
    }

    private struct SceneTimes {
        let start: Double
        let end: Double
    }

    private static func sceneTimes(_ scene: StageScene, lines: [PlayerEngine.LyricLine]) -> SceneTimes {
        let from = scene.lineIndices.compactMap { lines[safe: $0]?.from }.min() ?? 0
        let to = scene.lineIndices.compactMap { lines[safe: $0]?.to }.max() ?? (from + 1)
        return SceneTimes(start: from, end: max(from + 0.12, to))
    }

    private static func resolveGlyphs(_ target: StageActorTarget, tokens: [[StageToken]]) -> [GlyphKey] {
        switch target {
        case .line(let lineIndex):
            let count = tokens[safe: lineIndex]?.last?.glyphRange.upperBound ?? 0
            return (0..<count).map { GlyphKey(lineIndex: lineIndex, glyphIndex: $0) }
        case .tokens(let lineIndex, let tokenIndices):
            guard let lineTokens = tokens[safe: lineIndex] else { return [] }
            return tokenIndices.flatMap { index -> [GlyphKey] in
                guard let token = lineTokens[safe: index] else { return [] }
                return token.glyphRange.map { GlyphKey(lineIndex: lineIndex, glyphIndex: $0) }
            }
        case .glyphs(let lineIndex, let from, let to):
            return (from...to).map { GlyphKey(lineIndex: lineIndex, glyphIndex: $0) }
        }
    }

    private static func layout(
        scene: StageScene,
        lines: [PlayerEngine.LyricLine],
        tokens: [[StageToken]],
        canvasSize: CGSize,
        typeSystem: StageTypeSystem,
        dynamicTypeScale: CGFloat
    ) -> [GlyphLayout] {
        let width = min(maxWidth, max(120, canvasSize.width))
        var blocks: [(lineIndex: Int, glyphs: [GlyphLayout], height: CGFloat, anchor: StageAnchor)] = []
        for lineIndex in scene.lineIndices {
            guard let line = lines[safe: lineIndex] else { continue }
            let base = baseActor(for: lineIndex, in: scene)
            let measured = measureLine(
                lineIndex: lineIndex,
                text: line.text,
                tokens: tokens[safe: lineIndex] ?? [],
                role: base?.typeRole ?? .normal,
                actorID: base?.id ?? "base-\(lineIndex)",
                paletteRole: base?.paletteRole ?? .primary,
                typeSystem: typeSystem,
                scale: dynamicTypeScale,
                maxWidth: width,
                composition: scene.composition,
                voice: line.voiceRole,
                anchor: base?.anchor ?? .center)
            blocks.append((lineIndex, measured, blockHeight(measured), base?.anchor ?? .center))
        }
        let totalHeight = blocks.reduce(CGFloat(0)) { $0 + $1.height + 6 } - (blocks.isEmpty ? 0 : 6)
        var y = max(0, (canvasSize.height - totalHeight) / 2)
        var result: [GlyphLayout] = []
        var placedByKey: [GlyphKey: Int] = [:]
        for (offset, block) in blocks.enumerated() {
            let splitShift: CGFloat = scene.composition == .splitVoices
                ? (offset == 0 ? -18 : 18)
                : 0
            let verticalNudge = anchorNudge(block.anchor)
            for glyph in block.glyphs {
                let placed = moved(
                    glyph,
                    by: CGSize(width: splitShift, height: y + verticalNudge))
                placedByKey[GlyphKey(lineIndex: placed.lineIndex, glyphIndex: placed.glyphIndex)] = result.count
                result.append(placed)
            }
            y += block.height + 6
        }

        for actor in scene.actors where actor.role != .backdrop && actor.role != .base && actor.role != .vocalA && actor.role != .vocalB {
            let keys = resolveGlyphs(actor.target, tokens: tokens)
            for key in keys {
                guard let index = placedByKey[key] else { continue }
                result[index] = restyled(result[index], actor: actor, typeSystem: typeSystem, scale: dynamicTypeScale)
            }
        }

        if scene.composition == .heroBackdrop || scene.actors.contains(where: { $0.role == .backdrop }) {
            result.append(contentsOf: backdropLayouts(
                scene: scene,
                lines: lines,
                tokens: tokens,
                canvasSize: canvasSize,
                typeSystem: typeSystem,
                scale: dynamicTypeScale))
        }
        return result
    }

    private static func measureLine(
        lineIndex: Int,
        text: String,
        tokens: [StageToken],
        role: StageTypeRole,
        actorID: String,
        paletteRole: StagePaletteRole,
        typeSystem: StageTypeSystem,
        scale: CGFloat,
        maxWidth: CGFloat,
        composition: StageComposition,
        voice: LyricVoiceRole,
        anchor: StageAnchor
    ) -> [GlyphLayout] {
        let fontSize = typeSystem.size(for: role) * Double(scale)
        let font = UIFont.systemFont(
            ofSize: fontSize,
            weight: role == .whisper || role == .supporting ? .semibold : .black)
        let lineHeight = font.lineHeight
        let characters = Array(text)
        let tokenUnits = tokens.flatMap { token in
            Array(token.text).enumerated().map { offset, character in
                (
                    glyphIndex: token.glyphRange.lowerBound + offset,
                    text: String(character),
                    unbreakable: token.kind == .word || token.kind == .particle,
                    tokenID: token.id
                )
            }
        }
        let units: [(glyphIndex: Int, text: String, unbreakable: Bool, tokenID: Int)]
        if tokenUnits.map(\.text).joined() == text {
            units = tokenUnits
        } else {
            units = characters.enumerated().map { ($0.offset, String($0.element), false, $0.offset) }
        }
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rows: [[GlyphLayout]] = [[]]
        var index = 0
        while index < units.count {
            var end = index + 1
            if units[index].unbreakable {
                while end < units.count,
                      units[end].unbreakable,
                      units[end].tokenID == units[index].tokenID,
                      units[end].glyphIndex == units[end - 1].glyphIndex + 1 {
                    end += 1
                }
            }
            let run = units[index..<end]
            let runWidth = run.reduce(CGFloat(0)) { partial, unit in
                partial + (unit.text as NSString).size(withAttributes: [.font: font]).width
            }
            if rowWidth > 0, rowWidth + runWidth > maxWidth, !(run.count == 1 && units[index].text == " ") {
                rows.append([])
                x = 0
                y += lineHeight + 4
                rowWidth = 0
            }
            for unit in run {
                let size = (unit.text as NSString).size(withAttributes: [.font: font])
                rows[rows.count - 1].append(
                    GlyphLayout(
                        lineIndex: lineIndex,
                        glyphIndex: unit.glyphIndex,
                        text: unit.text,
                        origin: CGPoint(x: x, y: y),
                        size: size,
                        fontSize: fontSize,
                        isBold: role != .whisper && role != .supporting,
                        typeRole: role,
                        actorID: actorID,
                        isBackdrop: false,
                        paletteRole: paletteRole))
                x += size.width
                rowWidth += size.width
            }
            index = end
        }
        let aligned = rows.flatMap { row -> [GlyphLayout] in
            let width = row.last.map { $0.origin.x + $0.size.width } ?? 0
            let originX = rowOriginX(
                rowWidth: width,
                maxWidth: maxWidth,
                composition: composition,
                voice: voice,
                anchor: anchor)
            return row.map { glyph in
                moved(glyph, by: CGSize(width: originX, height: 0))
            }
        }
        if aligned.map(\.text).joined() == text || tokens.isEmpty {
            return aligned
        }
        return measureLine(
            lineIndex: lineIndex,
            text: text,
            tokens: [],
            role: role,
            actorID: actorID,
            paletteRole: paletteRole,
            typeSystem: typeSystem,
            scale: scale,
            maxWidth: maxWidth,
            composition: composition,
            voice: voice,
            anchor: anchor)
    }

    private static func rowOriginX(
        rowWidth: CGFloat,
        maxWidth: CGFloat,
        composition: StageComposition,
        voice: LyricVoiceRole,
        anchor: StageAnchor
    ) -> CGFloat {
        if composition == .splitVoices {
            switch voice {
            case .duetA, .lead: return 8
            case .duetB: return max(8, maxWidth - rowWidth - 8)
            default: break
            }
        }
        switch anchor {
        case .leading, .upperLeading, .lowerLeading:
            return 8
        case .trailing, .upperTrailing, .lowerTrailing:
            return max(0, maxWidth - rowWidth - 8)
        default:
            return max(0, (maxWidth - rowWidth) / 2)
        }
    }

    private static func baseActor(for lineIndex: Int, in scene: StageScene) -> StageActor? {
        let candidates = scene.actors.filter { actor in
            actor.target.lineIndex == lineIndex && actor.role != .backdrop
        }
        return candidates.first { $0.role == .base || $0.role == .vocalA || $0.role == .vocalB }
    }

    private static func blockHeight(_ glyphs: [GlyphLayout]) -> CGFloat {
        guard let minY = glyphs.map(\.origin.y).min(),
              let maxBottom = glyphs.map({ $0.origin.y + $0.size.height }).max()
        else { return 0 }
        return max(0, maxBottom - minY)
    }

    private static func moved(_ glyph: GlyphLayout, by delta: CGSize) -> GlyphLayout {
        GlyphLayout(
            lineIndex: glyph.lineIndex,
            glyphIndex: glyph.glyphIndex,
            text: glyph.text,
            origin: CGPoint(x: glyph.origin.x + delta.width, y: glyph.origin.y + delta.height),
            size: glyph.size,
            fontSize: glyph.fontSize,
            isBold: glyph.isBold,
            typeRole: glyph.typeRole,
            actorID: glyph.actorID,
            isBackdrop: glyph.isBackdrop,
            paletteRole: glyph.paletteRole)
    }

    private static func restyled(
        _ glyph: GlyphLayout,
        actor: StageActor,
        typeSystem: StageTypeSystem,
        scale: CGFloat
    ) -> GlyphLayout {
        let fontSize = typeSystem.size(for: actor.typeRole) * Double(scale)
        let font = UIFont.systemFont(
            ofSize: fontSize,
            weight: actor.typeRole == .whisper || actor.typeRole == .supporting ? .semibold : .black)
        let size = (glyph.text as NSString).size(withAttributes: [.font: font])
        let center = CGPoint(
            x: glyph.origin.x + glyph.size.width / 2,
            y: glyph.origin.y + glyph.size.height / 2)
        return GlyphLayout(
            lineIndex: glyph.lineIndex,
            glyphIndex: glyph.glyphIndex,
            text: glyph.text,
            origin: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            size: size,
            fontSize: fontSize,
            isBold: actor.typeRole != .whisper && actor.typeRole != .supporting,
            typeRole: actor.typeRole,
            actorID: actor.id,
            isBackdrop: false,
            paletteRole: actor.paletteRole)
    }

    private static func backdropLayouts(
        scene: StageScene,
        lines: [PlayerEngine.LyricLine],
        tokens: [[StageToken]],
        canvasSize: CGSize,
        typeSystem: StageTypeSystem,
        scale: CGFloat
    ) -> [GlyphLayout] {
        let actors = scene.actors.filter { actor in
            actor.role == .backdrop || (scene.composition == .heroBackdrop && actor.typeRole == .hero)
        }
        return actors.flatMap { actor -> [GlyphLayout] in
            let keys = resolveGlyphs(actor.target, tokens: tokens).sorted {
                $0.lineIndex == $1.lineIndex ? $0.glyphIndex < $1.glyphIndex : $0.lineIndex < $1.lineIndex
            }
            guard !keys.isEmpty else { return [] }
            let fontSize = typeSystem.size(for: actor.typeRole == .hero ? .hero : actor.typeRole) * Double(scale)
            let font = UIFont.systemFont(ofSize: fontSize, weight: .black)
            var x: CGFloat = 0
            var glyphs: [GlyphLayout] = []
            for key in keys {
                guard let line = lines[safe: key.lineIndex] else { continue }
                let characters = Array(line.text)
                guard characters.indices.contains(key.glyphIndex) else { continue }
                let text = String(characters[key.glyphIndex])
                let size = (text as NSString).size(withAttributes: [.font: font])
                glyphs.append(
                    GlyphLayout(
                        lineIndex: key.lineIndex,
                        glyphIndex: key.glyphIndex,
                        text: text,
                        origin: CGPoint(x: x, y: 0),
                        size: size,
                        fontSize: fontSize,
                        isBold: true,
                        typeRole: actor.typeRole,
                        actorID: actor.id,
                        isBackdrop: true,
                        paletteRole: actor.paletteRole))
                x += size.width
            }
            let width = glyphs.last.map { $0.origin.x + $0.size.width } ?? 0
            let originX = max(0, (min(maxWidth, canvasSize.width) - width) / 2)
            let originY = max(0, canvasSize.height * 0.18)
            return glyphs.map { moved($0, by: CGSize(width: originX, height: originY)) }
        }
    }

    private static func anchorNudge(_ anchor: StageAnchor) -> CGFloat {
        switch anchor {
        case .upperLeading, .upperTrailing, .aboveStage: return -10
        case .lowerLeading, .lowerTrailing, .belowStage: return 10
        default: return 0
        }
    }

    private static func performanceWindow(
        for token: StageToken?,
        times: SceneTimes,
        glyphIndex: Int
    ) -> ClosedRange<Double> {
        let span = max(0.12, times.end - times.start)
        let entranceEnd = times.start + span * 0.35
        let exitStart = times.start + span * 0.80
        if let token {
            let tokenSpan = Double(token.id) * min(0.08, span * 0.12)
            let start = min(entranceEnd, times.start + tokenSpan)
            return start...max(start + 0.08, exitStart)
        }
        let start = min(entranceEnd, times.start + Double(glyphIndex) * min(0.03, span * 0.08))
        return start...max(start + 0.08, exitStart)
    }

    private static func resolvedEvent(
        _ event: StageEvent,
        times: SceneTimes,
        actor: StageActor,
        layout: GlyphLayout,
        actorOrigins: [ActorKey: CGPoint],
        scene: StageScene
    ) -> ResolvedGlyphEvent {
        let span = max(0.12, times.end - times.start)
        let start = times.start + event.start * span
        let end = min(times.end, start + event.duration * span)
        let direction: Int
        switch actor.anchor {
        case .leading, .upperLeading, .lowerLeading, .offstageLeft: direction = -1
        case .trailing, .upperTrailing, .lowerTrailing, .offstageRight: direction = 1
        default: direction = 1
        }
        return ResolvedGlyphEvent(
            phase: event.phase,
            verb: event.verb,
            start: start,
            end: end,
            intensity: event.intensity,
            direction: direction,
            relationOffset: relationOffset(
                event.relation,
                layout: layout,
                actorOrigins: actorOrigins,
                scene: scene))
    }

    private static func relationOffset(
        _ relation: StageRelation?,
        layout: GlyphLayout,
        actorOrigins: [ActorKey: CGPoint],
        scene: StageScene
    ) -> CGSize {
        switch relation {
        case .pushNeighbors:
            return CGSize(width: layout.origin.x < 170 ? -8 : 8, height: 0)
        case .attractTo(let actorID):
            guard let target = actorOrigins[ActorKey(sceneID: scene.id, actorID: actorID)] else { return .zero }
            return CGSize(width: (target.x - layout.origin.x) * 0.18, height: (target.y - layout.origin.y) * 0.18)
        case .mirrorWith:
            let isB = scene.actors.first { $0.target.lineIndex == layout.lineIndex }?.role == .vocalB
            return CGSize(width: isB ? 28 : -28, height: 0)
        case nil:
            return .zero
        }
    }

    private static func actorCenters(
        score: LyricStageScoreV2,
        lines: [PlayerEngine.LyricLine],
        tokens: [[StageToken]],
        canvasSize: CGSize,
        dynamicTypeScale: CGFloat
    ) -> [ActorKey: CGPoint] {
        var result: [ActorKey: CGPoint] = [:]
        for scene in score.scenes {
            let layouts = layout(
                scene: scene,
                lines: lines,
                tokens: tokens,
                canvasSize: canvasSize,
                typeSystem: score.styleSheet.typeSystem,
                dynamicTypeScale: dynamicTypeScale)
            for actor in scene.actors {
                let keys = Set(resolveGlyphs(actor.target, tokens: tokens))
                let points = layouts.filter {
                    keys.contains(GlyphKey(lineIndex: $0.lineIndex, glyphIndex: $0.glyphIndex))
                }
                guard !points.isEmpty else { continue }
                let x = points.map(\.origin.x).reduce(0, +) / CGFloat(points.count)
                let y = points.map(\.origin.y).reduce(0, +) / CGFloat(points.count)
                result[ActorKey(sceneID: scene.id, actorID: actor.id)] = CGPoint(x: x, y: y)
            }
        }
        return result
    }

    private static func compiledHandoff(
        _ handoff: StageHandoff?,
        times: SceneTimes,
        nextTimes: SceneTimes?,
        outgoing: Bool
    ) -> ResolvedHandoffWindow? {
        guard let handoff, let nextTimes else { return nil }
        switch handoff {
        case .cut:
            return nil
        case .residue:
            return ResolvedHandoffWindow(
                kind: .dissolve,
                start: outgoing ? times.end - 0.18 : nextTimes.start,
                end: outgoing ? nextTimes.start + 0.12 : nextTimes.start + 0.28,
                outgoing: outgoing)
        case .dissolve, .push:
            let start = outgoing ? max(times.start, times.end - 0.22) : nextTimes.start
            let end = outgoing ? nextTimes.start + 0.18 : nextTimes.start + 0.32
            return ResolvedHandoffWindow(kind: handoff, start: start, end: max(start + 0.08, end), outgoing: outgoing)
        }
    }

    private static func tokenID(for glyphIndex: Int, tokens: [StageToken]) -> Int {
        tokens.first { $0.glyphRange.contains(glyphIndex) }?.id ?? glyphIndex
    }

    private static func typeRank(_ role: StageTypeRole) -> Int {
        switch role {
        case .whisper: 0
        case .supporting: 1
        case .normal: 2
        case .emphasis: 3
        case .hero: 4
        }
    }
}

private extension StageHandoff {
    var label: String {
        switch self {
        case .cut: "cut"
        case .dissolve: "dissolve"
        case .push(let direction): "push-\(direction.rawValue)"
        case .residue(let actorID): "residue-\(actorID)"
        }
    }
}
