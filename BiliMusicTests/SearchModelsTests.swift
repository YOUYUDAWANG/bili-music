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

    func testLyricsClientBuildsBroadDedupedSearchPlans() {
        let client = LyricsClient()
        let artists = client.artistCandidates(parsedArtist: "周杰伦", trackArtist: "音乐分享UP")
        let plans = client.queryPlans(
            title: "晴天",
            rawTitle: "【4K修复】周杰伦《晴天》Official MV",
            artists: artists,
            duration: 269)

        XCTAssertEqual(artists, ["周杰伦"])
        XCTAssertTrue(plans.contains { plan in
            if case .exactGet(track: "晴天", artist: "周杰伦", duration: 269) = plan.kind { return true }
            return false
        })
        XCTAssertTrue(plans.contains { plan in
            if case .searchText("晴天") = plan.kind { return true }
            return false
        })
        XCTAssertTrue(plans.contains { plan in
            if case .searchText("周杰伦 晴天") = plan.kind { return true }
            return false
        })
        XCTAssertEqual(Set(plans).count, plans.count)
    }

    func testLyricsClientMatchesLongerMVDurationWhenArtistMatches() throws {
        let client = LyricsClient()
        let candidate = LyricsClient.Candidate(
            id: 1,
            trackName: "晴天",
            artistName: "周杰伦",
            albumName: "叶惠美",
            duration: 270,
            instrumental: false,
            syncedLyrics: nil,
            plainLyrics: "故事的小黄花\n从出生那年就飘着")

        let best = try XCTUnwrap(client.bestCandidate(
            [candidate],
            songTitle: "晴天",
            artists: ["周杰伦"],
            duration: 304))
        let lines = client.lyricLines(from: best, duration: 304)

        XCTAssertEqual(best.trackName, "晴天")
        XCTAssertEqual(lines.map(\.text), ["故事的小黄花", "从出生那年就飘着"])
        XCTAssertGreaterThan(lines[1].from, lines[0].from)
    }

    func testLyricsClientUsesArtistEmbeddedInTitleForMVDurationTolerance() throws {
        let client = LyricsClient()
        let candidate = LyricsClient.Candidate(
            id: 2,
            trackName: "晴天",
            artistName: "周杰伦",
            albumName: "叶惠美",
            duration: 270,
            instrumental: false,
            syncedLyrics: "[00:01.00]故事的小黄花",
            plainLyrics: nil)

        let best = try XCTUnwrap(client.bestCandidate(
            [candidate],
            songTitle: "周杰伦 晴天",
            artists: [],
            duration: 304))

        XCTAssertEqual(best.artistName, "周杰伦")
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
