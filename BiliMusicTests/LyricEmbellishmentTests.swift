import XCTest
@testable import BiliMusic

final class LyricEmbellishmentTests: XCTestCase {
    
    // MARK: - Word Level Embellishment Tests
    
    func testWordEmbellishmentEmptyAndWhitespaceReturnsNone() {
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: ""), .none)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "   \n\t "), .none)
    }
    
    func testWordEmbellishmentPunctuationHeuristics() {
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "GO!"), .impact)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "さあ！"), .impact)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "where?"), .floating)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "どこ？"), .floating)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "secret…"), .whisper)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "ずっと..."), .whisper)
    }
    
    func testWordEmbellishmentWhisperKeywords() {
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "嘘"), .whisper)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "そっと"), .whisper)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "Whisper"), .whisper)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "gentle"), .whisper)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "悄悄"), .whisper)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "晚安"), .whisper)
    }
    
    func testWordEmbellishmentShimmerKeywords() {
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "星"), .shimmer)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "夜空"), .shimmer)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "shine"), .shimmer)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "SPARKLE"), .shimmer)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "闪耀"), .shimmer)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "キラキラ"), .shimmer)
    }
    
    func testWordEmbellishmentImpactKeywords() {
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "BANG"), .impact)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "JUMP"), .impact)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "叫べ"), .impact)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "冲"), .impact)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "爆炸"), .impact)
    }
    
    func testWordEmbellishmentFloatingKeywords() {
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "夢"), .floating)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "ゆめ"), .floating)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "DREAM"), .floating)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "漂う"), .floating)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "漂浮"), .floating)
    }
    
    func testWordEmbellishmentDigitalKeywords() {
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "8bit"), .digital)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "8-bit"), .digital)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "ROM"), .digital)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "Pixel"), .digital)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "电波"), .digital)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "回路"), .digital)
    }
    
    func testWordEmbellishmentNewStylesKeywords() {
        // Neon
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "neon"), .neon)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "ネオン"), .neon)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "霓虹"), .neon)

        // Blaze
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "fire"), .blaze)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "炎"), .blaze)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "燃烧"), .blaze)

        // Crystallize
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "crystal"), .crystallize)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "雪"), .crystallize)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "冰晶"), .crystallize)

        // Heartbeat
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "heartbeat"), .heartbeat)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "ドキドキ"), .heartbeat)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "心跳"), .heartbeat)

        // Vintage
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "nostalgia"), .vintage)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "想い出"), .vintage)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "老唱片"), .vintage)

        // Sway
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "breeze"), .sway)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "そよ風"), .sway)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "微风"), .sway)
    }
    
    func testWordEmbellishmentRepeatPatternRecognizesRipple() {
        let line = "bye bye my love"
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "bye", lineText: line), .ripple)
        
        let nonRepeatLine = "hello world"
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forWord: "hello", lineText: nonRepeatLine), .none)
    }
    
    // MARK: - Luna AI Embellishment Score Priority Tests
    
    func testAiScoreOverridesLocalRules() {
        let aiScore = LyricEmbellishmentScore(
            trackID: "track-1",
            lyricsHash: "hash-1",
            mood: "Electric",
            cues: [
                LyricEmbellishmentCue(lineIndex: 0, wordIndex: 1, style: .neon, note: "AI neon choice"),
                LyricEmbellishmentCue(lineIndex: 1, wordIndex: nil, style: .blaze, note: "AI blaze line")
            ]
        )

        // Word level override
        let wordStyle = LyricEmbellishmentDirector.embellishment(
            forWord: "обычное_слово", // neutral word
            lineIndex: 0,
            wordIndex: 1,
            lineText: "some line",
            aiScore: aiScore
        )
        XCTAssertEqual(wordStyle, .neon)

        // Line level override
        let lineStyle = LyricEmbellishmentDirector.embellishment(
            forLine: "ordinary line",
            lineIndex: 1,
            isSecondary: false,
            aiScore: aiScore
        )
        XCTAssertEqual(lineStyle, .blaze)
    }
    
    // MARK: - Line Level Embellishment Tests
    
    func testLineEmbellishmentSecondaryVoiceForcesWhisper() {
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forLine: "FIRE!", isSecondary: true), .whisper)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forLine: "normal line", isSecondary: true), .whisper)
    }
    
    func testLineEmbellishmentPunctuationAndKeywords() {
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forLine: "今すぐ跳べ！"), .impact)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forLine: "あなたはどこ？"), .floating)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forLine: "夜空に光る星"), .shimmer)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forLine: "8bit retro system code"), .digital)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forLine: "そっと息を潜めて"), .whisper)
        XCTAssertEqual(LyricEmbellishmentDirector.embellishment(forLine: "今日のご飯は何かな"), .none)
    }
}
