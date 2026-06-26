---
phase: 3
slug: player-interaction-and-regression-coverage
status: approved
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-27
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for player interaction and regression coverage.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest and XCUITest bundled with Xcode 26.3 |
| **Config file** | `project.yml`; no separate XCTest config file |
| **Quick run command** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -target BiliMusicTests -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO` |
| **Full suite command** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO` |
| **Estimated runtime** | quick: 3-5 min; full: 8-15 min depending on simulator state |

---

## Sampling Rate

- **After every task commit:** Run the focused unit/UI command named in the task verify block.
- **After every plan wave:** Run the full unit target plus relevant `PlayerChromeUITests`.
- **Before `$gsd-verify-work`:** Full simulator suite must be green.
- **Max feedback latency:** no more than one plan task may modify gesture/layout behavior without a focused test run.

---

## Requirement Verification Map

| Requirement | Behavior | Test Type | Automated Command | File Exists | Status |
|-------------|----------|-----------|-------------------|-------------|--------|
| PLYR-01 | Mini-player upward drag tracks full-player offset/opacity/scale and completes or cancels by policy | unit + UI | `xcodebuild test ... -only-testing:BiliMusicTests/PlayerGesturePolicyTests -only-testing:BiliMusicUITests/PlayerChromeUITests/testMiniPlayerSlowDragOpensRespectsSafeAreaAndClosesFromTopChrome` | partial | pending |
| PLYR-02 | Full-player downward minimize works from allowed center-page regions with deliberate threshold | unit + UI | `xcodebuild test ... -only-testing:BiliMusicTests/PlayerGesturePolicyTests -only-testing:BiliMusicUITests/PlayerChromeUITests` | partial | pending |
| PLYR-03 | Queue and recommendation list vertical scroll never minimizes full player | UI + policy | `xcodebuild test ... -only-testing:BiliMusicUITests/PlayerChromeUITests` | partial | pending |
| PLYR-04 | Progress scrub, horizontal page swipe, and vertical minimize do not fight | unit + UI | `xcodebuild test ... -only-testing:BiliMusicTests/PlayerGesturePolicyTests -only-testing:BiliMusicUITests/PlayerChromeUITests` | gap | pending |
| PLYR-05 | Dense Apple Music-like layout has no excessive bottom void on compact and modern iPhone sizes | UI + manual UAT | Preflight-create missing `iPhone SE (3rd generation)` and `iPhone 16` simulators under iOS 26.3, then run `xcodebuild test ... -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)' -only-testing:BiliMusicUITests/PlayerChromeUITests` and `xcodebuild test ... -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:BiliMusicUITests/PlayerChromeUITests`; keep real-device visual check for subjective density | gap | pending |
| TEST-01 | Search identity, mode identity, pagination, stale-result rejection, and music-only filtering stay covered | unit | `xcodebuild test ... -only-testing:BiliMusicTests/SearchModelsTests` | yes | pending |
| TEST-02 | Playback request still occurs before post-start enrichment is awaited | unit | `xcodebuild test ... -only-testing:BiliMusicTests/PlaybackCriticalPathTests` | yes | pending |
| TEST-03 | Home and Now Playing recommendation list stability remains covered | unit + UI | `xcodebuild test ... -only-testing:BiliMusicTests/RecommendationSchedulingTests -only-testing:BiliMusicUITests/PlayerChromeUITests/testTappingRecommendationKeepsHomeListStable` | yes | pending |
| TEST-05 | Target-size image caching or memory-pressure cleanup remains covered | unit | `xcodebuild test ... -only-testing:BiliMusicTests/ImageCacheTests` | yes | pending |

---

## Wave 0 Requirements

- [ ] `BiliMusicTests/PlayerGesturePolicyTests.swift` covers center-page body dismiss, list-page top-chrome-only dismiss, horizontal intent gating, and scrub/dismiss suppression where expressible as pure logic.
- [ ] `BiliMusicUITests/PlayerChromeUITests.swift` covers queue-page scroll, recommendation-page scroll, progress scrub not paging/dismissing, page swipe not minimizing, and dense layout identifiers/frame assertions on `iPhone SE (3rd generation)` and `iPhone 16`.
- [ ] `BiliMusic/Features/Player/NowPlayingView.swift` exposes stable accessibility identifiers for page hints, queue page, recommendation page, cover, progress, toolbar, and primary controls.
- [ ] `project.yml` is regenerated with `xcodegen generate` only if Phase 3 adds new Swift files.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Apple Music-like density and touch feel on the user's iPhone | PLYR-01, PLYR-05 | Automated UI tests catch identifier existence, frame ordering, non-overlap, and coarse bottom-gap regressions on `iPhone SE (3rd generation)` and `iPhone 16`, but cannot prove subjective drag feel or visual density | After simulator gates pass, on the real iPhone, open player from mini-player, drag up slowly, drag down from center body, scroll queue/recommendation pages, scrub progress, and confirm the player feels direct without bottom void |
| Reduced Motion transition feel | PLYR-01, PLYR-02 | Simulator can toggle the setting, but final acceptability is visual/tactile | Enable Reduce Motion in iOS settings, repeat open/close/page interactions, and confirm hierarchy remains clear without springy or scale-heavy motion |

---

## Validation Sign-Off

- [x] All Phase 3 requirements have an automated verify path or a Wave 0 dependency.
- [x] Sampling continuity: no 3 consecutive implementation tasks should proceed without automated verify.
- [x] Wave 0 requirements cover the known missing player interaction checks.
- [x] No watch-mode flags are used in required commands.
- [x] Feedback latency target is defined.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** approved 2026-06-27
