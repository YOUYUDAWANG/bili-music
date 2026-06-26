---
phase: 01
slug: playback-critical-path-and-responsiveness
status: complete
nyquist_compliant: true
wave_0_complete: true
automated_status: passed
human_status: pending
verified: 2026-06-26T07:26:33Z
---

# Phase 01 - Validation Strategy

Per-phase validation contract and execution record for Phase 01.

## Test Infrastructure

| Property | Value |
|----------|-------|
| Framework | XCTest + XCUITest through Xcode |
| Config file | `project.yml`; generated `BiliMusic.xcodeproj` |
| Focused unit command | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicTests CODE_SIGNING_ALLOWED=NO` |
| Full suite command | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO` |
| Final automated run | 2026-06-26T07:24:20Z to 2026-06-26T07:25:31Z |

## Final Automated Result

| Suite | Result |
|-------|--------|
| `BiliMusicTests` | PASS - 33 tests, 0 failures |
| `BiliMusicUITests` | PASS - 6 tests, 0 failures |
| Full command exit | PASS - `TEST SUCCEEDED` |

Xcode printed known passcode-protected physical-device `notification_proxy` warnings while the simulator run was executing. The simulator test session completed successfully and exited with code 0.

## Per-Task Verification Map

| Task ID | Plan | Requirement | Test Type | Evidence | Status |
|---------|------|-------------|-----------|----------|--------|
| 01-01-01 | 01 | PLAY-01 | unit | `PlaybackCriticalPathTests` fixture home created and later exercised in 01-02 | green |
| 01-01-02 | 01 | PLAY-02 | unit | `PlaybackCriticalPathTests` fixture home created and later exercised in 01-02 | green |
| 01-01-03 | 01 | PLAY-03 | unit / instrumentation | `PlaybackDiagnosticsTests` verifies ordered sanitized checkpoints | green |
| 01-01-04 | 01 | PLAY-04 | unit | `PreparedStreamRetryTests` verifies one retry and no retry loop | green |
| 01-01-05 | 01 | PLAY-05 | unit | `PlaybackCriticalPathTests` verifies post-first-playing enrichment ordering | green |
| 01-02-01 | 03 | SRCH-01 | unit | `SearchFocusTests` verifies focus and typing stay local | green |
| 01-02-02 | 03 | SRCH-02 | unit + UI fixture | `SearchFocusTests` verifies local history/recent/cache projection | green |
| 01-03-01 | 04 | RECO-01 | XCUITest fixture | `PlayerChromeUITests/testTappingRecommendationKeepsHomeListStable` | green |
| 01-03-02 | 04 | RECO-04 | unit | `RecommendationSchedulingTests` verifies bounded lower-priority Home policy | green |
| 01-04-01 | 05 | MEM-01 | unit | `ImageCacheTests` verifies target-size downsampling | green |
| 01-04-02 | 05 | MEM-02 | unit | `ImageCacheTests` verifies target-size cache separation and in-flight coalescing | green |
| 01-04-03 | 05 | MEM-03 | unit + app-shell helper | `ImageCacheTests` verifies memory/background cleanup preserves playback state | green |

## Wave 0 Requirements

- [x] `BiliMusicTests/PlaybackCriticalPathTests.swift` covers PLAY-01, PLAY-02, PLAY-05.
- [x] `BiliMusicTests/PlaybackDiagnosticsTests.swift` covers PLAY-03.
- [x] `BiliMusicTests/PreparedStreamRetryTests.swift` covers PLAY-04.
- [x] `BiliMusicTests/SearchFocusTests.swift` covers SRCH-01 and SRCH-02.
- [x] `BiliMusicTests/RecommendationSchedulingTests.swift` covers RECO-04.
- [x] `BiliMusicTests/ImageCacheTests.swift` covers MEM-01, MEM-02, and MEM-03.
- [x] `BiliMusicUITests/PlayerChromeUITests.swift` covers RECO-01 Home list stability and player chrome fixture behavior.
- [x] Test seams exist for `PlayerEngine` source resolution, diagnostics sink, post-start enrichment ordering, prepared stream retry, and image cache cleanup.

## Manual-Only Verifications

| Behavior | Requirement | Status | Why Manual | Test Instructions |
|----------|-------------|--------|------------|-------------------|
| Real Bilibili prepared-stream expiry or CDN 403 retry behavior | PLAY-04 | pending in `01-UAT.md` | Exact CDN/AVPlayer failure shape may differ from fake resolver tests and depends on short-lived remote URLs. | Use a real playable BVID, force or wait for an expired prepared stream if feasible, then verify one automatic fresh stream resolution occurs and no second tap is required. |
| Real first-audible playback feel on device | PLAY-01, PLAY-02, PLAY-05 | pending in `01-UAT.md` | Simulator/unit tests prove ordering, but audible latency and AVAudioSession behavior should be felt on the target iPhone. | Install on the user's iPhone, cold-launch, tap first Home/Search track, and confirm current-track feedback is immediate and audio begins before lyrics/recommendations/MV/artwork enrichments complete. |

## Security Notes

| Threat Ref | Risk | Required Mitigation | Status |
|------------|------|---------------------|--------|
| T-01 | Diagnostics leaking Cookie, auth headers, or private stream URLs | Metrics carry bvid, cid, source kind, checkpoint names, durations, and quality labels only. | verified by `PlaybackDiagnosticsTests` |
| T-02 | Persisting short-lived Bilibili playurl media URLs | Retry logic discards and re-resolves remote URLs in memory only. | verified by 01-02 source check and retry tests |
| T-03 | Search focus causing unintended Bilibili network calls or privacy leaks | Focus/typing path remains local; Bilibili search starts only on explicit submit/retry/broaden/load-more. | verified by `SearchFocusTests` |

## Validation Sign-Off

- [x] All task requirements have automated verification or a recorded manual-only follow-up.
- [x] Sampling continuity maintained across all five Phase 01 plans.
- [x] Wave 0 dependencies are in place and exercised.
- [x] No watch-mode flags used.
- [x] Final full-suite feedback latency was under 8 minutes.
- [x] `nyquist_compliant: true` set after Wave 0 and final full-suite run.

**Approval:** Automated checks passed. Manual iPhone/CDN checks are carried in `01-UAT.md` and keep the phase in human verification state.
