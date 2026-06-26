import XCTest
@testable import BiliMusic

final class PreparedStreamRetryTests: XCTestCase {
    func testPreparedRemoteFailureInvalidatesOnceBeforeFreshRetry() {
        var fixture = PreparedStreamRetryFixture()

        let first = fixture.handlePreparedRemoteFailure(for: Self.track())
        let second = fixture.handlePreparedRemoteFailure(for: Self.track())

        XCTAssertEqual(first, .retryFreshStream)
        XCTAssertEqual(second, .surfaceFailure)
        XCTAssertEqual(fixture.invalidatedKeys, [TrackKey(bvid: "BVRETRY001", cid: 1001)])
    }

    private static func track() -> Track {
        Track(
            typeID: 3,
            bvid: "BVRETRY001",
            cid: 1001,
            title: "Retry Song",
            artist: "Fixture Artist",
            coverURL: nil,
            duration: 188)
    }
}

private struct PreparedStreamRetryFixture {
    enum Decision {
        case retryFreshStream
        case surfaceFailure
    }

    private(set) var invalidatedKeys: [TrackKey] = []
    private var didRetry = false

    mutating func handlePreparedRemoteFailure(for track: Track) -> Decision {
        guard !didRetry else { return .surfaceFailure }
        didRetry = true
        invalidatedKeys.append(track.key)
        return .retryFreshStream
    }
}
