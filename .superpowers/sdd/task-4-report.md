## Task 4 Report - 2026-06-28

- Branch: `codex/apple-music-smoothness`
- Scope: smooth the mini-player expansion into a single Apple Music-like object without touching playback startup behavior

### Changes

- Added matched geometry for shared artwork using `playerTransition` / `playerArtwork` between the mini player and full player.
- Added matched geometry for the shared title using `playerTransition` / `playerTitle` between the mini player and full player.
- Added stable UI test identifiers for transition-critical artwork surfaces: `miniPlayerArtwork` and `nowPlayingArtwork`.
- Removed the dead `progressScrubGeneration` state from `NowPlayingView` and its write in `setProgressScrubbing`.
- Removed per-frame DEBUG logging from `handleMiniOpenDragChanged` to avoid simulator/UI-test drag jank.
- Kept title cleaning experimental and off by default by making mini-player and full-player display metadata respect `cleanListTitles = false`.
- Extended `PlayerChromeUITests` with a round-trip artwork regression that opens and closes the player twice and asserts both mini and full artwork remain present through the transitions.

### Tests

- Command:
  `xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicUITests/PlayerChromeUITests`
- Result: passed

### Exact Test Output Summary

```text
Test Suite 'PlayerChromeUITests' passed at 2026-06-28 06:45:06.446.
     Executed 17 tests, with 0 failures (0 unexpected) in 229.000 (229.021) seconds
Test Suite 'BiliMusicUITests.xctest' passed at 2026-06-28 06:45:06.447.
     Executed 17 tests, with 0 failures (0 unexpected) in 229.000 (229.022) seconds
Test Suite 'Selected tests' passed at 2026-06-28 06:45:06.448.
     Executed 17 tests, with 0 failures (0 unexpected) in 229.000 (229.023) seconds
** TEST SUCCEEDED **
```

### Concerns

- `handleMiniOpenDragEnded` still keeps its single DEBUG end-of-drag log. The jank-causing per-frame changed logging is removed.
- The new shared-element behavior is exercised by UITests via presence and round-trip stability checks, but there is still no pixel-diff visual assertion for the interpolation curve itself.
