---
phase: 03-player-interaction-and-regression-coverage
plan: 03
subsystem: ui-testing
tags: [swiftui, player, gestures, xctest, xcuitest]

requires:
  - phase: 03-player-interaction-and-regression-coverage
    provides: Mini-player pull-up transition and dense player page layout from plans 03-01 and 03-02.
provides:
  - Region-aware full-player dismiss policy with list/scrub/page-swipe conflict protection.
  - Compact and modern player chrome UI regression coverage.
  - Preserved search, playback, recommendation, image-cache, and gesture unit regressions.
affects: [player, gestures, ui-tests, regression-coverage]

tech-stack:
  added: []
  patterns:
    - Region-aware SwiftUI gesture ownership through PlayerGesturePolicy.
    - XCUITest fixture checks for player chrome density and conflict boundaries.

key-files:
  created:
    - .planning/phases/03-player-interaction-and-regression-coverage/03-03-SUMMARY.md
  modified:
    - BiliMusic/Features/Player/NowPlayingView.swift
    - BiliMusic/Features/Player/PlayerControlViews.swift
    - BiliMusic/Features/Player/PlayerGesturePolicy.swift
    - BiliMusicTests/PlayerGesturePolicyTests.swift
    - BiliMusicUITests/PlayerChromeUITests.swift

key-decisions:
  - "Queue and recommendation list bodies own vertical scrolling; full-player minimize is restricted to top chrome on those pages."
  - "Progress scrub owns the full progress block, including labels, so TabView page swipes cannot steal scrub gestures."
  - "Dense player layout gates run on both compact and modern simulator sizes."

patterns-established:
  - "Gesture conflict policy is tested in pure PlayerGesturePolicy tests before wiring into SwiftUI."
  - "PlayerChromeUITests uses stable accessibility identifiers for page hint, cover, metadata, progress, transport controls, and toolbar."
  - "Progress scrub suppression is treated as player-page ownership, not only as a visual progress-bar interaction."

requirements-completed:
  - PLYR-02
  - PLYR-03
  - PLYR-04
  - PLYR-05
  - TEST-01
  - TEST-02
  - TEST-03
  - TEST-05

duration: 30min
completed: 2026-06-27
status: complete
---

# Phase 03-03: Region-Aware Gesture Conflicts and Preserved Regressions Summary

**Player gestures now have explicit ownership across minimize, list scroll, progress scrub, and page swipe, backed by compact/modern UI checks plus preserved v1 regression suites.**

## Performance

- **Duration:** 30 min
- **Started:** 2026-06-27T00:10:00Z
- **Completed:** 2026-06-27T00:23:46Z
- **Tasks:** 3
- **Files modified:** 5 source/test files plus this summary

## Accomplishments

- Added deterministic `PlayerGesturePolicy` coverage for center body, top chrome, list body, horizontal page intent, and active progress scrub suppression.
- Wired `NowPlayingView` so center body can deliberately minimize, list pages do not minimize from scroll bodies, top chrome can minimize across pages, and progress/page gestures have explicit conflict guards.
- Added `PlayerChromeUITests` coverage for queue/recommendation list drag, progress scrub, horizontal page swipe, and dense layout frame/order/bottom-gap gates.
- Fixed a real SE-sized progress hit-target issue by making the whole progress block own scrub gestures, preventing `TabView(.page)` from stealing horizontal progress drags.
- Re-ran preserved search, playback, recommendation, image-cache, and gesture regression suites.

## Task Commits

1. **Task 1: Add pure gesture conflict policy coverage** - `58e673c` (test) and `3e8ff7a` (feat)
2. **Task 2: Wire dismiss regions and gesture ownership into Now Playing** - `11656fb` (feat)
3. **Task 3: Add UI conflict checks and run preserved regression suite** - `091e8ed` (test/fix)

## Files Created/Modified

- `BiliMusic/Features/Player/PlayerGesturePolicy.swift` - Region-aware dismiss and horizontal page-swipe policy.
- `BiliMusicTests/PlayerGesturePolicyTests.swift` - Pure unit tests for dismiss/page/scrub ownership rules.
- `BiliMusic/Features/Player/NowPlayingView.swift` - SwiftUI wiring for player-page gestures, scrub suppression, frame identifiers, and layout test hooks.
- `BiliMusic/Features/Player/PlayerControlViews.swift` - Progress scrub gesture expanded to the full progress block so accessibility hit targets do not leak to page swipe.
- `BiliMusicUITests/PlayerChromeUITests.swift` - UI tests for list-scroll non-dismissal, progress scrub/page conflicts, horizontal page swipe, and compact/modern dense layout.

## Decisions Made

- Used region-aware policy instead of ad hoc SwiftUI checks so the behavior is unit-testable and stable across layout changes.
- Kept list-page minimize restricted to top chrome; queue and recommendation list bodies should never close the player during vertical scroll.
- Treated the full progress block as scrub-owned, because XCUITest and VoiceOver hit targets may land on the time labels instead of the thin visual track.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Progress label hit target still allowed TabView page swipe**
- **Found during:** Task 3 compact UI verification
- **Issue:** On `iPhone SE (3rd generation)`, dragging the `nowPlayingProgress` accessibility element could land on the progress time label. The inner progress track did not receive `onScrubChanged(true)`, so `TabView(.page)` handled the horizontal drag and switched to the queue page.
- **Fix:** Expanded `PlayerProgressBar`'s high-priority drag gesture from the thin track to the full padded progress block, including labels, and mapped gesture coordinates back to the measured track width.
- **Files modified:** `BiliMusic/Features/Player/PlayerControlViews.swift`
- **Verification:** Re-ran the failing SE progress-scrub UI test, then full compact and modern `PlayerChromeUITests`.
- **Committed in:** `091e8ed`

---

**Total deviations:** 1 auto-fixed (Rule 2)
**Impact on plan:** Required for PLYR-04 correctness. No scope expansion beyond player gesture ownership.

## Issues Encountered

- The original preserved unit command needed `-scheme BiliMusic` and a concrete simulator destination with current Xcode. The same test set was re-run on `iPhone 17` with unchanged `only-testing` filters.

## Verification

- `xcodebuild test ... -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)' ... -only-testing:BiliMusicUITests/PlayerChromeUITests/testProgressScrubDoesNotDismissOrChangePlayerPage` - passed.
- `xcodebuild test ... -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)' ... -only-testing:BiliMusicUITests/PlayerChromeUITests` - passed, 12 tests.
- `xcodebuild test ... -destination 'platform=iOS Simulator,name=iPhone 16' ... -only-testing:BiliMusicUITests/PlayerChromeUITests` - passed, 12 tests.
- `xcodebuild test ... -destination 'platform=iOS Simulator,name=iPhone 17' ... -only-testing:BiliMusicTests/SearchModelsTests -only-testing:BiliMusicTests/PlaybackCriticalPathTests -only-testing:BiliMusicTests/RecommendationSchedulingTests -only-testing:BiliMusicTests/ImageCacheTests -only-testing:BiliMusicTests/PlayerGesturePolicyTests` - passed, 46 tests.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 3 now has coverage for mini-player expansion, full-player minimization, list scroll ownership, progress scrub ownership, page swipe ownership, dense layout checks, and preserved v1 regressions. v1 stabilization can move to final audit/milestone close-out, with broader API/auth/cache/music-feature polish still deferred to v2 unless the user reprioritizes it.

---
*Phase: 03-player-interaction-and-regression-coverage*
*Completed: 2026-06-27*
