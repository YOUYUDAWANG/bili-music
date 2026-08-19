import XCTest
@testable import BiliMusic

final class LyricStageTimelineTests: XCTestCase {
    func testSampleIsAPureFunctionOfTime() {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 4, text: "sample")]
        let score = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines)
        XCTAssertEqual(score?.sample(at: 1.5), score?.sample(at: 1.5))
        XCTAssertNotEqual(score?.sample(at: 0.1).first?.opacity, score?.sample(at: 1.5).first?.opacity)
    }

    func testSampleDoesNotTruncateForegroundText() {
        let text = String(repeating: "abcde ", count: 30)
        XCTAssertGreaterThan(Array(text).count, LyricStageBudget.maxActiveGlyphs)
        let lines = [PlayerEngine.LyricLine(from: 0, to: 3, text: text)]
        let sampled = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines)?.sample(at: 1) ?? []
        XCTAssertEqual(sampled.filter { !$0.isBackdrop }.map(\.text).joined(), text)
    }

    func testPausedSeekDoesNotDependOnPreviousFrame() {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 5, text: "seek back")]
        let score = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines)
        _ = score?.sample(at: 4.8)
        let jumped = score?.sample(at: 0.4)
        let direct = LyricStageCompilerV2.compile(trackID: "fixture", lines: lines)?.sample(at: 0.4)
        XCTAssertEqual(jumped, direct)
    }
}
