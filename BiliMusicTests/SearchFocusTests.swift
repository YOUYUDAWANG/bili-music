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

    func testLocalSuggestionFixtureCombinesHistoryRecentAndCachedTracks() {
        let suggestions = SearchFocusFixture.localSuggestions(
            history: ["晴天"],
            recent: [Self.track(bvid: "BVRECENT001")],
            cached: [Self.track(bvid: "BVCACHE001")])

        XCTAssertEqual(suggestions.map(\.label), ["晴天", "Recent: BVRECENT001", "Cached: BVCACHE001"])
    }

    private static func track(bvid: String) -> Track {
        Track(typeID: 3, bvid: bvid, cid: 1001, title: "Search Focus Song", artist: "Fixture Artist", coverURL: nil, duration: 211)
    }

    private static func sourceFile(_ relativePath: String) throws -> String {
        let testURL = URL(fileURLWithPath: #filePath)
        let rootURL = testURL.deletingLastPathComponent().deletingLastPathComponent()
        let url = rootURL.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private enum SearchFocusFixture {
    struct Suggestion: Equatable {
        let label: String
    }

    static func localSuggestions(history: [String], recent: [Track], cached: [Track]) -> [Suggestion] {
        history.map(Suggestion.init(label:))
            + recent.map { Suggestion(label: "Recent: \($0.bvid)") }
            + cached.map { Suggestion(label: "Cached: \($0.bvid)") }
    }
}
