---
phase: 01-playback-critical-path-and-responsiveness
plan: 02
subsystem: playback
tags: [playback, avplayer, stream-resolver, performance, xctest]

requires:
  - phase: 01-01
    provides: Sanitized playback diagnostics and Phase 1 regression test homes
provides:
  - Protected tap-to-play critical path that assigns current track before awaited source resolution
  - Source-kind-aware playback start model for local cache, prepared remote, fresh remote, and MV remote sources
  - One-retry prepared remote audio invalidation path
  - Regression coverage for post-first-playing enrichment ordering and prepared-stream retry behavior
affects: [phase-01, playback, stream-resolution, diagnostics]

tech-stack:
  added: []
  patterns:
    - Source-kind-aware PlaybackSource boundary inside PlayerEngine
    - Injectable AudioStreamResolving seam for playback unit tests
    - AVPlayerItem failure/status retry guard scoped to the active playback generation

key-files:
  created: []
  modified:
    - BiliMusic/Player/PlayerEngine.swift
    - BiliMusic/Player/StreamResolver.swift
    - BiliMusicTests/PlaybackCriticalPathTests.swift
    - BiliMusicTests/PreparedStreamRetryTests.swift

key-decisions:
  - "First playback now waits only for cache hit, prepared audio hit, or one fresh audio stream before the AVPlayer play request."
  - "History, artwork, and lyrics are the only work scheduled after first observed playing by the first playback path."
  - "Prepared remote stream retry is generation-scoped and memory-only; remote playurl values are not persisted."

patterns-established:
  - "PlaybackSource carries source kind, URL locality, quality, and bandwidth through startPlayback for diagnostics and retry behavior."
  - "AudioStreamResolving lets unit tests exercise PlayerEngine without live Bilibili network or AVPlayer playback."
  - "simulateCurrentPlaybackItemFailureForTesting drives the same prepared-stream failure path used by AVPlayer item failure observers."

requirements-completed: [PLAY-01, PLAY-02, PLAY-04, PLAY-05]

duration: 15 min
completed: 2026-06-26
status: complete
---

# Phase 01 Plan 02: Playback Critical Path Summary

**Tap-to-play now reaches AVPlayer through a protected minimal source path, with prepared stream retry covered by real PlayerEngine tests**

## Performance

- **Duration:** 15 min
- **Started:** 2026-06-26T05:55:58Z
- **Completed:** 2026-06-26T06:09:48Z
- **Tasks:** 2 completed
- **Files modified:** 4 tracked files

## Accomplishments

- Split playback startup into explicit source resolution and playback start steps.
- Added `PlaybackSource` and `AudioStreamResolving` so playback tests can observe source kind and avoid live network/AVPlayer work.
- Moved history persistence out of the pre-play request path; post-first-playing scheduling is limited to history, artwork, and lyrics.
- Added prepared remote failure handling that invalidates cached prepared audio, resolves one fresh stream, and retries without another user tap.
- Replaced the prepared-stream retry fixture test with real `PlayerEngine` tests for invalidation, one retry, and failure surfacing.

## Task Commits

1. **Task 1 RED: Add playback critical path failing tests** - `9a956f1` (test)
2. **Task 1 GREEN: Protect playback critical path** - `bd8d6a0` (feat)
3. **Task 2: Cover prepared stream retry path** - `8c62a10` (test)

**Plan metadata:** this SUMMARY commit.

## Files Created/Modified

- `BiliMusic/Player/PlayerEngine.swift` - Adds `PlaybackSource`, injectable startup hooks, protected source resolution, post-first-playing scheduling, and prepared stream failure retry.
- `BiliMusic/Player/StreamResolver.swift` - Adds `AudioStreamResolving` protocol conformance for testable source resolution and invalidation.
- `BiliMusicTests/PlaybackCriticalPathTests.swift` - Verifies current assignment precedes awaited source resolution, pre-play source resolution stays minimal, and first-playing schedules only allowed post-sound work.
- `BiliMusicTests/PreparedStreamRetryTests.swift` - Verifies prepared remote failure invalidates matching/fallback keys, retries once with a fresh stream, and surfaces failure without looping.

## Decisions Made

- Kept retry state in `PlayerEngine` memory and scoped it to the current playback generation.
- Retried only `.preparedRemote` failures. Fresh remote, local cache, and MV failures do not loop through the prepared-stream retry path.
- Kept MV preparation, recommendation loading, queue/radio prefetch, and auto-cache out of the first playback post-sound task.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Shared implementation boundary] Prepared retry skeleton landed with Task 1 GREEN**
- **Found during:** Task 2 (`Retry expired prepared audio once`)
- **Issue:** The AVPlayer item failure observers and retry handler were introduced while refactoring `startPlayback` for Task 1 because the source-kind boundary and observer cleanup were shared with the critical-path extraction.
- **Fix:** Left the shared implementation in `bd8d6a0` and used Task 2 to replace the old fixture test with real `PlayerEngine` regression coverage.
- **Files modified:** `BiliMusic/Player/PlayerEngine.swift`, `BiliMusicTests/PreparedStreamRetryTests.swift`
- **Verification:** `PreparedStreamRetryTests`, `PlaybackCriticalPathTests`, `PlaybackDiagnosticsTests`, and the full `BiliMusicTests` target passed.
- **Committed in:** `bd8d6a0` and `8c62a10`

---

**Total deviations:** 1 auto-fixed (shared playback implementation boundary).
**Impact on plan:** No scope expansion. The final behavior and tests match the 01-02 acceptance criteria.

## Issues Encountered

- Running two `xcodebuild test` commands in parallel caused one simulator test process to exit before bootstrapping. The same `PlaybackCriticalPathTests` command passed when rerun sequentially.
- Xcode continues to print noisy warnings about a passcode-protected physical device and empty supported-platform metadata. These warnings did not affect simulator test pass results.

## Verification

- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicTests/PreparedStreamRetryTests CODE_SIGNING_ALLOWED=NO`
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicTests/PlaybackDiagnosticsTests CODE_SIGNING_ALLOWED=NO`
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicTests/PlaybackCriticalPathTests CODE_SIGNING_ALLOWED=NO`
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicTests CODE_SIGNING_ALLOWED=NO`
- PASS: `git diff --check`
- PASS: Source check found no `CacheStore`, `UserDefaults`, or JSON persistence writes for remote audio URLs in the playback retry path.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for `01-03`: first playback can now be protected from recommendation refresh work using the committed source-resolution and diagnostics seams.

## Self-Check: PASSED

- Key files exist on disk.
- Three commits exist for `01-02`.
- Acceptance criteria for PLAY-01, PLAY-02, PLAY-04, and PLAY-05 are covered by focused tests.
- Remote media URLs remain memory-only in playback and stream resolver code.

---
*Phase: 01-playback-critical-path-and-responsiveness*
*Completed: 2026-06-26*
