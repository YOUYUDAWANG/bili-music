import XCTest
@testable import BiliMusic

final class LyricMotionDirectorTests: XCTestCase {
    func testCueIsDeterministicAcrossRepeatedCalls() {
        let first = cue("Electric night begins", duration: 3.4, lineIndex: 2)
        let second = cue("Electric night begins", duration: 3.4, lineIndex: 2)
        XCTAssertEqual(first, second)
    }

    func testStrongShortLineUsesImpact() {
        XCTAssertEqual(cue("Run!", duration: 1.4).effect, .impact)
        XCTAssertEqual(cue("走！", duration: 2.4).effect, .impact)
    }

    func testQuestionUsesDriftBeforeShortLineRule() {
        XCTAssertEqual(cue("Why?", duration: 1.5).effect, .drift)
        XCTAssertEqual(cue("为什么？", duration: 2.8).effect, .drift)
    }

    func testLongOrLingeringLineUsesBreathe() {
        XCTAssertEqual(cue("Hold on to this quiet moment", duration: 5.2).effect, .breathe)
        XCTAssertEqual(cue("まだここにいる…", duration: 3.2).effect, .breathe)
    }

    func testRepeatedPhraseUsesEcho() {
        XCTAssertEqual(cue("again again", duration: 3).effect, .echo)
        XCTAssertEqual(cue("好き好き", duration: 3).effect, .echo)
    }

    func testReduceMotionPreservesLayoutCueButMarksAnimationForDowngrade() {
        let normal = cue("Where are you?", duration: 3, reduceMotion: false)
        let reduced = cue("Where are you?", duration: 3, reduceMotion: true)
        XCTAssertEqual(normal.effect, reduced.effect)
        XCTAssertFalse(normal.reduceMotion)
        XCTAssertTrue(reduced.reduceMotion)
    }

    func testInvalidDurationIsClamped() {
        XCTAssertEqual(cue("ordinary lyric line", duration: .infinity).duration, 2.8)
        XCTAssertEqual(cue("ordinary lyric line", duration: -4).duration, 1.2)
    }

    func testExpandedEffectsProduceBoundedDistinctCues() {
        let effects: [LyricMotionEffect] = [.focus, .drop, .stretch, .cascade]
        XCTAssertEqual(LyricMotionEffect.allCases.count, 9)
        for effect in effects {
            let directed = LyricMotionDirector.cue(
                effect: effect,
                direction: -1,
                lineDuration: 3,
                reduceMotion: false
            )
            XCTAssertEqual(directed.effect, effect)
            XCTAssertTrue((24...29).contains(directed.fontSize))
            XCTAssertEqual(directed.direction, -1)
        }
    }

    func testStagePrototypeTimelineLoopsAcrossFourScenes() {
        XCTAssertEqual(LyricStagePrototypeTimeline.scene(at: 0.2), .assemble)
        XCTAssertEqual(LyricStagePrototypeTimeline.scene(at: 4.7), .gravity)
        XCTAssertEqual(LyricStagePrototypeTimeline.scene(at: 9.2), .duet)
        XCTAssertEqual(LyricStagePrototypeTimeline.scene(at: 13.8), .canvas)
        XCTAssertEqual(LyricStagePrototypeTimeline.scene(at: 18.2), .assemble)
        XCTAssertEqual(LyricStagePrototypeTimeline.loopTime(elapsed: 37), 1, accuracy: 0.001)
    }

    func testYouAizuGoldenTimelineCoversTheFullSong() {
        XCTAssertEqual(YouAizuGoldenTimeline.endTime - YouAizuGoldenTimeline.startTime, 176.518, accuracy: 0.001)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 8), .instrumentalIntro)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 18), .wakingSignal)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 31), .tuningPulse)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 38), .stepAndBreathe)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 44), .doubleBlink)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 50), .promiseWave)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 55), .twoVoicesConverge)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 58), .hookOne)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 61), .hookTwo)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 64), .hookThree)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 66), .hookFinale)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 70), .forwardDrive)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 86), .conductingBreak)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 100), .sundayArc)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 130), .reprise)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 156), .finalSignal)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 170), .instrumentalOutro)
        XCTAssertEqual(YouAizuGoldenTimeline.movement(at: 180), .outside)
    }

    func testYouAizuAudioMapDrivesBeatOnsetAndEnergyIndependently() {
        XCTAssertEqual(YouAizuAudioPerformanceMap.bpm, 178.206, accuracy: 0.001)
        XCTAssertGreaterThan(YouAizuAudioPerformanceMap.beatPulse(at: 0.2438), 0.99)
        XCTAssertLessThan(YouAizuAudioPerformanceMap.beatPulse(at: 0.41), 0.2)
        XCTAssertGreaterThan(YouAizuAudioPerformanceMap.onsetPulse(at: 38.16), 0.90)
        XCTAssertEqual(YouAizuAudioPerformanceMap.accentTrigger(near: 57.711), 57.711, accuracy: 0.001)
        XCTAssertEqual(YouAizuAudioPerformanceMap.accentTrigger(near: 58.743), 58.8277, accuracy: 0.001)
        XCTAssertGreaterThan(YouAizuAudioPerformanceMap.landingPulse(at: 58.84, lyricTime: 58.743), 0.80)
        XCTAssertGreaterThanOrEqual(YouAizuAudioPerformanceMap.energy(at: 50), 0)
        XCTAssertLessThanOrEqual(YouAizuAudioPerformanceMap.energy(at: 50), 1)
        XCTAssertGreaterThanOrEqual(YouAizuAudioPerformanceMap.energy(at: 150), 0)
        XCTAssertLessThanOrEqual(YouAizuAudioPerformanceMap.energy(at: 150), 1)
        XCTAssertEqual(YouAizuAudioPerformanceMap.energy(at: 180), 0)
    }

    func testV53GenericPlanEvolvesRepeatedHookWithoutTrackIdentity() {
        let lines = [
            PlayerEngine.LyricLine(from: 1, to: 3, text: "静かな始まり"),
            PlayerEngine.LyricLine(from: 3, to: 5, text: "You & 合図"),
            PlayerEngine.LyricLine(from: 5, to: 7, text: "You＆合図"),
            PlayerEngine.LyricLine(from: 7, to: 9, text: "YOU&合図"),
            PlayerEngine.LyricLine(from: 9, to: 11, text: "You & 合図"),
        ]

        let plan = LyricStageV53Plan.compile(lines: lines)

        XCTAssertEqual(plan.scene(for: 1)?.composition, .hookCall)
        XCTAssertEqual(plan.scene(for: 2)?.composition, .hookEcho)
        XCTAssertEqual(plan.scene(for: 3)?.composition, .hookConverge)
        XCTAssertEqual(plan.scene(for: 4)?.composition, .hookLock)
        XCTAssertEqual(plan.scene(for: 4)?.repetitionCount, 4)
    }

    func testV53GenericPlanCreatesCompositionContrastAndPreservesEveryLine() {
        let lines = [
            PlayerEngine.LyricLine(from: 2, to: 5, text: "开场是一片安静"),
            PlayerEngine.LyricLine(from: 5, to: 8, text: "从左边开始行走"),
            PlayerEngine.LyricLine(from: 8, to: 11, text: "然后在另一边回答"),
            PlayerEngine.LyricLine(from: 11, to: 12.5, text: "走！"),
            PlayerEngine.LyricLine(from: 15, to: 19, text: "新的段落重新展开"),
        ]

        let plan = LyricStageV53Plan.compile(lines: lines)

        XCTAssertEqual(plan.scenes.count, lines.count)
        XCTAssertEqual(Set(plan.scenes.map(\.lineIndex)), Set(lines.indices))
        XCTAssertGreaterThanOrEqual(Set(plan.scenes.map(\.composition)).count, 4)
        XCTAssertEqual(plan.scene(for: 3)?.composition, .hero)
        XCTAssertTrue(plan.scene(for: 4)?.isSectionStart == true)
    }

    func testStagePrototypeEasingAndSceneOpacityStayBounded() {
        for sample in stride(from: -1.0, through: 2.0, by: 0.05) {
            XCTAssertTrue((0...1).contains(LyricStagePrototypeTimeline.smooth(sample)))
            XCTAssertTrue((0...1.1).contains(LyricStagePrototypeTimeline.bounceOut(sample)))
        }
        XCTAssertEqual(LyricStagePrototypeTimeline.sceneOpacity(0, start: 0, end: 4.5), 0)
        XCTAssertEqual(LyricStagePrototypeTimeline.sceneOpacity(2, start: 0, end: 4.5), 1)
        XCTAssertEqual(
            LyricStagePrototypeTimeline.sceneOpacity(4.5, start: 0, end: 4.5),
            0,
            accuracy: 0.000_001)
    }

    func testStageCompilerCoversEveryLineAndPromotesOverlappingVoices() {
        let group = "duet"
        let lines = [
            PlayerEngine.LyricLine(
                from: 0,
                to: 3,
                text: "你从左边唱",
                voiceRole: .duetA,
                layerID: "a",
                overlapGroup: group),
            PlayerEngine.LyricLine(
                from: 0,
                to: 3,
                text: "我从右边回应",
                voiceRole: .duetB,
                layerID: "b",
                overlapGroup: group),
            PlayerEngine.LyricLine(from: 3, to: 6, text: "一起走向前"),
        ]

        let score = LyricStageCompiler.compile(
            trackID: "fixture",
            lines: lines,
            performanceScore: nil)

        XCTAssertEqual(score?.version, LyricStageScore.currentVersion)
        XCTAssertEqual(score?.scenes.count, lines.count)
        XCTAssertEqual(score?.scene(for: 0)?.behavior, .converge)
        XCTAssertEqual(score?.scene(for: 0)?.paletteRole, .accent)
        XCTAssertEqual(score?.scene(for: 1)?.paletteRole, .warm)
    }

    func testStageGlyphCompilerPreservesAllTextAndRealWordBounds() {
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

        let glyphs = LyricStageCompiler.glyphs(for: line)

        XCTAssertEqual(glyphs.map(\.text).joined(), line.text)
        XCTAssertTrue(glyphs.allSatisfy { $0.to > $0.from })
        XCTAssertTrue(glyphs.allSatisfy(\.hasRealWordTiming))
        XCTAssertEqual(glyphs.first?.from ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(glyphs.last?.to ?? -1, 3, accuracy: 0.001)
    }

    func testQuietBaselineUsesFocusWhenNoDirectiveExists() {
        let lines = [
            PlayerEngine.LyricLine(from: 0, to: 3, text: "安静的主歌"),
            PlayerEngine.LyricLine(from: 3, to: 6, text: "继续安静"),
        ]
        let score = LyricStageCompiler.compile(trackID: "fixture", lines: lines, performanceScore: nil)
        XCTAssertEqual(score?.scene(for: 0)?.behavior, .focus)
        XCTAssertEqual(score?.scene(for: 1)?.behavior, .focus)
        XCTAssertEqual(score?.scene(for: 0)?.intensity, 0.4)
    }

    func testLineOnlyGlyphsDoNotClaimRealWordTiming() {
        let glyphs = LyricStageCompiler.glyphs(for: PlayerEngine.LyricLine(from: 0, to: 4, text: "只有逐行"))
        XCTAssertEqual(glyphs.map(\.text).joined(), "只有逐行")
        XCTAssertTrue(glyphs.allSatisfy { $0.hasRealWordTiming == false })
        XCTAssertTrue(glyphs.allSatisfy { $0.performanceTo > $0.performanceFrom })
    }

    func testStageVisibilityUsesEveryActuallyOverlappingVoiceBeforeDirectorComposition() {
        let lines = [
            PlayerEngine.LyricLine(from: 0, to: 3, text: "A", voiceRole: .duetA, overlapGroup: "duet"),
            PlayerEngine.LyricLine(from: 0, to: 3, text: "B", voiceRole: .duetB, overlapGroup: "duet"),
            PlayerEngine.LyricLine(from: 3, to: 6, text: "next"),
        ]

        XCTAssertEqual(
            LyricStageCompiler.visibleLineIndices(lines: lines, at: 1, performanceScore: nil),
            [0, 1])
    }

    private func cue(
        _ text: String,
        duration: Double,
        lineIndex: Int = 0,
        reduceMotion: Bool = false
    ) -> LyricMotionCue {
        LyricMotionDirector.cue(
            text: text,
            lineDuration: duration,
            trackID: "fixture-track",
            lineIndex: lineIndex,
            reduceMotion: reduceMotion
        )
    }
}
