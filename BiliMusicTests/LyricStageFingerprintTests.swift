import XCTest
@testable import BiliMusic

final class LyricStageFingerprintTests: XCTestCase {
    func testScoreFingerprintIgnoresSceneCountAlone() {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 2, text: "hello world")]
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let appear = makeScore(hash: hash, verb: .appear, hero: false)
        let pulse = makeScore(hash: hash, verb: .pulse, hero: true)
        XCTAssertEqual(appear.scenes.count, pulse.scenes.count)
        XCTAssertNotEqual(LyricStageFingerprint.score(appear), LyricStageFingerprint.score(pulse))
    }

    func testPerformanceFingerprintChangesWithWordCues() {
        let lines = [
            PlayerEngine.LyricLine(
                from: 0,
                to: 2,
                text: "hello",
                words: [.init(from: 0, to: 2, text: "hello")]),
        ]
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let empty = LyricPerformanceScore(
            version: LyricPerformanceScore.currentVersion,
            directorVersion: "test",
            trackID: "fixture",
            lyricsHash: hash,
            lineCount: 1,
            mood: "a",
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
            ])
        let cued = LyricPerformanceScore(
            version: empty.version,
            directorVersion: empty.directorVersion,
            trackID: empty.trackID,
            lyricsHash: hash,
            lineCount: 1,
            mood: empty.mood,
            compositions: empty.compositions,
            scenes: empty.scenes,
            wordCues: [
                LyricWordCue(
                    lineIndex: 0,
                    startWordIndex: 0,
                    endWordIndex: 0,
                    effect: .impact,
                    intensity: 1,
                    direction: 1),
            ])
        XCTAssertNotEqual(LyricStageFingerprint.performance(empty), LyricStageFingerprint.performance(cued))
    }

    func testPaletteFingerprintUsesActualCoverColors() {
        XCTAssertNotEqual(
            LyricStageFingerprint.palette(.fallback),
            LyricStageFingerprint.palette(
                PlayerArtworkPalette(
                    top: UIColor.red,
                    middle: UIColor.blue,
                    bottom: UIColor.black)))
        XCTAssertEqual(
            LyricStageFingerprint.palette(.fallback),
            LyricStageFingerprint.palette(.fallback))
    }

    func testCacheKeyIncludesScorePerformanceAndPalette() {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 2, text: "hello")]
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let first = makeScore(hash: hash, verb: .appear, hero: false)
        let a = LyricStageFingerprint.cacheKey(
            trackID: "fixture",
            lyricsHash: hash,
            score: first,
            performanceScore: nil,
            palette: .fallback,
            canvasSize: CGSize(width: 340, height: 280),
            dynamicTypeScale: 1,
            reduceMotion: false)
        let b = LyricStageFingerprint.cacheKey(
            trackID: "fixture",
            lyricsHash: hash,
            score: makeScore(hash: hash, verb: .assemble, hero: true),
            performanceScore: nil,
            palette: .fallback,
            canvasSize: CGSize(width: 340, height: 280),
            dynamicTypeScale: 1,
            reduceMotion: false)
        let c = LyricStageFingerprint.cacheKey(
            trackID: "fixture",
            lyricsHash: hash,
            score: first,
            performanceScore: nil,
            palette: PlayerArtworkPalette(top: .red, middle: .blue, bottom: .black),
            canvasSize: CGSize(width: 340, height: 280),
            dynamicTypeScale: 1,
            reduceMotion: false)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    private func makeScore(hash: String, verb: StageVerb, hero: Bool) -> LyricStageScoreV2 {
        var actors = [
            StageActor(
                id: "base",
                target: .line(lineIndex: 0),
                role: .base,
                anchor: .center,
                typeRole: .normal,
                paletteRole: .primary),
        ]
        var events = [
            StageEvent(
                actorID: "base",
                phase: .entrance,
                verb: verb == .pulse ? .appear : verb,
                start: 0,
                duration: 0.3,
                intensity: 0.5,
                reason: .structuralTransition),
        ]
        if hero {
            actors.append(
                StageActor(
                    id: "hero",
                    target: .glyphs(lineIndex: 0, glyphFrom: 0, glyphTo: 0),
                    role: .protagonist,
                    anchor: .center,
                    typeRole: .hero,
                    paletteRole: .accent))
            events.append(
                StageEvent(
                    actorID: "hero",
                    phase: .performance,
                    verb: .pulse,
                    start: 0.4,
                    duration: 0.2,
                    intensity: 1,
                    reason: .actionWord))
        }
        return LyricStageScoreV2(
            trackID: "fixture",
            lyricsHash: hash,
            styleSheet: StageStyleSheet(
                concept: "fp",
                paletteStrategy: .coverAnalogous,
                typeSystem: .iPhone17Pro,
                motifs: []),
            sections: [],
            scenes: [
                StageScene(
                    id: "s0",
                    lineIndices: [0],
                    composition: .singleAnchor,
                    actors: actors,
                    events: events,
                    handoffOut: .dissolve),
            ])
    }
}
