import XCTest
@testable import BiliMusic

/// MusicFilter 纯函数覆盖:时长边界值 + 短词词边界匹配的正反例。
final class MusicFilterTests: XCTestCase {
    /// 明确命中音乐提示词("周杰伦"是中文提示词,子串匹配)的标题。
    private let musicTitle = "周杰伦 晴天 官方现场"
    private let musicArtist = "周杰伦"

    // MARK: - isMusic 时长边界(60...720)

    func testIsMusicDurationBoundaries() {
        XCTAssertFalse(MusicFilter.isMusic(title: musicTitle, artist: musicArtist, duration: 59))
        XCTAssertTrue(MusicFilter.isMusic(title: musicTitle, artist: musicArtist, duration: 60))
        XCTAssertTrue(MusicFilter.isMusic(title: musicTitle, artist: musicArtist, duration: 720))
        XCTAssertFalse(MusicFilter.isMusic(title: musicTitle, artist: musicArtist, duration: 721))
    }

    // MARK: - isStrictMusic 时长边界(75...540)

    func testIsStrictMusicDurationBoundaries() {
        XCTAssertFalse(MusicFilter.isStrictMusic(title: musicTitle, artist: musicArtist, duration: 74))
        XCTAssertTrue(MusicFilter.isStrictMusic(title: musicTitle, artist: musicArtist, duration: 75))
        XCTAssertTrue(MusicFilter.isStrictMusic(title: musicTitle, artist: musicArtist, duration: 540))
        XCTAssertFalse(MusicFilter.isStrictMusic(title: musicTitle, artist: musicArtist, duration: 541))
    }

    func testTrackOverloadsAgreeWithUnderlyingImplementation() {
        let track = Track(
            typeID: nil,
            bvid: "BVFILTER001",
            title: musicTitle,
            artist: musicArtist,
            coverURL: nil,
            duration: 240)
        XCTAssertTrue(MusicFilter.isMusic(track))
        XCTAssertTrue(MusicFilter.isStrictMusic(track))
    }

    // MARK: - 短 ASCII 提示词的词边界匹配

    func testShortASCIIHintsMatchOnWordBoundaries() {
        // "Official MV" 中 "mv" 独立成词 → 命中。
        XCTAssertTrue(MusicFilter.isMusic(title: "Jay Chou Sunny Day Official MV", artist: "UP", duration: 260))
        // 中英相邻时英文段仍独立成词:"陈奕迅mv合集" 的 "mv" 命中。
        XCTAssertTrue(MusicFilter.isMusic(title: "陈奕迅mv合集", artist: "UP", duration: 300))
    }

    func testShortASCIIHintsDoNotMatchInsideLongerWords() {
        // "explained" 不再命中 "ed"。
        XCTAssertFalse(MusicFilter.isMusic(title: "Quantum physics explained", artist: "Science UP", duration: 300))
        // "livehouse" 连写不命中 "live"。
        XCTAssertFalse(MusicFilter.isMusic(title: "livehouse空间介绍", artist: "探店UP", duration: 300))
        // "amv" 连写不命中 "mv"。
        XCTAssertFalse(MusicFilter.isMusic(title: "初音未来amv", artist: "UP", duration: 300))
        // "using" 不命中 "sing"。
        XCTAssertFalse(MusicFilter.isMusic(title: "Using Xcode instruments", artist: "Dev UP", duration: 300))
    }

    func testLongHintsAndCJKHintsKeepSubstringMatching() {
        // ≥5 字符英文提示词仍是子串匹配。
        XCTAssertTrue(MusicFilter.isMusic(title: "Bedroom Concert2023", artist: "UP", duration: 300))
        // 中文提示词子串匹配:"纯音乐" 内含 "音乐"。
        XCTAssertTrue(MusicFilter.isMusic(title: "深夜纯音乐助眠", artist: "UP", duration: 300))
    }

    func testNonMusicHintsStillVetoBySubstring() {
        // nonMusicHints 保持子串匹配:"游戏实况" 一票否决(无强音乐信号)。
        XCTAssertFalse(MusicFilter.isMusic(title: "三国杀游戏实况", artist: "游戏UP", duration: 300))
        XCTAssertFalse(MusicFilter.isStrictMusic(title: "晴天 教学解析", artist: "UP", duration: 300))
    }

    func testStrictMusicRejectsNonMusicHintEvenWithMusicSignal() {
        // 严格判定:命中非音乐词直接否决,即使同时带音乐信号。
        XCTAssertFalse(MusicFilter.isStrictMusic(title: "周杰伦 晴天 吉他教学", artist: "UP", duration: 300))
        // 宽松判定:强音乐信号可以豁免非音乐词。
        XCTAssertTrue(MusicFilter.isMusic(title: "周杰伦 晴天 吉他教学", artist: "UP", duration: 300))
    }

    func testSongTitleShapedNamesPassWithoutExplicitHints() {
        XCTAssertTrue(MusicFilter.isMusic(title: "Aimer - Ref:rain", artist: "搬运UP", duration: 260))
        XCTAssertTrue(MusicFilter.isStrictMusic(title: "《起风了》完整版", artist: "搬运UP", duration: 260))
    }
}
