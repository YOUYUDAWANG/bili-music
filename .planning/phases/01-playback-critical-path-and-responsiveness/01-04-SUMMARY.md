---
phase: 01-playback-critical-path-and-responsiveness
plan: 04
subsystem: recommendations
tags: [recommendations, playback-priority, home, swiftui, xctest]

requires:
  - phase: 01-01
    provides: Phase 1 fixture and playback chrome test foundation
  - phase: 01-02
    provides: Protected playback critical path for direct playback startup
provides:
  - Stable Home recommendation rows during first playback
  - Explicit Home recommendation scheduling policy with bounded work
  - Regression coverage proving Home work is not referenced from direct playback startup
affects: [phase-01, recommendations, playback, home]

tech-stack:
  added: []
  patterns:
    - RecommendationSchedulingPolicy for explicit Home recommendation triggers and bounds
    - HomeView passes initial-load/manual-refresh intent at the recommendation boundary

key-files:
  created: []
  modified:
    - BiliMusic/Features/Home/HomeView.swift
    - BiliMusic/Player/RecommendationEngine.swift
    - BiliMusicTests/RecommendationSchedulingTests.swift

key-decisions:
  - "Home recommendation calls now name their trigger and carry explicit seed/request bounds."
  - "Home recommendation scoring and fan-out child tasks run at utility priority; radio and related panel keep interactive priority."
  - "Direct playback remains free of Home recommendation refresh references."

patterns-established:
  - "Home recommendation work should enter through HomeView load/manual refresh paths, not PlayerEngine playback paths."
  - "RecommendationEngine mode defaults preserve existing radio/related behavior while allowing Home to opt into lower-priority scheduling."

requirements-completed: [RECO-01, RECO-04]

duration: 8 min
completed: 2026-06-26
status: complete
---

# Phase 01 Plan 04: Home Recommendation Stability Summary

**Home recommendations now stay stable during first playback and run through an explicit bounded low-priority scheduling policy**

## Performance

- **Duration:** 8 min
- **Started:** 2026-06-26T06:54:26Z
- **Completed:** 2026-06-26T07:01:38Z
- **Tasks:** 2 completed
- **Files modified:** 3 tracked files

## Accomplishments

- Kept the existing Home-row stability fixture test as RECO-01 coverage: tapping `homeTrackRow0` opens the mini player while the row remains visible.
- Added `RecommendationSchedulingPolicy` with explicit Home triggers, seed bounds, fallback bounds, and `.utility` priority.
- Changed Home initial load, pull refresh, and `换一批` to pass `.initialHomeLoad` or `.manualRefresh` into `RecommendationEngine`.
- Applied the Home policy to favorite seed count, related-per-seed count, history/cache seed count, fallback keyword count, scoring priority, and fan-out child task priority.
- Preserved radio and related-panel defaults at `.userInitiated` so next-radio behavior remains interactive.

## Task Commits

1. **Task 2 RED: Add failing recommendation scheduling policy tests** - `aaac7ff` (test)
2. **Task 2 GREEN: Bound Home recommendation scheduling** - `229b19b` (feat)

**Plan metadata:** this SUMMARY commit.

## Files Created/Modified

- `BiliMusic/Features/Home/HomeView.swift` - Passes explicit initial-load/manual-refresh triggers and Home policy into recommendation fetches.
- `BiliMusic/Player/RecommendationEngine.swift` - Adds `RecommendationSchedulingPolicy`, policy-aware bounds, and policy-driven priority for Home recommendation work.
- `BiliMusicTests/RecommendationSchedulingTests.swift` - Covers Home policy bounds, lower priority, radio default priority, and absence of Home refresh references in `PlayerEngine`.

## Decisions Made

- Kept policy defaults inside `RecommendationEngine` so existing radio and player-related callers do not need source changes.
- Used `.utility` for Home recommendation scheduling because playback startup is the direct user action and must remain higher priority.
- Did not add broad BiliClient, auth, cache, or favorite-folder rewrites; this plan stays at the Home/RecommendationEngine boundary.

## Deviations from Plan

None - plan executed within the planned recommendation/Home boundary.

## Issues Encountered

- Running two `xcodebuild` commands in parallel hit the DerivedData `build.db` lock. Re-running the focused test sequentially passed.
- Xcode still prints the known passcode-protected physical-device warning and empty supported-platform warning. They did not block simulator tests.

## Verification

- PASS: RED `build-for-testing` failed before GREEN because `RecommendationSchedulingPolicy` did not exist.
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicTests/RecommendationSchedulingTests CODE_SIGNING_ALLOWED=NO`
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicUITests/PlayerChromeUITests/testTappingRecommendationKeepsHomeListStable CODE_SIGNING_ALLOWED=NO`
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicTests CODE_SIGNING_ALLOWED=NO`

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for `01-05`: image memory and cache pressure work can proceed with playback and recommendation scheduling guarded.

## Self-Check: PASSED

- Key files exist on disk.
- Two commits exist for `01-04`.
- RECO-01 is covered by the Home-row UI fixture.
- RECO-04 is covered by `RecommendationSchedulingTests`.
- Direct playback startup still has no `mode: .home`, `initialHomeLoad`, or `manualRefresh` references.

---
*Phase: 01-playback-critical-path-and-responsiveness*
*Completed: 2026-06-26*
