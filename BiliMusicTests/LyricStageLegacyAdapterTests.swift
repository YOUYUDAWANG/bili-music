import XCTest
@testable import BiliMusic

final class LyricStageLegacyAdapterTests: XCTestCase {
    func testGravityDropBecomesADropEntrance() {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 3, text: "Drop it")]
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let performance = LyricPerformanceScore(
            version: LyricPerformanceScore.currentVersion,
            directorVersion: "legacy",
            trackID: "fixture",
            lyricsHash: hash,
            lineCount: 1,
            mood: "drop",
            compositions: [LyricTextComposition(lineIndex: 0, textLineIndices: [0])],
            scenes: [
                LyricPerformanceScene(
                    lineIndex: 0,
                    effect: .drop,
                    alignment: .center,
                    direction: 1,
                    intensity: 1,
                    fontScale: 1,
                    trackingScale: 1),
            ],
            stageDirectives: [
                LyricStageDirective(
                    lineIndex: 0,
                    behavior: .gravityDrop,
                    alignment: .center,
                    direction: 1,
                    intensity: 1,
                    fontScale: 1,
                    glyphStagger: 0.04,
                    paletteRole: .warm),
            ])
        let adapted = LyricStageLegacyAdapter.adapt(
            trackID: "fixture",
            lines: lines,
            performanceScore: performance)
        XCTAssertEqual(adapted.scenes.first?.events.first { $0.phase == .entrance }?.verb, .drop)
    }

    func testWordCuesBecomeTokenPerformanceEvents() {
        let lines = [
            PlayerEngine.LyricLine(
                from: 0,
                to: 3,
                text: "hold on",
                words: [
                    .init(from: 0, to: 1.2, text: "hold"),
                    .init(from: 1.3, to: 3, text: "on"),
                ]),
        ]
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let performance = LyricPerformanceScore(
            version: LyricPerformanceScore.currentVersion,
            directorVersion: "legacy",
            trackID: "fixture",
            lyricsHash: hash,
            lineCount: 1,
            mood: "cue",
            compositions: [LyricTextComposition(lineIndex: 0, textLineIndices: [0])],
            scenes: [
                LyricPerformanceScene(
                    lineIndex: 0,
                    effect: .focus,
                    alignment: .center,
                    direction: 1,
                    intensity: 1,
                    fontScale: 1,
                    trackingScale: 1),
            ],
            wordCues: [
                LyricWordCue(
                    lineIndex: 0,
                    startWordIndex: 0,
                    endWordIndex: 0,
                    effect: .impact,
                    intensity: 1,
                    direction: 1),
            ])
        let adapted = LyricStageLegacyAdapter.adapt(
            trackID: "fixture",
            lines: lines,
            performanceScore: performance)
        XCTAssertTrue(adapted.scenes[0].actors.contains { actor in
            if case .tokens = actor.target { return true }
            return false
        })
        XCTAssertEqual(
            adapted.scenes[0].events.first { $0.phase == .performance }?.verb,
            .pulse)
    }
}
