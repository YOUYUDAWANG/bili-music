# Task 5 Report: Precompute Search-Focus Local Content

## What changed

- Moved search-focus local content preparation into `SearchStore` with a stored `localContent` snapshot.
- Added `loadLocalContent(history:cache:) async` so search history, playback history, and cache snapshots are prepared before the user focuses Search.
- Updated `SearchView` to consume `store.localContent` instead of recomputing recent/cached content in the view body.
- Kept query change behavior scoped to `store.queryDidChange(newValue)` and left Bilibili search on explicit submit/retry/load-more paths only.
- Kept title cleaning untouched and still default-off.

## Files changed

- `BiliMusic/Features/Search/SearchStore.swift`
- `BiliMusic/Features/Search/SearchView.swift`
- `BiliMusicTests/SearchStoreTests.swift`
- `BiliMusic.xcodeproj/project.pbxproj`
- `.superpowers/sdd/task-5-report.md`

## Tests

Ran:

```bash
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/SearchStoreTests
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/SearchModelsTests
```

Results:

- `SearchStoreTests`: 3 passed
- `SearchModelsTests`: 22 passed

## TDD evidence

- Added the new `SearchStoreTests` coverage first for:
  - snapshot preparation from history + cache
  - preserving prepared results while loading local content
  - empty-query focus path staying local/idle
- The first targeted run surfaced a target-inclusion gap for the new test file, so `project.pbxproj` was updated to include `SearchStoreTests.swift` in `BiliMusicTests`.

## Self-review

- `SearchStore.localContent` now owns the precomputed snapshot and updates history terms when history changes locally.
- `SearchView` no longer reads `PlaybackHistoryStore.shared.entries` or `CacheStore.shared.entries` on the focus/render path for empty search content.
- No playback-startup code was touched.
- No search typing path now starts Bilibili work beyond the existing explicit submit/retry/load-more flow.

## Concerns

- `project.pbxproj` needed a minimal update so the new `SearchStoreTests.swift` file is actually part of the test target; otherwise the requested `-only-testing:BiliMusicTests/SearchStoreTests` selector executed zero tests.
- `localContent` is now a prepared snapshot, so recent/cached sections refresh on explicit load rather than by directly observing the shared stores in the view body. This matches the task goal of keeping first focus local and cheap, but it is less live than the old computed view path.

## Task 5 Fix Report

### Files changed

- `BiliMusic/Features/Search/SearchStore.swift`
- `BiliMusic/Features/Search/SearchView.swift`
- `BiliMusicTests/SearchStoreTests.swift`
- `.superpowers/sdd/task-5-report.md`

### Commands run

```bash
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/SearchStoreTests
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/SearchModelsTests
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/SearchStoreTests
```

### Results

- `SearchStoreTests`: initial requested run failed before the bundle connected to the simulator (`Early unexpected exit, operation never finished bootstrapping`); immediate rerun passed `4/4`.
- `SearchModelsTests`: passed `22/22`.

### Self-review

- `SearchStore.localContent` is still precomputed and local, but now refreshes recent-playback and cached-track snapshots through explicit store refreshes and cheap count-based view triggers instead of staying stale for the lifetime of `SearchView`.
- `queryDidChange("")` no longer clears prepared results or sections, so focusing or returning to an empty query stays local and does not destroy already-loaded search state.
- The search-field focus path still avoids synchronous recent/cache scans in the SwiftUI body and still does not trigger Bilibili search work outside explicit submit/retry/pagination flows.

## Task 5 Second Fix Report

### Files changed

- `BiliMusic/Player/PlaybackHistoryStore.swift`
- `BiliMusic/Cache/CacheStore.swift`
- `BiliMusic/Features/Search/SearchView.swift`
- `BiliMusicTests/SearchStoreTests.swift`
- `.superpowers/sdd/task-5-report.md`

### Commands run

```bash
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/SearchStoreTests
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/SearchModelsTests
```

### Results

- `SearchStoreTests`: passed `5/5`, including same-count history replay and same-count cache replacement snapshot refresh coverage.
- `SearchModelsTests`: passed `22/22`.

### Self-review

- Added `contentRevision` to `PlaybackHistoryStore` and `CacheStore`, incrementing only when visible entry content or ordering actually changes, including replay reordering, same-key cache replacement, clear/remove, and loaded-entry application that changes the snapshot.
- Switched `SearchView` refresh triggers from `history.entries.count` and `cache.entries.count` to those revision integers, so same-count reorder/replace mutations now refresh `SearchStore.localContent`.
- Kept explicit-submit-only remote search behavior and left raw-title behavior untouched.

### Concerns

- An initial attempt to run both requested `xcodebuild` selectors in parallel hit Xcode's `build.db` lock; rerunning serially succeeded without code changes.
