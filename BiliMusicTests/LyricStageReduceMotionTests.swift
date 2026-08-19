import XCTest
@testable import BiliMusic

final class LyricStageReduceMotionTests: XCTestCase {
    func testReduceMotionRemovesLargeTranslationAndBounce() {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 3, text: "Drop!")]
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let score = LyricStageScoreV2(
            trackID: "fixture",
            lyricsHash: hash,
            styleSheet: StageStyleSheet(
                concept: "motion",
                paletteStrategy: .coverAnalogous,
                typeSystem: .iPhone17Pro,
                motifs: []),
            sections: [],
            scenes: [
                StageScene(
                    id: "drop",
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
                            verb: .drop,
                            start: 0,
                            duration: 0.4,
                            intensity: 1,
                            reason: .actionWord),
                    ],
                    handoffOut: .push(direction: .trailing)),
            ])
        let moving = LyricStageCompilerV2.compile(
            trackID: "fixture",
            lines: lines,
            score: score,
            reduceMotion: false)?.sample(at: 0.2).first
        let reduced = LyricStageCompilerV2.compile(
            trackID: "fixture",
            lines: lines,
            score: score,
            reduceMotion: true)
        let sampled = reduced?.sample(at: 0.2).first
        XCTAssertTrue(reduced?.reduceMotion ?? false)
        XCTAssertLessThan(abs(sampled?.offset.height ?? 99), abs(moving?.offset.height ?? 0) * 0.4 + 4)
        XCTAssertEqual(sampled?.rotation ?? 99, 0, accuracy: 0.001)
        XCTAssertGreaterThan(sampled?.opacity ?? 0, 0.2)
    }
}
