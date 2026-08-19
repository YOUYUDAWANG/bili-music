import XCTest
@testable import BiliMusic

final class SearchModelsTests: XCTestCase {
    func testCacheKeyNormalizesWhitespaceAndCase() {
        let lhs = SearchCacheKey(query: "  Jay   Chou ", mode: .music)
        let rhs = SearchCacheKey(query: "jay chou", mode: .music)
        XCTAssertEqual(lhs, rhs)
    }

    func testModeControlsBiliMusicOnlySearch() {
        XCTAssertEqual(SearchResultMode.allCases, [.music, .expanded])
        XCTAssertTrue(SearchResultMode.music.usesBiliMusicOnlySearch)
        XCTAssertFalse(SearchResultMode.expanded.usesBiliMusicOnlySearch)
        XCTAssertEqual(SearchResultMode.expanded.title, "更多")
    }

    func testSectionsPromoteFirstResultAndSplitMV() {
        let best = Track(typeID: 3, bvid: "BV1", title: "晴天", artist: "周杰伦",
                         coverURL: nil, duration: 269)
        let song = Track(typeID: 3, bvid: "BV2", title: "七里香", artist: "周杰伦",
                         coverURL: nil, duration: 295)
        let mv = Track(typeID: 193, bvid: "BV3", title: "稻香 MV", artist: "周杰伦",
                       coverURL: nil, duration: 260)

        let sections = SearchResultSections.make(from: [best, song, mv])

        XCTAssertEqual(sections.bestMatch?.bvid, "BV1")
        XCTAssertEqual(sections.songs.map(\.bvid), ["BV2"])
        XCTAssertEqual(sections.mvs.map(\.bvid), ["BV3"])
    }

    func testExpandedSearchRejectsObviousNonMusic() {
        let gameplay = Track(typeID: 17, bvid: "BV9", title: "三国杀实况攻略合集", artist: "游戏区UP",
                             coverURL: nil, duration: 320)

        XCTAssertFalse(MusicFilter.isSearchResult(gameplay, query: "三国杀", mode: .expanded))
    }

    func testMusicModeAcceptsMVSignalAsResultSection() {
        let mv = Track(typeID: 193, bvid: "BV3", title: "周杰伦《晴天》Official MV", artist: "周杰伦",
                       coverURL: nil, duration: 269)

        XCTAssertTrue(MusicFilter.isSearchResult(mv, query: "晴天", mode: .music))
    }

    func testTrackTitleFormatterExtractsTitleAndArtistFromNoisyBiliTitles() {
        let quoted = Track(typeID: 193, bvid: "BV3", title: "【4K修复】周杰伦《晴天》Official MV", artist: "音乐UP",
                           coverURL: nil, duration: 269)
        let separated = Track(typeID: 193, bvid: "BV4", title: "YOASOBI - アイドル Official MV", artist: "搬运UP",
                              coverURL: nil, duration: 213)

        XCTAssertEqual(
            TrackTitleFormatter.displayMetadata(for: quoted, clean: true),
            TrackTitleFormatter.DisplayMetadata(title: "晴天", artist: "周杰伦"))
        XCTAssertEqual(
            TrackTitleFormatter.displayMetadata(for: separated, clean: true),
            TrackTitleFormatter.DisplayMetadata(title: "アイドル", artist: "YOASOBI"))
        XCTAssertEqual(
            TrackTitleFormatter.displayMetadata(for: quoted, clean: false),
            TrackTitleFormatter.DisplayMetadata(title: "【4K修复】周杰伦《晴天》Official MV", artist: "音乐UP"))
    }

    func testTrackTitleFormatterDefaultsToOriginalTitles() {
        let defaults = UserDefaults.standard
        let key = TrackTitleFormatter.cleanListTitlesDefaultsKey
        let previous = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let track = Track(typeID: 193, bvid: "BV12", title: "【4K修复】周杰伦《晴天》Official MV", artist: "音乐UP",
                          coverURL: nil, duration: 269)

        XCTAssertFalse(TrackTitleFormatter.shouldCleanListTitles)
        XCTAssertEqual(
            TrackTitleFormatter.displayMetadata(for: track),
            TrackTitleFormatter.DisplayMetadata(title: "【4K修复】周杰伦《晴天》Official MV", artist: "音乐UP"))
    }

    func testTrackTitleFormatterCachesMetadataByTrackContentAndCleaningFlag() {
        TrackTitleFormatter.resetDisplayMetadataCacheForTesting()
        defer { TrackTitleFormatter.resetDisplayMetadataCacheForTesting() }

        let track = Track(typeID: 193, bvid: "BV13", title: "【4K修复】周杰伦《晴天》Official MV", artist: "音乐UP",
                          coverURL: nil, duration: 269)
        let updatedTrack = Track(typeID: 193, bvid: "BV13", title: "陈奕迅《富士山下》Official MV", artist: "另一个UP",
                                 coverURL: nil, duration: 269)

        let cleanedOnce = TrackTitleFormatter.displayMetadata(for: track, clean: true)
        let cleanedTwice = TrackTitleFormatter.displayMetadata(for: track, clean: true)
        let rawOnce = TrackTitleFormatter.displayMetadata(for: track, clean: false)
        let rawTwice = TrackTitleFormatter.displayMetadata(for: track, clean: false)
        let updated = TrackTitleFormatter.displayMetadata(for: updatedTrack, clean: true)

        XCTAssertEqual(cleanedOnce, cleanedTwice)
        XCTAssertEqual(rawOnce, rawTwice)
        XCTAssertEqual(updated, TrackTitleFormatter.DisplayMetadata(title: "富士山下", artist: "陈奕迅"))
        XCTAssertEqual(TrackTitleFormatter.displayMetadataCacheCountForTesting, 3)
        XCTAssertEqual(TrackTitleFormatter.displayMetadataCacheMissesForTesting, 3)
    }

    func testTrackTitleFormatterKeepsAmbiguousTitlesUnchanged() {
        let commentary = Track(typeID: 3, bvid: "BV5", title: "【乐评】周杰伦晴天到底好在哪里", artist: "音乐杂谈UP",
                               coverURL: nil, duration: 360)
        let bracketTitle = Track(typeID: 3, bvid: "BV6", title: "【晴天】周杰伦", artist: "音乐分享UP",
                                 coverURL: nil, duration: 269)

        XCTAssertEqual(
            TrackTitleFormatter.displayMetadata(for: commentary, clean: true),
            TrackTitleFormatter.DisplayMetadata(title: "【乐评】周杰伦晴天到底好在哪里", artist: "音乐杂谈UP"))
        XCTAssertEqual(
            TrackTitleFormatter.displayMetadata(for: bracketTitle, clean: true),
            TrackTitleFormatter.DisplayMetadata(title: "【晴天】周杰伦", artist: "音乐分享UP"))
    }

    func testTrackTitleFormatterUsesBracketOnlyWhenItMatchesFallbackArtist() {
        let artistInBracket = Track(typeID: 3, bvid: "BV7", title: "【周杰伦】晴天 Official MV", artist: "周杰伦",
                                    coverURL: nil, duration: 269)
        let titleInBracket = Track(typeID: 3, bvid: "BV8", title: "【晴天】周杰伦 Official MV", artist: "周杰伦",
                                   coverURL: nil, duration: 269)

        XCTAssertEqual(
            TrackTitleFormatter.displayMetadata(for: artistInBracket, clean: true),
            TrackTitleFormatter.DisplayMetadata(title: "晴天", artist: "周杰伦"))
        XCTAssertEqual(
            TrackTitleFormatter.displayMetadata(for: titleInBracket, clean: true),
            TrackTitleFormatter.DisplayMetadata(title: "晴天", artist: "周杰伦"))
    }

    func testTrackTitleFormatterDoesNotDropLiveInsideRealTitle() {
        let track = Track(typeID: 3, bvid: "BV9", title: "Oasis - Live Forever Official MV", artist: "搬运UP",
                          coverURL: nil, duration: 276)

        XCTAssertEqual(
            TrackTitleFormatter.displayMetadata(for: track, clean: true),
            TrackTitleFormatter.DisplayMetadata(title: "Live Forever", artist: "Oasis"))
    }

    func testTrackTitleFormatterDoesNotStripShortNoiseInsideWords() {
        let track = Track(typeID: 3, bvid: "BV10", title: "Artist - MVP", artist: "搬运UP",
                          coverURL: nil, duration: 210)

        XCTAssertEqual(
            TrackTitleFormatter.displayMetadata(for: track, clean: true),
            TrackTitleFormatter.DisplayMetadata(title: "MVP", artist: "Artist"))
    }

    func testTrackTitleFormatterKeepsNoiseOnlyCleanupOutOfDisplay() {
        let track = Track(typeID: 3, bvid: "BV11", title: "【4K修复】晴天 Official MV", artist: "音乐分享UP",
                          coverURL: nil, duration: 269)

        XCTAssertEqual(
            TrackTitleFormatter.displayMetadata(for: track, clean: true),
            TrackTitleFormatter.DisplayMetadata(title: "【4K修复】晴天 Official MV", artist: "音乐分享UP"))
    }

    func testMetingLyricsProviderUsesKugouForJayAndNeteaseOtherwise() {
        XCTAssertEqual(MetingLyricsClient.preferredProvider(for: "周杰伦 - 晴天"), .kugou)
        XCTAssertEqual(MetingLyricsClient.preferredProvider(for: "YOASOBI アイドル"), .netease)
    }

    func testMetingLyricsSearchKeywordUsesCleanTrackMetadataDirectly() async {
        let track = Track(
            bvid: "BVJAPAN",
            title: "アイドル",
            artist: "YOASOBI",
            coverURL: nil,
            duration: 213)

        let keyword = await MetingLyricsClient().resolveSearchKeyword(for: track)

        XCTAssertEqual(keyword, "アイドル-YOASOBI")
    }

    func testMetingLyricsRanksExactTitleAheadOfSameArtistWrongSong() {
        let wrong = LyricsSearchResult(
            provider: .netease,
            id: "wrong",
            title: "君は水、私は魚",
            artist: "花譜",
            album: nil,
            duration: nil,
            artworkID: nil)
        let exact = LyricsSearchResult(
            provider: .netease,
            id: "exact",
            title: "夏夜のマジック",
            artist: "土岐麻子",
            album: nil,
            duration: nil,
            artworkID: nil)

        let ranked = MetingLyricsClient.rankedCandidates(
            [wrong, exact],
            keyword: "夏夜のマジック-花谱")

        XCTAssertEqual(ranked.map(\.id), ["exact", "wrong"])
    }

    func testLyricsParserPrefersKaraokeWordsAndAlignsTranslation() throws {
        let result = LyricsSearchResult(
            provider: .netease,
            id: "1",
            title: "晴天",
            artist: "周杰伦",
            album: "叶惠美",
            duration: 269,
            artworkID: nil)
        let document = LyricsDocument(
            result: result,
            lyric: "[00:28.95]故事的小黄花",
            translatedLyric: "[00:28.95]The little yellow flower",
            romanizedLyric: nil,
            karaokeLyric: "[28950,1600](0,500,0)故事(500,400,0)的小(900,700,0)黄花",
            karaokeTranslatedLyric: nil)

        let line = try XCTUnwrap(LyricsParser.lines(from: document, duration: 269).first)

        XCTAssertEqual(line.text, "故事的小黄花")
        XCTAssertEqual(line.translation, "The little yellow flower")
        XCTAssertEqual(line.words.map(\.text), ["故事", "的小", "黄花"])
        XCTAssertEqual(try XCTUnwrap(line.words.first).from, 28.95, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(line.words.last).to, 30.55, accuracy: 0.001)
    }

    func testLyricsParserExpandsMultipleLRCTimestamps() {
        let result = LyricsSearchResult(
            provider: .tencent,
            id: "2",
            title: "重复句",
            artist: "歌手",
            album: nil,
            duration: 120,
            artworkID: nil)
        let document = LyricsDocument(
            result: result,
            lyric: "[00:01.00][00:05.50]同一句",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil)

        let lines = LyricsParser.lines(from: document, duration: 120)

        XCTAssertEqual(lines.map(\.text), ["同一句", "同一句"])
        XCTAssertEqual(lines.map(\.from), [1, 5.5])
    }

    @MainActor
    func testLyricsStorePersistsManualSelectionAndOffset() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("lyrics.json")
        let track = Track(bvid: "BVLYRIC", cid: 42, title: "晴天", artist: "周杰伦", coverURL: nil, duration: 269)
        let result = LyricsSearchResult(
            provider: .kugou,
            id: "hash",
            title: "晴天",
            artist: "周杰伦",
            album: "叶惠美",
            duration: 269,
            artworkID: nil)
        let document = LyricsDocument(
            result: result,
            lyric: "[00:01.00]故事的小黄花",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil)
        let store = LyricsStore(fileURLForTesting: fileURL)

        await store.save(document: document, offsetMilliseconds: 500, for: track)

        let reloaded = LyricsStore(fileURLForTesting: fileURL)
        let entry = await reloaded.entry(for: track)
        XCTAssertEqual(entry?.document, document)
        XCTAssertEqual(entry?.offsetMilliseconds, 500)
    }

    func testTrackMetadataStorePersistsAndResolverSkipsSecondOnlineNormalization() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackMetadataStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("track-metadata.json")
        let dirtyTrack = Track(
            bvid: "BVCLEAN",
            cid: 88,
            title: "【4K/中字】YOASOBI《アイドル》Official MV",
            artist: "搬运UP",
            coverURL: nil,
            duration: 213)
        let metadata = NormalizedTrackMetadata(
            canonicalTitle: "アイドル",
            originalArtists: ["YOASOBI"],
            coverPerformers: [],
            uploader: "搬运UP",
            language: "ja",
            aliases: [],
            lyricSearchQueries: ["アイドル YOASOBI"],
            isCover: false,
            confidence: 0.98,
            needsReview: false,
            serviceVersion: "test-v1")
        let firstNormalizer = CountingMetadataNormalizer(result: metadata)
        let firstStore = TrackMetadataStore(fileURLForTesting: fileURL)
        let firstResolver = TrackMetadataResolver(store: firstStore, normalizer: firstNormalizer)

        let first = try await firstResolver.resolve(dirtyTrack)

        XCTAssertEqual(first.title, "アイドル")
        XCTAssertEqual(first.artist, "YOASOBI")
        let firstCallCount = await firstNormalizer.callCount()
        XCTAssertEqual(firstCallCount, 1)

        let secondNormalizer = CountingMetadataNormalizer(result: metadata)
        let reloadedStore = TrackMetadataStore(fileURLForTesting: fileURL)
        let secondResolver = TrackMetadataResolver(store: reloadedStore, normalizer: secondNormalizer)
        let second = try await secondResolver.resolve(dirtyTrack)

        XCTAssertEqual(second.title, "アイドル")
        XCTAssertEqual(second.artist, "YOASOBI")
        let secondCallCount = await secondNormalizer.callCount()
        XCTAssertEqual(secondCallCount, 0)
    }

    @MainActor
    func testSearchStoreRestoresCachedSnapshot() {
        let store = SearchStore()
        let track = Track(typeID: 3, bvid: "BV1", title: "晴天", artist: "周杰伦",
                          coverURL: nil, duration: 269)
        store.storeCachedSnapshotForTesting(
            query: "晴天",
            mode: .music,
            snapshot: SearchCachedSnapshot(
                tracks: [track],
                nextPage: 4,
                activeKeywords: ["晴天"],
                hasMoreResults: true))

        let restored = store.restoreCachedResultsIfAvailable(for: " 晴天 ")

        XCTAssertTrue(restored)
        XCTAssertEqual(store.results.map(\.bvid), ["BV1"])
        XCTAssertTrue(store.hasMoreResults)
    }

    func testSearchLocalContentSurfacesCachedEntriesBeyondFirstSixWhenEarlierEntriesAreExcluded() {
        let recentTracks = (1...6).map { index in
            makeTrack(bvid: String(format: "BVCACHE%03d", index), title: "最近 \(index)")
        }
        let cachedTracks = (1...12).map { index in
            makeTrack(bvid: String(format: "BVCACHE%03d", index), title: "缓存 \(index)")
        }

        let content = SearchLocalContent(
            historyTerms: ["晴天"],
            recentTracks: recentTracks,
            cachedTracks: cachedTracks)

        XCTAssertEqual(
            content.cachedTracks.map(\.bvid),
            ["BVCACHE007", "BVCACHE008", "BVCACHE009", "BVCACHE010", "BVCACHE011", "BVCACHE012"])
    }

    @MainActor
    func testChangingModeClearsTransientResultsForSameQuery() {
        let store = SearchStore()
        store.setMode(.expanded, query: "晴天")

        XCTAssertEqual(store.mode, .expanded)
        XCTAssertTrue(store.results.isEmpty)
        XCTAssertFalse(store.hasMoreResults)
    }

    @MainActor
    func testChangingQueryAfterMoreResultsReturnsToMusicMode() {
        let store = SearchStore()
        store.setMode(.expanded, query: "晴天")

        store.queryDidChange("七里香")

        XCTAssertEqual(store.mode, .music)
    }

    @MainActor
    func testStaleSearchResultsCannotReplaceActiveQuery() async throws {
        let oldTrack = makeTrack(bvid: "BVOLD", title: "旧歌 Live")
        let newTrack = makeTrack(bvid: "BVNEW", title: "新歌 Live")
        let store = SearchStore(searchPageForTesting: { keyword, _, _ in
            if keyword == "旧歌" {
                try? await Task.sleep(nanoseconds: 150_000_000)
                return [oldTrack]
            }
            return [newTrack]
        })

        store.submitSearch("旧歌") { _ in }
        try await Task.sleep(nanoseconds: 20_000_000)
        store.submitSearch("新歌") { _ in }
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(store.resultsQuery, "新歌")
        XCTAssertEqual(store.results.map { $0.bvid }, ["BVNEW"])
        XCTAssertFalse(store.searching)
    }

    @MainActor
    func testConcurrentSearchPagesKeepRelevanceOrderInsteadOfCompletionOrder() async throws {
        let store = SearchStore(searchPageForTesting: { _, page, _ in
            if page == 1 {
                try? await Task.sleep(nanoseconds: 120_000_000)
            } else if page == 2 {
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
            return [makeTrack(
                bvid: "BVPAGE\(page)",
                title: "晴天 Official MV 第 \(page) 页")]
        })

        store.submitSearch("晴天") { _ in }
        try await Task.sleep(nanoseconds: 220_000_000)

        XCTAssertEqual(store.results.map(\.bvid), ["BVPAGE1", "BVPAGE2", "BVPAGE3"])
        XCTAssertFalse(store.searching)
    }

    @MainActor
    func testSearchSnapshotCacheEvictsLeastRecentlyUsedEntry() {
        let store = SearchStore()
        for index in 0..<13 {
            store.storeCachedSnapshotForTesting(
                query: "query-\(index)",
                mode: .music,
                snapshot: SearchCachedSnapshot(
                    tracks: [makeTrack(
                        bvid: "BVCACHE\(index)",
                        title: "缓存歌曲 \(index)")],
                    nextPage: 4,
                    activeKeywords: ["query-\(index)"],
                    hasMoreResults: true))
        }

        XCTAssertFalse(store.restoreCachedResultsIfAvailable(for: "query-0"))
        XCTAssertTrue(store.restoreCachedResultsIfAvailable(for: "query-12"))
        XCTAssertEqual(store.results.map(\.bvid), ["BVCACHE12"])
    }

    @MainActor
    func testLoadMoreFailurePreservesExistingResultsAndRetryState() async throws {
        let seed = makeTrack(bvid: "BVSEED", title: "晴天 Live")
        let store = SearchStore(searchPageForTesting: { _, _, _ in
            throw SearchStoreTestError.pageFailed
        })
        restoreSearch(store, query: "晴天", tracks: [seed], nextPage: 4, hasMoreResults: true)

        await store.loadMore { _ in }

        XCTAssertEqual(store.results.map { $0.bvid }, ["BVSEED"])
        XCTAssertTrue(store.hasMoreResults)
        XCTAssertNotNil(store.loadMoreErrorMessage)
        XCTAssertFalse(store.loadingMore)
    }

    @MainActor
    func testLoadMoreAppendsFilteredMusicResultsAndRebuildsSections() async throws {
        let seed = makeTrack(bvid: "BVSEED", title: "晴天 Live")
        let music = makeTrack(bvid: "BVMUSIC", title: "周杰伦《晴天》现场版")
        let nonMusic = makeTrack(typeID: 17, bvid: "BVGAME", title: "三国杀实况攻略合集", artist: "游戏区UP")
        let store = SearchStore(searchPageForTesting: { _, _, _ in
            [music, nonMusic]
        })
        restoreSearch(store, query: "晴天", tracks: [seed], nextPage: 4, hasMoreResults: true)

        await store.loadMore { _ in }

        XCTAssertEqual(store.results.map { $0.bvid }, ["BVSEED", "BVMUSIC"])
        XCTAssertEqual(store.sections?.bestMatch?.bvid, "BVSEED")
        XCTAssertEqual(store.sections?.songs.map { $0.bvid }, ["BVMUSIC"])
        XCTAssertNil(store.loadMoreErrorMessage)
    }

    @MainActor
    func testLoadMoreSkipsFilteredEmptyPagesWithinBoundedWindow() async throws {
        let seed = makeTrack(bvid: "BVSEED", title: "晴天 Live")
        let music = makeTrack(bvid: "BVMUSIC", title: "周杰伦《晴天》Official MV")
        let nonMusic = makeTrack(typeID: 17, bvid: "BVGAME", title: "三国杀实况攻略合集", artist: "游戏区UP")
        let store = SearchStore(searchPageForTesting: { _, page, _ in
            page < 6 ? [nonMusic] : [music]
        })
        restoreSearch(store, query: "晴天", tracks: [seed], nextPage: 4, hasMoreResults: true)

        await store.loadMore { _ in }

        XCTAssertEqual(store.results.map { $0.bvid }, ["BVSEED", "BVMUSIC"])
        XCTAssertTrue(store.hasMoreResults)
    }
}

private enum SearchStoreTestError: LocalizedError {
    case pageFailed

    var errorDescription: String? { "page failed" }
}

private actor CountingMetadataNormalizer: TrackMetadataNormalizing {
    private let result: NormalizedTrackMetadata
    private var calls = 0

    init(result: NormalizedTrackMetadata) {
        self.result = result
    }

    func normalize(_ track: Track) async throws -> NormalizedTrackMetadata {
        calls += 1
        return result
    }

    func callCount() -> Int { calls }
}

private func makeTrack(
    typeID: Int? = 3,
    bvid: String,
    title: String,
    artist: String = "周杰伦",
    duration: Int = 269
) -> Track {
    Track(typeID: typeID, bvid: bvid, title: title, artist: artist, coverURL: nil, duration: duration)
}

@MainActor
private func restoreSearch(
    _ store: SearchStore,
    query: String,
    tracks: [Track],
    nextPage: Int,
    hasMoreResults: Bool
) {
    store.storeCachedSnapshotForTesting(
        query: query,
        mode: .music,
        snapshot: SearchCachedSnapshot(
            tracks: tracks,
            nextPage: nextPage,
            activeKeywords: [query],
            hasMoreResults: hasMoreResults))
    XCTAssertTrue(store.restoreCachedResultsIfAvailable(for: query))
}
