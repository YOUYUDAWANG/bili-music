import XCTest
@testable import BiliMusic

final class OnDeviceLyricsAlignerTests: XCTestCase {
    func testInlineParentheticalBackingVocalBecomesParallelLayer() {
        let document = LyricsDocument(
            result: sourceDocument.result,
            lyric: "[00:01.00]向前走（别回头）\n[00:05.00]下一句",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil,
            versionScope: .manual,
            timingKind: .line)

        let lines = LyricsParser.lines(from: document, duration: 10)

        XCTAssertEqual(lines.map(\.text), ["向前走", "别回头", "下一句"])
        XCTAssertEqual(lines[0].voiceRole, .lead)
        XCTAssertEqual(lines[1].voiceRole, .backing)
        XCTAssertEqual(lines[0].overlapGroup, lines[1].overlapGroup)
        XCTAssertEqual(lines[0].from, lines[1].from)
        XCTAssertEqual(lines[0].to, lines[1].to)
    }

    func testStageDirectionInParenthesesIsNotTreatedAsBackingVocal() {
        let document = LyricsDocument(
            result: sourceDocument.result,
            lyric: "[00:01.00]等待（间奏）\n[00:05.00]归来",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil,
            versionScope: .manual,
            timingKind: .line)

        let lines = LyricsParser.lines(from: document, duration: 10)

        XCTAssertEqual(lines.map(\.text), ["等待（间奏）", "归来"])
        XCTAssertTrue(lines.allSatisfy { $0.overlapGroup == nil })
    }

    func testRepeatedTimestampLinesBecomeEqualDuetLanesUntilNextTimestamp() {
        let document = LyricsDocument(
            result: sourceDocument.result,
            lyric: "[00:01.00]A声部\n[00:01.00]B声部\n[00:05.00]合流",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil,
            versionScope: .manual,
            timingKind: .line)

        let lines = LyricsParser.lines(from: document, duration: 10)

        XCTAssertEqual(lines[0].voiceRole, .duetA)
        XCTAssertEqual(lines[1].voiceRole, .duetB)
        XCTAssertEqual(lines[0].to, 5, accuracy: 0.001)
        XCTAssertEqual(lines[1].to, 5, accuracy: 0.001)
        XCTAssertEqual(lines[0].overlapGroup, lines[1].overlapGroup)
    }

    func testHighlightModelReturnsEverySimultaneousVoiceAndPrefersLead() {
        let group = "chorus"
        let lines = [
            PlayerEngine.LyricLine(
                from: 1,
                to: 4,
                text: "和声",
                voiceRole: .backing,
                layerID: "backing",
                overlapGroup: group),
            PlayerEngine.LyricLine(
                from: 1,
                to: 4,
                text: "主唱",
                voiceRole: .lead,
                layerID: "lead",
                overlapGroup: group),
        ]

        XCTAssertEqual(LyricHighlightModel.activeLineIndices(lines: lines, at: 2), [0, 1])
        XCTAssertEqual(LyricHighlightModel.activeLineIndex(lines: lines, at: 2), 1)
    }

    func testCoarseTimelineSharesSearchWindowAcrossParallelVoices() {
        let group = "duet"
        let lines = [
            PlayerEngine.LyricLine(
                from: 0,
                to: 2,
                text: "甲",
                voiceRole: .duetA,
                layerID: "a",
                overlapGroup: group),
            PlayerEngine.LyricLine(
                from: 2,
                to: 4,
                text: "乙",
                voiceRole: .duetB,
                layerID: "b",
                overlapGroup: group),
            PlayerEngine.LyricLine(from: 4, to: 6, text: "合"),
        ]
        let ranges = [
            OnDeviceAlignedLineRange(from: 1, to: 2),
            OnDeviceAlignedLineRange(from: 2, to: 3),
            OnDeviceAlignedLineRange(from: 4, to: 5),
        ]

        let shared = OnDeviceKaraokeBuilder.sharedVocalWindows(lines: lines, ranges: ranges)

        XCTAssertEqual(shared[0], OnDeviceAlignedLineRange(from: 1, to: 3))
        XCTAssertEqual(shared[1], OnDeviceAlignedLineRange(from: 1, to: 3))
        XCTAssertEqual(shared[2], ranges[2])
    }

    func testVocalLayersSurviveLyricsDocumentPersistence() throws {
        var document = sourceDocument
        document.vocalLines = [LyricsVocalLine(
            from: 1,
            to: 2,
            text: "和声",
            translation: nil,
            words: [LyricsWordPayload(from: 1.1, to: 1.8, text: "和声")],
            voiceRole: .backing,
            layerID: "backing",
            overlapGroup: "chorus")]

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(LyricsDocument.self, from: data)

        XCTAssertEqual(decoded.vocalLines, document.vocalLines)
        XCTAssertEqual(decoded.vocalLines?.first?.voiceRole, .backing)
    }

    func testChineseAndJapaneseInputsKeepEveryVisibleCharacter() {
        let chinese = OnDeviceKaraokeBuilder.preparedInput(from: [
            PlayerEngine.LyricLine(from: 0, to: 2, text: "春天，来了")
        ])
        XCTAssertEqual(chinese.language, "Chinese")
        XCTAssertEqual(chinese.text, "春 天 来 了")
        XCTAssertEqual(chinese.unitsByLine[0].map(\.surfaceText), ["春", "天，", "来", "了"])

        let japanese = OnDeviceKaraokeBuilder.preparedInput(from: [
            PlayerEngine.LyricLine(from: 0, to: 2, text: "未来へ Go!")
        ])
        XCTAssertEqual(japanese.language, "Japanese")
        XCTAssertEqual(japanese.text, "未 来 へ Go")
        XCTAssertEqual(japanese.unitsByLine[0].map(\.surfaceText).joined(), "未来へGo!")
    }

    func testJapaneseInputUsesSystemWordSegmentationBeforeCharacterDisplayExpansion() {
        let input = OnDeviceKaraokeBuilder.preparedInput(
            from: [PlayerEngine.LyricLine(
                from: 0,
                to: 8,
                text: "あなたと私 ちょうどいい昼間")],
            preferredLanguageCode: "ja")

        XCTAssertEqual(input.language, "Japanese")
        XCTAssertEqual(input.unitsByLine[0].map(\.modelText), [
            "あなた", "と", "私", "ちょうど", "いい", "昼", "間",
        ])
        XCTAssertEqual(input.text, "あなた と 私 ちょうど いい 昼 間")
        XCTAssertEqual(input.unitsByLine[0].flatMap(\.displayTexts).joined(), "あなたと私ちょうどいい昼間")
    }

    func testJapaneseModelPhraseExpandsBackIntoCharacterTimedLyrics() throws {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 2, text: "あなた")]
        let input = OnDeviceKaraokeBuilder.preparedInput(
            from: lines,
            preferredLanguageCode: "ja")
        XCTAssertEqual(input.unitsByLine[0].map(\.modelText), ["あなた"])
        let result = OnDeviceLyricsAlignmentResult(
            words: [OnDeviceAlignedWord(text: "あなた", startTime: 0.2, endTime: 1.4)],
            language: "Japanese",
            audioDuration: 2,
            elapsedTime: 0.1,
            peakMemoryGB: 1)

        let upgraded = try OnDeviceKaraokeBuilder.upgradedDocument(
            from: sourceDocument,
            lines: lines,
            input: input,
            alignment: result)
        let words = LyricsParser.lines(from: upgraded, duration: 2).flatMap(\.words)

        XCTAssertEqual(words.map(\.text), ["あ", "な", "た"])
        XCTAssertEqual(words[0].from, 0, accuracy: 0.001)
        XCTAssertEqual(words[1].from, 0.4, accuracy: 0.001)
        XCTAssertEqual(words[2].from, 0.8, accuracy: 0.001)
        XCTAssertEqual(words[2].to, 1.2, accuracy: 0.001)
    }

    func testRebuiltTimelineStillAllowsFineModelToChooseLineOnset() throws {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 2, text: "あなた")]
        let input = OnDeviceKaraokeBuilder.preparedInput(
            from: lines,
            preferredLanguageCode: "ja")
        let result = OnDeviceLyricsAlignmentResult(
            words: [OnDeviceAlignedWord(text: "あなた", startTime: 0.2, endTime: 1.4)],
            language: "Japanese",
            audioDuration: 2,
            elapsedTime: 0.1,
            peakMemoryGB: 1,
            lineRanges: [OnDeviceAlignedLineRange(from: 0, to: 2)],
            rebuiltTimeline: true)

        let upgraded = try OnDeviceKaraokeBuilder.upgradedDocument(
            from: sourceDocument,
            lines: lines,
            input: input,
            alignment: result)
        let words = LyricsParser.lines(from: upgraded, duration: 2).flatMap(\.words)

        XCTAssertEqual(words.first?.from ?? -1, 0.2, accuracy: 0.001)
        XCTAssertEqual(words.last?.to ?? -1, 1.4, accuracy: 0.001)
    }

    func testWholeSongCalibrationOwnsCorrectedLineOnset() throws {
        let lines = [PlayerEngine.LyricLine(from: 10, to: 12, text: "あなた")]
        let input = OnDeviceKaraokeBuilder.preparedInput(
            from: lines,
            preferredLanguageCode: "ja")
        let calibration = OnDeviceTimelineCalibration(
            offsetSeconds: -6.2,
            confidence: 0.8,
            sampleCount: 8,
            dispersion: 0.4)
        let result = OnDeviceLyricsAlignmentResult(
            words: [OnDeviceAlignedWord(text: "あなた", startTime: 17, endTime: 18)],
            language: "Japanese",
            audioDuration: 20,
            elapsedTime: 0.1,
            peakMemoryGB: 1,
            lineRanges: [OnDeviceAlignedLineRange(from: 16.2, to: 18.2)],
            rebuiltTimeline: false,
            timelineCalibration: calibration)

        let upgraded = try OnDeviceKaraokeBuilder.upgradedDocument(
            from: sourceDocument,
            lines: lines,
            input: input,
            alignment: result)
        let words = LyricsParser.lines(from: upgraded, duration: 20).flatMap(\.words)

        XCTAssertEqual(words.first?.from ?? -1, 16.2, accuracy: 0.001)
    }

    func testEnglishInputKeepsWordGranularity() {
        let input = OnDeviceKaraokeBuilder.preparedInput(from: [
            PlayerEngine.LyricLine(from: 0, to: 2, text: "Don't stop now")
        ])
        XCTAssertEqual(input.language, "English")
        XCTAssertEqual(input.text, "Don't stop now")
        XCTAssertEqual(input.unitsByLine[0].map(\.surfaceText), ["Don't", "stop", "now"])
    }

    func testCleanedSongLanguageOverridesAmbiguousLyricScript() {
        let japanese = OnDeviceKaraokeBuilder.preparedInput(
            from: [PlayerEngine.LyricLine(from: 0, to: 2, text: "愛")],
            preferredLanguageCode: "ja")
        XCTAssertEqual(japanese.language, "Japanese")

        let fallback = OnDeviceKaraokeBuilder.preparedInput(
            from: [PlayerEngine.LyricLine(from: 0, to: 2, text: "愛")],
            preferredLanguageCode: "und")
        XCTAssertEqual(fallback.language, "Chinese")

        let kanaWins = OnDeviceKaraokeBuilder.preparedInput(
            from: [PlayerEngine.LyricLine(from: 0, to: 2, text: "未来へ")],
            preferredLanguageCode: "zh")
        XCTAssertEqual(kanaWins.language, "Japanese")

        let latinWins = OnDeviceKaraokeBuilder.preparedInput(
            from: [PlayerEngine.LyricLine(from: 0, to: 2, text: "hello")],
            preferredLanguageCode: "ja")
        XCTAssertEqual(latinWins.language, "English")
    }

    func testLongSongIsSplitIntoBoundedSegments() {
        let lineDuration = 4.2
        let lines = (0..<45).map { index in
            PlayerEngine.LyricLine(
                from: Double(index) * lineDuration,
                to: Double(index + 1) * lineDuration,
                text: "甚至出现交易几乎停滞的情况。")
        }
        let input = OnDeviceKaraokeBuilder.preparedInput(from: lines)
        let segments = OnDeviceKaraokeBuilder.alignmentSegments(
            lines: lines,
            input: input,
            audioDuration: Double(lines.count) * lineDuration)

        XCTAssertEqual(segments.flatMap(\.lineIndices), Array(lines.indices))
        XCTAssertTrue(segments.allSatisfy { $0.endTime - $0.startTime <= 9.0 })
        XCTAssertEqual(segments.count, lines.count)
        XCTAssertTrue(segments.allSatisfy { $0.lineIndices.count == 1 })
        XCTAssertTrue(segments.allSatisfy { $0.expectedUnitCount <= OnDeviceKaraokeBuilder.maximumSegmentUnits })
        XCTAssertEqual(segments.reduce(0) { $0 + $1.expectedUnitCount }, input.unitsByLine.flatMap { $0 }.count)
    }

    func testLongLRCGapDoesNotBecomeAFullAlignmentWindow() {
        let lines = [PlayerEngine.LyricLine(
            from: 171.7,
            to: 196.39,
            text: "目眩晴れ白い蘭の月")]
        let input = OnDeviceKaraokeBuilder.preparedInput(
            from: lines,
            preferredLanguageCode: "ja")
        let segment = OnDeviceKaraokeBuilder.alignmentSegments(
            lines: lines,
            input: input,
            audioDuration: 257).first

        XCTAssertNotNil(segment)
        XCTAssertLessThan(segment!.endTime - segment!.startTime, 6)
    }

    func testAlignmentBuildsWordTimedQRCWithoutTruncatingLyrics() throws {
        let lines = [
            PlayerEngine.LyricLine(from: 0, to: 2, text: "春天，来了"),
            PlayerEngine.LyricLine(from: 2, to: 4, text: "一起走吧")
        ]
        let input = OnDeviceKaraokeBuilder.preparedInput(from: lines)
        let words = (0..<8).map { index in
            OnDeviceAlignedWord(
                text: input.unitsByLine.flatMap { $0 }[index].modelText,
                startTime: Double(index) * 0.45,
                endTime: Double(index) * 0.45 + 0.4)
        }
        let result = OnDeviceLyricsAlignmentResult(
            words: words,
            language: "Chinese",
            audioDuration: 4,
            elapsedTime: 1.2,
            peakMemoryGB: 1.3)
        let upgraded = try OnDeviceKaraokeBuilder.upgradedDocument(
            from: sourceDocument,
            lines: lines,
            input: input,
            alignment: result)

        XCTAssertEqual(upgraded.timingKind, .word)
        XCTAssertEqual(upgraded.lyric, sourceDocument.lyric)
        let parsed = LyricsParser.lines(from: upgraded, duration: 4)
        XCTAssertEqual(parsed.map(\.text), ["春天，来了", "一起走吧"])
        XCTAssertEqual(parsed.flatMap(\.words).map(\.text).joined(), "春天，来了一起走吧")
        XCTAssertFalse(upgraded.karaokeLyric?.contains("…") == true)
    }

    func testAdjacentSegmentsMayOverlapWithoutRejectingOrderedLines() throws {
        let lines = [
            PlayerEngine.LyricLine(from: 0, to: 2, text: "春天"),
            PlayerEngine.LyricLine(from: 2, to: 4, text: "来了")
        ]
        let input = OnDeviceKaraokeBuilder.preparedInput(from: lines)
        let result = OnDeviceLyricsAlignmentResult(
            words: [
                OnDeviceAlignedWord(text: "春", startTime: 0.6, endTime: 1.1),
                OnDeviceAlignedWord(text: "天", startTime: 1.8, endTime: 2.2),
                OnDeviceAlignedWord(text: "来", startTime: 1.35, endTime: 2.1),
                OnDeviceAlignedWord(text: "了", startTime: 2.4, endTime: 3.0)
            ],
            language: "Chinese",
            audioDuration: 4,
            elapsedTime: 1,
            peakMemoryGB: 1)

        let upgraded = try OnDeviceKaraokeBuilder.upgradedDocument(
            from: sourceDocument,
            lines: lines,
            input: input,
            alignment: result)
        let parsed = LyricsParser.lines(from: upgraded, duration: 4)
        XCTAssertEqual(parsed.map(\.text), ["春天", "来了"])
        XCTAssertEqual(parsed[0].words.first?.from ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(parsed[1].words.first?.from ?? -1, 2, accuracy: 0.001)
        XCTAssertTrue(parsed[0].words.allSatisfy { $0.from >= 0 && $0.to <= 2 })
        XCTAssertTrue(parsed[1].words.allSatisfy { $0.from >= 2 && $0.to <= 4 })
        for line in parsed {
            for pair in zip(line.words, line.words.dropFirst()) {
                XCTAssertEqual(pair.0.to, pair.1.from, accuracy: 0.001)
            }
        }
    }

    func testCoarseASRMatchesPlainLyricsIntoOrderedSearchWindows() throws {
        let lines = [
            PlayerEngine.LyricLine(from: 0, to: 5, text: "春天来了我们出发"),
            PlayerEngine.LyricLine(from: 5, to: 10, text: "沿着河流走向远方"),
            PlayerEngine.LyricLine(from: 10, to: 15, text: "夜空亮起新的星光")
        ]
        let result = try OnDeviceCoarseTimelineBuilder.build(
            lines: lines,
            chunks: [
                OnDeviceASRChunk(text: "春天来了我们出发", from: 8, to: 16),
                OnDeviceASRChunk(text: "沿着河流走向远方", from: 16, to: 24),
                OnDeviceASRChunk(text: "夜空亮起新的星光", from: 24, to: 32)
            ],
            audioDuration: 40)

        XCTAssertEqual(result.lineRanges.count, lines.count)
        XCTAssertGreaterThan(result.characterCoverage, 0.95)
        XCTAssertGreaterThan(result.lineCoverage, 0.95)
        XCTAssertTrue(zip(result.lineRanges, result.lineRanges.dropFirst()).allSatisfy {
            $0.0.from < $0.1.from
        })
        XCTAssertTrue(result.lineRanges.allSatisfy { $0.from >= 0 && $0.to <= 40 && $0.to > $0.from })
    }

    func testTimelineCalibratorFindsStableWholeSongShift() throws {
        let lines = (0..<6).map { index in
            PlayerEngine.LyricLine(
                from: 10 + Double(index) * 5,
                to: 14 + Double(index) * 5,
                text: "第\(index)句歌词")
        }
        let estimates = (0..<6).map { index in
            OnDeviceAlignedLineRange(
                from: 2.5 + Double(index) * 5,
                to: 6.5 + Double(index) * 5)
        }
        let timeline = OnDeviceCoarseTimeline(
            lineRanges: estimates,
            lineEstimates: estimates,
            characterCoverage: 0.9,
            lineCoverage: 1)

        let suggestion = try XCTUnwrap(OnDeviceTimelineCalibrator.suggest(
            lines: lines,
            timeline: timeline))

        XCTAssertEqual(suggestion.offsetSeconds, 7.5, accuracy: 0.001)
        XCTAssertEqual(suggestion.sampleCount, 6)
        XCTAssertGreaterThan(suggestion.confidence, 0.7)
    }

    func testTimelineCalibratorRejectsNonlinearDrift() {
        let lines = (0..<6).map { index in
            PlayerEngine.LyricLine(
                from: 10 + Double(index) * 5,
                to: 14 + Double(index) * 5,
                text: "第\(index)句歌词")
        }
        let offsets = [0.5, 2.5, 4.5, 6.5, 8.5, 9.5]
        let estimates = zip(lines, offsets).map { line, offset in
            OnDeviceAlignedLineRange(from: line.from - offset, to: line.to - offset)
        }
        let timeline = OnDeviceCoarseTimeline(
            lineRanges: estimates,
            lineEstimates: estimates,
            characterCoverage: 0.9,
            lineCoverage: 1)

        XCTAssertNil(OnDeviceTimelineCalibrator.suggest(lines: lines, timeline: timeline))
    }

    func testCoarseASRRejectsUnrelatedTranscription() {
        let lines = [
            PlayerEngine.LyricLine(from: 0, to: 5, text: "春天来了我们出发"),
            PlayerEngine.LyricLine(from: 5, to: 10, text: "沿着河流走向远方")
        ]
        XCTAssertThrowsError(try OnDeviceCoarseTimelineBuilder.build(
            lines: lines,
            chunks: [OnDeviceASRChunk(text: "completely unrelated speech", from: 0, to: 10)],
            audioDuration: 10)) { error in
            XCTAssertEqual(error as? OnDeviceLyricsAlignerError, .coarseAlignmentLowConfidence)
        }
    }

    func testZeroDurationModelSpansAreExpandedInsteadOfRejected() throws {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 2, text: "春天")]
        let input = OnDeviceKaraokeBuilder.preparedInput(from: lines)
        let result = OnDeviceLyricsAlignmentResult(
            words: [
                OnDeviceAlignedWord(text: "春", startTime: 0.5, endTime: 0.5),
                OnDeviceAlignedWord(text: "天", startTime: 0.5, endTime: 0.5)
            ],
            language: "Chinese",
            audioDuration: 2,
            elapsedTime: 1,
            peakMemoryGB: 1)

        let upgraded = try OnDeviceKaraokeBuilder.upgradedDocument(
            from: sourceDocument,
            lines: lines,
            input: input,
            alignment: result)
        let words = LyricsParser.lines(from: upgraded, duration: 2).flatMap(\.words)
        XCTAssertEqual(words.map(\.text), ["春", "天"])
        XCTAssertTrue(words.allSatisfy { $0.to > $0.from })
    }

    func testCollapsedModelTimelineUsesMarkedRhythmicFallbackInsteadOfFortyMillisecondWords() throws {
        let lines = [PlayerEngine.LyricLine(from: 0, to: 8, text: "春天来了我们")]
        let input = OnDeviceKaraokeBuilder.preparedInput(from: lines)
        let result = OnDeviceLyricsAlignmentResult(
            words: [
                OnDeviceAlignedWord(text: "春", startTime: 0, endTime: 0),
                OnDeviceAlignedWord(text: "天", startTime: 0, endTime: 0),
                OnDeviceAlignedWord(text: "来", startTime: 0, endTime: 0),
                OnDeviceAlignedWord(text: "了", startTime: 0, endTime: 0),
                OnDeviceAlignedWord(text: "我", startTime: 7.9, endTime: 7.9),
                OnDeviceAlignedWord(text: "们", startTime: 7.9, endTime: 7.9),
            ],
            language: "Chinese",
            audioDuration: 8,
            elapsedTime: 0.1,
            peakMemoryGB: 1)

        let upgraded = try OnDeviceKaraokeBuilder.upgradedDocument(
            from: sourceDocument,
            lines: lines,
            input: input,
            alignment: result)
        let words = LyricsParser.lines(from: upgraded, duration: 8).flatMap(\.words)

        XCTAssertTrue(upgraded.timingNeedsConfirmation)
        XCTAssertEqual(words.map(\.text).joined(), "春天来了我们")
        XCTAssertTrue(words.allSatisfy { $0.to - $0.from > 0.1 })
        XCTAssertLessThan(words.map { $0.to - $0.from }.max() ?? 9, 1.5)
    }

    func testSeverelyImbalancedJapaneseLineUsesRhythmicFallback() throws {
        let lines = [PlayerEngine.LyricLine(
            from: 0,
            to: 8,
            text: "あなたと私 ちょうどいい昼間")]
        let input = OnDeviceKaraokeBuilder.preparedInput(
            from: lines,
            preferredLanguageCode: "ja")
        let starts = [0.0, 0.154, 0.308, 3.623, 4.5, 6.5, 7.5]
        let result = OnDeviceLyricsAlignmentResult(
            words: zip(input.unitsByLine[0], starts).map { unit, start in
                OnDeviceAlignedWord(text: unit.modelText, startTime: start, endTime: start)
            },
            language: "Japanese",
            audioDuration: 8,
            elapsedTime: 0.1,
            peakMemoryGB: 1)

        let upgraded = try OnDeviceKaraokeBuilder.upgradedDocument(
            from: sourceDocument,
            lines: lines,
            input: input,
            alignment: result)
        let words = LyricsParser.lines(from: upgraded, duration: 8).flatMap(\.words)

        XCTAssertTrue(upgraded.timingNeedsConfirmation)
        XCTAssertEqual(words.map(\.text).joined(), "あなたと私ちょうどいい昼間")
        XCTAssertLessThan(words.map { $0.to - $0.from }.max() ?? 9, 0.8)
        XCTAssertGreaterThan(words.map { $0.to - $0.from }.min() ?? 0, 0.1)
    }

    func testGeneratedWordDocumentPreservesParallelVoiceMetadata() throws {
        let group = "parallel"
        let lines = [
            PlayerEngine.LyricLine(
                from: 0,
                to: 2,
                text: "主唱",
                voiceRole: .lead,
                layerID: "lead",
                overlapGroup: group),
            PlayerEngine.LyricLine(
                from: 0,
                to: 2,
                text: "和声",
                voiceRole: .backing,
                layerID: "backing",
                overlapGroup: group),
        ]
        let input = OnDeviceKaraokeBuilder.preparedInput(from: lines)
        let result = OnDeviceLyricsAlignmentResult(
            words: [
                OnDeviceAlignedWord(text: "主", startTime: 0.4, endTime: 0.8),
                OnDeviceAlignedWord(text: "唱", startTime: 0.8, endTime: 1.2),
                OnDeviceAlignedWord(text: "和", startTime: 0.3, endTime: 0.9),
                OnDeviceAlignedWord(text: "声", startTime: 0.9, endTime: 1.4),
            ],
            language: "Chinese",
            audioDuration: 2,
            elapsedTime: 1,
            peakMemoryGB: 1)

        let upgraded = try OnDeviceKaraokeBuilder.upgradedDocument(
            from: sourceDocument,
            lines: lines,
            input: input,
            alignment: result)
        let parsed = LyricsParser.lines(from: upgraded, duration: 2)

        XCTAssertEqual(parsed.map(\.voiceRole), [.lead, .backing])
        XCTAssertEqual(parsed.map(\.overlapGroup), [group, group])
        XCTAssertTrue(parsed.allSatisfy { !$0.words.isEmpty })
    }

    private var sourceDocument: LyricsDocument {
        LyricsDocument(
            result: LyricsSearchResult(
                provider: .imported,
                id: "local-test",
                title: "Test",
                artist: "Artist",
                album: nil,
                duration: 4,
                artworkID: nil),
            lyric: "[00:00.00]春天，来了\n[00:02.00]一起走吧",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil,
            versionScope: .manual,
            timingKind: .line)
    }
}
