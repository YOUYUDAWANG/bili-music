import XCTest
@testable import BiliMusic

final class LyricsIdentityTests: XCTestCase {
    func testCoverDisplayKeepsPerformerAndOriginalSeparate() {
        let metadata = NormalizedTrackMetadata(
            canonicalTitle: "夏夜のマジック",
            originalArtists: ["土岐麻子"],
            coverPerformers: ["花譜"],
            uploader: "花譜 - KAF",
            language: "ja",
            aliases: ["夏夜的魔法"],
            lyricSearchQueries: NormalizedTrackMetadata.lyricSearchQueries(
                canonicalTitle: "夏夜のマジック",
                originalArtists: ["土岐麻子"],
                coverPerformers: ["花譜"],
                aliases: ["夏夜的魔法"]),
            isCover: true,
            confidence: 0.94,
            needsReview: false,
            serviceVersion: "test")

        XCTAssertEqual(metadata.displayArtist(fallback: "UP"), "花譜（翻唱） · 原唱：土岐麻子")
        XCTAssertEqual(metadata.coverVersionQueries(), ["夏夜のマジック 花譜"])
        XCTAssertEqual(metadata.originalVersionQueries().first, "夏夜のマジック 土岐麻子")
        XCTAssertFalse(metadata.lyricSearchQueries.contains { $0.contains("夏夜的魔法") })
    }

    func testLyricSearchUsesCleanedJapaneseTitleNotChineseTranslation() {
        let track = Track(
            bvid: "BV1",
            title: "【花譜】日文翻唱《夏夜のマジック/夏夜的魔法》",
            artist: "花譜 - KAF",
            coverURL: nil,
            duration: 246)
        let metadata = NormalizedTrackMetadata(
            canonicalTitle: "夏夜のマジック",
            originalArtists: ["土岐麻子"],
            coverPerformers: ["花譜"],
            uploader: "花譜 - KAF",
            language: "ja",
            aliases: ["夏夜的魔法"],
            lyricSearchQueries: [
                "夏夜のマジック 土岐麻子",
                "夏夜的魔法 土岐麻子",
                "夏夜のマジック",
                "夏夜のマジック 花譜",
                "夏夜的魔法 花譜",
            ],
            isCover: true,
            confidence: 0.94,
            needsReview: false,
            serviceVersion: "test")

        XCTAssertEqual(LyricsAutoMatchGate.searchTitle(track: track, metadata: metadata), "夏夜のマジック")
        XCTAssertEqual(LyricsAutoMatchGate.searchTitle(track: track, metadata: nil), "夏夜のマジック")
        XCTAssertEqual(
            LyricsAutoMatchGate.defaultSearchKeyword(
                track: track,
                metadata: metadata,
                lastKeyword: "夏夜的魔法 土岐麻子"),
            "夏夜のマジック")
        XCTAssertEqual(
            LyricsAutoMatchGate.defaultSearchKeyword(
                track: track,
                metadata: metadata,
                lastKeyword: "夏夜のマジック 土岐麻子"),
            "夏夜のマジック 土岐麻子")
        XCTAssertEqual(
            LyricsAutoMatchGate.preferredSearchTitle(
                canonicalTitle: "夏夜的魔法",
                aliases: ["夏夜のマジック"]),
            "夏夜のマジック")
    }

    func testKanjiLatinTitleIsTreatedAsJapaneseAndMatchesAmpersandVariants() {
        let track = Track(
            bvid: "BVAIZU",
            title: "【cover】You＆合図 / 音乃瀬奏",
            artist: "cover UP",
            coverURL: nil,
            duration: 176)
        XCTAssertTrue(LyricsAutoMatchGate.containsJapaneseWriting("You＆合図"))
        XCTAssertFalse(LyricsAutoMatchGate.containsJapaneseKana("You＆合図"))
        XCTAssertTrue(LyricsVersionClassifier.isJapaneseContext(track: track, metadata: nil))
        XCTAssertTrue(LyricsAutoMatchGate.titleMatches("You & 合図", expected: "You＆合図"))
        XCTAssertEqual(
            LRCLibLyricsProvider.searchQueryItems(title: "You＆合図").map(\.name),
            ["q"])
    }

    func testOffsetEstimatorUsesLyricPlacementInsteadOfBlindDurationDelta() {
        let earlyVocal = [1.5, 48.0, 92.0, 160.0, 230.0]
        XCTAssertEqual(
            LyricsOffsetEstimator.suggestedOffsetMilliseconds(
                trackDuration: 250,
                lyricsDuration: 246,
                lineStarts: earlyVocal,
                timingKind: .line),
            -4_000)
        XCTAssertNil(
            LyricsOffsetEstimator.suggestedOffsetMilliseconds(
                trackDuration: 250,
                lyricsDuration: 246,
                lineStarts: [14.0, 48.0, 92.0, 160.0, 228.0],
                timingKind: .line),
            "Extra video time after a normal intro is more likely outro, not a forced shift.")
        XCTAssertEqual(
            LyricsOffsetEstimator.suggestedOffsetMilliseconds(
                trackDuration: 240,
                lyricsDuration: 246,
                lineStarts: [12.0, 48.0, 92.0, 160.0, 230.0],
                timingKind: .line),
            6_000)
        XCTAssertNil(
            LyricsOffsetEstimator.suggestedOffsetMilliseconds(
                trackDuration: 246,
                lyricsDuration: 246,
                lineStarts: earlyVocal,
                timingKind: .line))
        XCTAssertNil(
            LyricsOffsetEstimator.suggestedOffsetMilliseconds(
                trackDuration: 247,
                lyricsDuration: 246,
                lineStarts: earlyVocal,
                timingKind: .line))
        XCTAssertNil(
            LyricsOffsetEstimator.suggestedOffsetMilliseconds(
                trackDuration: 250,
                lyricsDuration: 246,
                lineStarts: earlyVocal,
                timingKind: .none))
        XCTAssertNil(
            LyricsOffsetEstimator.suggestedOffsetMilliseconds(
                trackDuration: 250,
                lyricsDuration: 246,
                lineStarts: [0, 5, 10],
                timingKind: .line))
    }

    func testOffsetEstimatorAlignsLyricOnsetsToAudioEnergy() {
        let hop = LyricsOffsetEstimator.hop
        var rms = Array(repeating: 0.012, count: 400)
        func bump(_ time: Double) {
            let center = Int((time / hop).rounded())
            for delta in -3...3 where rms.indices.contains(center + delta) {
                rms[center + delta] += 0.45 * (1 - Double(abs(delta)) / 4)
            }
        }
        bump(4)
        bump(8)
        bump(12)
        bump(16)
        let suggestion = LyricsOffsetEstimator.suggest(
            trackDuration: 200,
            lyricsDuration: 200,
            lineStarts: [1.0, 5.0, 9.0, 13.0],
            timingKind: .line,
            audioRMS: rms)
        XCTAssertEqual(Double(suggestion?.offsetMilliseconds ?? 0), -3_000, accuracy: 200)
        XCTAssertGreaterThan(suggestion?.confidence ?? 0, 0.42)
    }

    func testOfficialDisplayStaysOriginalArtist() {
        let metadata = NormalizedTrackMetadata(
            canonicalTitle: "アイドル",
            originalArtists: ["YOASOBI"],
            coverPerformers: [],
            uploader: "YOASOBI",
            language: "ja",
            aliases: [],
            lyricSearchQueries: ["アイドル YOASOBI"],
            isCover: false,
            confidence: 0.98,
            needsReview: false,
            serviceVersion: "test")

        XCTAssertEqual(metadata.displayArtist(fallback: "UP"), "YOASOBI")
        XCTAssertEqual(metadata.applying(to: Track(
            bvid: "BV1",
            title: "YOASOBI「アイドル」Official Music Video",
            artist: "YOASOBI",
            coverURL: nil,
            duration: 213)).artist, "YOASOBI")
    }

    func testVersionScopedRankingPutsCoverAheadOfOriginalWhenPreferringCover() {
        let cover = LyricsSearchResult(
            provider: .netease,
            id: "cover",
            title: "夏夜のマジック",
            artist: "花譜",
            album: nil,
            duration: 246,
            artworkID: nil)
        let original = LyricsSearchResult(
            provider: .netease,
            id: "original",
            title: "夏夜のマジック",
            artist: "土岐麻子",
            album: nil,
            duration: 245,
            artworkID: nil)

        let ranked = MetingLyricsClient.rankedCandidates(
            [original, cover],
            keyword: "夏夜のマジック 花譜",
            originalArtists: ["土岐麻子"],
            coverPerformers: ["花譜"],
            duration: 246,
            preferCover: true)

        XCTAssertEqual(ranked.map(\.id), ["cover", "original"])
    }

    func testRankingPrefersDurationMatchOverLongerSameTitle() {
        let live = LyricsSearchResult(
            provider: .netease,
            id: "live",
            title: "アイドル",
            artist: "YOASOBI",
            album: nil,
            duration: 312,
            artworkID: nil)
        let official = LyricsSearchResult(
            provider: .tencent,
            id: "official",
            title: "アイドル",
            artist: "YOASOBI",
            album: nil,
            duration: 213,
            artworkID: nil)
        let ranked = MetingLyricsClient.rankedCandidates(
            [live, official],
            keyword: "アイドル YOASOBI",
            originalArtists: ["YOASOBI"],
            duration: 213)
        XCTAssertEqual(ranked.map(\.id), ["official", "live"])
    }

    func testAggregatedSearchKeepsEachSourceAndShowsStableIDs() {
        let netease = LyricsSearchResult(
            provider: .netease,
            id: "1",
            title: "You & 合図",
            artist: "音乃瀬奏",
            album: nil,
            duration: 159,
            artworkID: nil)
        let lrclib = LyricsSearchResult(
            provider: .lrclib,
            id: "35193797",
            title: "You & 合図",
            artist: "音乃瀬奏",
            album: nil,
            duration: 159,
            artworkID: nil)
        let duplicate = LyricsSearchResult(
            provider: .netease,
            id: "1",
            title: "You＆合図",
            artist: "音乃瀬奏",
            album: nil,
            duration: 159,
            artworkID: nil)
        let merged = MetingLyricsClient.aggregatedCandidates(
            [[netease, duplicate], [lrclib]],
            keyword: "You＆合図",
            originalArtists: ["音乃瀬奏"],
            duration: 159)
        XCTAssertEqual(merged.map(\.stableID), ["netease:1", "lrclib:35193797"])
        XCTAssertEqual(Set(merged.map(\.provider.displayName)), ["网易云", "LRCLIB"])
    }

    func testTextOnlyFallbackFollowsPlaybackWhenDurationMatches() {
        let close = LyricsTimingPolicy.resolve(
            scope: .textOnlyFallback,
            trackDuration: 159,
            candidateDuration: 159,
            hasWordSync: false,
            hasLineSync: true)
        XCTAssertEqual(close.timingKind, .line)
        XCTAssertTrue(close.followsPlayback)
        XCTAssertTrue(close.needsConfirmation)

        let document = LyricsDocument(
            result: LyricsSearchResult(
                provider: .lrclib,
                id: "1",
                title: "You & 合図",
                artist: "音乃瀬奏",
                album: nil,
                duration: 159,
                artworkID: nil),
            lyric: "[00:12.00]合図",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil)
            .applying(policy: close)
        XCTAssertEqual(document.timingKind, .line)
        XCTAssertTrue(document.followsPlayback)
        XCTAssertEqual(document.bannerText, "歌词 · 待确认")

        let far = LyricsTimingPolicy.resolve(
            scope: .textOnlyFallback,
            trackDuration: 159,
            candidateDuration: 312,
            hasWordSync: false,
            hasLineSync: true)
        XCTAssertEqual(far.timingKind, .line)
        XCTAssertFalse(far.followsPlayback)
        XCTAssertEqual(
            LyricsDocument(
                result: LyricsSearchResult(
                    provider: .lrclib,
                    id: "2",
                    title: "You & 合図",
                    artist: "音乃瀬奏",
                    album: nil,
                    duration: 312,
                    artworkID: nil),
                lyric: "[00:12.00]合図",
                translatedLyric: nil,
                romanizedLyric: nil,
                karaokeLyric: nil,
                karaokeTranslatedLyric: nil)
                .applying(policy: far)
                .bannerText,
            "歌词 · 不跟随播放")
    }

    func testAdoptionPrefersTimedLyricsInsideTheSameIdentityRank() {
        let plain = LyricsSearchResult(
            provider: .netease,
            id: "plain",
            title: "アイドル",
            artist: "YOASOBI",
            album: nil,
            duration: 213,
            artworkID: nil)
        let synced = LyricsSearchResult(
            provider: .tencent,
            id: "synced",
            title: "アイドル",
            artist: "YOASOBI",
            album: nil,
            duration: 213,
            artworkID: nil)
        let fallbackTimed = LyricsSearchResult(
            provider: .lrclib,
            id: "other",
            title: "アイドル",
            artist: "Various",
            album: nil,
            duration: 213,
            artworkID: nil)
        let documents: [String: LyricsDocument] = [
            synced.stableID: LyricsDocument(
                result: synced,
                lyric: "[00:12.00]青",
                translatedLyric: nil,
                romanizedLyric: nil,
                karaokeLyric: nil,
                karaokeTranslatedLyric: nil),
            fallbackTimed.stableID: LyricsDocument(
                result: fallbackTimed,
                lyric: "[00:01.00]青",
                translatedLyric: nil,
                romanizedLyric: nil,
                karaokeLyric: nil,
                karaokeTranslatedLyric: nil),
        ]
        let ordered = LyricsAdoption.orderedForFetch(
            [plain, fallbackTimed, synced],
            documents: documents,
            originalArtists: ["YOASOBI"],
            coverPerformers: [],
            preferCover: false)
        XCTAssertEqual(ordered.map(\.id), ["synced", "plain", "other"])

        let picked = LyricsAdoption.bestDocument(in: [
            (0, documents[synced.stableID]!),
            (0, LyricsDocument(
                result: plain,
                lyric: "青",
                translatedLyric: nil,
                romanizedLyric: nil,
                karaokeLyric: nil,
                karaokeTranslatedLyric: nil)),
            (4, documents[fallbackTimed.stableID]!),
        ])
        XCTAssertEqual(picked?.result.id, "synced")
    }

    func testVerifiedWordCandidatesSortFirstWithinTheSameVersionScope() {
        let plain = LyricsSearchResult(
            provider: .netease,
            id: "plain",
            title: "アイドル",
            artist: "YOASOBI",
            album: nil,
            duration: 213,
            artworkID: nil)
        let line = LyricsSearchResult(
            provider: .lrclib,
            id: "line",
            title: "アイドル",
            artist: "YOASOBI",
            album: nil,
            duration: 213,
            artworkID: nil,
            timingKindHint: .line)
        let word = LyricsSearchResult(
            provider: .kugou,
            id: "word",
            title: "アイドル",
            artist: "YOASOBI",
            album: nil,
            duration: 213,
            artworkID: nil,
            timingKindHint: .word)

        let ranked = MetingLyricsClient.rankedCandidates(
            [plain, line, word],
            keyword: "アイドル-YOASOBI",
            originalArtists: ["YOASOBI"],
            duration: 213)

        XCTAssertEqual(ranked.map(\.id), ["word", "plain", "line"])
    }

    func testDurationMismatchedWordCandidateDoesNotReceiveReliablePriority() {
        let exactDuration = LyricsSearchResult(
            provider: .netease,
            id: "exact-line",
            title: "Melt -10th ANNIVERSARY MIX-",
            artist: "やなぎなぎ",
            album: nil,
            duration: 616,
            artworkID: nil,
            timingKindHint: .line)
        let shortWord = LyricsSearchResult(
            provider: .kugou,
            id: "short-word",
            title: "Melt -10th ANNIVERSARY MIX-",
            artist: "やなぎなぎ",
            album: nil,
            duration: 305,
            artworkID: nil,
            timingKindHint: .word)

        let ranked = MetingLyricsClient.rankedCandidates(
            [shortWord, exactDuration],
            keyword: "Melt -10th ANNIVERSARY MIX--やなぎなぎ",
            coverPerformers: ["やなぎなぎ"],
            duration: 616,
            preferCover: true)

        XCTAssertEqual(ranked.map(\.id), ["exact-line", "short-word"])
        XCTAssertFalse(MetingLyricsClient.hasReliableWordTiming(
            shortWord,
            expectedDuration: 616))
    }

    func testVerifiedWordHintCannotOutrankTheRequestedVersion() {
        let exactCover = LyricsSearchResult(
            provider: .netease,
            id: "cover-line",
            title: "パレード",
            artist: "花譜",
            album: nil,
            duration: 240,
            artworkID: nil)
        let originalWord = LyricsSearchResult(
            provider: .kugou,
            id: "original-word",
            title: "パレード",
            artist: "ヨルシカ",
            album: nil,
            duration: 240,
            artworkID: nil,
            timingKindHint: .word)

        let ranked = MetingLyricsClient.rankedCandidates(
            [originalWord, exactCover],
            keyword: "パレード",
            originalArtists: ["ヨルシカ"],
            coverPerformers: ["花譜"],
            duration: 240,
            preferCover: true)

        XCTAssertEqual(ranked.map(\.id), ["cover-line", "original-word"])
    }

    func testManualAggregationKeepsVerifiedWordMetadataWhenCatalogIDDuplicates() {
        let verified = LyricsSearchResult(
            provider: .kugou,
            id: "same-id",
            title: "アイドル",
            artist: "YOASOBI",
            album: nil,
            duration: 213,
            artworkID: nil,
            timingKindHint: .word)
        let ordinary = LyricsSearchResult(
            provider: .kugou,
            id: "same-id",
            title: "アイドル",
            artist: "YOASOBI",
            album: nil,
            duration: 213,
            artworkID: nil)

        let ranked = MetingLyricsClient.aggregatedCandidates(
            [[verified], [ordinary]],
            keyword: "アイドル-YOASOBI",
            originalArtists: ["YOASOBI"],
            duration: 213)

        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.timingKindHint, .word)
    }

    func testAutoMatchRejectsAnotherSongByTheSameCoverPerformer() {
        let wrong = LyricsSearchResult(
            provider: .netease,
            id: "wrong",
            title: "届かない恋",
            artist: "花譜",
            album: nil,
            duration: 246,
            artworkID: nil)
        let titles = LyricsAutoMatchGate.expectedTitles(
            track: Track(
                bvid: "BV1",
                title: "【花譜】日文翻唱《夏夜のマジック/夏夜的魔法》",
                artist: "花譜 - KAF",
                coverURL: nil,
                duration: 246),
            metadata: NormalizedTrackMetadata(
                canonicalTitle: "夏夜のマジック",
                originalArtists: ["土岐麻子"],
                coverPerformers: ["花譜"],
                uploader: "花譜 - KAF",
                language: "ja",
                aliases: ["夏夜的魔法"],
                lyricSearchQueries: [],
                isCover: true,
                confidence: 0.94,
                needsReview: false,
                serviceVersion: "test"))

        XCTAssertFalse(LyricsAutoMatchGate.accepts(wrong, titles: titles))
        XCTAssertTrue(LyricsAutoMatchGate.titleMatches("夏夜のマジック (Cover)", expected: "夏夜のマジック"))
        XCTAssertTrue(LyricsAutoMatchGate.titleMatches("夏夜的魔法", expected: "夏夜のマジック"))
        XCTAssertFalse(LyricsAutoMatchGate.titleMatches("夜", expected: "夏夜のマジック"))
        XCTAssertTrue(LyricsAutoMatchGate.isHighConfidenceCover(
            LyricsSearchResult(
                provider: .netease,
                id: "cover",
                title: "夏夜のマジック",
                artist: "花譜",
                album: nil,
                duration: 246,
                artworkID: nil),
            titles: titles,
            coverPerformers: ["花譜"],
            trackDuration: 246))
        XCTAssertFalse(LyricsAutoMatchGate.isHighConfidenceCover(
            LyricsSearchResult(
                provider: .netease,
                id: "cover-far",
                title: "夏夜のマジック",
                artist: "花譜",
                album: nil,
                duration: 312,
                artworkID: nil),
            titles: titles,
            coverPerformers: ["花譜"],
            trackDuration: 246))
        XCTAssertTrue(LyricsAutoMatchGate.isHighConfidenceCover(
            LyricsSearchResult(
                provider: .netease,
                id: "cover-unknown",
                title: "夏夜のマジック",
                artist: "花譜",
                album: nil,
                duration: nil,
                artworkID: nil),
            titles: titles,
            coverPerformers: ["花譜"],
            trackDuration: 246))
        XCTAssertTrue(LyricsAutoMatchGate.isHighConfidenceCover(
            LyricsSearchResult(
                provider: .netease,
                id: "cover-pad",
                title: "夏夜のマジック",
                artist: "花譜",
                album: nil,
                duration: 258,
                artworkID: nil),
            titles: titles,
            coverPerformers: ["花譜"],
            trackDuration: 246))
    }

    @MainActor
    func testResolverSkipsWrongTitleEvenWhenItHasLyricsFirst() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsWrongFirst-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LyricsStore(fileURLForTesting: directory.appendingPathComponent("lyrics.json"))
        let resolver = LyricsResolver(catalog: WrongFirstLyricsCatalog())
        let track = Track(
            bvid: "BVCROSS",
            cid: 1,
            title: "【花譜】日文翻唱《夏夜のマジック/夏夜的魔法》",
            artist: "花譜 - KAF",
            coverURL: nil,
            duration: 246)
        let metadata = NormalizedTrackMetadata(
            canonicalTitle: "夏夜のマジック",
            originalArtists: ["土岐麻子"],
            coverPerformers: ["花譜"],
            uploader: "花譜 - KAF",
            language: "ja",
            aliases: ["夏夜的魔法"],
            lyricSearchQueries: [
                "夏夜のマジック 花譜",
                "夏夜のマジック 土岐麻子",
            ],
            isCover: true,
            confidence: 0.94,
            needsReview: false,
            serviceVersion: "test")

        let result = await resolver.resolve(track: track, metadata: metadata, store: store, ignoreCache: false)

        XCTAssertEqual(result.session.document?.result.id, "right")
        XCTAssertEqual(result.session.document?.result.title, "夏夜のマジック")
    }

    @MainActor
    func testAutomaticPrefersOriginalWhenCoverDurationDoesNotMatch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsPreferOriginal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LyricsStore(fileURLForTesting: directory.appendingPathComponent("lyrics.json"))
        let resolver = LyricsResolver(catalog: CoverAndOriginalLyricsCatalog(coverDuration: 312))
        let track = Track(
            bvid: "BVORIG",
            cid: 1,
            title: "【花譜】日文翻唱《夏夜のマジック/夏夜的魔法》",
            artist: "花譜 - KAF",
            coverURL: nil,
            duration: 246)
        let metadata = NormalizedTrackMetadata(
            canonicalTitle: "夏夜のマジック",
            originalArtists: ["土岐麻子"],
            coverPerformers: ["花譜"],
            uploader: "花譜 - KAF",
            language: "ja",
            aliases: ["夏夜的魔法"],
            lyricSearchQueries: [
                "夏夜のマジック 花譜",
                "夏夜のマジック 土岐麻子",
            ],
            isCover: true,
            confidence: 0.94,
            needsReview: false,
            serviceVersion: "test")

        let result = await resolver.resolve(track: track, metadata: metadata, store: store, ignoreCache: true)

        XCTAssertEqual(result.session.document?.result.id, "original")
        XCTAssertEqual(result.session.document?.result.artist, "土岐麻子")
    }

    @MainActor
    func testAutomaticUsesHighConfidenceCoverWhenDurationMatches() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsHighCover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LyricsStore(fileURLForTesting: directory.appendingPathComponent("lyrics.json"))
        let resolver = LyricsResolver(catalog: CoverAndOriginalLyricsCatalog(coverDuration: 246))
        let track = Track(
            bvid: "BVCOVER",
            cid: 1,
            title: "【花譜】日文翻唱《夏夜のマジック/夏夜的魔法》",
            artist: "花譜 - KAF",
            coverURL: nil,
            duration: 246)
        let metadata = NormalizedTrackMetadata(
            canonicalTitle: "夏夜のマジック",
            originalArtists: ["土岐麻子"],
            coverPerformers: ["花譜"],
            uploader: "花譜 - KAF",
            language: "ja",
            aliases: ["夏夜的魔法"],
            lyricSearchQueries: [
                "夏夜のマジック 花譜",
                "夏夜のマジック 土岐麻子",
            ],
            isCover: true,
            confidence: 0.94,
            needsReview: false,
            serviceVersion: "test")

        let result = await resolver.resolve(track: track, metadata: metadata, store: store, ignoreCache: true)

        XCTAssertEqual(result.session.document?.result.id, "cover")
        XCTAssertEqual(result.session.document?.result.artist, "花譜")
    }

    @MainActor
    func testResolverDoesNotSearchChineseTranslationEvenIfCachedQueriesIncludeIt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsNoZhQuery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LyricsStore(fileURLForTesting: directory.appendingPathComponent("lyrics.json"))
        let catalog = RecordingLyricsCatalog()
        let resolver = LyricsResolver(catalog: catalog)
        let track = Track(
            bvid: "BVZH",
            cid: 1,
            title: "【花譜】日文翻唱《夏夜のマジック/夏夜的魔法》",
            artist: "花譜 - KAF",
            coverURL: nil,
            duration: 246)
        let metadata = NormalizedTrackMetadata(
            canonicalTitle: "夏夜のマジック",
            originalArtists: ["土岐麻子"],
            coverPerformers: ["花譜"],
            uploader: "花譜 - KAF",
            language: "ja",
            aliases: ["夏夜的魔法"],
            lyricSearchQueries: [
                "夏夜的魔法 土岐麻子",
                "夏夜的魔法 花譜",
                "夏夜のマジック 土岐麻子",
            ],
            isCover: true,
            confidence: 0.94,
            needsReview: false,
            serviceVersion: "test")

        _ = await resolver.resolve(track: track, metadata: metadata, store: store, ignoreCache: true)
        let keywords = await catalog.recordedKeywords()

        XCTAssertFalse(keywords.isEmpty)
        XCTAssertFalse(keywords.contains { $0.contains("夏夜的魔法") })
        XCTAssertTrue(keywords.contains { $0.contains("夏夜のマジック") })
        XCTAssertEqual(keywords.first, "夏夜のマジック 花譜")
    }

    @MainActor
    func testResolverDoesNotShiftSyncedLyricsOnFirstMatch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsAutoOffset-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LyricsStore(fileURLForTesting: directory.appendingPathComponent("lyrics.json"))
        let resolver = LyricsResolver(catalog: IntroDelayLyricsCatalog())
        let track = Track(
            bvid: "BVINTRO",
            cid: 1,
            title: "YOASOBI「アイドル」Official Music Video",
            artist: "YOASOBI",
            coverURL: nil,
            duration: 250)
        let metadata = NormalizedTrackMetadata(
            canonicalTitle: "アイドル",
            originalArtists: ["YOASOBI"],
            coverPerformers: [],
            uploader: "YOASOBI",
            language: "ja",
            aliases: [],
            lyricSearchQueries: ["アイドル YOASOBI"],
            isCover: false,
            confidence: 0.98,
            needsReview: false,
            serviceVersion: "test")

        let first = await resolver.resolve(track: track, metadata: metadata, store: store, ignoreCache: true)
        XCTAssertEqual(first.session.offsetMilliseconds, 0)

        await store.updateOffset(800, for: track)
        let second = await resolver.resolve(track: track, metadata: metadata, store: store, ignoreCache: true)
        XCTAssertEqual(second.session.offsetMilliseconds, 800)
    }

    @MainActor
    func testResolverPrefersDurationMatchedCandidateAcrossProviders() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsDurationPick-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LyricsStore(fileURLForTesting: directory.appendingPathComponent("lyrics.json"))
        let resolver = LyricsResolver(catalog: SplitProviderLyricsCatalog())
        let track = Track(
            bvid: "BVDUR",
            cid: 1,
            title: "YOASOBI「アイドル」Official Music Video",
            artist: "YOASOBI",
            coverURL: nil,
            duration: 213)
        let metadata = NormalizedTrackMetadata(
            canonicalTitle: "アイドル",
            originalArtists: ["YOASOBI"],
            coverPerformers: [],
            uploader: "YOASOBI",
            language: "ja",
            aliases: [],
            lyricSearchQueries: ["アイドル YOASOBI"],
            isCover: false,
            confidence: 0.98,
            needsReview: false,
            serviceVersion: "test")

        let result = await resolver.resolve(track: track, metadata: metadata, store: store, ignoreCache: true)
        XCTAssertEqual(result.session.document?.result.id, "official")
        XCTAssertEqual(result.session.document?.result.provider, .tencent)
    }

    @MainActor
    func testResolverPrefersSyncedLyricsOverPlainAtSameIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsPreferSync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LyricsStore(fileURLForTesting: directory.appendingPathComponent("lyrics.json"))
        let resolver = LyricsResolver(catalog: PlainThenSyncedLyricsCatalog())
        let track = Track(
            bvid: "BVSYNC",
            cid: 1,
            title: "YOASOBI「アイドル」Official Music Video",
            artist: "YOASOBI",
            coverURL: nil,
            duration: 213)
        let metadata = NormalizedTrackMetadata(
            canonicalTitle: "アイドル",
            originalArtists: ["YOASOBI"],
            coverPerformers: [],
            uploader: "YOASOBI",
            language: "ja",
            aliases: [],
            lyricSearchQueries: ["アイドル YOASOBI"],
            isCover: false,
            confidence: 0.98,
            needsReview: false,
            serviceVersion: "test")

        let result = await resolver.resolve(track: track, metadata: metadata, store: store, ignoreCache: true)
        XCTAssertEqual(result.session.document?.result.id, "synced")
        XCTAssertEqual(result.session.document?.timingKind, .line)
        XCTAssertEqual(result.session.document?.followsPlayback, true)
    }

    @MainActor
    func testResolverDoesNotTakeTimedFallbackOverMatchingPlainIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsIdentityFirst-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LyricsStore(fileURLForTesting: directory.appendingPathComponent("lyrics.json"))
        let resolver = LyricsResolver(catalog: MatchingPlainAndFallbackTimedCatalog())
        let track = Track(
            bvid: "BVIDENT",
            cid: 1,
            title: "YOASOBI「アイドル」",
            artist: "YOASOBI",
            coverURL: nil,
            duration: 213)
        let metadata = NormalizedTrackMetadata(
            canonicalTitle: "アイドル",
            originalArtists: ["YOASOBI"],
            coverPerformers: [],
            uploader: "YOASOBI",
            language: "ja",
            aliases: [],
            lyricSearchQueries: ["アイドル YOASOBI"],
            isCover: false,
            confidence: 0.98,
            needsReview: false,
            serviceVersion: "test")

        let result = await resolver.resolve(track: track, metadata: metadata, store: store, ignoreCache: true)
        XCTAssertEqual(result.session.document?.result.id, "plain")
        XCTAssertEqual(result.session.document?.timingKind, LyricsTimingKind.none)
    }

    func testLRCLibParsesSyncedJapaneseHitWithoutUsingScoreField() {
        let json = """
        [{"id":77,"trackName":"アイドル","artistName":"YOASOBI","albumName":"","duration":213.2,"instrumental":false,"syncedLyrics":"[00:12.00]青","plainLyrics":"青","score":0.11}]
        """.data(using: .utf8)!
        let hits = LRCLibLyricsProvider.parseSearch(json)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].result.provider, .lrclib)
        XCTAssertEqual(hits[0].result.title, "アイドル")
        XCTAssertEqual(hits[0].result.duration, 213)
        XCTAssertTrue(hits[0].document.hasLineSync)
    }

    func testOriginalOnCoverUsesConfirmationTimingAndDropsLargeDeltaSync() {
        let close = LyricsTimingPolicy.resolve(
            scope: .canonicalOriginal,
            trackDuration: 245,
            candidateDuration: 247,
            hasWordSync: true,
            hasLineSync: true)
        XCTAssertEqual(close.timingKind, .word)
        XCTAssertTrue(close.needsConfirmation)
        XCTAssertTrue(close.followsPlayback)
        XCTAssertFalse(close.appliesToCurrentCover)

        let far = LyricsTimingPolicy.resolve(
            scope: .canonicalOriginal,
            trackDuration: 245,
            candidateDuration: 312,
            hasWordSync: true,
            hasLineSync: true)
        XCTAssertEqual(far.timingKind, .none)
        XCTAssertFalse(far.followsPlayback)

        var document = LyricsDocument(
            result: LyricsSearchResult(
                provider: .netease,
                id: "1",
                title: "夏夜のマジック",
                artist: "土岐麻子",
                album: nil,
                duration: 247,
                artworkID: nil),
            lyric: "[00:01.00]夜",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil)
        document = document.applying(policy: close)
        XCTAssertEqual(document.bannerText, "原唱歌词 · 时间轴待确认")
    }

    func testExactCoverKeepsWordTimingBanner() {
        let policy = LyricsTimingPolicy.resolve(
            scope: .exactCover,
            trackDuration: 246,
            candidateDuration: 246,
            hasWordSync: true,
            hasLineSync: true)
        XCTAssertEqual(policy.timingKind, .word)
        XCTAssertFalse(policy.needsConfirmation)
        let document = LyricsDocument(
            result: LyricsSearchResult(
                provider: .netease,
                id: "2",
                title: "夏夜のマジック",
                artist: "花譜",
                album: nil,
                duration: 246,
                artworkID: nil),
            lyric: "[00:01.00]夜",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: "[1000,800](0,800,0)夜",
            karaokeTranslatedLyric: nil)
            .applying(policy: policy)
        XCTAssertEqual(document.bannerText, "翻唱版 · 精确同步")
    }

    func testExplicitLyricChoiceKeepsSyncAndDoesNotShowPendingBanner() {
        let policy = LyricsTimingPolicy.forExplicitChoice(hasWordSync: false, hasLineSync: true)
        XCTAssertEqual(policy.timingKind, .line)
        XCTAssertFalse(policy.needsConfirmation)
        XCTAssertTrue(policy.followsPlayback)

        let frozen = LyricsTimingPolicy.resolve(
            scope: .canonicalOriginal,
            trackDuration: 245,
            candidateDuration: 312,
            hasWordSync: false,
            hasLineSync: true)
        var document = LyricsDocument(
            result: LyricsSearchResult(
                provider: .netease,
                id: "1",
                title: "夏夜のマジック",
                artist: "土岐麻子",
                album: nil,
                duration: 312,
                artworkID: nil),
            lyric: "[00:01.00]夜",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil)
            .applying(policy: frozen)
        XCTAssertEqual(document.timingKind, .none)
        XCTAssertEqual(document.bannerText, "原唱歌词 · 时间轴待确认")

        document = document.restoringPlaybackTiming()
        XCTAssertEqual(document.timingKind, .line)
        XCTAssertFalse(document.timingNeedsConfirmation)
        XCTAssertNil(document.bannerText)

        let imported = LyricsDocument(
            result: LyricsSearchResult(
                provider: .imported,
                id: "local",
                title: "夏夜のマジック",
                artist: "花譜",
                album: nil,
                duration: 246,
                artworkID: nil),
            lyric: "[00:01.00]夜",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil,
            versionScope: .manual)
        XCTAssertEqual(imported.bannerText, "本地手动歌词")
    }

    @MainActor
    func testUserRequestedOriginalSearchKeepsLineTimingOnCover() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsUserOriginal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LyricsStore(fileURLForTesting: directory.appendingPathComponent("lyrics.json"))
        let resolver = LyricsResolver(catalog: OriginalFarDurationCatalog())
        let track = Track(
            bvid: "BVUSER",
            cid: 1,
            title: "【花譜】日文翻唱《夏夜のマジック》",
            artist: "花譜 - KAF",
            coverURL: nil,
            duration: 200)
        let metadata = NormalizedTrackMetadata(
            canonicalTitle: "夏夜のマジック",
            originalArtists: ["土岐麻子"],
            coverPerformers: ["花譜"],
            uploader: "花譜 - KAF",
            language: "ja",
            aliases: [],
            lyricSearchQueries: ["夏夜のマジック 土岐麻子"],
            isCover: true,
            confidence: 0.94,
            needsReview: false,
            serviceVersion: "test")

        let result = await resolver.resolve(
            track: track,
            metadata: metadata,
            store: store,
            ignoreCache: true,
            scope: .originalRecording)

        XCTAssertEqual(result.session.document?.timingKind, .line)
        XCTAssertEqual(result.session.document?.timingNeedsConfirmation, false)
        XCTAssertNotEqual(result.session.document?.bannerText, "原唱歌词 · 时间轴待确认")
    }

    @MainActor
    func testLyricsStoreMissExpiresAfterSevenDaysAndRespectsPartKeys() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsMiss-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LyricsStore(fileURLForTesting: directory.appendingPathComponent("lyrics.json"))
        let first = Track(bvid: "BVPART", cid: 1, title: "P1", artist: "A", coverURL: nil, duration: 120)
        let second = Track(bvid: "BVPART", cid: 2, title: "P2", artist: "A", coverURL: nil, duration: 130)

        await store.saveMiss(for: first, now: Date())
        await store.save(
            document: LyricsDocument(
                result: LyricsSearchResult(
                    provider: .imported,
                    id: "p2",
                    title: "P2",
                    artist: "A",
                    album: nil,
                    duration: 130,
                    artworkID: nil),
                lyric: "plain",
                translatedLyric: nil,
                romanizedLyric: nil,
                karaokeLyric: nil,
                karaokeTranslatedLyric: nil,
                versionScope: .manual,
                timingKind: .none),
            offsetMilliseconds: 0,
            for: second)

        let fresh = await store.entry(for: first)
        XCTAssertTrue(fresh?.isActiveMiss() == true)
        XCTAssertNil(fresh?.document)
        let otherPart = await store.entry(for: second)
        XCTAssertEqual(otherPart?.document?.lyric, "plain")

        let expired = Date().addingTimeInterval(LyricsStore.missCacheTTL + 10)
        XCTAssertFalse(fresh?.isActiveMiss(at: expired) == true)
    }

    @MainActor
    func testCachedPrecisionHostLyricsDiscardStaleManualOffset() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrecisionHostOffset-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LyricsStore(fileURLForTesting: directory.appendingPathComponent("lyrics.json"))
        let track = Track(
            bvid: "BVMELT",
            cid: 28663450,
            title: "メルト",
            artist: "ryo",
            coverURL: nil,
            duration: 308)
        let document = LyricsDocument(
            result: LyricsSearchResult(
                provider: .precisionHost,
                id: "melt-v2",
                title: "メルト",
                artist: "ryo",
                album: nil,
                duration: 308,
                artworkID: nil),
            lyric: "[00:03.00]メルト",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: "[3000,1000]<0,250,0>メ<250,250,0>ル<500,500,0>ト",
            karaokeTranslatedLyric: nil,
            timingKind: .word)
        await store.save(
            document: document,
            offsetMilliseconds: -10_000,
            offsetIsUserSet: true,
            for: track)
        let resolver = LyricsResolver(catalog: EmptyLyricsCatalog())

        let resolution = await resolver.resolve(
            track: track,
            metadata: nil,
            store: store,
            ignoreCache: false)

        XCTAssertEqual(resolution.session.document?.result.provider, .precisionHost)
        XCTAssertEqual(resolution.session.offsetMilliseconds, 0)
        XCTAssertFalse(resolution.session.offsetIsUserSet)
        let repaired = await store.entry(for: track)
        XCTAssertEqual(repaired?.offsetMilliseconds, 0)
        XCTAssertFalse(repaired?.offsetIsUserSet == true)
        XCTAssertEqual(resolution.networkRequests, 0)
    }

    @MainActor
    func testResolverSkipsNetworkOnSecondPlayAndHonorsMissCache() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsResolver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LyricsStore(fileURLForTesting: directory.appendingPathComponent("lyrics.json"))
        let catalog = CountingLyricsCatalog()
        let resolver = LyricsResolver(catalog: catalog)
        let track = Track(bvid: "BVLYRIC2", cid: 7, title: "アイドル", artist: "YOASOBI", coverURL: nil, duration: 213)
        let metadata = NormalizedTrackMetadata(
            canonicalTitle: "アイドル",
            originalArtists: ["YOASOBI"],
            coverPerformers: [],
            uploader: "YOASOBI",
            language: "ja",
            aliases: [],
            lyricSearchQueries: ["アイドル YOASOBI"],
            isCover: false,
            confidence: 0.99,
            needsReview: false,
            serviceVersion: "test")

        let first = await resolver.resolve(track: track, metadata: metadata, store: store, ignoreCache: false)
        XCTAssertEqual(first.session.document?.result.id, "hit")
        XCTAssertGreaterThan(first.networkRequests, 0)
        let afterFirst = await catalog.callCount()
        XCTAssertGreaterThan(afterFirst, 0)

        let second = await resolver.resolve(track: track, metadata: metadata, store: store, ignoreCache: false)
        XCTAssertTrue(second.fromCache)
        XCTAssertEqual(second.networkRequests, 0)
        let afterSecond = await catalog.callCount()
        XCTAssertEqual(afterSecond, afterFirst)

        let missTrack = Track(bvid: "BVMISS", cid: 1, title: "none", artist: "none", coverURL: nil, duration: 90)
        let emptyCatalog = EmptyLyricsCatalog()
        let missResolver = LyricsResolver(catalog: emptyCatalog)
        let miss = await missResolver.resolve(track: missTrack, metadata: nil, store: store, ignoreCache: false)
        XCTAssertNil(miss.session.document)
        let cachedMiss = await missResolver.resolve(track: missTrack, metadata: nil, store: store, ignoreCache: false)
        XCTAssertTrue(cachedMiss.fromCache)
        XCTAssertTrue(cachedMiss.session.isMissCached)
        XCTAssertEqual(cachedMiss.networkRequests, 0)
    }

    @MainActor
    func testResolverMatchesOfficialSongWithoutMetadataByTitle() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsResolverNoMeta-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LyricsStore(fileURLForTesting: directory.appendingPathComponent("lyrics.json"))
        let resolver = LyricsResolver(catalog: CountingLyricsCatalog())
        let track = Track(
            bvid: "BVNOMETA",
            cid: 3,
            title: "YOASOBI「アイドル」Official Music Video",
            artist: "搬运UP",
            coverURL: nil,
            duration: 213)

        let result = await resolver.resolve(track: track, metadata: nil, store: store, ignoreCache: false)

        XCTAssertEqual(result.session.document?.result.id, "hit")
        XCTAssertEqual(result.session.document?.result.title, "アイドル")
    }

    func testOriginalLyricsWithoutDurationStayUnsynced() {
        let policy = LyricsTimingPolicy.resolve(
            scope: .canonicalOriginal,
            trackDuration: 245,
            candidateDuration: nil,
            hasWordSync: false,
            hasLineSync: true)
        XCTAssertEqual(policy.timingKind, .none)
        XCTAssertFalse(policy.followsPlayback)
    }

    @MainActor
    func testLyricsStoreDropsRetiredBilibiliSubtitleEntries() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsDropBili-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("lyrics.json")
        let track = Track(
            bvid: "BVSUB",
            cid: 1,
            title: "口白",
            artist: "UP",
            coverURL: nil,
            duration: 120)
        let polluted = StoredLyricsEntry(
            trackKey: track.key,
            document: LyricsDocument(
                result: LyricsSearchResult(
                    provider: .biliSubtitle,
                    id: "\(track.bvid)#1",
                    title: track.title,
                    artist: track.artist,
                    album: nil,
                    duration: track.duration,
                    artworkID: nil),
                lyric: "[00:01.00]大家好",
                translatedLyric: nil,
                romanizedLyric: nil,
                karaokeLyric: nil,
                karaokeTranslatedLyric: nil),
            offsetMilliseconds: 0,
            updatedAt: Date(),
            missExpiresAt: nil)
        try JSONEncoder().encode([polluted]).write(to: fileURL)

        let store = LyricsStore(fileURLForTesting: fileURL)
        let entry = await store.entry(for: track)

        XCTAssertNil(entry)
        XCTAssertTrue(store.storedEntriesForTesting.isEmpty)
    }

    func testAMLLParserKeepsTranslationAndRomanizationOffTheMainLine() {
        let ttml = """
        <div>
        <p begin="00:00:01.00" end="00:00:03.00">
        <span begin="00:00:01.00" end="00:00:02.00">夏夜</span>
        <span begin="00:00:02.00" end="00:00:03.00">のマジック</span>
        <span ttm:role="x-translation">夏夜的魔法</span>
        <span ttm:role="x-romanization">natsu yo no magic</span>
        </p>
        </div>
        """
        let parsed = AMLLTTMLParser.parse(ttml)
        XCTAssertTrue(parsed.lyric.contains("夏夜のマジック"))
        XCTAssertFalse(parsed.lyric.contains("夏夜的魔法"))
        XCTAssertEqual(parsed.translation?.contains("夏夜的魔法"), true)
        XCTAssertEqual(parsed.romanization?.contains("natsu yo no magic"), true)
        XCTAssertNotNil(parsed.karaoke)
    }

    func testBracketTagsAreNotTreatedAsSyncedLyrics() {
        XCTAssertFalse(LyricsDocument.containsLRCTimestamps("[ar:土岐麻子]\n歌詞だけ"))
        XCTAssertTrue(LyricsDocument.containsLRCTimestamps("[00:12.00]夜が明ける"))
    }
}

private actor CountingLyricsCatalog: LyricsCatalogSearching {
    private var calls = 0

    func search(keyword: String, provider: LyricsProvider) async throws -> [LyricsSearchResult] {
        calls += 1
        return [
            LyricsSearchResult(
                provider: provider,
                id: "hit",
                title: "アイドル",
                artist: "YOASOBI",
                album: nil,
                duration: 213,
                artworkID: nil),
        ]
    }

    func fetchLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        calls += 1
        return LyricsDocument(
            result: result,
            lyric: "[00:01.00]アイドル",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil)
    }

    func callCount() -> Int { calls }
}

private actor WrongFirstLyricsCatalog: LyricsCatalogSearching {
    func search(keyword: String, provider: LyricsProvider) async throws -> [LyricsSearchResult] {
        [
            LyricsSearchResult(
                provider: provider,
                id: "wrong",
                title: "届かない恋",
                artist: "花譜",
                album: nil,
                duration: 240,
                artworkID: nil),
            LyricsSearchResult(
                provider: provider,
                id: "right",
                title: "夏夜のマジック",
                artist: "花譜",
                album: nil,
                duration: 246,
                artworkID: nil),
        ]
    }

    func fetchLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        LyricsDocument(
            result: result,
            lyric: result.id == "wrong" ? "[00:01.00]別の歌" : "[00:01.00]夏夜のマジック",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil)
    }
}

private actor OriginalFarDurationCatalog: LyricsCatalogSearching {
    func search(keyword: String, provider: LyricsProvider) async throws -> [LyricsSearchResult] {
        [
            LyricsSearchResult(
                provider: provider,
                id: "original",
                title: "夏夜のマジック",
                artist: "土岐麻子",
                album: nil,
                duration: 400,
                artworkID: nil),
        ]
    }

    func fetchLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        LyricsDocument(
            result: result,
            lyric: "[00:01.00]夜が明ける",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil)
    }
}

private actor CoverAndOriginalLyricsCatalog: LyricsCatalogSearching {
    let coverDuration: Int

    init(coverDuration: Int) {
        self.coverDuration = coverDuration
    }

    func search(keyword: String, provider: LyricsProvider) async throws -> [LyricsSearchResult] {
        if keyword.contains("花譜") {
            return [
                LyricsSearchResult(
                    provider: provider,
                    id: "cover",
                    title: "夏夜のマジック",
                    artist: "花譜",
                    album: nil,
                    duration: coverDuration,
                    artworkID: nil),
            ]
        }
        return [
            LyricsSearchResult(
                provider: provider,
                id: "original",
                title: "夏夜のマジック",
                artist: "土岐麻子",
                album: nil,
                duration: 246,
                artworkID: nil),
        ]
    }

    func fetchLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        LyricsDocument(
            result: result,
            lyric: result.id == "cover" ? "[00:01.00]花譜カバー" : "[00:01.00]原唱",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil)
    }
}

private actor IntroDelayLyricsCatalog: LyricsCatalogSearching {
    func search(keyword: String, provider: LyricsProvider) async throws -> [LyricsSearchResult] {
        [
            LyricsSearchResult(
                provider: provider,
                id: "idol",
                title: "アイドル",
                artist: "YOASOBI",
                album: nil,
                duration: 246,
                artworkID: nil),
        ]
    }

    func fetchLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        LyricsDocument(
            result: result,
            lyric: "[00:01.50]青\n[00:48.00]空\n[01:32.00]に\n[02:40.00]歌\n[03:50.00]え",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil)
    }
}

private actor SplitProviderLyricsCatalog: LyricsCatalogSearching {
    func search(keyword: String, provider: LyricsProvider) async throws -> [LyricsSearchResult] {
        switch provider {
        case .netease:
            return [
                LyricsSearchResult(
                    provider: .netease,
                    id: "live",
                    title: "アイドル",
                    artist: "YOASOBI",
                    album: nil,
                    duration: 312,
                    artworkID: nil),
            ]
        case .tencent:
            return [
                LyricsSearchResult(
                    provider: .tencent,
                    id: "official",
                    title: "アイドル",
                    artist: "YOASOBI",
                    album: nil,
                    duration: 213,
                    artworkID: nil),
            ]
        default:
            return []
        }
    }

    func fetchLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        LyricsDocument(
            result: result,
            lyric: result.id == "official" ? "[00:12.00]青" : "[00:01.00]ライブ",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil)
    }
}

private actor PlainThenSyncedLyricsCatalog: LyricsCatalogSearching {
    func search(keyword: String, provider: LyricsProvider) async throws -> [LyricsSearchResult] {
        switch provider {
        case .netease:
            return [
                LyricsSearchResult(
                    provider: .netease,
                    id: "plain",
                    title: "アイドル",
                    artist: "YOASOBI",
                    album: nil,
                    duration: 213,
                    artworkID: nil),
            ]
        case .tencent:
            return [
                LyricsSearchResult(
                    provider: .tencent,
                    id: "synced",
                    title: "アイドル",
                    artist: "YOASOBI",
                    album: nil,
                    duration: 213,
                    artworkID: nil),
            ]
        default:
            return []
        }
    }

    func fetchLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        LyricsDocument(
            result: result,
            lyric: result.id == "synced" ? "[00:12.00]青" : "青",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil)
    }
}

private actor MatchingPlainAndFallbackTimedCatalog: LyricsCatalogSearching {
    func search(keyword: String, provider: LyricsProvider) async throws -> [LyricsSearchResult] {
        switch provider {
        case .netease:
            return [
                LyricsSearchResult(
                    provider: .netease,
                    id: "plain",
                    title: "アイドル",
                    artist: "YOASOBI",
                    album: nil,
                    duration: 213,
                    artworkID: nil),
            ]
        case .kugou:
            return [
                LyricsSearchResult(
                    provider: .kugou,
                    id: "fallback",
                    title: "アイドル",
                    artist: "Various Artists",
                    album: nil,
                    duration: 213,
                    artworkID: nil),
            ]
        default:
            return []
        }
    }

    func fetchLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        LyricsDocument(
            result: result,
            lyric: result.id == "fallback" ? "[00:01.00]青" : "青",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil)
    }
}

private actor RecordingLyricsCatalog: LyricsCatalogSearching {
    private var keywords: [String] = []

    func search(keyword: String, provider: LyricsProvider) async throws -> [LyricsSearchResult] {
        keywords.append(keyword)
        return []
    }

    func fetchLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        throw MetingLyricsClient.ClientError.noLyrics
    }

    func recordedKeywords() -> [String] { keywords }
}

private actor EmptyLyricsCatalog: LyricsCatalogSearching {
    func search(keyword: String, provider: LyricsProvider) async throws -> [LyricsSearchResult] {
        []
    }

    func fetchLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        throw MetingLyricsClient.ClientError.noLyrics
    }
}
