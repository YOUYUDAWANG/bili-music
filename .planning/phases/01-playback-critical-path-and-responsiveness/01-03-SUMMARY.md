---
phase: 01-playback-critical-path-and-responsiveness
plan: 03
subsystem: search
tags: [search, responsiveness, swiftui, local-suggestions, xctest]

requires:
  - phase: 01-01
    provides: Phase 1 search focus regression test home
provides:
  - Submit-only search behavior
  - Local empty-search content projection for history, recent playback, and cached songs
  - Regression coverage for focus/typing staying local
affects: [phase-01, search, performance, local-suggestions]

tech-stack:
  added: []
  patterns:
    - SearchLocalContent value projection for local-only search focus content
    - Source-level regression guard for SearchView query-change debounce removal

key-files:
  created: []
  modified:
    - BiliMusic/Features/Search/SearchView.swift
    - BiliMusic/Features/Search/SearchStore.swift
    - BiliMusicTests/SearchFocusTests.swift

key-decisions:
  - "Typing in the search field no longer starts debounced Bilibili search or result preloading."
  - "Network search remains available only through explicit submit, retry, broaden, and pagination entry points."
  - "Empty search renders only already-local history, recent playback, and cached songs."

patterns-established:
  - "SearchLocalContent caps history suggestions at 8 and dedupes cached tracks against recent tracks."
  - "SearchView empty search content is derived from local stores without BiliClient, WBISigner, or engine.preload calls."

requirements-completed: [SRCH-01, SRCH-02]

duration: 23 min
completed: 2026-06-26
status: complete
---

# Phase 01 Plan 03: Search Focus Summary

**Search focus and typing now stay local; explicit submit is the only normal search network trigger**

## Performance

- **Duration:** 23 min
- **Started:** 2026-06-26T06:10:00Z
- **Completed:** 2026-06-26T06:32:49Z
- **Tasks:** 2 completed
- **Files modified:** 3 tracked files

## Accomplishments

- Removed `SearchView`'s 450 ms typing debounce and the `debouncedSearch()` path.
- Kept `SearchStore.queryDidChange(_:)` as the only typing-time state update.
- Added `SearchLocalContent` to project local search-history, recent playback, and cached songs without remote work.
- Rendered recent playback and cached songs in the empty search surface, with the existing approved empty copy when no local tracks exist.
- Added tests proving focus/typing stays idle and local, history suggestions cap at 8, and recent/cache local content dedupes.

## Task Commits

1. **Task 1 RED: Add failing search focus tests** - `6c3bb0a` (test)
2. **Task 1 GREEN: Make search submit-only** - `c660eb4` (fix)
3. **Task 2 RED: Add failing local search suggestion tests** - `b24e727` (test)
4. **Task 2 GREEN: Show local search focus content** - `1ab9667` (feat)

**Plan metadata:** this SUMMARY commit.

## Files Created/Modified

- `BiliMusic/Features/Search/SearchView.swift` - Removes typing debounce network work and renders local empty-search sections.
- `BiliMusic/Features/Search/SearchStore.swift` - Adds `SearchLocalContent` for local-only suggestion projection.
- `BiliMusicTests/SearchFocusTests.swift` - Covers local typing behavior, SearchView debounce removal, explicit submit presence, and local suggestion projection.

## Decisions Made

- Did not restore cached remote search results while typing. Cached result restore now happens through explicit submit, keeping focus/typing cheap.
- Kept favorite-folder seed suggestions out of Phase 1, matching D-06.
- Used the existing `TrackRow` list presentation for local recent/cache rows instead of adding another search-specific row component.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Xcode test runner hung during RED verification**
- **Found during:** Task 1 RED verification
- **Issue:** `xcodebuild test` hung waiting for simulator test workers to materialize after an interrupted runner.
- **Fix:** Killed the hung `xcodebuild` process, used a direct source check to confirm the RED condition, then used `build-for-testing` and focused tests after the runner recovered.
- **Files modified:** none
- **Verification:** Later `SearchFocusTests` and full `BiliMusicTests` passed.
- **Committed in:** no source commit; environment/test-runner issue only.

---

**Total deviations:** 1 auto-fixed (test-runner recovery).
**Impact on plan:** No product scope change. Final tests and source checks satisfy the acceptance criteria.

## Issues Encountered

- Xcode still prints the known empty supported-platform warning. It did not block later simulator test runs.

## Verification

- PASS: RED source check failed before Task 1 GREEN because `SearchView` still contained `debounceTask`, `debouncedSearch`, and the 450 ms sleep.
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -quiet -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicTests/SearchFocusTests CODE_SIGNING_ALLOWED=NO`
- PASS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicTests CODE_SIGNING_ALLOWED=NO`
- PASS: `git diff --check`

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for `01-04`: Home recommendation stability can now be handled separately from search focus and playback startup.

## Self-Check: PASSED

- Key files exist on disk.
- Four commits exist for `01-03`.
- SRCH-01 and SRCH-02 are covered by focused tests.
- Search focus no longer triggers Bilibili search, WBI work, or result preloading through typing.

---
*Phase: 01-playback-critical-path-and-responsiveness*
*Completed: 2026-06-26*
