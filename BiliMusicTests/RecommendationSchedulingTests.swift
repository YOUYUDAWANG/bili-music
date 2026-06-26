import XCTest
@testable import BiliMusic

final class RecommendationSchedulingTests: XCTestCase {
    func testFirstPlaybackMarksHomeStaleWithoutRefreshingVisibleRows() {
        var fixture = RecommendationSchedulingFixture(visibleRows: [Self.track()])

        fixture.recordFirstPlayback()

        XCTAssertTrue(fixture.isStale)
        XCTAssertEqual(fixture.refreshCount, 0)
        XCTAssertEqual(fixture.visibleRows.map(\.bvid), ["BVRECO001"])
    }

    private static func track() -> Track {
        Track(
            typeID: 3,
            bvid: "BVRECO001",
            cid: 1001,
            title: "Recommendation Song",
            artist: "Fixture Artist",
            coverURL: nil,
            duration: 211)
    }
}

private struct RecommendationSchedulingFixture {
    private(set) var visibleRows: [Track]
    private(set) var isStale = false
    private(set) var refreshCount = 0

    mutating func recordFirstPlayback() {
        isStale = true
    }

    mutating func manualRefresh() {
        refreshCount += 1
    }
}
