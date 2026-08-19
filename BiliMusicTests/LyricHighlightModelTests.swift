import XCTest
@testable import BiliMusic

final class LyricHighlightModelTests: XCTestCase {
    func testActiveLineIndexIsNilBeforeTheFirstLine() {
        let lines = [
            line(from: 4, to: 8, text: "one"),
            line(from: 10, to: 14, text: "two")
        ]
        XCTAssertNil(LyricHighlightModel.activeLineIndex(lines: lines, at: 0))
        XCTAssertNil(LyricHighlightModel.activeLineIndex(lines: lines, at: 3.99))
    }

    func testActiveLineIndexUsesClosedOpenIntervalThenFallsBackToLastStartedLine() {
        let lines = [
            line(from: 4, to: 8, text: "one"),
            line(from: 10, to: 14, text: "two"),
            line(from: 16, to: 20, text: "three")
        ]
        XCTAssertEqual(LyricHighlightModel.activeLineIndex(lines: lines, at: 4), 0)
        XCTAssertEqual(LyricHighlightModel.activeLineIndex(lines: lines, at: 7.9), 0)
        XCTAssertEqual(LyricHighlightModel.activeLineIndex(lines: lines, at: 8), 0)
        XCTAssertEqual(LyricHighlightModel.activeLineIndex(lines: lines, at: 9), 0)
        XCTAssertEqual(LyricHighlightModel.activeLineIndex(lines: lines, at: 10), 1)
        XCTAssertEqual(LyricHighlightModel.activeLineIndex(lines: lines, at: 21), 2)
    }

    func testActiveLineIndexIsNilForEmptyLyrics() {
        XCTAssertNil(LyricHighlightModel.activeLineIndex(lines: [], at: 12))
    }

    func testHighlightedLinesUseTheSameFallbackAsAutoScrollDuringTimestampGaps() {
        let lines = [
            line(from: 4, to: 8, text: "one"),
            line(from: 10, to: 14, text: "two")
        ]

        XCTAssertEqual(LyricHighlightModel.highlightedLineIndices(lines: lines, at: 6), [0])
        XCTAssertEqual(LyricHighlightModel.highlightedLineIndices(lines: lines, at: 9), [0])
        XCTAssertEqual(LyricHighlightModel.highlightedLineIndices(lines: lines, at: 10), [1])
        XCTAssertTrue(LyricHighlightModel.highlightedLineIndices(lines: lines, at: 3.9).isEmpty)
    }

    func testWordStatesAreEmptyWhenALineHasNoWords() {
        let empty = line(from: 0, to: 4, text: "plain")
        XCTAssertTrue(LyricHighlightModel.wordStates(of: empty, at: 1).isEmpty)
    }

    func testWordStatesSortUnstableInputAndClassifySungCurrentUnsung() {
        let shuffled = PlayerEngine.LyricLine(
            from: 0,
            to: 6,
            text: "a b c",
            words: [
                PlayerEngine.LyricWord(from: 4, to: 6, text: "c"),
                PlayerEngine.LyricWord(from: 0, to: 2, text: "a"),
                PlayerEngine.LyricWord(from: 2, to: 4, text: "b")
            ])
        XCTAssertEqual(
            LyricHighlightModel.wordStates(of: shuffled, at: 2.5),
            [.sung, .current(progress: 0.25), .unsung])
        XCTAssertEqual(
            LyricHighlightModel.wordStates(of: shuffled, at: 6),
            [.sung, .sung, .sung])
        XCTAssertEqual(
            LyricHighlightModel.wordStates(of: shuffled, at: 0),
            [.current(progress: 0), .unsung, .unsung])
    }

    func testWordFillProgressConsumesCurrentTimingContinuously() {
        XCTAssertEqual(LyricHighlightModel.fillProgress(for: .unsung), 0)
        XCTAssertEqual(LyricHighlightModel.fillProgress(for: .current(progress: 0.25)), 0.25)
        XCTAssertEqual(LyricHighlightModel.fillProgress(for: .current(progress: -1)), 0)
        XCTAssertEqual(LyricHighlightModel.fillProgress(for: .current(progress: 2)), 1)
        XCTAssertEqual(LyricHighlightModel.fillProgress(for: .sung), 1)
    }

    private func line(from: Double, to: Double, text: String) -> PlayerEngine.LyricLine {
        PlayerEngine.LyricLine(from: from, to: to, text: text)
    }
}
