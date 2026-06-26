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
