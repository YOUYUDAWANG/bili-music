import XCTest
@testable import BiliMusic

final class LyricStagePlanV4Tests: XCTestCase {
    func testSceneValidatorRepairsCompatibleFieldsAndDropsOnlyInvalidFamilies() throws {
        let lines = makeV4FixtureLines(count: 12)
        let score = makeV4FixtureScore(lines: lines)
        let track = Track(
            bvid: "BVV4PLAN",
            cid: 1,
            title: "Plan",
            artist: "Fixture",
            coverURL: nil,
            duration: 760)
        let rail = LyricStageSceneRecipeV4(
            lineIndex: 1,
            family: .railHandoff,
            topology: .contour,
            entrance: .aperture,
            focus: .tokenRange,
            tokenRange: LyricStageTokenRangeV4(startTokenIndex: 0, endTokenIndex: 0),
            sustain: .echo,
            continuity: .clear,
            driver: .structuralMoment,
            landmarkIDs: [],
            companionLineIndices: [2, 99],
            motifPhase: .develop,
            intensity: 2)
        let invalidLens = LyricStageSceneRecipeV4(
            lineIndex: 2,
            family: .semanticLens,
            topology: .anchor,
            entrance: .settle,
            focus: .wholeLine,
            tokenRange: nil,
            sustain: .sweep,
            continuity: .clear,
            driver: .wordReveal,
            landmarkIDs: [],
            companionLineIndices: [],
            motifPhase: .develop,
            intensity: 0.7)
        let chorus = LyricStageSceneRecipeV4(
            lineIndex: 5,
            family: .chorusMemory,
            topology: .stack,
            entrance: .gather,
            focus: .wholeLine,
            tokenRange: nil,
            sustain: .echo,
            continuity: .accumulate,
            driver: .structuralMoment,
            landmarkIDs: [],
            companionLineIndices: [],
            motifPhase: .transform,
            intensity: 0.9)
        let direction = makeV4Direction(
            track: track,
            lines: lines,
            score: score,
            scenes: [rail, invalidLens, chorus])

        let safe = try XCTUnwrap(LyricStageDirectorV4.validated(
            direction,
            trackID: track.key.description,
            lyricsHash: LyricPerformanceFingerprint.lyricsHash(lines),
            lines: lines,
            audioScore: score))

        XCTAssertEqual(safe.scenes.map(\.lineIndex), [1, 5])
        let repairedRail = try XCTUnwrap(safe.scenes.first)
        XCTAssertEqual(repairedRail.topology, .relay)
        XCTAssertEqual(repairedRail.entrance, .slide)
        XCTAssertEqual(repairedRail.focus, .wholeLine)
        XCTAssertNil(repairedRail.tokenRange)
        XCTAssertEqual(repairedRail.sustain, .railTravel)
        XCTAssertEqual(repairedRail.continuity, .handoff)
        XCTAssertEqual(repairedRail.driver, .lyricReveal)
        XCTAssertEqual(repairedRail.companionLineIndices, [2])
        XCTAssertEqual(safe.scenes.last?.family, .chorusMemory)
        XCTAssertEqual(safe.scenes.last?.driver, .lyricReveal)
        XCTAssertFalse(safe.scenes.last?.companionLineIndices.isEmpty ?? true)
    }

    func testSilenceApertureRequiresSameLineStructuralLandmark() throws {
        let lines = makeV4FixtureLines(count: 20)
        let score = makeV4FixtureScore(lines: lines)
        let track = Track(
            bvid: "BVV4SILENCE",
            cid: 2,
            title: "Silence",
            artist: "Fixture",
            coverURL: nil,
            duration: 760)
        let moment = try XCTUnwrap(score.moments.first {
            ($0.kind == .sectionStart || $0.kind == .silenceExit) && $0.lineIndex != nil
        })
        let wrongLine = (try XCTUnwrap(moment.lineIndex) + 1) % lines.count
        let recipe = LyricStageSceneRecipeV4(
            lineIndex: wrongLine,
            family: .silenceAperture,
            topology: .split,
            entrance: .aperture,
            focus: .wholeLine,
            tokenRange: nil,
            sustain: .none,
            continuity: .clear,
            driver: .structuralMoment,
            landmarkIDs: [moment.id],
            companionLineIndices: [],
            motifPhase: .introduce,
            intensity: 0.6)
        let fallback = makeV4RailRecipe(lineIndex: 0)
        let secondFallback = makeV4RailRecipe(lineIndex: 1)
        let direction = makeV4Direction(
            track: track,
            lines: lines,
            score: score,
            scenes: [recipe, fallback, secondFallback])

        let safe = try XCTUnwrap(LyricStageDirectorV4.validated(
            direction,
            trackID: track.key.description,
            lyricsHash: LyricPerformanceFingerprint.lyricsHash(lines),
            lines: lines,
            audioScore: score))

        XCTAssertEqual(safe.scenes.map(\.lineIndex), [0, 1])
    }

    func testSemanticLensWordRevealRequiresTimingAcrossEveryVisibleFocusedToken() throws {
        let line = PlayerEngine.LyricLine(
            from: 0,
            to: 3,
            text: "hello !",
            words: [.init(from: 0, to: 2, text: "hello")])
        let lines = [line]
        let score = makeV4FixtureScore(lines: lines)
        let track = Track(
            bvid: "BVV4FOCUS",
            cid: 7,
            title: "Focus",
            artist: "Fixture",
            coverURL: nil,
            duration: 760)
        let recipe = LyricStageSceneRecipeV4(
            lineIndex: 0,
            family: .semanticLens,
            topology: .anchor,
            entrance: .settle,
            focus: .tokenRange,
            tokenRange: LyricStageTokenRangeV4(startTokenIndex: 0, endTokenIndex: 2),
            sustain: .sweep,
            continuity: .clear,
            driver: .wordReveal,
            landmarkIDs: [],
            companionLineIndices: [],
            motifPhase: .develop,
            intensity: 0.7)
        let direction = makeV4Direction(
            track: track,
            lines: lines,
            score: score,
            scenes: [recipe])

        let safe = try XCTUnwrap(LyricStageDirectorV4.validated(
            direction,
            trackID: track.key.description,
            lyricsHash: LyricPerformanceFingerprint.lyricsHash(lines),
            lines: lines,
            audioScore: score))

        XCTAssertEqual(safe.scenes.first?.focus, .tokenRange)
        XCTAssertEqual(safe.scenes.first?.driver, .lyricReveal)
    }

    func testNilOrWrongVersionDirectionKeepsCompleteLocalV53FallbackAndTiming() {
        let lines = makeV4FixtureLines(count: 14)
        let snapshot = lines
        let map = makeV4FixtureMap()
        let score = AudioStructureScoreBuilderV4.make(map: map, lines: lines)

        let plan = LyricStageDirectorV4.resolve(
            trackID: "BVV4FALLBACK#3",
            lines: lines,
            audioMap: map,
            audioScore: score,
            direction: nil)

        XCTAssertEqual(plan.source, .local)
        XCTAssertTrue(plan.recipes.isEmpty)
        XCTAssertEqual(plan.basePlan.scenes.count, lines.count)
        XCTAssertEqual(plan.basePlan.lyricsHash, LyricPerformanceFingerprint.lyricsHash(lines))
        XCTAssertEqual(lines, snapshot)
    }

    func testRecipeDictionaryKeepsFirstDuplicateWithoutTrap() {
        let lines = makeV4FixtureLines(count: 4)
        let map = makeV4FixtureMap()
        let score = AudioStructureScoreBuilderV4.make(map: map, lines: lines)
        let local = LyricStageDirectorV4.localPlan(
            trackID: "BVV4DUPLICATE#4",
            lines: lines,
            audioMap: map,
            audioScore: score)
        let first = makeV4RailRecipe(lineIndex: 1, intensity: 0.4)
        let second = makeV4RailRecipe(lineIndex: 1, intensity: 0.9)
        let plan = LyricStagePlanV4(
            version: local.version,
            grammarVersion: local.grammarVersion,
            compilerVersion: local.compilerVersion,
            directorVersion: local.directorVersion,
            trackID: local.trackID,
            lyricsHash: local.lyricsHash,
            audioScoreHash: local.audioScoreHash,
            basePlan: local.basePlan,
            audioScore: local.audioScore,
            stageBible: local.stageBible,
            recipes: [first, second],
            landmarkByID: local.landmarkByID,
            source: .gemini,
            partial: true)

        XCTAssertEqual(plan.recipeByLineIndex.count, 1)
        XCTAssertEqual(plan.recipeByLineIndex[1]?.intensity, 0.4)
    }
}
