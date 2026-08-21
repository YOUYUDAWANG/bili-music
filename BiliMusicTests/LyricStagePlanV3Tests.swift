import XCTest
@testable import BiliMusic

final class LyricStagePlanV3Tests: XCTestCase {
    func testFastSongDetectsRepeatedMultiLineChorusWithoutTrackIdentity() {
        let lines = makeLines([
            "短いイントロ",
            "走り出す信号",
            "君へ届く声",
            "夜を越えてゆく",
            "静かな間奏",
            "走り出す信号！",
            "君へ届く声",
            "夜を越えてゆく",
        ], step: 1.1)

        let plan = LyricStageDirectorV3.localPlan(
            trackID: "fast-fixture",
            lines: lines,
            audioSummary: .empty(duration: 12))

        let chorusScenes = plan.scenes.filter { $0.motifRef?.hasPrefix("chorus-block-") == true }
        XCTAssertGreaterThanOrEqual(chorusScenes.count, 6)
        XCTAssertTrue(plan.sections.contains { $0.kind == .chorus })
        XCTAssertEqual(Set(plan.scenes.map(\.lineIndex)), Set(lines.indices))
    }

    func testSlowSongKeepsCompletePlanAndUsesSilenceAsSectionBoundary() {
        let lines = [
            PlayerEngine.LyricLine(from: 2, to: 5, text: "第一景慢慢展开"),
            PlayerEngine.LyricLine(from: 8, to: 12, text: "留下足够的呼吸"),
            PlayerEngine.LyricLine(from: 15, to: 20, text: "最后安静地收束"),
        ]

        let plan = LyricStageDirectorV3.localPlan(
            trackID: "slow-fixture",
            lines: lines,
            audioSummary: .empty(duration: 22))

        XCTAssertEqual(plan.scenes.count, lines.count)
        XCTAssertTrue(plan.scenes.allSatisfy(\.isSectionStart))
        XCTAssertEqual(plan.sections.first?.lineFrom, 0)
        XCTAssertEqual(plan.sections.last?.lineTo, lines.count - 1)
    }

    func testSeparatedSingleLineRepeatKeepsCompatibleHookProgression() {
        let lines = makeLines([
            "opening",
            "same signal",
            "verse one",
            "verse two",
            "same signal",
            "ending",
        ], step: 1.4)

        let plan = LyricStageDirectorV3.localPlan(
            trackID: "separated-hook-fixture",
            lines: lines,
            audioSummary: .empty(duration: 10))

        XCTAssertEqual(plan.scene(for: 1)?.composition, .hookCall)
        XCTAssertEqual(plan.scene(for: 4)?.composition, .hookLock)
    }

    func testDenseShortLinesRespectHeroBudgetAndAvoidThreeIdenticalLayouts() {
        let lines = makeLines((0..<24).map { "字\($0)" }, step: 0.9)

        let plan = LyricStageDirectorV3.localPlan(
            trackID: "short-dense-fixture",
            lines: lines,
            audioSummary: .empty(duration: 24))

        let heroes = plan.scenes.filter { $0.composition == .hero || $0.composition == .hookLock }
        XCTAssertLessThanOrEqual(heroes.count, Int(ceil(Double(lines.count) * 0.12)))
        for index in 2..<plan.scenes.count {
            let run = plan.scenes[(index - 2)...index].map(\.composition)
            XCTAssertFalse(run[0] == run[1] && run[1] == run[2])
        }
        XCTAssertTrue(plan.scenes.allSatisfy { (0...1).contains($0.intensity) })
    }

    func testVeryLongLineFallsBackToWrappingAnchorWithoutRewritingText() {
        let original = String(repeating: "这是一句必须完整显示而且绝对不能省略的长歌词", count: 4)
        let lines = makeLines([original, "收束"], step: 3)

        let plan = LyricStageDirectorV3.localPlan(
            trackID: "long-line-fixture",
            lines: lines,
            audioSummary: .empty(duration: 8))

        let composition = plan.scene(for: 0)?.composition
        XCTAssertTrue(composition == .leadingAnchor || composition == .stillness)
        XCTAssertEqual(lines[0].text, original)
        XCTAssertGreaterThan(lines[0].text.count, 80)
    }

    func testDuetUsesRealOverlapAsDialogueCompanions() {
        let lines = [
            PlayerEngine.LyricLine(
                from: 1,
                to: 3,
                text: "左声部",
                voiceRole: .duetA,
                overlapGroup: "duet"),
            PlayerEngine.LyricLine(
                from: 1,
                to: 3,
                text: "右声部",
                voiceRole: .duetB,
                overlapGroup: "duet"),
            PlayerEngine.LyricLine(from: 3, to: 5, text: "一起向前"),
        ]

        let plan = LyricStageDirectorV3.localPlan(
            trackID: "duet-fixture",
            lines: lines,
            audioSummary: .empty(duration: 6))

        XCTAssertEqual(plan.scene(for: 0)?.composition, .dialogue)
        XCTAssertEqual(plan.scene(for: 0)?.companionLineIndices, [1])
        XCTAssertEqual(plan.scene(for: 1)?.companionLineIndices, [0])
    }

    func testRichAudioSummaryChangesCompositionAndIntensityWithoutChangingLyricsTime() {
        let lines = makeLines([
            "平静的开头",
            "能量突然抵达",
            "旋律继续上升",
            "回到安静结尾",
        ], step: 2)
        let summary = makeAudioSummary(lines: lines)

        let plan = LyricStageDirectorV3.localPlan(
            trackID: "audio-fixture",
            lines: lines,
            audioSummary: summary)

        XCTAssertEqual(plan.scene(for: 1)?.composition, .hero)
        XCTAssertEqual(plan.scene(for: 2)?.composition, .stillness)
        XCTAssertEqual(plan.scene(for: 2)?.isSectionStart, true)
        XCTAssertNotEqual(plan.scene(for: 1)?.sectionIndex, plan.scene(for: 2)?.sectionIndex)
        XCTAssertGreaterThan(plan.scene(for: 1)?.intensity ?? 0, 0.75)
        XCTAssertEqual(lines[1].from, 2, accuracy: 0.0001)
        XCTAssertEqual(lines[1].to, 3.6, accuracy: 0.0001)
    }

    func testV3AudioAndLunaVariantsPreserveCanonicalLyricTruth() {
        var lines = [
            PlayerEngine.LyricLine(
                from: 0.25,
                to: 2.90,
                text: "未来へ Go!",
                words: [
                    .init(from: 0.25, to: 0.70, text: "未"),
                    .init(from: 0.70, to: 1.10, text: "来"),
                    .init(from: 1.10, to: 1.45, text: "へ"),
                    .init(from: 1.70, to: 2.90, text: "Go!"),
                ]),
        ]
        lines.append(contentsOf: (1..<12).map { index in
            let from = 3.0 + Double(index - 1) * 1.85
            return PlayerEngine.LyricLine(
                from: from,
                to: from + 1.35 + Double(index % 3) * 0.10,
                text: "逐行歌词 \(index) 必须保持原文",
                words: [])
        })
        let canonical = lines
        let trackID = "truth-property-fixture"
        let audioVariants = [
            LyricStageAudioSummaryV3.empty(duration: 26),
            makeAudioSummary(lines: lines),
        ]

        for (audioIndex, audio) in audioVariants.enumerated() {
            let local = LyricStageDirectorV3.localPlan(
                trackID: trackID,
                lines: lines,
                audioSummary: audio)
            assertV3PlanKeepsOneScenePerCanonicalLine(local, lines: canonical)
            assertLyricTruth(lines, equals: canonical)

            for lunaVariant in 0..<2 {
                let firstIndex = lunaVariant == 0 ? 3 : 4
                let secondIndex = lunaVariant == 0 ? 8 : 9
                let direction = LyricStageDirectionV3(
                    directorVersion: "truth-director-\(audioIndex)-\(lunaVariant)",
                    trackID: trackID,
                    lyricsHash: LyricPerformanceFingerprint.lyricsHash(lines),
                    lineCount: lines.count,
                    audioSummaryHash: audio.summaryHash,
                    stageBible: bible,
                    sections: [
                        LyricStageSectionV3(
                            id: "whole",
                            lineFrom: 0,
                            lineTo: lines.count - 1,
                            kind: .verse,
                            intensity: 0.55,
                            motifPhase: lunaVariant == 0 ? .develop : .transform),
                    ],
                    scenes: [
                        LyricStageSceneOverrideV3(
                            lineIndex: firstIndex,
                            composition: lunaVariant == 0 ? .leadingAnchor : .trailingAnchor),
                        LyricStageSceneOverrideV3(
                            lineIndex: secondIndex,
                            composition: lunaVariant == 0 ? .trailingAnchor : .stillness),
                    ])
                let resolved = LyricStageDirectorV3.resolve(
                    trackID: trackID,
                    lines: lines,
                    audioSummary: audio,
                    direction: direction)

                XCTAssertEqual(resolved.source, .luna)
                assertV3PlanKeepsOneScenePerCanonicalLine(resolved, lines: canonical)
                assertLyricTruth(lines, equals: canonical)
                for line in lines where line.words.isEmpty {
                    let glyphs = LyricStageCompiler.glyphs(for: line)
                    XCTAssertEqual(glyphs.map(\.text).joined(), line.text)
                    XCTAssertTrue(glyphs.allSatisfy { !$0.hasRealWordTiming })
                }
            }
        }
    }

    func testValidSparseDirectionOverridesLocalPlanAndInvalidHookIsRejected() {
        let lines = makeLines((0..<10).map { "different line \($0)" }, step: 1.5)
        let trackID = "online-fixture"
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        let audio = LyricStageAudioSummaryV3.empty(duration: 18)
        let sections = [
            LyricStageSectionV3(
                id: "whole",
                lineFrom: 0,
                lineTo: 9,
                kind: .verse,
                intensity: 0.5,
                motifPhase: .develop),
        ]
        let valid = LyricStageDirectionV3(
            directorVersion: "test-v3",
            trackID: trackID,
            lyricsHash: hash,
            lineCount: lines.count,
            audioSummaryHash: audio.summaryHash,
            stageBible: bible,
            sections: sections,
            scenes: [
                LyricStageSceneOverrideV3(lineIndex: 3, composition: .trailingAnchor),
            ])

        let resolved = LyricStageDirectorV3.resolve(
            trackID: trackID,
            lines: lines,
            audioSummary: audio,
            direction: valid)
        XCTAssertEqual(resolved.source, .luna)
        XCTAssertEqual(resolved.scene(for: 3)?.composition, .trailingAnchor)
        XCTAssertEqual(resolved.scenes.count, lines.count)

        let invalid = LyricStageDirectionV3(
            directorVersion: "test-v3",
            trackID: trackID,
            lyricsHash: hash,
            lineCount: lines.count,
            audioSummaryHash: audio.summaryHash,
            stageBible: bible,
            sections: sections,
            scenes: [
                LyricStageSceneOverrideV3(lineIndex: 3, composition: .hookCall),
            ])
        XCTAssertNil(invalid.validated(
            trackID: trackID,
            lyricsHash: hash,
            lines: lines,
            audioSummaryHash: audio.summaryHash))
    }

    @MainActor
    func testV3StoreRoundTripsAndInvalidatesWhenAudioSummaryChanges() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyric-stage-v3-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("stage-v3.json")
        let track = Track(
            bvid: "BVSTOREV3",
            cid: 7,
            title: "Store",
            artist: "Fixture",
            coverURL: nil,
            duration: 20)
        let lines = makeLines((0..<10).map { "cache line \($0)" }, step: 1.5)
        let audio = LyricStageAudioSummaryV3.empty(duration: 20)
        let direction = makeDirection(track: track, lines: lines, audio: audio)
        let writer = LyricStageStoreV3(fileURLForTesting: fileURL)

        let saved = await writer.save(direction, for: track, lines: lines, audioSummary: audio)
        XCTAssertTrue(saved)
        let reader = LyricStageStoreV3(fileURLForTesting: fileURL)
        let restored = await reader.direction(for: track, lines: lines, audioSummary: audio)
        XCTAssertEqual(restored, direction)

        let changedAudio = LyricStageAudioSummaryV3.empty(duration: 21)
        let invalidated = await reader.direction(for: track, lines: lines, audioSummary: changedAudio)
        XCTAssertNil(invalidated)
    }

    @MainActor
    func testV3StoreKeepsResolvedPartsIsolatedFromBVOnlyMutations() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyric-stage-v3-parts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LyricStageStoreV3(fileURLForTesting: directory.appendingPathComponent("stage-v3.json"))
        let lines = makeLines((0..<10).map { "shared lyric \($0)" }, step: 1.5)
        let audio = LyricStageAudioSummaryV3.empty(duration: 20)
        let partOne = Track(
            bvid: "BVMULTIPART",
            cid: 101,
            title: "Part 1",
            artist: "Fixture",
            coverURL: nil,
            duration: 20)
        let partTwo = Track(
            bvid: "BVMULTIPART",
            cid: 202,
            title: "Part 2",
            artist: "Fixture",
            coverURL: nil,
            duration: 20)
        let unresolved = Track(
            bvid: "BVMULTIPART",
            cid: nil,
            title: "Unknown Part",
            artist: "Fixture",
            coverURL: nil,
            duration: 20)

        let savedOne = await store.save(
            makeDirection(track: partOne, lines: lines, audio: audio),
            for: partOne,
            lines: lines,
            audioSummary: audio)
        let savedTwo = await store.save(
            makeDirection(track: partTwo, lines: lines, audio: audio),
            for: partTwo,
            lines: lines,
            audioSummary: audio)
        XCTAssertTrue(savedOne)
        XCTAssertTrue(savedTwo)

        await store.clear(for: unresolved)
        let retainedOne = await store.direction(for: partOne, lines: lines, audioSummary: audio)
        let retainedTwo = await store.direction(for: partTwo, lines: lines, audioSummary: audio)
        XCTAssertNotNil(retainedOne)
        XCTAssertNotNil(retainedTwo)
        let ambiguousUnresolved = await store.direction(for: unresolved, lines: lines, audioSummary: audio)
        XCTAssertNil(ambiguousUnresolved)

        let savedLegacy = await store.save(
            makeDirection(track: unresolved, lines: lines, audio: audio),
            for: unresolved,
            lines: lines,
            audioSummary: audio)
        XCTAssertTrue(savedLegacy)
        let replacedOne = await store.save(
            makeDirection(track: partOne, lines: lines, audio: audio),
            for: partOne,
            lines: lines,
            audioSummary: audio)
        XCTAssertTrue(replacedOne)
        let stillRetainedTwo = await store.direction(for: partTwo, lines: lines, audioSummary: audio)
        XCTAssertNotNil(stillRetainedTwo)
        let legacyAfterResolvedSave = await store.direction(
            for: unresolved,
            lines: lines,
            audioSummary: audio)
        XCTAssertNil(legacyAfterResolvedSave)
    }

    func testV3CacheIdentityIncludesDirectorVersion() {
        let first = LyricStageFingerprintV3.cacheIdentity(
            trackID: "fixture",
            lyricsHash: "lyrics",
            audioSummaryHash: "audio",
            directorVersion: "director-a")
        let second = LyricStageFingerprintV3.cacheIdentity(
            trackID: "fixture",
            lyricsHash: "lyrics",
            audioSummaryHash: "audio",
            directorVersion: "director-b")
        XCTAssertNotEqual(first, second)
    }

    private let bible = LyricStageBibleV3(
        concept: "fixture concept",
        motif: "fixture motif",
        intensityArc: "quiet build resolve")

    private func makeDirection(
        track: Track,
        lines: [PlayerEngine.LyricLine],
        audio: LyricStageAudioSummaryV3
    ) -> LyricStageDirectionV3 {
        LyricStageDirectionV3(
            directorVersion: "test-v3",
            trackID: track.key.description,
            lyricsHash: LyricPerformanceFingerprint.lyricsHash(lines),
            lineCount: lines.count,
            audioSummaryHash: audio.summaryHash,
            stageBible: bible,
            sections: [
                LyricStageSectionV3(
                    id: "whole",
                    lineFrom: 0,
                    lineTo: lines.count - 1,
                    kind: .verse,
                    intensity: 0.5,
                    motifPhase: .develop),
            ],
            scenes: [LyricStageSceneOverrideV3(lineIndex: 3, composition: .trailingAnchor)])
    }

    private func makeLines(_ texts: [String], step: Double) -> [PlayerEngine.LyricLine] {
        texts.enumerated().map { index, text in
            let from = Double(index) * step
            return PlayerEngine.LyricLine(from: from, to: from + step * 0.8, text: text)
        }
    }

    private func makeAudioSummary(lines: [PlayerEngine.LyricLine]) -> LyricStageAudioSummaryV3 {
        let confidence = AudioPerformanceConfidence(
            beat: 0.8,
            downbeat: 0.7,
            onset: 0.9,
            energy: 0.9,
            pitch: 0.8,
            regions: 0.8,
            overall: 0.85)
        let summaries = lines.enumerated().map { index, line in
            LyricStageAudioLineSummaryV3(
                lineIndex: index,
                from: line.from,
                to: line.to,
                sectionIndex: index < 2 ? 0 : 1,
                meanEnergy: index == 1 ? 0.82 : 0.35,
                peakEnergy: index == 1 ? 0.96 : 0.45,
                energyDelta: 0.05,
                onsetCount: index == 1 ? 3 : 0,
                nearestBeatDistance: 0.02,
                pitchStart: index == 2 ? 220 : nil,
                pitchEnd: index == 2 ? 250 : nil,
                pitchTrend: index == 2 ? 30 : nil,
                pitchConfidence: index == 2 ? 0.8 : nil,
                silenceBefore: index == 0 ? 0.8 : 0,
                silenceAfter: 0)
        }
        return LyricStageAudioSummaryV3(
            version: AudioPerformanceMapV2Version.stageSummary,
            mapFingerprint: "fixture-map",
            summaryHash: "fixture-summary",
            duration: 8,
            confidence: confidence,
            sections: [
                LyricStageAudioSectionSummaryV3(
                    index: 0,
                    from: 0,
                    to: 4,
                    lineFrom: 0,
                    lineTo: 1,
                    meanEnergy: 0.7,
                    energyTrend: 0.4,
                    onsetDensity: 1.2,
                    pitchTrend: 0,
                    confidence: 0.8),
                LyricStageAudioSectionSummaryV3(
                    index: 1,
                    from: 4,
                    to: 8,
                    lineFrom: 2,
                    lineTo: 3,
                    meanEnergy: 0.4,
                    energyTrend: -0.2,
                    onsetDensity: 0.3,
                    pitchTrend: 30,
                    confidence: 0.8),
            ],
            lines: summaries)
    }

    private func assertV3PlanKeepsOneScenePerCanonicalLine(
        _ plan: LyricStagePlanV3,
        lines: [PlayerEngine.LyricLine],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(plan.scenes.count, lines.count, file: file, line: line)
        XCTAssertEqual(plan.scenes.map(\.lineIndex).sorted(), Array(lines.indices), file: file, line: line)
    }

    private func assertLyricTruth(
        _ actual: [PlayerEngine.LyricLine],
        equals expected: [PlayerEngine.LyricLine],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualLine, expectedLine) in zip(actual, expected) {
            XCTAssertEqual(actualLine.text, expectedLine.text, file: file, line: line)
            XCTAssertEqual(actualLine.from, expectedLine.from, accuracy: 0.000_001, file: file, line: line)
            XCTAssertEqual(actualLine.to, expectedLine.to, accuracy: 0.000_001, file: file, line: line)
            XCTAssertEqual(actualLine.words.count, expectedLine.words.count, file: file, line: line)
            for (actualWord, expectedWord) in zip(actualLine.words, expectedLine.words) {
                XCTAssertEqual(actualWord.text, expectedWord.text, file: file, line: line)
                XCTAssertEqual(actualWord.from, expectedWord.from, accuracy: 0.000_001, file: file, line: line)
                XCTAssertEqual(actualWord.to, expectedWord.to, accuracy: 0.000_001, file: file, line: line)
            }
        }
    }
}
