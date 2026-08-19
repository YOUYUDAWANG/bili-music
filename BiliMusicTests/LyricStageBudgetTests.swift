import XCTest
@testable import BiliMusic

final class LyricStageBudgetTests: XCTestCase {
    func testExtraHeroAndEchoAreDroppedInsteadOfRejectingTheScore() {
        let lines = [
            PlayerEngine.LyricLine(from: 0, to: 2, text: "quiet verse"),
            PlayerEngine.LyricLine(from: 12, to: 14, text: "hero one"),
            PlayerEngine.LyricLine(from: 15, to: 17, text: "hero two too soon"),
        ]
        let score = LyricStageDirectorV2.compose(trackID: "fixture", lines: lines)
        let overloaded = LyricStageScoreV2(
            trackID: score.trackID,
            lyricsHash: score.lyricsHash,
            styleSheet: score.styleSheet,
            sections: score.sections,
            scenes: score.scenes.enumerated().map { index, scene in
                guard index > 0 else { return scene }
                return StageScene(
                    id: scene.id,
                    lineIndices: scene.lineIndices,
                    composition: .heroBackdrop,
                    actors: scene.actors + [
                        StageActor(
                            id: "hero-\(index)-a",
                            target: .glyphs(lineIndex: scene.lineIndices[0], glyphFrom: 0, glyphTo: 0),
                            role: .protagonist,
                            anchor: .center,
                            typeRole: .hero,
                            paletteRole: .accent),
                        StageActor(
                            id: "hero-\(index)-b",
                            target: .glyphs(lineIndex: scene.lineIndices[0], glyphFrom: 1, glyphTo: 1),
                            role: .protagonist,
                            anchor: .center,
                            typeRole: .hero,
                            paletteRole: .warm),
                    ],
                    events: scene.events + [
                        StageEvent(
                            actorID: "hero-\(index)-a",
                            phase: .performance,
                            verb: .pulse,
                            start: 0.4,
                            duration: 0.2,
                            intensity: 1,
                            reason: .emotionalPeak,
                            priority: 3),
                        StageEvent(
                            actorID: scene.actors[0].id,
                            phase: .performance,
                            verb: .echo,
                            start: 0.4,
                            duration: 0.2,
                            intensity: 1,
                            reason: .hookRepeat),
                        StageEvent(
                            actorID: "hero-\(index)-b",
                            phase: .performance,
                            verb: .echo,
                            start: 0.5,
                            duration: 0.2,
                            intensity: 1,
                            reason: .hookRepeat),
                    ],
                    handoffOut: scene.handoffOut)
            })

        let outcome = LyricStageBudget.apply(
            overloaded,
            lines: lines,
            tokens: lines.map(LyricStageTokenizer.tokens(for:)))
        let heroScenes = outcome.score.scenes.filter { scene in
            scene.actors.contains { $0.typeRole == .hero }
        }
        XCTAssertLessThanOrEqual(heroScenes.count, 1)
        XCTAssertFalse(outcome.dropped.isEmpty)
        XCTAssertEqual(outcome.score.scenes.count, overloaded.scenes.count)
    }

    func testOrdinarySceneCannotKeepDropPulseAndScatterTogether() {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 3, text: "ordinary")]
        let local = LyricStageDirectorV2.compose(trackID: "fixture", lines: lines)
        let stacked = withEvents(local, verbs: [.drop, .pulse, .scatter])
        let outcome = LyricStageBudget.apply(
            stacked,
            lines: lines,
            tokens: lines.map(LyricStageTokenizer.tokens(for:)))
        let verbs = Set(outcome.score.scenes[0].events.map(\.verb))
        XCTAssertFalse(verbs.isSuperset(of: [.drop, .pulse, .scatter]))
    }

    func testTrimConcurrentRemovesEchoEventsNotJustTheCachedLayerCount() {
        let event = ResolvedGlyphEvent(
            phase: .performance,
            verb: .echo,
            start: 0.4,
            end: 1.2,
            intensity: 1,
            direction: 1,
            relationOffset: .zero)
        let glyphs = (0..<130).map { index in
            ResolvedStageGlyph(
                id: index,
                text: "a",
                lineIndex: 0,
                tokenID: 0,
                actorID: "base",
                origin: CGPoint(x: CGFloat(index), y: 0),
                size: CGSize(width: 8, height: 20),
                fontSize: 20,
                isBold: true,
                paletteRole: .primary,
                syncWindow: nil,
                performanceWindow: 0...2,
                visibleWindow: 0...2,
                events: [event],
                handoffs: [],
                echoLayers: 2,
                isBackdrop: false,
                seed: index)
        }
        let trimmed = LyricStageBudget.trimConcurrent(glyphs)
        XCTAssertEqual(trimmed.count, 130)
        XCTAssertTrue(trimmed.allSatisfy { $0.echoLayers == 0 })
        XCTAssertFalse(trimmed.contains { glyph in glyph.events.contains { $0.verb == .echo } })
        let sampled = LyricStageTimeline.sample(trimmed, at: 0.8, palette: LyricStagePaletteResolver.resolve(strategy: .coverAnalogous), reduceMotion: false)
        XCTAssertTrue(sampled.allSatisfy { $0.echoLayers == 0 })
    }

    func testMotifRefReusesTheMotifVerb() {
        let lines = [
            PlayerEngine.LyricLine(from: 0, to: 2, text: "hook"),
            PlayerEngine.LyricLine(from: 2, to: 4, text: "hook"),
        ]
        var score = LyricStageDirectorV2.compose(trackID: "fixture", lines: lines)
        score = LyricStageScoreV2(
            trackID: score.trackID,
            lyricsHash: score.lyricsHash,
            styleSheet: StageStyleSheet(
                concept: score.styleSheet.concept,
                paletteStrategy: score.styleSheet.paletteStrategy,
                typeSystem: score.styleSheet.typeSystem,
                motifs: [StageMotif(id: "echo-repeat", verb: .echo, note: "hook")]),
            sections: [
                StageSection(
                    id: "chorus",
                    lineFrom: 0,
                    lineTo: 1,
                    kind: .chorus,
                    density: 0.9,
                    heroBudget: 1,
                    accentBudget: 0.2,
                    preferredMotifs: ["echo-repeat"]),
            ],
            scenes: score.scenes.map { scene in
                StageScene(
                    id: scene.id,
                    lineIndices: scene.lineIndices,
                    composition: scene.composition,
                    actors: scene.actors,
                    events: [
                        StageEvent(
                            actorID: scene.actors[0].id,
                            phase: .performance,
                            verb: .pulse,
                            start: 0.4,
                            duration: 0.3,
                            intensity: 0.6,
                            motifRef: "echo-repeat",
                            reason: .hookRepeat,
                            priority: 2),
                    ],
                    handoffOut: scene.handoffOut)
            })
        let outcome = LyricStageBudget.apply(
            score,
            lines: lines,
            tokens: lines.map(LyricStageTokenizer.tokens(for:)))
        XCTAssertTrue(outcome.score.scenes.contains { scene in
            scene.events.contains { $0.motifRef == "echo-repeat" && $0.verb == .echo }
        })
    }

    func testVerseKeepsMostlyQuietBaseline() {
        let lines = (0..<8).map { index in
            PlayerEngine.LyricLine(from: Double(index), to: Double(index) + 0.9, text: "verse \(index)")
        }
        var score = LyricStageDirectorV2.compose(trackID: "fixture", lines: lines)
        score = LyricStageScoreV2(
            trackID: score.trackID,
            lyricsHash: score.lyricsHash,
            styleSheet: score.styleSheet,
            sections: [
                StageSection(
                    id: "verse",
                    lineFrom: 0,
                    lineTo: 7,
                    kind: .verse,
                    density: 0.2,
                    heroBudget: 0,
                    accentBudget: 0.12,
                    preferredMotifs: []),
            ],
            scenes: score.scenes.map { scene in
                StageScene(
                    id: scene.id,
                    lineIndices: scene.lineIndices,
                    composition: scene.composition,
                    actors: scene.actors,
                    events: scene.events + [
                        StageEvent(
                            actorID: scene.actors[0].id,
                            phase: .performance,
                            verb: .scatter,
                            start: 0.4,
                            duration: 0.3,
                            intensity: 1,
                            reason: .emotionalPeak,
                            priority: 2),
                    ],
                    handoffOut: scene.handoffOut)
            })
        let outcome = LyricStageBudget.apply(
            score,
            lines: lines,
            tokens: lines.map(LyricStageTokenizer.tokens(for:)))
        let quiet = outcome.score.scenes.filter { scene in
            scene.events.allSatisfy { $0.verb == .appear || $0.verb == .dissolve }
        }
        XCTAssertGreaterThanOrEqual(Double(quiet.count) / Double(outcome.score.scenes.count), 0.6)
    }

    private func withEvents(_ score: LyricStageScoreV2, verbs: [StageVerb]) -> LyricStageScoreV2 {
        LyricStageScoreV2(
            trackID: score.trackID,
            lyricsHash: score.lyricsHash,
            styleSheet: score.styleSheet,
            sections: score.sections,
            scenes: score.scenes.map { scene in
                let extras = verbs.map { verb in
                    StageEvent(
                        actorID: scene.actors[0].id,
                        phase: .performance,
                        verb: verb,
                        start: 0.35,
                        duration: 0.3,
                        intensity: 1,
                        reason: .emotionalPeak,
                        priority: 2)
                }
                return StageScene(
                    id: scene.id,
                    lineIndices: scene.lineIndices,
                    composition: scene.composition,
                    actors: scene.actors,
                    events: scene.events + extras,
                    handoffOut: scene.handoffOut)
            })
    }
}
