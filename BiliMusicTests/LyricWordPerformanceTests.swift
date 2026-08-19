import XCTest
@testable import BiliMusic

final class LyricWordPerformanceTests: XCTestCase {
    func testDisplayTokensPreserveOriginalJapaneseTextAndPunctuation() {
        let line = PlayerEngine.LyricLine(
            from: 0,
            to: 2,
            text: "君は、笑った。",
            words: [
                word(0, 0.3, "君"),
                word(0.3, 0.6, "は、"),
                word(0.6, 1.0, "笑"),
                word(1.0, 1.3, "っ"),
                word(1.3, 1.6, "た。"),
            ])

        let tokens = LyricWordPerformanceModel.displayTokens(for: line)
        XCTAssertEqual(tokens.map(\.text).joined(), line.text)
        XCTAssertEqual(tokens.compactMap(\.wordIndex), Array(0..<5))
    }

    func testDisplayTokensKeepEnglishWhitespaceWithoutEllipsis() {
        let line = PlayerEngine.LyricLine(
            from: 0,
            to: 2,
            text: "Don't stop now",
            words: [
                word(0, 0.6, "Don't"),
                word(0.6, 1.2, "stop"),
                word(1.2, 1.8, "now"),
            ])

        let tokens = LyricWordPerformanceModel.displayTokens(for: line)
        XCTAssertEqual(tokens.map(\.text), ["Don't", " stop", " now"])
        XCTAssertEqual(tokens.map(\.text).joined(), line.text)
        XCTAssertFalse(tokens.map(\.text).joined().contains("…"))
    }

    func testUnmatchedWordPayloadFallsBackToFullUnmodifiedLine() {
        let line = PlayerEngine.LyricLine(
            from: 0,
            to: 2,
            text: "完全な歌詞",
            words: [word(0, 1, "different")])
        let tokens = LyricWordPerformanceModel.displayTokens(for: line)
        XCTAssertEqual(tokens.map(\.text), ["完全な歌詞"])
        XCTAssertNil(tokens[0].wordIndex)
    }

    func testPlaybackStateUsesRealWordTiming() {
        let token = LyricWordDisplayToken(id: 0, text: "歌", wordIndex: 0, from: 1, to: 2)
        XCTAssertEqual(LyricWordPerformanceModel.playbackState(for: token, at: 0.9), .unsung)
        XCTAssertEqual(LyricWordPerformanceModel.playbackState(for: token, at: 1.25), .current(progress: 0.25))
        XCTAssertEqual(LyricWordPerformanceModel.playbackState(for: token, at: 2), .sung)
    }

    private func word(_ from: Double, _ to: Double, _ text: String) -> PlayerEngine.LyricWord {
        PlayerEngine.LyricWord(from: from, to: to, text: text)
    }
}
