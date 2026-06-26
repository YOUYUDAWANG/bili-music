---
phase: 03-player-interaction-and-regression-coverage
plan: 02
subsystem: ui
tags: [swiftui, player, toolbar, recommendations, regression-tests]

requires:
  - phase: 02-discovery-reliability-and-music-only-results
    provides: recommendation tap stability and related-panel refresh policy
provides:
  - Dense Apple Music-like full-player center page without bottom context card stacks
  - Persistent player toolbar for lyrics, favorite, cache/download, quality, and MV switching
  - Stable queue/recommendation page identifiers and recommendation tap regression coverage
affects: [player, now-playing, recommendations, ui-tests]

tech-stack:
  added: []
  patterns:
    - SwiftUI toolbar controls with shared active, disabled, busy, and accessibility states
    - Lightweight page-dot/title hints replacing segmented full-player top chrome

key-files:
  created:
    - .planning/phases/03-player-interaction-and-regression-coverage/03-02-SUMMARY.md
  modified:
    - BiliMusic/Features/Player/NowPlayingView.swift
    - BiliMusic/Features/Player/PlayerControlViews.swift
    - BiliMusicTests/RecommendationSchedulingTests.swift

key-decisions:
  - "Full-player page navigation uses lightweight page hints; MV/music switching moved into the persistent toolbar instead of a segmented top control."
  - "Center Now Playing no longer renders queue or playlist context panels; queue and recommendations stay on horizontal side pages."
  - "Recommendation tap stability is protected by a regression assertion that suppression is assigned before related playback starts."

patterns-established:
  - "PlayerToolbarActionButton centralizes toolbar hit target, active, disabled, busy, and accessibility behavior."
  - "Player side pages expose stable accessibility identifiers for page bodies and empty/loading/error states."

requirements-completed: [PLYR-03, PLYR-05, TEST-03]

duration: 10min
completed: 2026-06-27
status: complete
---

# Phase 03 Plan 02: Dense Player Layout, Toolbar, and Pages Summary

**Dense Now Playing surface with persistent toolbar actions and stable side-page recommendation regressions.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-06-26T22:30:39Z
- **Completed:** 2026-06-26T22:40:31Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Reshaped the center Now Playing page into a denser playback surface with large cover, capped metadata, progress, transport controls, queue-mode affordance, and a unified toolbar.
- Replaced the visible segmented top control with lightweight page dots/title plus a close affordance; MV/music switching now lives in the toolbar.
- Added five persistent toolbar actions: lyrics, favorite, cache/download, audio quality, and MV switch, reusing existing manager and player-engine behavior.
- Kept queue and recommendations as horizontal side pages with stable identifiers and Chinese empty/loading/error states.
- Added a focused recommendation regression proving the related-track tap suppression remains before the playback call.

## Task Commits

1. **Task 1: Reshape center Now Playing into the approved dense layout** - `67ee3e4` (feat)
2. **Task 2: Build the persistent Apple Music-like toolbar** - `a407900` (feat)
3. **Task 3: Keep queue and recommendations as stable horizontal pages** - `b545c47` (feat)

## Files Created/Modified

- `BiliMusic/Features/Player/NowPlayingView.swift` - Dense center layout, lightweight top chrome/page hints, persistent toolbar wiring, side-page state identifiers, and stable recommendation tap handling.
- `BiliMusic/Features/Player/PlayerControlViews.swift` - Added reusable toolbar button/label visuals for active, disabled, busy, and accessible states.
- `BiliMusicTests/RecommendationSchedulingTests.swift` - Added regression coverage for recommendation tap suppression ordering.

## Decisions Made

- Full-player page selection is now communicated through page dots and a Chinese page title instead of the earlier segmented top control.
- Queue play mode remains near the transport controls so it does not displace the required five persistent toolbar actions.
- Unavailable lyrics and unavailable MV remain aligned in the toolbar with disabled/inactive accessibility labels rather than disappearing.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -derivedDataPath build/phase03-plan02 CODE_SIGNING_ALLOWED=NO build` - passed after Task 1 and Task 2.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath build/phase03-plan02-regressions CODE_SIGNING_ALLOWED=NO -only-testing:BiliMusicTests/RecommendationSchedulingTests` - passed, 10 tests with 0 failures.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Adjusted Xcode verification invocation**
- **Found during:** Task 1 and Task 3 verification
- **Issue:** The planned `xcodebuild` commands used `-target` with `-derivedDataPath`; this Xcode requires `-scheme` for that combination, and tests require a concrete simulator destination.
- **Fix:** Used the equivalent `BiliMusic` scheme build and the installed iPhone 17 simulator destination for the focused test run.
- **Files modified:** None
- **Verification:** Scheme build passed; focused `RecommendationSchedulingTests` passed.
- **Committed in:** N/A - verification command adjustment only.

---

**Total deviations:** 1 auto-fixed (1 blocking verification issue)
**Impact on plan:** No product scope change. The adjusted commands verified the same app target and focused recommendation tests required by the plan.

## Issues Encountered

- The simulator test command needed a concrete destination; rerunning on `iPhone 17, OS 26.3.1` resolved it.

## Known Stubs

None - stub scan found only existing state initializers, real empty/loading UI states, and the intentional `CachedAsyncImage` placeholder.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 03 can add UI-level assertions against the stable identifiers for cover, metadata, progress, transport controls, toolbar, page hint, queue page, and recommendation page states.

## Self-Check: PASSED

- Found modified files: `BiliMusic/Features/Player/NowPlayingView.swift`, `BiliMusic/Features/Player/PlayerControlViews.swift`, `BiliMusicTests/RecommendationSchedulingTests.swift`.
- Found task commits: `67ee3e4`, `a407900`, `b545c47`.
- No unexpected file deletions were committed.

---
*Phase: 03-player-interaction-and-regression-coverage*
*Completed: 2026-06-27*
