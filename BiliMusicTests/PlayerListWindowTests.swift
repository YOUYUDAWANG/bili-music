import XCTest
@testable import BiliMusic

final class PlayerListWindowTests: XCTestCase {
    func testLargeCollectionOnlyReturnsVisibleWindowAroundCurrentTrack() {
        let tracks = (0..<300).map {
            Track(bvid: "BV\($0)", title: "Song \($0)", artist: "UP",
                  coverURL: nil, duration: 180)
        }
        let items = PlayerListWindow.items(tracks: tracks, current: tracks[150], maxRows: 7)

        XCTAssertLessThanOrEqual(items.count, 7)
        XCTAssertTrue(items.contains { $0.index == 150 })
        XCTAssertEqual(items.first?.index, 147)
        XCTAssertEqual(items.last?.index, 153)
    }

    func testWindowClampsAtCollectionStartAndEnd() {
        let tracks = (0..<20).map {
            Track(bvid: "BV\($0)", title: "Song \($0)", artist: "UP",
                  coverURL: nil, duration: 180)
        }

        XCTAssertEqual(
            PlayerListWindow.items(tracks: tracks, current: tracks[0], maxRows: 5).map(\.index),
            [0, 1, 2, 3, 4])
        XCTAssertEqual(
            PlayerListWindow.items(tracks: tracks, current: tracks[19], maxRows: 5).map(\.index),
            [15, 16, 17, 18, 19])
    }

    func testPositionTextUsesCurrentIndexWhenAvailable() {
        let tracks = (0..<3).map {
            Track(bvid: "BV\($0)", title: "Song \($0)", artist: "UP",
                  coverURL: nil, duration: 180)
        }

        XCTAssertEqual(PlayerListWindow.positionText(tracks: tracks, current: tracks[1]), "2/3")
        XCTAssertEqual(PlayerListWindow.positionText(tracks: tracks, current: nil), "3 首")
    }
}
