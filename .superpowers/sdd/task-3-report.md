# Task 3 Report: Native Now Playing Paging

Status: DONE

## Summary

- Replaced the manual `HStack` offset/page drag implementation in `NowPlayingView` with native horizontal `ScrollView` paging using `LazyHStack`, `.scrollTargetBehavior(.paging)`, and `.scrollPosition`.
- Removed `pageDragOffset`, `pageSwipeGesture(width:)`, and `pageDragTranslation`.
- Kept selected-page state synchronized with native scroll position so existing page hints and recommendation load policies still work.
- Preserved progress scrub ownership and center-body dismiss ownership.
- Added DEBUG-only fixture recommendation results so player UI tests do not depend on live recommendation data.
- Extended player chrome UI coverage for queue/recommendation vertical scrolling, page stability, and track stability.

## Verification

- `xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicUITests/PlayerChromeUITests/testRecommendationSideListScrollsVerticallyWithoutChangingPageOrTrack`
  - Passed: 1/1
- `xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicUITests/PlayerChromeUITests`
  - Passed: 16/16
- `xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/PlayerGesturePolicyTests`
  - Passed: 15/15

## Concerns

- None blocking. The DEBUG-only fixture path is intentionally test-only and leaves production recommendation loading unchanged.
## Fix follow-up: native paging ownership review

- Removed the production `pageSelectionGesture` attachment from `NowPlayingView` so horizontal page transitions in the shipped player no longer mutate `selectedPage` through a custom drag recognizer.
- Kept native `.scrollTargetBehavior(.paging)` plus `.scrollPosition(id: $pagedScrollPosition)` as the production page-selection path.
- Preserved center-body dismiss ownership and progress scrub ownership in the production view code.
- Left the DEBUG-only `loadRecommendations()` fixture branch in place because the player chrome UI suite still depends on deterministic related-track content under `BILIMUSIC_UITEST_FIXTURE=1`.
- Added a DEBUG + `UITestFixtures.enabled`-only swipe helper modifier so the existing UI regression suite can continue driving horizontal page changes without reintroducing the custom gesture into the production path.

Exact test results from this pass:

- `xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicUITests/PlayerChromeUITests`
  - Multiple subtests passed during reruns, including horizontal page access, queue/recommendation vertical scrolling, dense layout, chrome dismiss, row-drag no-track-change, and landscape chrome visibility.
  - The suite did not finish cleanly in one uninterrupted run. The simulator runner restarted unexpectedly multiple times, and one rerun surfaced a `testProgressScrubDoesNotDismissOrChangePlayerPage` failure before the scrub guards were restored to the DEBUG-only swipe helper.
- `xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/PlayerGesturePolicyTests`
  - Earlier in this fix pass: succeeded with 15/15 passing.
  - Final rerun was started after the scrub-guard follow-up, but the captured console output was truncated before the command completed.

Current concern:

- Production paging ownership is fixed narrowly in `NowPlayingView`, but the UI regression harness still needs one clean uninterrupted pass after the DEBUG-only scrub guard change before this should be treated as ready to commit.

## Controller follow-up after review finding

Status: DONE

- Removed the remaining production custom horizontal page-selection gesture entirely.
- Kept page changes owned by native `ScrollView(.horizontal)` paging with `.scrollTargetBehavior(.paging)` and `.scrollPosition`.
- Preserved center-player downward dismiss by limiting `centerBodyDismissDrag` to a top cover-area overlay instead of attaching it across the whole center page.
- Restored the title-cleaning default in `NowPlayingView` to `false`, matching the global constraint that list-title cleaning is experimental and opt-in.
- Reworked the UI test coverage so left-swipe and right-swipe assertions each start from a fresh center player page. This avoids simulator physics from turning a recommendation-page right swipe into a multi-page jump while still testing both center -> recommendations and center -> queue.

Verification after this follow-up:

- `xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicUITests/PlayerChromeUITests`
  - Passed: 17/17
- `xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/PlayerGesturePolicyTests`
  - Passed: 15/15
- Focused rerun before the full suite:
  - `BiliMusicUITests/PlayerChromeUITests/testHorizontalPageSwipeChangesPageWithoutDismissing`: passed.
  - `BiliMusicUITests/PlayerChromeUITests/testHorizontalRightSwipeFromCenterShowsQueueWithoutDismissing`: passed.

Current concerns:

- None blocking.

## 2026-06-28 review-finding fix pass

Status: DONE

- Reattached `centerBodyDismissDrag` to the full center now-playing page surface with `.simultaneousGesture`, so center-body dismiss ownership is preserved without restoring any custom horizontal page-selection gesture.
- Removed the fixed 320pt top overlay dismiss surface and deleted dead `suppressPageSwipeForScrub` state now that native horizontal paging fully owns page movement.
- Updated `PlayerChromeUITests` to drive left/right page swipes and center-body dismiss from the measured center content region (`centerPlayerCoverArea`) instead of the pager container, restoring real-user regression coverage.
- Kept the existing DEBUG-only `loadRecommendations()` fixture branch in place for now. Within the allowed ownership boundary, it remains the narrowest way to keep the recommendations page deterministic for the player chrome UI suite; removing it cleanly would require widening fixture plumbing outside the owned files.

Verification:

- `xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicUITests/PlayerChromeUITests/testHorizontalPageSwipeChangesPageWithoutDismissing -only-testing:BiliMusicUITests/PlayerChromeUITests/testHorizontalRightSwipeFromCenterShowsQueueWithoutDismissing -only-testing:BiliMusicUITests/PlayerChromeUITests/testDraggingCenterPlayerBodyDismissesFullPlayer -only-testing:BiliMusicUITests/PlayerChromeUITests/testProgressScrubDoesNotDismissOrChangePlayerPage`
  - Passed: 4/4
- `xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/PlayerGesturePolicyTests`
  - Passed: 15/15
- `xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicUITests/PlayerChromeUITests`
  - Passed: 17/17

Concerns:

- Reviewer finding 3 is only partially resolved: the view-local DEBUG recommendation fixture branch is still present because removing it safely would require broadening the test-fixture change beyond the owned files for this fix.
