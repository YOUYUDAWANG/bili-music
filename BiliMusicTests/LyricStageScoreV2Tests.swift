import XCTest
@testable import BiliMusic

final class LyricStageScoreV2Tests: XCTestCase {
    func testRoundTripPreservesActorsEventsAndHandoff() throws {
        let original = fixtureScore()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LyricStageScoreV2.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testValidationDropsOutOfRangeTokensAndClampsIntensity() {
        let lines = fixtureLines()
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let invalid = LyricStageScoreV2(
            trackID: "fixture",
            lyricsHash: hash,
            styleSheet: StageStyleSheet(
                concept: "test",
                paletteStrategy: .coverAnalogous,
                typeSystem: .iPhone17Pro,
                motifs: []),
            sections: [
                StageSection(
                    id: "verse",
                    lineFrom: 0,
                    lineTo: 1,
                    kind: .verse,
                    density: 2,
                    heroBudget: 9,
                    accentBudget: 1,
                    preferredMotifs: []),
            ],
            scenes: [
                StageScene(
                    id: "s0",
                    lineIndices: [0, 99],
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
                            id: "bad",
                            target: .tokens(lineIndex: 0, tokenIndices: [99]),
                            role: .protagonist,
                            anchor: .center,
                            typeRole: .hero,
                            paletteRole: .accent),
                    ],
                    events: [
                        StageEvent(
                            actorID: "base",
                            phase: .entrance,
                            verb: .appear,
                            start: -1,
                            duration: 4,
                            intensity: 9,
                            reason: .structuralTransition),
                        StageEvent(
                            actorID: "missing",
                            phase: .performance,
                            verb: .pulse,
                            start: 0.2,
                            duration: 0.2,
                            intensity: 1,
                            reason: .actionWord),
                    ],
                    handoffOut: .dissolve),
            ])

        let safe = invalid.validated(
            trackID: "fixture",
            lyricsHash: hash,
            lineCount: lines.count,
            tokenCounts: LyricStageTokenizer.tokenCounts(for: lines),
            glyphCounts: LyricStageTokenizer.glyphCounts(for: lines))

        XCTAssertEqual(safe?.sections.first?.density, 1)
        XCTAssertEqual(safe?.sections.first?.heroBudget, 4)
        XCTAssertEqual(safe?.scenes.first?.actors.map(\.id), ["base"])
        XCTAssertEqual(safe?.scenes.first?.events.count, 1)
        XCTAssertEqual(safe?.scenes.first?.events.first?.intensity, 1.25)
        XCTAssertEqual(safe?.scenes.first?.lineIndices, [0])
    }

    func testValidationDropsIncompatiblePhaseVerbPairs() {
        let lines = fixtureLines()
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let score = LyricStageScoreV2(
            trackID: "fixture",
            lyricsHash: hash,
            styleSheet: StageStyleSheet(
                concept: "phase",
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
                            verb: .dissolve,
                            start: 0,
                            duration: 0.3,
                            intensity: 1,
                            reason: .structuralTransition),
                        StageEvent(
                            actorID: "base",
                            phase: .exit,
                            verb: .appear,
                            start: 0.8,
                            duration: 0.2,
                            intensity: 1,
                            reason: .structuralTransition),
                        StageEvent(
                            actorID: "base",
                            phase: .hold,
                            verb: .scatter,
                            start: 0.4,
                            duration: 0.2,
                            intensity: 1,
                            reason: .emotionalPeak),
                        StageEvent(
                            actorID: "base",
                            phase: .entrance,
                            verb: .appear,
                            start: 0,
                            duration: 0.3,
                            intensity: 0.6,
                            reason: .structuralTransition),
                    ],
                    handoffOut: .dissolve),
            ])
        let safe = score.validated(
            trackID: "fixture",
            lyricsHash: hash,
            lineCount: lines.count,
            tokenCounts: LyricStageTokenizer.tokenCounts(for: lines),
            glyphCounts: LyricStageTokenizer.glyphCounts(for: lines))
        XCTAssertEqual(safe?.scenes.first?.events.map(\.verb), [.appear])
        XCTAssertEqual(safe?.scenes.first?.events.first?.phase, .entrance)
    }

    func testWrongVersionOrHashIsRejected() {
        let lines = fixtureLines()
        let score = fixtureScore()
        XCTAssertNil(
            score.validated(
                trackID: "fixture",
                lyricsHash: "deadbeef",
                lineCount: lines.count,
                tokenCounts: [:],
                glyphCounts: [:]))
    }

    private func fixtureLines() -> [PlayerEngine.LyricLine] {
        [
            PlayerEngine.LyricLine(from: 0, to: 2, text: "hello world"),
            PlayerEngine.LyricLine(from: 2, to: 4, text: "again"),
        ]
    }

    private func fixtureScore() -> LyricStageScoreV2 {
        let lines = fixtureLines()
        return LyricStageScoreV2(
            trackID: "fixture",
            lyricsHash: LyricPerformanceFingerprint.lyricsHash(lines),
            styleSheet: StageStyleSheet(
                concept: "fixture concept",
                paletteStrategy: .warmClimax,
                typeSystem: .iPhone17Pro,
                motifs: [StageMotif(id: "echo-repeat", verb: .echo, note: "hook")]),
            sections: [
                StageSection(
                    id: "chorus",
                    lineFrom: 0,
                    lineTo: 1,
                    kind: .chorus,
                    density: 0.85,
                    heroBudget: 1,
                    accentBudget: 0.2,
                    preferredMotifs: ["echo-repeat"]),
            ],
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
                        StageActor(
                            id: "hero",
                            target: .glyphs(lineIndex: 0, glyphFrom: 0, glyphTo: 0),
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
                            intensity: 0.8,
                            reason: .structuralTransition),
                        StageEvent(
                            actorID: "hero",
                            phase: .performance,
                            verb: .pulse,
                            start: 0.4,
                            duration: 0.3,
                            intensity: 1,
                            reason: .emotionalPeak),
                    ],
                    handoffOut: .push(direction: .trailing)),
            ])
    }
}
