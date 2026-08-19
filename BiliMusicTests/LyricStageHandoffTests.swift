import XCTest
@testable import BiliMusic

final class LyricStageHandoffTests: XCTestCase {
    func testDissolveHandoffIsCompiledIntoAbsoluteWindows() {
        let lines = [
            PlayerEngine.LyricLine(from: 0, to: 2, text: "first"),
            PlayerEngine.LyricLine(from: 2, to: 4, text: "second"),
        ]
        let glyphs = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines)?.glyphs ?? []
        XCTAssertTrue(glyphs.contains { glyph in
            glyph.handoffs.contains { window in
                if case .dissolve = window.kind { return true }
                return false
            }
        })
    }

    func testPushHandoffOffsetsAtTheBoundaryWithoutPreviousFrameState() {
        let lines = [
            PlayerEngine.LyricLine(from: 0, to: 2, text: "first"),
            PlayerEngine.LyricLine(from: 2, to: 4, text: "second"),
        ]
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let score = LyricStageScoreV2(
            trackID: "fixture",
            lyricsHash: hash,
            styleSheet: StageStyleSheet(
                concept: "push",
                paletteStrategy: .coverAnalogous,
                typeSystem: .iPhone17Pro,
                motifs: []),
            sections: [],
            scenes: [
                StageScene(
                    id: "a",
                    lineIndices: [0],
                    composition: .singleAnchor,
                    actors: [
                        StageActor(
                            id: "a",
                            target: .line(lineIndex: 0),
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
                    handoffOut: .push(direction: .trailing)),
                StageScene(
                    id: "b",
                    lineIndices: [1],
                    composition: .singleAnchor,
                    actors: [
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
                            actorID: "b",
                            phase: .entrance,
                            verb: .appear,
                            start: 0,
                            duration: 0.3,
                            intensity: 0.5,
                            reason: .structuralTransition),
                    ],
                    handoffOut: .dissolve),
            ])
        let resolved = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines, score: score)
        let atBoundary = resolved?.sample(at: 2.05) ?? []
        XCTAssertFalse(atBoundary.isEmpty)
        XCTAssertTrue(atBoundary.contains { abs($0.offset.width) > 1 })
        XCTAssertEqual(resolved?.sample(at: 2.05), resolved?.sample(at: 2.05))
    }
}
