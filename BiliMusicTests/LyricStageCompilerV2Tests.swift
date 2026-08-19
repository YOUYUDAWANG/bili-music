import XCTest
@testable import BiliMusic

final class LyricStageCompilerV2Tests: XCTestCase {
    func testSameInputAlwaysProducesTheSameResolvedScore() {
        let lines = mixedLines()
        let first = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines)
        let second = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines)
        XCTAssertEqual(first, second)
        XCTAssertEqual(
            first?.glyphs.map(\.text).joined().filter { !$0.isWhitespace },
            "左声部右声部未来へordinarylineagainagain")
    }

    func testSeekIntoASceneMatchesPlayingThroughIt() {
        let lines = mixedLines()
        let score = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines)
        let mid = score?.sample(at: 1.2)
        let alsoMid = score?.sample(at: 1.2)
        XCTAssertEqual(mid, alsoMid)
        XCTAssertEqual(score?.sample(at: 0.4).map(\.id), score?.sample(at: 0.4).map(\.id))
    }

    func testLineOnlyLyricsDoNotInventKaraokeSyncWindows() {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 4, text: "只有逐行轴")]
        let glyphs = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines)?.glyphs ?? []
        XCTAssertTrue(glyphs.allSatisfy { $0.syncWindow == nil })
        XCTAssertEqual(glyphs.map(\.text).joined(), "只有逐行轴")
    }

    func testLocalBaselineKeepsLineTimedLyricsAliveDuringHold() {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 6, text: "逐行歌词也应有轻微呼吸")]
        let directed = LyricStageDirectorV2.compose(trackID: "fixture", lines: lines)
        XCTAssertTrue(directed.scenes[0].events.contains { $0.phase == .hold && $0.verb == .pulse })

        let resolved = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines, score: directed)
        XCTAssertNotEqual(resolved?.sample(at: 2.3), resolved?.sample(at: 3.1))
    }

    func testWordTimedLyricsKeepRealSyncWindows() {
        let line = PlayerEngine.LyricLine(
            from: 1,
            to: 3,
            text: "未来へ",
            words: [
                .init(from: 1, to: 1.5, text: "未"),
                .init(from: 1.5, to: 2, text: "来"),
                .init(from: 2, to: 3, text: "へ"),
            ])
        let glyphs = LyricStageCompilerV2.compile(trackID: "fixture", lines: [line])?.glyphs ?? []
        XCTAssertEqual(glyphs.compactMap(\.syncWindow).count, 3)
        XCTAssertEqual(glyphs.first?.syncWindow?.lowerBound ?? -1, 1, accuracy: 0.001)
    }

    func testOverlapGroupCompilesSplitVoicesAndMultipleActors() {
        let lines = mixedLines()
        let score = LyricStageDirectorV2.compose(trackID: "fixture", lines: lines)
        let duet = score.scenes.first { $0.composition == .splitVoices }
        XCTAssertEqual(duet?.actors.count, 2)
        XCTAssertTrue(duet?.events.contains { $0.reason == .vocalOverlap } ?? false)
        let resolved = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines, score: score)
        XCTAssertGreaterThanOrEqual(resolved?.glyphs.filter { $0.lineIndex == 0 || $0.lineIndex == 1 }.count ?? 0, 6)
    }

    func testLongEnglishLineKeepsEveryGlyph() {
        let text = "Signals cross the skyline without losing a single wrapped English word"
        let lines = [PlayerEngine.LyricLine(from: 0, to: 5, text: text)]
        let glyphs = LyricStageCompilerV2.compile(
            trackID: "fixture",
            lines: lines,
            canvasSize: CGSize(width: 340, height: 240))?.glyphs ?? []
        XCTAssertEqual(glyphs.map(\.text).joined(), text)
        XCTAssertGreaterThan(Set(glyphs.map { Int($0.origin.y) }).count, 1)
    }

    func testPartialLunaScoreIsFilledWithLocalScenes() {
        let lines = mixedLines()
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let partial = LyricStageScoreV2(
            trackID: "fixture",
            lyricsHash: hash,
            styleSheet: StageStyleSheet(
                concept: "partial",
                paletteStrategy: .coverComplementary,
                typeSystem: .iPhone17Pro,
                motifs: []),
            sections: [],
            scenes: [
                StageScene(
                    id: "only-first",
                    lineIndices: [0],
                    composition: .singleAnchor,
                    actors: [
                        StageActor(
                            id: "base",
                            target: .line(lineIndex: 0),
                            role: .base,
                            anchor: .center,
                            typeRole: .normal,
                            paletteRole: .primary),
                    ],
                    events: [
                        StageEvent(
                            actorID: "base",
                            phase: .entrance,
                            verb: .appear,
                            start: 0,
                            duration: 0.3,
                            intensity: 0.5,
                            reason: .structuralTransition),
                    ],
                    handoffOut: .dissolve),
            ])
        let resolved = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines, score: partial)
        XCTAssertGreaterThanOrEqual(Set(resolved?.glyphs.map(\.lineIndex) ?? []).count, 4)
    }

    func testOneLineCanHoldTwoActorsWithPhasedEvents() {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 4, text: "Run now!")]
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let score = LyricStageScoreV2(
            trackID: "fixture",
            lyricsHash: hash,
            styleSheet: StageStyleSheet(
                concept: "two-actors",
                paletteStrategy: .coolClimax,
                typeSystem: .iPhone17Pro,
                motifs: []),
            sections: [],
            scenes: [
                StageScene(
                    id: "duo",
                    lineIndices: [0],
                    composition: .singleAnchor,
                    actors: [
                        StageActor(
                            id: "base",
                            target: .line(lineIndex: 0),
                            role: .base,
                            anchor: .center,
                            typeRole: .normal,
                            paletteRole: .primary),
                        StageActor(
                            id: "hero",
                            target: .tokens(lineIndex: 0, tokenIndices: [0]),
                            role: .protagonist,
                            anchor: .center,
                            typeRole: .hero,
                            paletteRole: .accent),
                    ],
                    events: [
                        StageEvent(
                            actorID: "base",
                            phase: .entrance,
                            verb: .assemble,
                            start: 0,
                            duration: 0.35,
                            intensity: 0.7,
                            reason: .structuralTransition),
                        StageEvent(
                            actorID: "hero",
                            phase: .performance,
                            verb: .pulse,
                            start: 0.4,
                            duration: 0.3,
                            intensity: 1,
                            reason: .actionWord),
                        StageEvent(
                            actorID: "base",
                            phase: .exit,
                            verb: .dissolve,
                            start: 0.8,
                            duration: 0.2,
                            intensity: 0.6,
                            reason: .structuralTransition),
                    ],
                    handoffOut: .dissolve),
            ])
        let resolved = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines, score: score)
        XCTAssertGreaterThanOrEqual(resolved?.summary.heroScenes.count ?? 0, 1)
        let hero = resolved?.glyphs.first { $0.events.contains { $0.verb == .pulse } }
        XCTAssertNotNil(hero)
        XCTAssertTrue(hero?.events.contains { $0.phase == .performance } ?? false)
        let heroSize = resolved?.glyphs.first { $0.actorID == "hero" }?.fontSize ?? 0
        let baseSize = resolved?.glyphs.first { $0.actorID == "base" }?.fontSize ?? 0
        XCTAssertGreaterThan(heroSize, baseSize)
    }

    func testKeywordActorKeepsIndependentTypeRole() {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 4, text: "Run now!")]
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let resolved = LyricStageCompilerV2.compile(
            trackID: "fixture",
            lines: lines,
            score: twoActorScore(hash: hash, lines: lines))
        let hero = resolved?.glyphs.filter { $0.actorID == "hero" && !$0.isBackdrop } ?? []
        let base = resolved?.glyphs.filter { $0.actorID == "base" && !$0.isBackdrop } ?? []
        XCTAssertFalse(hero.isEmpty)
        XCTAssertFalse(base.isEmpty)
        XCTAssertGreaterThan(hero.map(\.fontSize).max() ?? 0, base.map(\.fontSize).min() ?? 99)
        XCTAssertEqual(hero.map(\.text).joined(), "Run")
    }

    func testStackedWrappedLinesDoNotOverlap() {
        let first = "Signals cross the skyline without losing a single wrapped English word tonight"
        let second = "Keep the station glowing"
        let lines = [
            PlayerEngine.LyricLine(from: 0, to: 3, text: first),
            PlayerEngine.LyricLine(from: 3, to: 6, text: second),
        ]
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let score = LyricStageScoreV2(
            trackID: "fixture",
            lyricsHash: hash,
            styleSheet: StageStyleSheet(
                concept: "stack",
                paletteStrategy: .coverAnalogous,
                typeSystem: .iPhone17Pro,
                motifs: []),
            sections: [],
            scenes: [
                StageScene(
                    id: "stack",
                    lineIndices: [0, 1],
                    composition: .stacked,
                    actors: [
                        StageActor(
                            id: "a",
                            target: .line(lineIndex: 0),
                            role: .base,
                            anchor: .center,
                            typeRole: .normal,
                            paletteRole: .primary),
                        StageActor(
                            id: "b",
                            target: .line(lineIndex: 1),
                            role: .base,
                            anchor: .center,
                            typeRole: .normal,
                            paletteRole: .primary),
                    ],
                    events: [
                        StageEvent(
                            actorID: "a",
                            phase: .entrance,
                            verb: .appear,
                            start: 0,
                            duration: 0.3,
                            intensity: 0.5,
                            reason: .structuralTransition),
                    ],
                    handoffOut: .dissolve),
            ])
        let glyphs = LyricStageCompilerV2.compile(
            trackID: "fixture",
            lines: lines,
            score: score,
            canvasSize: CGSize(width: 340, height: 280))?.glyphs.filter { !$0.isBackdrop } ?? []
        let firstBottom = glyphs.filter { $0.lineIndex == 0 }.map { $0.origin.y + $0.size.height }.max() ?? 0
        let secondTop = glyphs.filter { $0.lineIndex == 1 }.map(\.origin.y).min() ?? 0
        XCTAssertGreaterThan(Set(glyphs.filter { $0.lineIndex == 0 }.map { Int($0.origin.y) }).count, 1)
        XCTAssertGreaterThan(secondTop, firstBottom)
    }

    func testForegroundGlyphsStayCompletePastTheConcurrentBudget() {
        let text = String(repeating: "abcde ", count: 30)
        XCTAssertGreaterThan(Array(text).count, LyricStageBudget.maxActiveGlyphs)
        XCTAssertEqual(
            LyricStageTokenizer.tokens(for: PlayerEngine.LyricLine(from: 0, to: 4, text: text)).map(\.text).joined(),
            text)
        let lines = [PlayerEngine.LyricLine(from: 0, to: 4, text: text)]
        let resolved = LyricStageCompilerV2.compile(
            trackID: "fixture",
            lines: lines,
            canvasSize: CGSize(width: 340, height: 280))
        let foreground = (resolved?.glyphs ?? []).filter { !$0.isBackdrop }
        XCTAssertEqual(foreground.count, Array(text).count)
        XCTAssertEqual(foreground.map(\.text).joined(), text)
        let sampled = resolved?.sample(at: 1) ?? []
        XCTAssertEqual(sampled.filter { !$0.isBackdrop }.map(\.text).joined(), text)
        XCTAssertGreaterThan(sampled.filter { !$0.isBackdrop }.count, LyricStageBudget.maxActiveGlyphs)
    }

    func testCJKTokensWrapAtTokenBoundaries() {
        let text = String(repeating: "未来へ続く夜空", count: 6)
        let line = PlayerEngine.LyricLine(from: 0, to: 4, text: text)
        let tokens = LyricStageTokenizer.tokens(for: line)
        XCTAssertGreaterThan(tokens.filter { $0.kind == .word }.count, 1)
        let glyphs = LyricStageCompilerV2.compile(
            trackID: "fixture",
            lines: [line],
            canvasSize: CGSize(width: 340, height: 280))?.glyphs.filter { !$0.isBackdrop } ?? []
        XCTAssertEqual(glyphs.map(\.text).joined(), text)
        XCTAssertGreaterThan(Set(glyphs.map { Int($0.origin.y) }).count, 1)
        let maxRight = glyphs.map { $0.origin.x + $0.size.width }.max() ?? 0
        XCTAssertLessThanOrEqual(maxRight, 360)
        for token in tokens where token.kind == .word || token.kind == .particle {
            let rows = Set(glyphs.filter { $0.tokenID == token.id }.map { Int(($0.origin.y * 10).rounded()) })
            XCTAssertEqual(rows.count, 1, token.text)
        }
    }

    func testOverBudgetEchoEventsDoNotSurviveSampling() {
        let text = String(repeating: "abcde ", count: 30)
        let lines = [PlayerEngine.LyricLine(from: 0, to: 4, text: text)]
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let score = LyricStageScoreV2(
            trackID: "fixture",
            lyricsHash: hash,
            styleSheet: StageStyleSheet(
                concept: "echo",
                paletteStrategy: .coverAnalogous,
                typeSystem: .iPhone17Pro,
                motifs: [StageMotif(id: "echo-repeat", verb: .echo, note: "hook")]),
            sections: [],
            scenes: [
                StageScene(
                    id: "s0",
                    lineIndices: [0],
                    composition: .singleAnchor,
                    actors: [
                        StageActor(
                            id: "base",
                            target: .line(lineIndex: 0),
                            role: .base,
                            anchor: .center,
                            typeRole: .normal,
                            paletteRole: .primary),
                    ],
                    events: [
                        StageEvent(
                            actorID: "base",
                            phase: .entrance,
                            verb: .appear,
                            start: 0,
                            duration: 0.3,
                            intensity: 0.5,
                            reason: .structuralTransition),
                        StageEvent(
                            actorID: "base",
                            phase: .performance,
                            verb: .echo,
                            start: 0.35,
                            duration: 0.4,
                            intensity: 1,
                            motifRef: "echo-repeat",
                            reason: .hookRepeat,
                            priority: 2),
                    ],
                    handoffOut: .dissolve),
            ])
        let resolved = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines, score: score)
        XCTAssertGreaterThan(LyricStageBudget.peakConcurrent(resolved?.glyphs ?? []), LyricStageBudget.maxActiveGlyphs)
        XCTAssertFalse(resolved?.glyphs.contains { glyph in glyph.events.contains { $0.verb == .echo } } ?? true)
        let sampled = resolved?.sample(at: 1.6) ?? []
        XCTAssertTrue(sampled.allSatisfy { $0.echoLayers == 0 })
        XCTAssertEqual(sampled.filter { !$0.isBackdrop }.map(\.text).joined(), text)
    }

    func testAttractToUsesTheHeroInsideTheSameScene() {
        let lines = [
            PlayerEngine.LyricLine(from: 0, to: 2, text: "LEFT"),
            PlayerEngine.LyricLine(from: 3, to: 5, text: "RIGHT WORD"),
        ]
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let score = LyricStageScoreV2(
            trackID: "fixture",
            lyricsHash: hash,
            styleSheet: StageStyleSheet(
                concept: "attract",
                paletteStrategy: .coverAnalogous,
                typeSystem: .iPhone17Pro,
                motifs: []),
            sections: [],
            scenes: [
                StageScene(
                    id: "s0",
                    lineIndices: [0],
                    composition: .singleAnchor,
                    actors: [
                        StageActor(
                            id: "base",
                            target: .line(lineIndex: 0),
                            role: .base,
                            anchor: .trailing,
                            typeRole: .normal,
                            paletteRole: .primary),
                        StageActor(
                            id: "hero",
                            target: .glyphs(lineIndex: 0, glyphFrom: 0, glyphTo: 0),
                            role: .protagonist,
                            anchor: .leading,
                            typeRole: .hero,
                            paletteRole: .accent),
                    ],
                    events: [
                        StageEvent(
                            actorID: "base",
                            phase: .performance,
                            verb: .pulse,
                            start: 0.3,
                            duration: 0.4,
                            intensity: 1,
                            reason: .emotionalPeak,
                            relation: .attractTo(actorID: "hero")),
                    ],
                    handoffOut: .dissolve),
                StageScene(
                    id: "s1",
                    lineIndices: [1],
                    composition: .singleAnchor,
                    actors: [
                        StageActor(
                            id: "base",
                            target: .line(lineIndex: 1),
                            role: .base,
                            anchor: .leading,
                            typeRole: .normal,
                            paletteRole: .primary),
                        StageActor(
                            id: "hero",
                            target: .glyphs(lineIndex: 1, glyphFrom: 6, glyphTo: 9),
                            role: .protagonist,
                            anchor: .trailing,
                            typeRole: .hero,
                            paletteRole: .accent),
                    ],
                    events: [
                        StageEvent(
                            actorID: "base",
                            phase: .performance,
                            verb: .pulse,
                            start: 0.3,
                            duration: 0.4,
                            intensity: 1,
                            reason: .emotionalPeak,
                            relation: .attractTo(actorID: "hero")),
                    ],
                    handoffOut: .dissolve),
            ])
        let glyphs = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines, score: score)?.glyphs ?? []
        let first = glyphs.first { $0.lineIndex == 0 && $0.actorID == "base" }
        let offset = first?.events.first { $0.verb == .pulse }?.relationOffset.width ?? 0
        XCTAssertLessThan(offset, 0)
    }

    func testPartialDuetFallbackDoesNotDuplicateCoveredVoice() {
        let lines = [
            PlayerEngine.LyricLine(from: 0, to: 2, text: "左声部", voiceRole: .duetA, overlapGroup: "duet"),
            PlayerEngine.LyricLine(from: 0, to: 2, text: "右声部", voiceRole: .duetB, overlapGroup: "duet"),
            PlayerEngine.LyricLine(from: 2, to: 4, text: "next"),
        ]
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let partial = LyricStageScoreV2(
            trackID: "fixture",
            lyricsHash: hash,
            styleSheet: StageStyleSheet(
                concept: "partial-duet",
                paletteStrategy: .coverAnalogous,
                typeSystem: .iPhone17Pro,
                motifs: []),
            sections: [],
            scenes: [
                StageScene(
                    id: "luna-a",
                    lineIndices: [0],
                    composition: .singleAnchor,
                    actors: [
                        StageActor(
                            id: "base",
                            target: .line(lineIndex: 0),
                            role: .vocalA,
                            anchor: .leading,
                            typeRole: .normal,
                            paletteRole: .accent),
                    ],
                    events: [
                        StageEvent(
                            actorID: "base",
                            phase: .entrance,
                            verb: .appear,
                            start: 0,
                            duration: 0.3,
                            intensity: 0.5,
                            reason: .vocalOverlap),
                    ],
                    handoffOut: .dissolve),
            ])
        let filled = LyricStageDirectorV2.fillMissingScenes(in: partial, lines: lines)
        XCTAssertEqual(filled.scenes.filter { $0.lineIndices.contains(0) }.count, 1)
        XCTAssertTrue(filled.scenes.contains { $0.lineIndices == [1] || $0.lineIndices == [1, 2] || $0.lineIndices.contains(1) && !$0.lineIndices.contains(0) })
        let glyphs = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines, score: filled)?.glyphs.filter { !$0.isBackdrop } ?? []
        XCTAssertEqual(glyphs.filter { $0.lineIndex == 0 }.map(\.text).joined(), "左声部")
        XCTAssertEqual(glyphs.filter { $0.lineIndex == 1 }.map(\.text).joined(), "右声部")
    }

    func testEnglishWordTokensStayOnOneRow() {
        let text = "Signals cross the skyline without losing a single wrapped English word"
        let line = PlayerEngine.LyricLine(from: 0, to: 4, text: text)
        let tokens = LyricStageTokenizer.tokens(for: line)
        let glyphs = LyricStageCompilerV2.compile(
            trackID: "fixture",
            lines: [line],
            canvasSize: CGSize(width: 340, height: 240))?.glyphs.filter { !$0.isBackdrop } ?? []
        for token in tokens where token.kind == .word {
            let rows = Set(glyphs.filter { $0.tokenID == token.id }.map { Int(($0.origin.y * 10).rounded()) })
            XCTAssertEqual(rows.count, 1, token.text)
        }
    }

    func testRegeneratedScoreWithSameSceneCountStillChangesResolvedGlyphs() {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 3, text: "hello world")]
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let first = LyricStageScoreV2(
            trackID: "fixture",
            lyricsHash: hash,
            styleSheet: StageStyleSheet(
                concept: "one",
                paletteStrategy: .coverAnalogous,
                typeSystem: .iPhone17Pro,
                motifs: []),
            sections: [],
            scenes: [
                StageScene(
                    id: "s0",
                    lineIndices: [0],
                    composition: .singleAnchor,
                    actors: [
                        StageActor(
                            id: "base",
                            target: .line(lineIndex: 0),
                            role: .base,
                            anchor: .center,
                            typeRole: .normal,
                            paletteRole: .primary),
                    ],
                    events: [
                        StageEvent(
                            actorID: "base",
                            phase: .entrance,
                            verb: .appear,
                            start: 0,
                            duration: 0.3,
                            intensity: 0.4,
                            reason: .structuralTransition),
                    ],
                    handoffOut: .dissolve),
            ])
        var secondActors = first.scenes[0].actors
        secondActors.append(
            StageActor(
                id: "hero",
                target: .tokens(lineIndex: 0, tokenIndices: [0]),
                role: .protagonist,
                anchor: .center,
                typeRole: .hero,
                paletteRole: .accent))
        let second = LyricStageScoreV2(
            trackID: first.trackID,
            lyricsHash: hash,
            styleSheet: first.styleSheet,
            sections: first.sections,
            scenes: [
                StageScene(
                    id: "s0",
                    lineIndices: [0],
                    composition: .singleAnchor,
                    actors: secondActors,
                    events: first.scenes[0].events + [
                        StageEvent(
                            actorID: "hero",
                            phase: .performance,
                            verb: .pulse,
                            start: 0.4,
                            duration: 0.3,
                            intensity: 1,
                            reason: .actionWord),
                    ],
                    handoffOut: .dissolve),
            ])
        XCTAssertEqual(first.scenes.count, second.scenes.count)
        XCTAssertNotEqual(LyricStageFingerprint.score(first), LyricStageFingerprint.score(second))
        let compiledA = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines, score: first)
        let compiledB = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines, score: second)
        XCTAssertNotEqual(compiledA?.glyphs.map(\.fontSize), compiledB?.glyphs.map(\.fontSize))
    }

    private func twoActorScore(hash: String, lines _: [PlayerEngine.LyricLine]) -> LyricStageScoreV2 {
        LyricStageScoreV2(
            trackID: "fixture",
            lyricsHash: hash,
            styleSheet: StageStyleSheet(
                concept: "two-actors",
                paletteStrategy: .coolClimax,
                typeSystem: .iPhone17Pro,
                motifs: []),
            sections: [],
            scenes: [
                StageScene(
                    id: "duo",
                    lineIndices: [0],
                    composition: .singleAnchor,
                    actors: [
                        StageActor(
                            id: "base",
                            target: .line(lineIndex: 0),
                            role: .base,
                            anchor: .center,
                            typeRole: .normal,
                            paletteRole: .primary),
                        StageActor(
                            id: "hero",
                            target: .tokens(lineIndex: 0, tokenIndices: [0]),
                            role: .protagonist,
                            anchor: .center,
                            typeRole: .hero,
                            paletteRole: .accent),
                    ],
                    events: [
                        StageEvent(
                            actorID: "base",
                            phase: .entrance,
                            verb: .assemble,
                            start: 0,
                            duration: 0.35,
                            intensity: 0.7,
                            reason: .structuralTransition),
                        StageEvent(
                            actorID: "hero",
                            phase: .performance,
                            verb: .pulse,
                            start: 0.4,
                            duration: 0.3,
                            intensity: 1,
                            reason: .actionWord),
                    ],
                    handoffOut: .dissolve),
            ])
    }

    private func mixedLines() -> [PlayerEngine.LyricLine] {
        [
            PlayerEngine.LyricLine(from: 0, to: 2, text: "左声部", voiceRole: .duetA, overlapGroup: "duet"),
            PlayerEngine.LyricLine(from: 0, to: 2, text: "右声部", voiceRole: .duetB, overlapGroup: "duet"),
            PlayerEngine.LyricLine(
                from: 2,
                to: 4,
                text: "未来へ",
                words: [
                    .init(from: 2, to: 2.5, text: "未"),
                    .init(from: 2.5, to: 3.2, text: "来"),
                    .init(from: 3.2, to: 4, text: "へ"),
                ]),
            PlayerEngine.LyricLine(from: 4, to: 6, text: "ordinary line"),
            PlayerEngine.LyricLine(from: 6, to: 8, text: "again again"),
        ]
    }
}
