import XCTest
@testable import BiliMusic

/// QueueController 纯函数覆盖:nextIndex 全模式边界 + appendUnique 去重。
final class QueueControllerTests: XCTestCase {
    // MARK: - nextIndex / sequential

    func testSequentialAdvancesUntilTailThenStops() {
        XCTAssertEqual(
            QueueController.nextIndex(mode: .sequential, queueCount: 3, currentIndex: 0, automatic: true), 1)
        XCTAssertEqual(
            QueueController.nextIndex(mode: .sequential, queueCount: 3, currentIndex: 1, automatic: false), 2)
        XCTAssertNil(
            QueueController.nextIndex(mode: .sequential, queueCount: 3, currentIndex: 2, automatic: true))
        XCTAssertNil(
            QueueController.nextIndex(mode: .sequential, queueCount: 3, currentIndex: 2, automatic: false))
    }

    func testSequentialEmptyAndSingleTrackQueues() {
        XCTAssertNil(
            QueueController.nextIndex(mode: .sequential, queueCount: 0, currentIndex: 0, automatic: true))
        XCTAssertNil(
            QueueController.nextIndex(mode: .sequential, queueCount: 1, currentIndex: 0, automatic: false))
    }

    // MARK: - nextIndex / radio

    func testRadioBehavesLikeSequentialWithinExistingQueue() {
        XCTAssertEqual(
            QueueController.nextIndex(mode: .radio, queueCount: 4, currentIndex: 1, automatic: true), 2)
        XCTAssertNil(
            QueueController.nextIndex(mode: .radio, queueCount: 4, currentIndex: 3, automatic: true))
        XCTAssertNil(
            QueueController.nextIndex(mode: .radio, queueCount: 0, currentIndex: 0, automatic: false))
    }

    // MARK: - nextIndex / repeatOne

    func testRepeatOneAutomaticRepeatsCurrentIndex() {
        XCTAssertEqual(
            QueueController.nextIndex(mode: .repeatOne, queueCount: 3, currentIndex: 0, automatic: true), 0)
        XCTAssertEqual(
            QueueController.nextIndex(mode: .repeatOne, queueCount: 3, currentIndex: 2, automatic: true), 2)
        XCTAssertEqual(
            QueueController.nextIndex(mode: .repeatOne, queueCount: 1, currentIndex: 0, automatic: true), 0)
    }

    func testRepeatOneManualAdvanceWrapsAtTail() {
        // 锁屏「下一曲」在单曲循环下恒可点:队尾手动切歌回绕到队首而不是返回 nil。
        XCTAssertEqual(
            QueueController.nextIndex(mode: .repeatOne, queueCount: 3, currentIndex: 1, automatic: false), 2)
        XCTAssertEqual(
            QueueController.nextIndex(mode: .repeatOne, queueCount: 3, currentIndex: 2, automatic: false), 0)
        XCTAssertEqual(
            QueueController.nextIndex(mode: .repeatOne, queueCount: 1, currentIndex: 0, automatic: false), 0)
    }

    func testRepeatOneManualAdvanceOnEmptyQueueHasNoNext() {
        XCTAssertNil(
            QueueController.nextIndex(mode: .repeatOne, queueCount: 0, currentIndex: 0, automatic: false))
    }

    // MARK: - nextIndex / shuffle

    func testShuffleNeedsAtLeastTwoTracks() {
        XCTAssertNil(
            QueueController.nextIndex(mode: .shuffle, queueCount: 0, currentIndex: 0, automatic: true))
        XCTAssertNil(
            QueueController.nextIndex(mode: .shuffle, queueCount: 1, currentIndex: 0, automatic: false))
    }

    func testShuffleAlwaysPicksADifferentInBoundsIndex() {
        for _ in 0..<50 {
            let next = QueueController.nextIndex(
                mode: .shuffle, queueCount: 5, currentIndex: 2, automatic: false)
            let unwrapped = try? XCTUnwrap(next)
            XCTAssertNotEqual(unwrapped, 2)
            XCTAssertTrue((0..<5).contains(unwrapped ?? -1))
        }
        // 两首歌时只可能选中另一首,结果是确定的。
        XCTAssertEqual(
            QueueController.nextIndex(mode: .shuffle, queueCount: 2, currentIndex: 0, automatic: true), 1)
    }

    // MARK: - appendUnique

    func testAppendUniqueSkipsTracksAlreadyInQueue() {
        var queue = [track(bvid: "BV1", cid: 100), track(bvid: "BV2", cid: 200)]

        let additions = QueueController.appendUnique(
            [track(bvid: "BV2", cid: 200), track(bvid: "BV3", cid: 300)],
            to: &queue)

        XCTAssertEqual(additions.map(\.bvid), ["BV3"])
        XCTAssertEqual(queue.map(\.bvid), ["BV1", "BV2", "BV3"])
    }

    func testAppendUniqueMatchesLooselyWhenCIDUnresolved() {
        // TrackKey.matches:任一侧 cid 为 nil 时只按 bvid 匹配,
        // 未解析分P的同一 BV 不应重复入队。
        var queue = [track(bvid: "BV1", cid: 100)]

        let additions = QueueController.appendUnique([track(bvid: "BV1", cid: nil)], to: &queue)

        XCTAssertTrue(additions.isEmpty)
        XCTAssertEqual(queue.count, 1)
    }

    func testAppendUniqueTreatsDifferentPartsAsDistinctTracks() {
        var queue = [track(bvid: "BV1", cid: 100)]

        let additions = QueueController.appendUnique([track(bvid: "BV1", cid: 101)], to: &queue)

        XCTAssertEqual(additions.map(\.cid), [101])
        XCTAssertEqual(queue.count, 2)
    }

    func testAppendUniqueIntoEmptyQueueAppendsEverything() {
        var queue: [Track] = []

        let additions = QueueController.appendUnique(
            [track(bvid: "BV1", cid: 100), track(bvid: "BV2", cid: nil)],
            to: &queue)

        XCTAssertEqual(additions.count, 2)
        XCTAssertEqual(queue.map(\.bvid), ["BV1", "BV2"])
    }

    private func track(bvid: String, cid: Int?) -> Track {
        Track(
            typeID: 3,
            bvid: bvid,
            cid: cid,
            title: "Queue Song \(bvid)",
            artist: "Fixture Artist",
            coverURL: nil,
            duration: 211)
    }
}
