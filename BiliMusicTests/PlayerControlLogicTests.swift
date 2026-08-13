import XCTest
@testable import BiliMusic

final class PlayerControlLogicTests: XCTestCase {
    func testProgressScrubClampsTimeToPlayableDuration() {
        XCTAssertEqual(ProgressScrubMath.clampedTime(-30, duration: 240), 0)
        XCTAssertEqual(ProgressScrubMath.clampedTime(120, duration: 240), 120)
        XCTAssertEqual(ProgressScrubMath.clampedTime(300, duration: 240), 240)
        XCTAssertEqual(ProgressScrubMath.clampedTime(.infinity, duration: 240), 0)
        XCTAssertEqual(ProgressScrubMath.clampedTime(120, duration: 0), 0)
    }
}
