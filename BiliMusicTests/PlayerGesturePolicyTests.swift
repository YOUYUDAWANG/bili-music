import CoreGraphics
import XCTest
@testable import BiliMusic

final class PlayerGesturePolicyTests: XCTestCase {
    func testMiniPlayerOpenProgressTracksUpwardDragMonotonically() {
        let small = PlayerGesturePolicy.miniOpenProgress(for: -24)
        let medium = PlayerGesturePolicy.miniOpenProgress(for: -72)
        let full = PlayerGesturePolicy.miniOpenProgress(for: -260)

        XCTAssertGreaterThan(small, 0)
        XCTAssertLessThan(small, medium)
        XCTAssertLessThan(medium, full)
        XCTAssertEqual(full, 1)
    }

    func testMiniPlayerOpenProgressClampsAtBothEnds() {
        XCTAssertEqual(PlayerGesturePolicy.miniOpenProgress(for: 24), 0)
        XCTAssertEqual(PlayerGesturePolicy.miniOpenProgress(for: 0), 0)
        XCTAssertEqual(PlayerGesturePolicy.miniOpenProgress(for: -PlayerGesturePolicy.miniOpeningDragRange), 1)
        XCTAssertEqual(PlayerGesturePolicy.miniOpenProgress(for: -PlayerGesturePolicy.miniOpeningDragRange * 1.5), 1)
    }

    func testMiniPlayerOpenRequiresIntentionalVerticalUpwardDrag() {
        XCTAssertFalse(PlayerGesturePolicy.shouldBeginMiniOpenDrag(
            translation: CGSize(width: 0, height: -16)))
        XCTAssertFalse(PlayerGesturePolicy.shouldBeginMiniOpenDrag(
            translation: CGSize(width: 30, height: -24)))
        XCTAssertFalse(PlayerGesturePolicy.shouldBeginMiniOpenDrag(
            translation: CGSize(width: 0, height: 40)))

        XCTAssertTrue(PlayerGesturePolicy.shouldBeginMiniOpenDrag(
            translation: CGSize(width: 8, height: -24)))
    }

    func testMiniPlayerShortUpwardDragCancelsBelowCompletionThreshold() {
        XCTAssertFalse(PlayerGesturePolicy.shouldFinishMiniOpenDrag(
            translationY: -48,
            velocityY: 0))
        XCTAssertFalse(PlayerGesturePolicy.shouldOpenMiniPlayerLive(
            translationY: -48,
            velocityY: 0))
    }

    func testMiniPlayerOpenCanUseProjectedVelocityWithoutWaitingForLongDrag() {
        XCTAssertFalse(PlayerGesturePolicy.shouldFinishMiniOpenDrag(
            translationY: -22,
            velocityY: -260))
        XCTAssertTrue(PlayerGesturePolicy.shouldFinishMiniOpenDrag(
            translationY: -42,
            velocityY: -220))
        XCTAssertTrue(PlayerGesturePolicy.shouldFinishMiniOpenDrag(
            translationY: -86,
            velocityY: 0))
    }

    func testFullPlayerDismissIgnoresListAreaAndHorizontalDrags() {
        XCTAssertFalse(PlayerGesturePolicy.shouldDismissFullPlayer(
            translation: CGSize(width: 0, height: 180),
            predictedEndTranslation: CGSize(width: 0, height: 220),
            startY: 260))

        XCTAssertFalse(PlayerGesturePolicy.shouldDismissFullPlayer(
            translation: CGSize(width: 220, height: 150),
            predictedEndTranslation: CGSize(width: 260, height: 180),
            startY: 80))
    }

    func testCenterBodyDismissTracksAndRequiresDeliberateDrag() {
        XCTAssertEqual(PlayerGesturePolicy.dismissDragOffset(
            translation: CGSize(width: 0, height: 92),
            startY: 420,
            region: .centerBody,
            isProgressScrubbing: false), 92)
        XCTAssertFalse(PlayerGesturePolicy.shouldDismissFullPlayer(
            translation: CGSize(width: 0, height: 92),
            predictedEndTranslation: CGSize(width: 0, height: 120),
            startY: 420,
            region: .centerBody,
            isProgressScrubbing: false))

        XCTAssertTrue(PlayerGesturePolicy.shouldDismissFullPlayer(
            translation: CGSize(width: 0, height: 146),
            predictedEndTranslation: CGSize(width: 0, height: 170),
            startY: 420,
            region: .centerBody,
            isProgressScrubbing: false))
        XCTAssertTrue(PlayerGesturePolicy.shouldDismissFullPlayer(
            translation: CGSize(width: 0, height: 70),
            predictedEndTranslation: CGSize(width: 0, height: 280),
            startY: 420,
            region: .centerBody,
            isProgressScrubbing: false))
    }

    func testListBodyDismissNeverTracksEvenWhenLarge() {
        XCTAssertNil(PlayerGesturePolicy.dismissDragOffset(
            translation: CGSize(width: 0, height: 260),
            startY: 220,
            region: .listBody,
            isProgressScrubbing: false))
        XCTAssertFalse(PlayerGesturePolicy.shouldDismissFullPlayer(
            translation: CGSize(width: 0, height: 260),
            predictedEndTranslation: CGSize(width: 0, height: 520),
            startY: 220,
            region: .listBody,
            isProgressScrubbing: false))
    }

    func testTopChromeRegionDismissWorksAcrossPages() {
        XCTAssertEqual(PlayerGesturePolicy.dismissDragOffset(
            translation: CGSize(width: 0, height: 72),
            startY: 40,
            region: .topChrome,
            isProgressScrubbing: false), 72)
        XCTAssertTrue(PlayerGesturePolicy.shouldDismissFullPlayer(
            translation: CGSize(width: 0, height: 95),
            predictedEndTranslation: CGSize(width: 0, height: 120),
            startY: 40,
            region: .topChrome,
            isProgressScrubbing: false))
    }

    func testHorizontalIntentAndScrubSuppressVerticalDismiss() {
        XCTAssertNil(PlayerGesturePolicy.dismissDragOffset(
            translation: CGSize(width: 0, height: 180),
            startY: 60,
            region: .topChrome,
            isProgressScrubbing: true))
        XCTAssertFalse(PlayerGesturePolicy.shouldDismissFullPlayer(
            translation: CGSize(width: 0, height: 180),
            predictedEndTranslation: CGSize(width: 0, height: 280),
            startY: 60,
            region: .topChrome,
            isProgressScrubbing: true))
        XCTAssertFalse(PlayerGesturePolicy.isHorizontalPageSwipe(
            translation: CGSize(width: 52, height: 88),
            predictedEndTranslation: CGSize(width: 64, height: 124),
            width: 390))
        XCTAssertTrue(PlayerGesturePolicy.isHorizontalPageSwipe(
            translation: CGSize(width: -86, height: 12),
            predictedEndTranslation: CGSize(width: -116, height: 18),
            width: 390))
    }

    func testProgressScrubMathUsesVisibleTrackCoordinates() {
        XCTAssertEqual(ProgressScrubMath.progress(locationX: 0, trackWidth: 240), 0)
        XCTAssertEqual(ProgressScrubMath.progress(locationX: 120, trackWidth: 240), 0.5)
        XCTAssertEqual(ProgressScrubMath.progress(locationX: 240, trackWidth: 240), 1)
    }

    func testProgressScrubMathClampsOutsideVisibleTrack() {
        XCTAssertEqual(ProgressScrubMath.progress(locationX: -30, trackWidth: 240), 0)
        XCTAssertEqual(ProgressScrubMath.progress(locationX: 300, trackWidth: 240), 1)
        XCTAssertEqual(ProgressScrubMath.progress(locationX: 120, trackWidth: 0), 0)
    }

    func testProgressScrubRequiresClearHorizontalIntent() {
        XCTAssertTrue(ProgressScrubMath.shouldBeginScrub(
            translation: CGSize(width: 18, height: 4)
        ))
        XCTAssertFalse(ProgressScrubMath.shouldBeginScrub(
            translation: CGSize(width: 4, height: 18)
        ))
        XCTAssertFalse(ProgressScrubMath.shouldBeginScrub(
            translation: CGSize(width: 10, height: 8)
        ))
        XCTAssertFalse(ProgressScrubMath.shouldBeginScrub(
            translation: CGSize(width: 6, height: 0)
        ))
    }

    func testHorizontalListDragSuppressesRowTapWithoutBlockingVerticalScroll() {
        XCTAssertFalse(PlayerGesturePolicy.shouldSuppressListRowTap(
            translation: CGSize(width: 6, height: 2),
            predictedEndTranslation: CGSize(width: 8, height: 3)))
        XCTAssertFalse(PlayerGesturePolicy.shouldSuppressListRowTap(
            translation: CGSize(width: 18, height: 42),
            predictedEndTranslation: CGSize(width: 24, height: 80)))
        XCTAssertTrue(PlayerGesturePolicy.shouldSuppressListRowTap(
            translation: CGSize(width: -24, height: 4),
            predictedEndTranslation: CGSize(width: -58, height: 7)))
        XCTAssertTrue(PlayerGesturePolicy.shouldSuppressListRowTap(
            translation: CGSize(width: -12, height: 3),
            predictedEndTranslation: CGSize(width: -18, height: 4)))
        XCTAssertTrue(PlayerGesturePolicy.shouldSuppressListRowTap(
            translation: CGSize(width: 30, height: 22),
            predictedEndTranslation: CGSize(width: 64, height: 28)))
    }

    func testFullPlayerDismissRequiresDeliberateTopDownDragOrPrediction() {
        XCTAssertEqual(PlayerGesturePolicy.dismissDragOffset(
            translation: CGSize(width: 0, height: 96),
            startY: 80), 96)
        XCTAssertFalse(PlayerGesturePolicy.shouldDismissFullPlayer(
            translation: CGSize(width: 0, height: 96),
            predictedEndTranslation: CGSize(width: 0, height: 120),
            startY: 80))

        XCTAssertEqual(PlayerGesturePolicy.dismissDragOffset(
            translation: CGSize(width: 0, height: 160),
            startY: 80), 160)
        XCTAssertTrue(PlayerGesturePolicy.shouldDismissFullPlayer(
            translation: CGSize(width: 0, height: 160),
            predictedEndTranslation: CGSize(width: 0, height: 170),
            startY: 80))
        XCTAssertTrue(PlayerGesturePolicy.shouldDismissFullPlayer(
            translation: CGSize(width: 0, height: 80),
            predictedEndTranslation: CGSize(width: 0, height: 280),
            startY: 80))
    }

    func testTopChromeDismissUsesLowerThresholdThanContentDrag() {
        XCTAssertTrue(PlayerGesturePolicy.shouldDismissFromTopChrome(
            translation: CGSize(width: 0, height: 95),
            predictedEndTranslation: CGSize(width: 0, height: 120)))
        XCTAssertFalse(PlayerGesturePolicy.shouldDismissFromTopChrome(
            translation: CGSize(width: 80, height: 70),
            predictedEndTranslation: CGSize(width: 90, height: 90)))
    }
}
