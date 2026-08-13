import XCTest
@testable import BiliMusic

final class PlayerControlLogicTests: XCTestCase {
    func testProgressScrubRequiresClearHorizontalIntent() {
        XCTAssertTrue(ProgressScrubMath.shouldBeginScrub(
            translation: CGSize(width: 18, height: 4)))
        XCTAssertFalse(ProgressScrubMath.shouldBeginScrub(
            translation: CGSize(width: 4, height: 18)))
        XCTAssertFalse(ProgressScrubMath.shouldBeginScrub(
            translation: CGSize(width: 10, height: 8)))
        XCTAssertFalse(ProgressScrubMath.shouldBeginScrub(
            translation: CGSize(width: 6, height: 0)))
    }

    func testProgressScrubUsesAndClampsVisibleTrackCoordinates() {
        XCTAssertEqual(ProgressScrubMath.progress(locationX: -30, trackWidth: 240), 0)
        XCTAssertEqual(ProgressScrubMath.progress(locationX: 120, trackWidth: 240), 0.5)
        XCTAssertEqual(ProgressScrubMath.progress(locationX: 300, trackWidth: 240), 1)
        XCTAssertEqual(ProgressScrubMath.progress(locationX: 120, trackWidth: 0), 0)
    }
}
