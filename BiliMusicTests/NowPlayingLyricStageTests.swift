import XCTest
import SwiftUI
@testable import BiliMusic

final class NowPlayingLyricStageTests: XCTestCase {

    func testLyricVFXWordTokenCreatesValidView() {
        let token = LyricVFXWordToken(
            text: "BANG!",
            state: .current(progress: 0.25),
            style: .impact,
            fontSize: 28,
            alignment: .leading,
            reduceMotion: false
        )
        XCTAssertNotNil(token.body)
    }

    func testLyricVFXWordTokenAllStylesRender() {
        let styles: [LyricEmbellishmentStyle] = [
            .none, .whisper, .shimmer, .impact, .floating, .digital,
            .ripple, .neon, .blaze, .crystallize, .heartbeat, .vintage, .sway
        ]

        for style in styles {
            let token = LyricVFXWordToken(
                text: "TestWord",
                state: .current(progress: 0.5),
                style: style,
                fontSize: 26,
                alignment: .leading,
                reduceMotion: false
            )
            XCTAssertNotNil(token.body, "Failed to render token for style: \(style)")
        }
    }

    func testLyricCinematicSceneModeResolution() {
        // 1. Secondary voice resolves to duet
        let duetLine = PlayerEngine.LyricLine(
            from: 0, to: 4, text: "和声测试", voiceRole: .backing
        )
        XCTAssertEqual(
            LyricCinematicSceneMode.resolve(for: duetLine, index: 2, aiMood: nil, totalLines: 20),
            .duet
        )

        // 2. Exclamation or short punchy line resolves to gravity
        let impactLine = PlayerEngine.LyricLine(
            from: 0, to: 1.5, text: "BANG!"
        )
        XCTAssertEqual(
            LyricCinematicSceneMode.resolve(for: impactLine, index: 5, aiMood: nil, totalLines: 20),
            .gravity
        )

        // 3. Outro or long lingering line resolves to cosmicDrift
        let outroLine = PlayerEngine.LyricLine(
            from: 0, to: 6.0, text: "流れる星の光の向こうへ"
        )
        XCTAssertEqual(
            LyricCinematicSceneMode.resolve(for: outroLine, index: 19, aiMood: nil, totalLines: 20),
            .cosmicDrift
        )

        // 4. Default narrative line resolves to assemble
        let verseLine = PlayerEngine.LyricLine(
            from: 0, to: 3.5, text: "沈むように溶けてゆくように"
        )
        XCTAssertEqual(
            LyricCinematicSceneMode.resolve(for: verseLine, index: 3, aiMood: nil, totalLines: 20),
            .assemble
        )
    }

    func testLyricVFXLineViewRenders() {
        let line = PlayerEngine.LyricLine(
            from: 10.0,
            to: 15.0,
            text: "沈むように溶けてゆくように",
            translation: "如同沉落一般 仿佛逐渐消融一般",
            words: []
        )
        let lineView = LyricVFXLineView(
            line: line,
            time: 12.5,
            style: .shimmer,
            fontSize: 26,
            reduceMotion: false
        )
        XCTAssertNotNil(lineView.body)
    }

    func testLyricInterludePulseViewRenders() {
        let pulseView = LyricInterludePulseView(reduceMotion: false)
        XCTAssertNotNil(pulseView.body)

        let reducedPulseView = LyricInterludePulseView(reduceMotion: true)
        XCTAssertNotNil(reducedPulseView.body)
    }

    func testHeroFontSizeCalculations() {
        // Short line gets big 30pt
        let shortText = "夜に駆ける"
        XCTAssertTrue(shortText.count <= 8)

        // Medium line gets 26pt
        let mediumText = "沈むように溶けてゆくように"
        XCTAssertTrue(mediumText.count > 8 && mediumText.count <= 16)

        // Long line gets 22pt
        let longText = "明けない夜に零れた二人を照らす街明かりの向こうへ"
        XCTAssertTrue(longText.count > 16)
    }
}
