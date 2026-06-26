---
phase: 01-playback-critical-path-and-responsiveness
plan: 01
subsystem: testing
tags: [playback, diagnostics, xctest, xcuitest, phase-1]

requires: []
provides:
  - Sanitized playback diagnostics event model and sink
  - Tap-to-first-play checkpoint emission from PlayerEngine
  - Phase 1 XCTest homes for playback, retry, search focus, recommendation scheduling, and image cache work
  - Fixture-safe UI helper for Home recommendation stability
affects: [phase-01, playback, search, recommendations, images, player-ui]

tech-stack:
  added: []
  patterns:
    - OSLog-backed value-only diagnostics
    - XCTest fixture homes for future Phase 1 behavior assertions
    - XCUITest fixture helper extraction

key-files:
  created:
    - BiliMusic/Player/PlaybackDiagnostics.swift
    - BiliMusicTests/PlaybackDiagnosticsTests.swift
    - BiliMusicTests/PlaybackCriticalPathTests.swift
    - BiliMusicTests/PreparedStreamRetryTests.swift
    - BiliMusicTests/SearchFocusTests.swift
    - BiliMusicTests/RecommendationSchedulingTests.swift
    - BiliMusicTests/ImageCacheTests.swift
  modified:
    - BiliMusic/Player/PlayerEngine.swift
    - BiliMusicUITests/PlayerChromeUITests.swift

key-decisions:
  - "Playback diagnostics record only checkpoint, bvid, cid, source kind, quality, bandwidth, and elapsed time; they never carry media URLs or auth/header material."
  - "The plan's documented unit-target xcodebuild command is invalid for this generated project, so verification used the BiliMusic scheme with -only-testing:BiliMusicTests."

patterns-established:
  - "PlaybackDiagnostics.InMemorySink gives tests value-level access without scraping OSLog."
  - "Phase 1 regression files now exist as compile-ready homes for later behavior assertions."

requirements-completed: [PLAY-03]

duration: 8 min
completed: 2026-06-26
status: complete
---

# Phase 01 Plan 01: Feedback Harness Summary

**Sanitized playback diagnostics and runnable Phase 1 XCTest/XCUITest regression homes**

## Performance

- **Duration:** 8 min
- **Started:** 2026-06-26T05:40:12Z
- **Completed:** 2026-06-26T05:48:15Z
- **Tasks:** 2 completed
- **Files modified:** 8 tracked files

## Accomplishments

- Added `PlaybackDiagnostics` with ordered checkpoint events, OSLog output, and an in-memory sink for tests.
- Wired `PlayerEngine` to emit tap, current assignment, source resolution, player item creation, play request, and first observed playing checkpoints.
- Added Phase 1 regression test homes for playback critical path, prepared-stream retry, search focus, recommendation scheduling, and image cache behavior.
- Extracted the Home recommendation stability UI assertion into a fixture-safe helper.

## Task Commits

1. **Task 1 RED: Add playback diagnostics failing tests** - `994af36` (test)
2. **Task 1 GREEN: Add sanitized playback diagnostics seam** - `df20de0` (feat)
3. **Task 2: Create Phase 1 regression test homes and fixture assertions** - `03fb682` (test)

**Plan metadata:** this SUMMARY commit.

## Files Created/Modified

- `BiliMusic/Player/PlaybackDiagnostics.swift` - Sanitized playback checkpoint event model, OSLog sink, and test in-memory sink.
- `BiliMusic/Player/PlayerEngine.swift` - Emits playback diagnostics without changing queue/source/player ordering.
- `BiliMusicTests/PlaybackDiagnosticsTests.swift` - Verifies checkpoint ordering and payload sanitization.
- `BiliMusicTests/PlaybackCriticalPathTests.swift` - Provides playback critical-path fixture assertions.
- `BiliMusicTests/PreparedStreamRetryTests.swift` - Provides prepared remote retry fixture assertions.
- `BiliMusicTests/SearchFocusTests.swift` - Provides local-only search focus fixture assertions.
- `BiliMusicTests/RecommendationSchedulingTests.swift` - Provides Home recommendation scheduling fixture assertions.
- `BiliMusicTests/ImageCacheTests.swift` - Provides image cache smoke assertions.
- `BiliMusicUITests/PlayerChromeUITests.swift` - Reuses a helper for fixture Home list stability.

## Decisions Made

- Diagnostic events are value-only. They intentionally omit titles, URLs, headers, Cookies, and request dictionaries to reduce leakage risk.
- `PlayerEngine` records only the first `.playing` transition per playback generation, avoiding duplicate first-playing checkpoints after buffer recovery.
- Future Phase 1 plans can extend the new test files instead of creating additional scattered test surfaces.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added local ignored signing config for XcodeGen**
- **Found during:** Task 1 verification
- **Issue:** `xcodegen generate` failed because `project.yml` references `Local.xcconfig`, which was absent in this checkout.
- **Fix:** Created ignored local `Local.xcconfig` with an empty `DEVELOPMENT_TEAM` so simulator builds can generate.
- **Files modified:** `Local.xcconfig` local ignored file only; not committed.
- **Verification:** `xcodegen generate` succeeded before all later test runs.
- **Committed in:** not committed by design; file is machine-local and ignored.

---

**Total deviations:** 1 auto-fixed (blocking local environment setup).
**Impact on plan:** No product scope change. The generated project and tests now run in this checkout.

## Issues Encountered

- The documented quick command `xcodebuild test -project BiliMusic.xcodeproj -target BiliMusicTests -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO` fails because `xcodebuild test` requires a scheme. Verification used the equivalent working form:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicTests CODE_SIGNING_ALLOWED=NO`.

## Verification

- PASS: `xcodegen generate`
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicTests/PlaybackDiagnosticsTests CODE_SIGNING_ALLOWED=NO`
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicTests CODE_SIGNING_ALLOWED=NO`
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicUITests/PlayerChromeUITests/testTappingRecommendationKeepsHomeListStable CODE_SIGNING_ALLOWED=NO`
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for `01-02`: playback critical path and prepared-stream retry can now add behavior assertions against existing diagnostics and test homes.

## Self-Check: PASSED

- Key files exist on disk.
- Three task commits exist for `01-01`.
- Unit and UI fixture verification passed.
- `PLAY-03` is covered by executable diagnostics tests.

---
*Phase: 01-playback-critical-path-and-responsiveness*
*Completed: 2026-06-26*
