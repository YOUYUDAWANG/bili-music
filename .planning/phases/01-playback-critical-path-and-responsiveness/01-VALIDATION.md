---
phase: 01
slug: playback-critical-path-and-responsiveness
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-26
---

# Phase 01 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest + XCUITest through Xcode |
| **Config file** | `project.yml`; generated `BiliMusic.xcodeproj` |
| **Quick run command** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -target BiliMusicTests -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO` |
| **Full suite command** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO` |
| **Estimated runtime** | Quick: ~60-180 seconds; full suite: ~3-8 minutes depending on simulator state |

---

## Sampling Rate

- **After every task commit:** Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -target BiliMusicTests -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO`
- **After every plan wave:** Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`
- **Before `$gsd-verify-work`:** Full suite must be green, plus manual/autoplay playback verification for real Bilibili stream behavior where automated AVPlayer/CDN behavior cannot be fully simulated.
- **Max feedback latency:** 8 minutes for automated suite feedback; manual playback checks are allowed only for Bilibili CDN/AVPlayer integration edges called out below.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 0 | PLAY-01 | — | N/A | unit + UI fixture | Quick unit target, plus fixture UI assertion if plan touches player chrome | ❌ W0 `BiliMusicTests/PlaybackCriticalPathTests.swift` | ⬜ pending |
| 01-01-02 | 01 | 0 | PLAY-02 | — | N/A | unit | Quick unit target | ❌ W0 `BiliMusicTests/PlaybackCriticalPathTests.swift` | ⬜ pending |
| 01-01-03 | 01 | 0 | PLAY-03 | T-01 | Diagnostics must not log Cookie, auth headers, or private stream URLs | unit / instrumentation | Quick unit target; optional `XCTOSSignpostMetric` | ❌ W0 `BiliMusicTests/PlaybackDiagnosticsTests.swift` | ⬜ pending |
| 01-01-04 | 01 | 0 | PLAY-04 | T-02 | Short-lived media URLs remain memory-only; retry must not persist playurl output | unit with fake resolver/player item seam | Quick unit target | ❌ W0 `BiliMusicTests/PreparedStreamRetryTests.swift` | ⬜ pending |
| 01-01-05 | 01 | 0 | PLAY-05 | — | N/A | unit | Quick unit target | ❌ W0 `BiliMusicTests/PlaybackCriticalPathTests.swift` | ⬜ pending |
| 01-02-01 | 02 | 0 | SRCH-01 | T-03 | Focus and typing must not trigger unintended Bilibili network requests | unit | Quick unit target | ⚠️ Extend `BiliMusicTests/SearchModelsTests.swift` or add `SearchFocusTests.swift` | ⬜ pending |
| 01-02-02 | 02 | 0 | SRCH-02 | T-03 | Local suggestions must be built from local stores only | unit + UI fixture | Quick unit target; full suite for fixture UI | ❌ W0 `BiliMusicTests/SearchFocusTests.swift` | ⬜ pending |
| 01-03-01 | 03 | 0 | RECO-01 | — | N/A | XCUITest fixture | Full suite command | ⚠️ Extend `BiliMusicUITests/PlayerChromeUITests.swift` | ⬜ pending |
| 01-03-02 | 03 | 0 | RECO-04 | — | N/A | unit | Quick unit target | ❌ W0 `BiliMusicTests/RecommendationSchedulingTests.swift` | ⬜ pending |
| 01-04-01 | 04 | 0 | MEM-01 | — | N/A | unit | Quick unit target | ❌ W0 `BiliMusicTests/ImageCacheTests.swift` | ⬜ pending |
| 01-04-02 | 04 | 0 | MEM-02 | — | N/A | unit | Quick unit target | ❌ W0 `BiliMusicTests/ImageCacheTests.swift` | ⬜ pending |
| 01-04-03 | 04 | 0 | MEM-03 | — | N/A | unit + UI smoke | Quick unit target; fixture UI smoke if playback state is involved | ❌ W0 `BiliMusicTests/ImageCacheTests.swift` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `BiliMusicTests/PlaybackCriticalPathTests.swift` — stubs and tests for PLAY-01, PLAY-02, PLAY-05.
- [ ] `BiliMusicTests/PlaybackDiagnosticsTests.swift` — stubs and tests for PLAY-03.
- [ ] `BiliMusicTests/PreparedStreamRetryTests.swift` — stubs and tests for PLAY-04.
- [ ] `BiliMusicTests/SearchFocusTests.swift` or focused additions to `BiliMusicTests/SearchModelsTests.swift` — stubs and tests for SRCH-01, SRCH-02.
- [ ] `BiliMusicTests/RecommendationSchedulingTests.swift` — stubs and tests for RECO-04.
- [ ] `BiliMusicTests/ImageCacheTests.swift` — stubs and tests for MEM-01, MEM-02, MEM-03.
- [ ] `BiliMusicUITests/PlayerChromeUITests.swift` extension — fixture coverage for RECO-01 Home list stability.
- [ ] Test seams for `PlayerEngine` source resolution, diagnostics sink, post-start enrichment ordering, and image cache cleanup.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real Bilibili prepared-stream expiry or CDN 403 retry behavior | PLAY-04 | Exact CDN/AVPlayer failure shape may differ from fake resolver tests and depends on short-lived remote URLs. | Use a real playable BVID, force or wait for an expired prepared stream if feasible, then verify one automatic fresh stream resolution occurs and no second tap is required. |
| Real first-audible playback feel on device | PLAY-01, PLAY-02, PLAY-05 | Simulator/unit tests can prove ordering, but audible latency and AVAudioSession behavior should be felt on the target iPhone. | Install on the user's iPhone, cold-launch, tap first Home/Search track, and confirm current-track feedback is immediate and audio begins before lyrics/recommendations/MV/artwork enrichments complete. |

---

## Security Notes

| Threat Ref | Risk | Required Mitigation |
|------------|------|---------------------|
| T-01 | Diagnostics leaking Cookie, auth headers, or private stream URLs | Playback metrics may log bvid, cid, source kind, checkpoint names, durations, and quality labels only. Do not log Cookie, request headers, or full stream URLs. |
| T-02 | Persisting short-lived Bilibili playurl media URLs | Retry logic must discard and re-resolve remote URLs in memory only; persisted cache state remains bvid/cid/local-file based. |
| T-03 | Search focus causing unintended Bilibili network calls or privacy leaks | Focus/typing path must remain local; Bilibili search may start only on explicit submit/retry/broaden/load-more. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 8 minutes
- [ ] `nyquist_compliant: true` set in frontmatter after Wave 0 and required checks are in place

**Approval:** pending
