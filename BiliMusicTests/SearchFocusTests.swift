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
