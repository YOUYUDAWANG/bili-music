import XCTest
@testable import BiliMusic

final class LyricPerformanceScoreTests: XCTestCase {
    func testFingerprintIsStableAndChangesWithTimingOrText() {
        let original = lines()
        XCTAssertEqual(
            LyricPerformanceFingerprint.lyricsHash(original),
            LyricPerformanceFingerprint.lyricsHash(original)
        )
        let changed = [
            PlayerEngine.LyricLine(from: 0, to: 3.5, text: "first line"),
            PlayerEngine.LyricLine(from: 3.5, to: 8, text: "changed line"),
        ]
        XCTAssertNotEqual(
            LyricPerformanceFingerprint.lyricsHash(original),
            LyricPerformanceFingerprint.lyricsHash(changed)
        )
    }

    func testValidationClampsScenesAndDropsDuplicatesAndOutOfRangeLines() {
        let track = fixtureTrack()
        let lyrics = lines()
        let hash = LyricPerformanceFingerprint.lyricsHash(lyrics)
        let score = LyricPerformanceScore(
            version: LyricPerformanceScore.currentVersion,
            directorVersion: "luna-test-v1",
            trackID: track.key.description,
            lyricsHash: hash,
            lineCount: lyrics.count,
            mood: "dramatic",
            compositions: [
                composition(lineIndex: 0, textLineIndices: [1, 0, 1, 99]),
                composition(lineIndex: 1, textLineIndices: [0, 1]),
                composition(lineIndex: 1, textLineIndices: [1]),
            ],
            scenes: [
                scene(lineIndex: 0, effect: .impact, intensity: 9, fontScale: 4, trackingScale: 0),
                scene(lineIndex: 0, effect: .echo),
                scene(lineIndex: 99, effect: .rise),
            ]
        )

        let safe = score.validated(trackID: track.key.description, lyricsHash: hash, lineCount: lyrics.count)
        XCTAssertEqual(safe?.scenes.count, 1)
        XCTAssertEqual(safe?.scenes[0].intensity, 1.25)
        XCTAssertEqual(safe?.scenes[0].fontScale, 1.18)
        XCTAssertEqual(safe?.scenes[0].trackingScale, 0.5)
        XCTAssertEqual(safe?.compositions.map(\.textLineIndices), [[1, 0], [0, 1]])
        XCTAssertEqual(safe?.textLineIndices(for: 0), [1, 0])
    }

    func testValidationRequiresDirectorCompositionForEverySubmittedLine() {
        let lyrics = lines()
        let score = LyricPerformanceScore(
            version: LyricPerformanceScore.currentVersion,
            directorVersion: "luna-test-v2",
            trackID: "fixture",
            lyricsHash: "hash",
            lineCount: lyrics.count,
            mood: "sparse",
            compositions: [composition(lineIndex: 0, textLineIndices: [0])],
            scenes: []
        )

        XCTAssertNil(score.validated(trackID: "fixture", lyricsHash: "hash", lineCount: lyrics.count))
    }

    func testCascadeRequiresAMultilineComposition() {
        let lyrics = lines()
        let score = LyricPerformanceScore(
            version: LyricPerformanceScore.currentVersion,
            directorVersion: "luna-test-v3",
            trackID: "fixture",
            lyricsHash: "hash",
            lineCount: lyrics.count,
            mood: "layered",
            compositions: [
                composition(lineIndex: 0, textLineIndices: [0]),
                composition(lineIndex: 1, textLineIndices: [0, 1]),
            ],
            scenes: [
                scene(lineIndex: 0, effect: .cascade),
                scene(lineIndex: 1, effect: .cascade),
            ]
        )

        let safe = score.validated(trackID: "fixture", lyricsHash: "hash", lineCount: lyrics.count)
        XCTAssertEqual(safe?.scenes.map(\.lineIndex), [1])
    }

    func testDirectedCueOverridesOnlyScoredLinesAndKeepsLocalFallback() {
        let fallback = LyricMotionDirector.cue(
            text: "ordinary lyric line",
            lineDuration: 3,
            trackID: "fixture",
            lineIndex: 0,
            reduceMotion: false
        )
        let score = LyricPerformanceScore(
            version: LyricPerformanceScore.currentVersion,
            directorVersion: "luna-test-v1",
            trackID: "fixture",
            lyricsHash: "a",
            lineCount: 1,
            mood: "searching",
            compositions: [composition(lineIndex: 0, textLineIndices: [0])],
            scenes: [scene(lineIndex: 0, effect: .drift, alignment: .leading, direction: -1, intensity: 0.8)]
        )

        let directed = score.cue(for: 0, fallback: fallback)
        XCTAssertEqual(directed.effect, .drift)
        XCTAssertEqual(directed.alignment, .leading)
        XCTAssertEqual(directed.direction, -1)
        XCTAssertEqual(directed.intensity, 0.8)
        XCTAssertEqual(score.cue(for: 1, fallback: fallback), fallback)
    }

    func testWordCueRequiresRealWordTimingAndClampsItsRangeParameters() {
        let line = PlayerEngine.LyricLine(
            from: 0,
            to: 3,
            text: "まだ歌える",
            words: [
                PlayerEngine.LyricWord(from: 0, to: 0.5, text: "ま"),
                PlayerEngine.LyricWord(from: 0.5, to: 1, text: "だ"),
                PlayerEngine.LyricWord(from: 1, to: 1.5, text: "歌"),
                PlayerEngine.LyricWord(from: 1.5, to: 2, text: "え"),
                PlayerEngine.LyricWord(from: 2, to: 2.5, text: "る"),
            ])
        let lines = [line]
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let score = LyricPerformanceScore(
            version: LyricPerformanceScore.currentVersion,
            directorVersion: "luna-word-v1",
            trackID: "fixture",
            lyricsHash: hash,
            lineCount: 1,
            mood: "rising",
            compositions: [composition(lineIndex: 0, textLineIndices: [0])],
            scenes: [],
            wordCues: [LyricWordCue(
                lineIndex: 0,
                startWordIndex: 2,
                endWordIndex: 4,
                effect: .stretch,
                intensity: 9,
                direction: -4)])

        let safe = score.validated(
            trackID: "fixture",
            lyricsHash: hash,
            lineCount: 1,
            wordCounts: LyricPerformanceFingerprint.wordCounts(lines))
        XCTAssertEqual(safe?.wordCue(for: 0), LyricWordCue(
            lineIndex: 0,
            startWordIndex: 2,
            endWordIndex: 4,
            effect: .stretch,
            intensity: 1.25,
            direction: -1))
    }

    func testFingerprintChangesWhenOnlyWordTimingChanges() {
        let first = [PlayerEngine.LyricLine(
            from: 0,
            to: 2,
            text: "歌",
            words: [PlayerEngine.LyricWord(from: 0.2, to: 0.8, text: "歌")])]
        let second = [PlayerEngine.LyricLine(
            from: 0,
            to: 2,
            text: "歌",
            words: [PlayerEngine.LyricWord(from: 0.4, to: 1, text: "歌")])]
        XCTAssertNotEqual(
            LyricPerformanceFingerprint.lyricsHash(first),
            LyricPerformanceFingerprint.lyricsHash(second))
    }

    func testFingerprintChangesWhenOnlyVocalLayerChanges() {
        let lead = [PlayerEngine.LyricLine(from: 0, to: 2, text: "same")]
        let backing = [PlayerEngine.LyricLine(
            from: 0,
            to: 2,
            text: "same",
            voiceRole: .backing,
            layerID: "backing",
            overlapGroup: "chorus")]

        XCTAssertNotEqual(
            LyricPerformanceFingerprint.lyricsHash(lead),
            LyricPerformanceFingerprint.lyricsHash(backing))
    }

    func testStageBibleAndDirectivesAreValidatedAndAvailableToCompiler() {
        let lyrics = lines()
        let score = LyricPerformanceScore(
            version: LyricPerformanceScore.currentVersion,
            directorVersion: "luna-stage-v5",
            trackID: "fixture",
            lyricsHash: "hash",
            lineCount: lyrics.count,
            mood: "kinetic",
            compositions: [
                composition(lineIndex: 0, textLineIndices: [0]),
                composition(lineIndex: 1, textLineIndices: [1]),
            ],
            scenes: [],
            stageBible: LyricStageBible(
                concept: " falling type ",
                motif: "gather and release",
                intensityArc: "quiet to loud"),
            stageDirectives: [
                LyricStageDirective(
                    lineIndex: 0,
                    behavior: .gravityDrop,
                    alignment: .center,
                    direction: -4,
                    intensity: 9,
                    fontScale: 4,
                    glyphStagger: 1,
                    paletteRole: .warm),
                LyricStageDirective(
                    lineIndex: 99,
                    behavior: .echo,
                    alignment: nil,
                    direction: 1,
                    intensity: 1,
                    fontScale: 1,
                    glyphStagger: 0.04,
                    paletteRole: nil),
            ])

        let safe = score.validated(trackID: "fixture", lyricsHash: "hash", lineCount: lyrics.count)

        XCTAssertEqual(safe?.stageBible?.concept, "falling type")
        XCTAssertEqual(safe?.stageDirectives.count, 1)
        XCTAssertEqual(safe?.stageDirective(for: 0)?.direction, -1)
        XCTAssertEqual(safe?.stageDirective(for: 0)?.intensity, 1.25)
        XCTAssertEqual(safe?.stageDirective(for: 0)?.fontScale, 1.22)
        XCTAssertEqual(safe?.stageDirective(for: 0)?.glyphStagger, 0.14)
    }

    @MainActor
    func testStorePersistsValidatedScoreAndRejectsChangedLyrics() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricPerformanceScoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("scores.json")
        let track = fixtureTrack()
        let lyrics = lines()
        let hash = LyricPerformanceFingerprint.lyricsHash(lyrics)
        let score = LyricPerformanceScore(
            version: LyricPerformanceScore.currentVersion,
            directorVersion: "luna-test-v1",
            trackID: track.key.description,
            lyricsHash: hash,
            lineCount: lyrics.count,
            mood: "calm",
            compositions: [
                composition(lineIndex: 0, textLineIndices: [0]),
                composition(lineIndex: 1, textLineIndices: [0, 1]),
            ],
            scenes: [scene(lineIndex: 1, effect: .breathe)]
        )

        let writer = LyricPerformanceStore(fileURLForTesting: url)
        let didSave = await writer.save(score, for: track, lines: lyrics)
        XCTAssertTrue(didSave)
        let reader = LyricPerformanceStore(fileURLForTesting: url)
        let loaded = await reader.score(for: track, lines: lyrics)
        XCTAssertEqual(loaded, score)

        let changed = [PlayerEngine.LyricLine(from: 0, to: 4, text: "different")]
        let changedScore = await reader.score(for: track, lines: changed)
        XCTAssertNil(changedScore)
    }

    private func fixtureTrack() -> Track {
        Track(bvid: "BVPERFORMANCE", cid: 42, title: "Fixture", artist: "Artist", coverURL: nil, duration: 120)
    }

    private func lines() -> [PlayerEngine.LyricLine] {
        [
            PlayerEngine.LyricLine(from: 0, to: 3.5, text: "first line"),
            PlayerEngine.LyricLine(from: 3.5, to: 8, text: "second line"),
        ]
    }

    private func scene(
        lineIndex: Int,
        effect: LyricMotionEffect,
        alignment: LyricMotionAlignment? = nil,
        direction: Int = 1,
        intensity: Double = 1,
        fontScale: Double = 1,
        trackingScale: Double = 1
    ) -> LyricPerformanceScene {
        LyricPerformanceScene(
            lineIndex: lineIndex,
            effect: effect,
            alignment: alignment,
            direction: direction,
            intensity: intensity,
            fontScale: fontScale,
            trackingScale: trackingScale
        )
    }

    private func composition(lineIndex: Int, textLineIndices: [Int]) -> LyricTextComposition {
        LyricTextComposition(lineIndex: lineIndex, textLineIndices: textLineIndices)
    }
}
