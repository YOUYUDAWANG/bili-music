import XCTest
@testable import BiliMusic

final class SearchModelsTests: XCTestCase {
    func testCacheKeyNormalizesWhitespaceAndCase() {
        let lhs = SearchCacheKey(query: "  Jay   Chou ", mode: .music)
        let rhs = SearchCacheKey(query: "jay chou", mode: .music)
        XCTAssertEqual(lhs, rhs)
    }

    func testModeControlsBiliMusicOnlySearch() {
        XCTAssertTrue(SearchResultMode.music.usesBiliMusicOnlySearch)
        XCTAssertTrue(SearchResultMode.mv.usesBiliMusicOnlySearch)
        XCTAssertFalse(SearchResultMode.expanded.usesBiliMusicOnlySearch)
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
        store.setMode(.mv, query: "晴天")

        XCTAssertEqual(store.mode, .mv)
        XCTAssertTrue(store.results.isEmpty)
        XCTAssertFalse(store.hasMoreResults)
    }
}
