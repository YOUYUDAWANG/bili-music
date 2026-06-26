---
phase: 03-player-interaction-and-regression-coverage
plan: 01
subsystem: ui
tags: [swiftui, player-gestures, xctest, ui-tests]

requires:
  - phase: 01-playback-critical-path-and-responsiveness
    provides: playback startup and image memory guardrails reused by regression tests
  - phase: 02-discovery-reliability-and-music-only-results
    provides: stable recommendation and search fixture behavior used by player chrome tests
provides:
  - mini-player upward drag policy with deterministic progress, completion, and cancellation thresholds
  - SwiftUI full-player presentation that tracks mini-player pull-up progress
  - UI and unit coverage for deliberate mini-player open and shallow-drag cancel behavior
affects: [player-interaction, player-chrome-tests, playback-regressions, image-cache-regressions]

tech-stack:
  added: []
  patterns:
    - deterministic gesture policy math in PlayerGesturePolicy
    - RootView transition state driven by rendered player open progress
    - fixture-driven XCTest coverage for player chrome interactions

key-files:
  created:
    - .planning/phases/03-player-interaction-and-regression-coverage/03-01-SUMMARY.md
  modified:
    - BiliMusic/Features/RootView.swift
    - BiliMusic/Features/Player/PlayerGesturePolicy.swift
    - BiliMusicTests/PlayerGesturePolicyTests.swift
    - BiliMusicUITests/PlayerChromeUITests.swift

key-decisions:
  - "Mini-player pull-up completion uses deterministic policy thresholds, including distance and projected velocity, rather than view-local ad hoc gesture checks."
  - "The full-player overlay tracks rendered open progress for offset, opacity, and scale while Reduced Motion keeps scale disabled through existing guards."
  - "The UI fixture uses mini-player-relative drag coordinates to avoid simulator-global coordinate drift while preserving deliberate-open and shallow-cancel coverage."

patterns-established:
  - "Player drag math lives in PlayerGesturePolicy and is covered by pure unit tests before SwiftUI presentation behavior depends on it."
  - "RootView presents the full player from mini-player drag progress without adding playback, image, network, blur, or physics work to the gesture path."

requirements-completed: [PLYR-01, TEST-02, TEST-05]

duration: 35min
completed: 2026-06-27
status: complete
---

# Phase 03 Plan 01: Mini-Player Pull-Up Transition Summary

**Mini-player upward drag now pulls the full player from the bottom through deterministic gesture thresholds, with playback and image guardrail regressions still green.**

## Performance

- **Duration:** 35 min
- **Started:** 2026-06-26T21:50:11Z
- **Completed:** 2026-06-26T22:25:03Z
- **Tasks:** 3
- **Files modified:** 4 source/test files plus this summary

## Accomplishments

- Added mini-player pull-up policy coverage for progress clamping, monotonic upward progress, deliberate activation, projected velocity, and short-drag cancellation.
- Updated RootView so mini-player drag progress drives the full-player overlay offset, opacity, and scale while the mini-player fades and scales away from the same rendered progress.
- Added fixture UI coverage for deliberate mini-player open and shallow upward drag cancellation.
- Re-ran playback startup and image cache guardrails after the visual transition changes.

## Task Commits

Each task was committed or verified at its natural atomic boundary:

1. **Task 1: Add mini-player pull-up policy and fixture expectations** - `3a5be31` (test RED)
2. **Task 1 GREEN + Task 2: Make full-player presentation finger-track mini-player drag** - `8a5bdb5` (feat)
3. **Task 3: Preserve playback and image guardrails while changing transition surfaces** - verified with no source changes required

**Plan metadata:** recorded in the final docs commit.

## Files Created/Modified

- `BiliMusic/Features/Player/PlayerGesturePolicy.swift` - tightened mini-player open thresholds, live-open threshold, projected activation threshold, and begin-drag gate.
- `BiliMusic/Features/RootView.swift` - made full-player opacity and scale track rendered pull-up progress and kept mini-player drag sampling in global coordinates.
- `BiliMusicTests/PlayerGesturePolicyTests.swift` - added policy coverage for pull-up progress and open/cancel threshold behavior.
- `BiliMusicUITests/PlayerChromeUITests.swift` - added and stabilized mini-player deliberate-open and shallow-cancel fixture paths.

## Decisions Made

- Mini-player opening remains state-driven through `openFullPlayer(startProgress:)`, `handleMiniOpenDragChanged`, `handleMiniOpenDragEnded`, and `renderedPlayerOpenProgress`; no overlay architecture replacement was needed.
- Reduced Motion stays handled in the transition layer: scale effects are disabled when Reduce Motion is enabled, while offset and opacity continue to preserve hierarchy.
- The shallow UI drag fixture uses a smaller physical drag than the unit threshold case because XCUITest synthesizes projected velocity; unit tests retain the lower-level distance/velocity cancellation assertions.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/phase03-plan01 CODE_SIGNING_ALLOWED=NO -only-testing:BiliMusicTests/PlayerGesturePolicyTests -only-testing:BiliMusicUITests/PlayerChromeUITests`
  - Passed: 7 `PlayerChromeUITests` and 8 `PlayerGesturePolicyTests`, 0 failures.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/phase03-plan01-regressions CODE_SIGNING_ALLOWED=NO -only-testing:BiliMusicTests/PlaybackCriticalPathTests -only-testing:BiliMusicTests/ImageCacheTests`
  - Passed: 8 `ImageCacheTests` and 4 `PlaybackCriticalPathTests`, 0 failures.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added scheme to the Task 3 regression command**
- **Found during:** Task 3
- **Issue:** The plan's regression command used `-target BiliMusicTests` with `-derivedDataPath`; this Xcode version rejected that combination unless `-scheme`, `-testProductsPath`, or `-xctestrun` was supplied.
- **Fix:** Re-ran the same selected regression tests through the existing `BiliMusic` scheme and the requested simulator destination.
- **Files modified:** None
- **Verification:** Corrected command passed 12 selected regression tests with 0 failures.
- **Committed in:** Documentation only; no source change was required.

---

**Total deviations:** 1 auto-fixed (1 blocking verification command)
**Impact on plan:** Verification intent was preserved. No product scope or dependency changes were introduced.

## Issues Encountered

- XCUITest projects velocity for short drag gestures, so the UI shallow-drag fixture uses a very small drag while `PlayerGesturePolicyTests` cover the underlying cancellation threshold behavior directly.

## Known Stubs

None. Stub scan found only existing nil/state checks and the mini-player artwork placeholder closure, not unfinished data or UI placeholders introduced by this plan.

## Threat Flags

None. The plan changed local SwiftUI gesture and transition behavior only; it introduced no new network endpoints, auth paths, file access, schema changes, package installs, image preloading, or playback-startup work.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

03-02 can build on a full-player presentation path that now tracks mini-player drag progress and is covered by focused policy/UI tests. The playback and image guardrails used by later regression coverage remain green.

---
*Phase: 03-player-interaction-and-regression-coverage*
*Completed: 2026-06-27*

## Self-Check: PASSED

- Summary file exists at `.planning/phases/03-player-interaction-and-regression-coverage/03-01-SUMMARY.md`.
- Source/test files touched by the plan exist.
- Commits `3a5be31` and `8a5bdb5` are present in git history.
