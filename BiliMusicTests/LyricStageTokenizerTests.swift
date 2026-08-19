import XCTest
@testable import BiliMusic

final class LyricStageTokenizerTests: XCTestCase {
    func testChineseCharactersBecomeWordOrParticleTokens() {
        let tokens = LyricStageTokenizer.tokens(for: line("我的天空！"))
        XCTAssertEqual(tokens.map(\.text).joined(), "我的天空！")
        XCTAssertEqual(tokens.map(\.kind), [.word, .particle, .word, .punctuation])
        XCTAssertEqual(tokens.map(\.text), ["我", "的", "天空", "！"])
        XCTAssertTrue(tokens.allSatisfy { $0.realTiming == nil })
    }

    func testJapaneseParticlesStaySeparateFromWords() {
        let tokens = LyricStageTokenizer.tokens(for: line("夜は続く"))
        XCTAssertEqual(tokens.map(\.kind), [.word, .particle, .word])
        XCTAssertEqual(tokens.map(\.text), ["夜", "は", "続く"])
    }

    func testEnglishUsesWordBoundaries() {
        let tokens = LyricStageTokenizer.tokens(for: line("Electric night begins"))
        XCTAssertEqual(tokens.filter { $0.kind == .word }.map(\.text), ["Electric", "night", "begins"])
        XCTAssertEqual(tokens.filter { $0.kind == .whitespace }.count, 2)
    }

    func testEmojiAndPunctuationAreClassified() {
        let tokens = LyricStageTokenizer.tokens(for: line("Go!🌙"))
        XCTAssertEqual(tokens.map(\.kind), [.word, .punctuation, .emoji])
    }

    func testRealWordsPreserveTimingAndCoverEveryGlyph() {
        let line = PlayerEngine.LyricLine(
            from: 1,
            to: 3,
            text: "未来へ Go!",
            words: [
                .init(from: 1, to: 1.4, text: "未"),
                .init(from: 1.4, to: 1.8, text: "来"),
                .init(from: 1.8, to: 2.1, text: "へ"),
                .init(from: 2.2, to: 3, text: "Go!"),
            ])
        let tokens = LyricStageTokenizer.tokens(for: line)
        XCTAssertEqual(tokens.map(\.text).joined(), line.text)
        XCTAssertEqual(tokens.last?.realTiming?.lowerBound ?? -1, 2.2, accuracy: 0.001)
        XCTAssertEqual(tokens.last?.glyphRange.count, 3)
    }

    func testJapaneseDesuIsOneParticle() {
        let tokens = LyricStageTokenizer.tokens(for: line("好きです"))
        XCTAssertEqual(tokens.map(\.text), ["好き", "です"])
        XCTAssertEqual(tokens.map(\.kind), [.word, .particle])
    }

    func testLineOnlyGlyphsJoinBackToOriginalText() {
        let text = "長い英文 wraps across the stage without ellipsis"
        let tokens = LyricStageTokenizer.tokens(for: line(text))
        XCTAssertEqual(tokens.map(\.text).joined(), text)
        XCTAssertEqual(LyricStageTokenizer.glyphCount(for: text), Array(text).count)
    }

    private func line(_ text: String) -> PlayerEngine.LyricLine {
        PlayerEngine.LyricLine(from: 0, to: 3, text: text)
    }
}
