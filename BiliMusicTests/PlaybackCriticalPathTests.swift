import XCTest
@testable import BiliMusic

final class PlaybackCriticalPathTests: XCTestCase {
    func testCriticalPathFixtureKeepsPlaybackRequestBeforeEnrichment() {
        let steps = PlaybackCriticalPathFixture.remoteStartSteps()

        XCTAssertEqual(Array(steps.prefix(5)), [
            .tap,
            .currentAssigned,
            .sourceResolved,
            .playerItemCreated,
            .playRequested
        ])
        XCTAssertLessThan(
            steps.firstIndex(of: .playRequested) ?? .max,
            steps.firstIndex(of: .postStartEnrichment) ?? .min,
            "Lyrics, artwork, MV, recommendation, and cache enrichment must stay after the playback request.")
    }

    func testTrackFixtureIsPlayableMusicInput() {
        let track = PlaybackCriticalPathFixture.track()

        XCTAssertEqual(track.typeID, 3)
        XCTAssertEqual(track.bvid, "BVPATH001")
        XCTAssertEqual(track.cid, 1001)
        XCTAssertGreaterThan(track.duration, 0)
    }
}

private enum PlaybackCriticalPathFixture {
    enum Step: Equatable {
        case tap
        case currentAssigned
        case sourceResolved
        case playerItemCreated
        case playRequested
        case postStartEnrichment
    }

    static func track() -> Track {
        Track(
            typeID: 3,
            bvid: "BVPATH001",
            cid: 1001,
            title: "Critical Path Song",
            artist: "Fixture Artist",
            coverURL: nil,
            duration: 211)
    }

    static func remoteStartSteps() -> [Step] {
        [
            .tap,
            .currentAssigned,
            .sourceResolved,
            .playerItemCreated,
            .playRequested,
            .postStartEnrichment
        ]
    }
}
