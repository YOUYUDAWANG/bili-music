import XCTest
@testable import BiliMusic

final class SearchFocusTests: XCTestCase {
    @MainActor
    func testTypingFirstCharacterKeepsSearchStoreLocalAndIdle() {
        let store = SearchStore()

        store.queryDidChange("晴")

        XCTAssertFalse(store.searching)
        XCTAssertTrue(store.results.isEmpty)
        XCTAssertNil(store.sections)
        XCTAssertEqual(store.mode, .music)
        XCTAssertEqual(store.resultsQuery, "")
        XCTAssertEqual(store.activeQuery, "")
        XCTAssertFalse(store.hasMoreResults)
    }

    func testSearchViewQueryChangeDoesNotContainDebouncedSubmitPath() throws {
        let source = try Self.sourceFile("BiliMusic/Features/Search/SearchView.swift")

        XCTAssertFalse(source.contains("debounceTask"))
        XCTAssertFalse(source.contains("debouncedSearch"))
        XCTAssertFalse(source.contains("Task.sleep(for: .milliseconds(450))"))
    }

    func testSearchViewExplicitSubmitRemainsNetworkEntryPoint() throws {
        let source = try Self.sourceFile("BiliMusic/Features/Search/SearchView.swift")

        XCTAssertTrue(source.contains(".onSubmit(of: .search)"))
        XCTAssertTrue(source.contains("submitSearch()"))
    }

    func testLocalSuggestionProjectionCapsHistoryAtEight() {
        let history = (1...10).map { "搜索\($0)" }

        let content = SearchLocalContent(
            historyTerms: history,
            recentTracks: [],
            cachedTracks: [])

        XCTAssertEqual(content.historyTerms, Array(history.prefix(8)))
    }

    func testLocalSuggestionProjectionCombinesRecentAndCachedTracksWithoutDuplicates() {
        let repeated = Self.track(bvid: "BVSAME001")

        let content = SearchLocalContent(
            historyTerms: ["晴天"],
            recentTracks: [repeated, Self.track(bvid: "BVRECENT001")],
            cachedTracks: [repeated, Self.track(bvid: "BVCACHE001")])

        XCTAssertEqual(content.historyTerms, ["晴天"])
        XCTAssertEqual(content.recentTracks.map(\.bvid), ["BVSAME001", "BVRECENT001"])
        XCTAssertEqual(content.cachedTracks.map(\.bvid), ["BVCACHE001"])
    }

    func testLocalSuggestionProjectionReportsEmptyStateWhenNoLocalContentExists() {
        let content = SearchLocalContent(
            historyTerms: [],
            recentTracks: [],
            cachedTracks: [])

        XCTAssertTrue(content.isEmpty)
    }

    private static func sourceFile(_ relativePath: String) throws -> String {
        let testURL = URL(fileURLWithPath: #filePath)
        let rootURL = testURL.deletingLastPathComponent().deletingLastPathComponent()
        let url = rootURL.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func track(bvid: String) -> Track {
        Track(
            typeID: 3,
            bvid: bvid,
            cid: 1001,
            title: "Search Focus Song",
            artist: "Fixture Artist",
            coverURL: nil,
            duration: 211)
    }
}
