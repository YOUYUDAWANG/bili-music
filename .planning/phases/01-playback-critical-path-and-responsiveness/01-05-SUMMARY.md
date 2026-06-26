---
phase: 01-playback-critical-path-and-responsiveness
plan: 05
subsystem: image-memory
tags: [images, memory, downsampling, swiftui, xctest]

requires:
  - phase: 01-02
    provides: Protected playback critical path and post-start enrichment ordering
  - phase: 01-03
    provides: Search focus responsiveness boundary
  - phase: 01-04
    provides: Bounded recommendation scheduling below playback priority
provides:
  - Display-size-aware image cache keys and target-size downsampling
  - Coalesced URL plus target-size image loading
  - Background and memory-warning cleanup for reloadable decoded images
affects: [phase-01, images, playback, search, recommendations, player]

tech-stack:
  added: []
  patterns:
    - Image cache entries are keyed by URL plus target pixel size
    - ImageIO downsampling happens before decoded UIImages enter memory cache
    - AppResourceCleanup centralizes reloadable image release on background and memory warning

key-files:
  created:
    - .planning/phases/01-playback-critical-path-and-responsiveness/01-05-SUMMARY.md
  modified:
    - BiliMusic/Design/CachedAsyncImage.swift
    - BiliMusic/Design/TrackRow.swift
    - BiliMusic/Features/RootView.swift
    - BiliMusic/Features/Player/NowPlayingView.swift
    - BiliMusic/Player/PlayerEngine.swift
    - BiliMusicTests/ImageCacheTests.swift

key-decisions:
  - "Visible image surfaces pass display target sizes instead of relying on URL-only full-image decode."
  - "The mini-player no longer prewarms a 960x540 image on every track change."
  - "Background and memory-pressure cleanup release only reloadable decoded images and preserve PlayerEngine playback state."

patterns-established:
  - "Image loading APIs should carry target pixel/display size whenever the caller knows its rendered size."
  - "App lifecycle cleanup should go through AppResourceCleanup so tests cover the same release path as RootView."

requirements-completed: [MEM-01, MEM-02, MEM-03]

duration: 11 min
completed: 2026-06-26
status: complete
---

# Phase 01 Plan 05: Image Memory Guardrails Summary

**Image-heavy surfaces now downsample to display targets and release reloadable decoded images on pressure without dropping playback state**

## Performance

- **Duration:** 11 min
- **Started:** 2026-06-26T07:08:50Z
- **Completed:** 2026-06-26T07:17:36Z
- **Tasks:** 2 completed
- **Files modified:** 6 tracked source/test files

## Accomplishments

- Added URL plus target-pixel-size cache keys so the same cover can have separate list, mini-player, player, and lock-screen decoded variants.
- Replaced full `UIImage(data:)` decode on targeted loads with ImageIO thumbnail creation before the image enters `NSCache`.
- Preserved in-flight coalescing, now keyed by URL plus target pixel size.
- Passed stable target sizes from `TrackRow`, Now Playing cover, mini-player artwork, and `PlayerEngine.loadCover`.
- Removed mini-player 960x540 prewarm work so track changes do not trigger an extra large decoded image path.
- Added `ImageMemoryCache.releaseReloadableImages()` and wired it through `AppResourceCleanup` for backgrounding and UIKit memory warnings.
- Covered cleanup with tests proving cached images are released while `PlayerEngine.current`, `queue`, and `queueIndex` remain intact.

## Task Commits

1. **Task 1 RED: Add failing image cache sizing tests** - `31e886d` (test)
2. **Task 1 GREEN: Downsample image cache loads** - `29ba422` (feat)
3. **Task 2 RED: Add failing image cleanup tests** - `5f6093a` (test)
4. **Task 2 GREEN: Release reloadable images on pressure** - `c76fd54` (feat)

**Plan metadata:** this SUMMARY commit.

## Files Created/Modified

- `BiliMusic/Design/CachedAsyncImage.swift` - Adds target pixel sizing, ImageIO downsampling, size-aware cache/coalescing keys, and reloadable image release.
- `BiliMusic/Design/TrackRow.swift` - Passes the stable 64x36pt row thumbnail target size.
- `BiliMusic/Features/Player/NowPlayingView.swift` - Passes the existing full-player cover display size without changing layout.
- `BiliMusic/Features/RootView.swift` - Removes broad mini-player image prewarm, passes mini artwork target size, and wires background/memory cleanup.
- `BiliMusic/Player/PlayerEngine.swift` - Loads lock-screen artwork through a 600px target-size image path.
- `BiliMusicTests/ImageCacheTests.swift` - Covers target-size cache separation, downsampling cost, in-flight coalescing, release hook, background cleanup, and memory-warning cleanup.

## Decisions Made

- Kept the existing `NSCache` and `URLCache` stack; no third-party image pipeline was introduced.
- Used SwiftUI `displayScale` for view image requests instead of `UIScreen.main.scale`, avoiding deprecated iOS 26 API use.
- Kept background cleanup in the app shell and did not move or reset playback state.
- Left broad cache/auth/API work out of Phase 1; this plan only bounds decoded image memory and lifecycle cleanup.

## Deviations from Plan

None - plan executed within the planned image/cache/app-shell boundary.

## Issues Encountered

- RED tests initially exposed the intended missing API surface: target-size cache overloads, downsample helper, injectable image coordinator, release hook, and app cleanup helper.
- Xcode still prints passcode-protected physical-device `notification_proxy` warnings during simulator test runs. They did not affect the simulator tests or final exit code.

## Verification

- PASS: RED focused tests failed before GREEN because target-size image APIs did not exist.
- PASS: RED cleanup tests failed before GREEN because `releaseReloadableImages` and `AppResourceCleanup` did not exist.
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicTests/ImageCacheTests CODE_SIGNING_ALLOWED=NO`
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`
  - `BiliMusicTests`: 33 tests passed.
  - `BiliMusicUITests`: 6 tests passed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 1 implementation is complete. The project is ready for Phase 1 verification/closeout, then Phase 2 discovery reliability and music-only result work.

## Self-Check: PASSED

- Key files exist on disk.
- Four commits exist for `01-05`.
- MEM-01 is covered by target-size downsampling tests.
- MEM-02 is covered by target-size cache separation and in-flight coalescing tests.
- MEM-03 is covered by release hook, background cleanup, and memory-warning handler tests.
- Full scheme validation passed after all Phase 1 plans.

---
*Phase: 01-playback-critical-path-and-responsiveness*
*Completed: 2026-06-26*
