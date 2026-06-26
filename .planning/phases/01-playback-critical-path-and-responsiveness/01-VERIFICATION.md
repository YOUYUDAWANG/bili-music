---
phase: 01-playback-critical-path-and-responsiveness
verified: 2026-06-26T07:38:02Z
status: passed
score: 12/12 must-haves verified
behavior_unverified: 0
uat_instructions_updated: 2026-06-26T07:43:28Z
debug_autoplay_console_updated: 2026-06-26T07:49:21Z
first_audible_uat_passed: 2026-06-26T08:06:40Z
accepted_risk_items:
  - truth: "A real expired or unauthorized Bilibili prepared stream retries once without requiring another tap."
    test: "Use a real playable BVID with a prepared remote stream that has expired or returns a CDN/AVPlayer failure if feasible."
    disposition: "Accepted residual risk for Phase 2 entry because no reproducible real CDN failure was available; deterministic retry behavior is covered by PreparedStreamRetryTests."
---

# Phase 01: Playback Critical Path and Responsiveness Verification Report

**Phase Goal:** Users can tap a track and get responsive first playback without recommendation refreshes, search-focus freezes, or image memory work interfering with the music path.
**Verified:** 2026-06-26T07:38:02Z
**Status:** passed

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Tap-to-play assigns the selected track as current before awaited source resolution completes. | VERIFIED | `PlaybackCriticalPathTests/testPlayAssignsCurrentBeforeAwaitedSourceResolutionCompletes` passed. |
| 2 | Playback startup resolves only cached audio, prepared audio, or one fresh audio stream before requesting AVPlayer playback. | VERIFIED | `PlaybackCriticalPathTests/testPlaybackRequestUsesOnlyOneFreshAudioResolutionBeforePlay` passed. |
| 3 | Playback startup records tap, source resolution, item creation, play request, and first observed playing checkpoints. | VERIFIED | `PlaybackDiagnosticsTests/testRecordsTapToFirstPlayingCheckpointsInOrder` passed. |
| 4 | Diagnostics do not expose Cookies, headers, or stream URLs. | VERIFIED | `PlaybackDiagnosticsTests/testDiagnosticPayloadsAreSanitized` passed. |
| 5 | Prepared remote stream failure invalidates the prepared value and retries one fresh stream without looping. | VERIFIED | `PreparedStreamRetryTests/testPreparedRemoteFailureInvalidatesOnceBeforeFreshRetry` and failure-surfacing tests passed. |
| 6 | Post-start enrichment does not block first observed playback scheduling. | VERIFIED | `PlaybackCriticalPathTests/testFirstObservedPlayingSchedulesOnlyAllowedPostSoundWork` passed. |
| 7 | Search focus and typing stay local and do not trigger debounced Bilibili search work. | VERIFIED | `SearchFocusTests/testTypingFirstCharacterKeepsSearchStoreLocalAndIdle` and source guard tests passed. |
| 8 | Empty focused search can render local history/recent/cache content. | VERIFIED | `SearchFocusTests` local suggestion projection tests passed. |
| 9 | First playback from Home does not flash, reset, or clear the Home recommendation row. | VERIFIED | `PlayerChromeUITests/testTappingRecommendationKeepsHomeListStable` passed. |
| 10 | Home recommendation scheduling is explicit, bounded, and lower priority than direct playback startup. | VERIFIED | `RecommendationSchedulingTests` passed. |
| 11 | Image-heavy surfaces downsample, coalesce, and release reloadable decoded images without clearing playback state. | VERIFIED | `ImageCacheTests` passed, including background and memory-warning cleanup. |
| 12 | Player chrome gestures have guardrails for mini-player expansion, full-player minimization, and list-area drags that should not dismiss. | VERIFIED | `PlayerGesturePolicyTests` and `PlayerChromeUITests` passed. |

**Score:** 12/12 truths verified by automated tests.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `BiliMusic/Player/PlaybackDiagnostics.swift` | Sanitized playback checkpoint model | EXISTS + SUBSTANTIVE | Added in 01-01 and covered by diagnostics tests, including bounded DEBUG recent-event mirroring for UAT. |
| `BiliMusic/Player/PlayerEngine.swift` | Protected startup path and prepared-stream retry | EXISTS + SUBSTANTIVE | Covered by playback critical path and retry tests. |
| `BiliMusic/Features/Search/SearchStore.swift` | Local-only search focus content projection | EXISTS + SUBSTANTIVE | Covered by `SearchFocusTests`. |
| `BiliMusic/Features/Search/SearchView.swift` | Submit-only network search path | EXISTS + SUBSTANTIVE | Source guard verifies debounce removal and explicit submit entry point. |
| `BiliMusic/Player/RecommendationEngine.swift` | Home recommendation scheduling policy | EXISTS + SUBSTANTIVE | Covered by `RecommendationSchedulingTests`. |
| `BiliMusic/Design/CachedAsyncImage.swift` | Target-size image loading/cache cleanup | EXISTS + SUBSTANTIVE | Covered by `ImageCacheTests`. |
| `BiliMusic/Features/RootView.swift` | App lifecycle image cleanup hook | EXISTS + SUBSTANTIVE | Covered by memory/background cleanup tests. |
| `BiliMusic/Features/Player/PlayerGesturePolicy.swift` | Player gesture thresholds and false-positive policy | EXISTS + SUBSTANTIVE | Covered by `PlayerGesturePolicyTests`. |
| `BiliMusicUITests/PlayerChromeUITests.swift` | UI fixture checks for Home and player chrome | EXISTS + SUBSTANTIVE | Full UI suite passed. |

**Artifacts:** 9/9 verified.

## Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| PLAY-01 | SATISFIED | Real-device audible feel passed UAT: target iPhone starts audio in approximately 1-2 seconds after tapping a song. |
| PLAY-02 | SATISFIED | Real-device first-audible playback passed UAT; no blocking source-resolution issue observed. |
| PLAY-03 | SATISFIED | None. |
| PLAY-04 | SATISFIED | None for deterministic retry path; real CDN/expired-url behavior recorded as accepted residual risk. |
| PLAY-05 | SATISFIED | Real-device first-audible playback passed UAT; enrichment work did not visibly block first sound. |
| SRCH-01 | SATISFIED | None. |
| SRCH-02 | SATISFIED | None. |
| RECO-01 | SATISFIED | None. |
| RECO-04 | SATISFIED | None. |
| MEM-01 | SATISFIED | None. |
| MEM-02 | SATISFIED | None. |
| MEM-03 | SATISFIED | None. |
| TEST-04 | SATISFIED | None. |

**Coverage:** 13/13 Phase 01 mapped requirements satisfied by automated evidence; real-device first-audible playback passed UAT. One real CDN retry confirmation remains documented as accepted residual risk because no reproducible expired or unauthorized prepared-stream failure was available.

## Anti-Patterns Found

None found during this verification pass.

## Human Verification

### 1. Real iPhone First-Audible Playback

**Test:** Install on the user's iPhone, cold-launch, tap a first Home/Search track, and observe the immediate current-track feedback plus audible startup.
**Expected:** The selected track becomes current immediately and audio begins before lyrics, recommendations, MV, artwork, history, or cache enrichment visibly blocks the path.
**Result:** PASSED on 2026-06-26. User reported the app runs on the target iPhone and tapping a song produces audio in approximately 1-2 seconds.
**Why human:** Simulator/unit tests prove ordering but cannot verify audible latency and AVAudioSession feel on the target iPhone.
**Diagnostics:** Use Xcode's device console or the macOS Console app to filter subsystem `com.fubuki.BiliMusic`, category `playback-diagnostics`. For the tapped `bvid`, confirm the sequence reaches `checkpoint=firstPlaying` after `checkpoint=playRequested` and record `elapsedMs`. Optional `AUTOPLAY_BV` DEBUG runs also print `AUTOPLAY_DIAGNOSTIC checkpoint=...` lines directly to the Xcode console. Repeated fresh-remote starts over roughly 5 seconds on stable Wi-Fi should be treated as a performance regression candidate.

## Accepted Residual Risk

### Real Bilibili Expired Prepared Stream Retry

**Test:** Use a real playable BVID with a prepared remote stream that has expired or returns a CDN/AVPlayer failure if feasible.
**Expected:** The app invalidates the prepared stream, resolves one fresh stream, and requests playback without a second user tap.
**Disposition:** Accepted for Phase 2 entry. The exact CDN/AVPlayer failure shape depends on Bilibili short-lived media URLs and cannot be deterministically produced by the simulator suite; no reproducible live case was available during UAT. Deterministic retry behavior is covered by `PreparedStreamRetryTests`.
**Diagnostics if seen later:** Filter `playback-diagnostics` for the same `bvid` and confirm the prepared stream is discarded, the subsequent successful source resolution uses `source=freshRemote`, and playback reaches `playRequested` then `firstPlaying` without another tap.

## Gaps Summary

No blocking implementation gaps found. The only unobserved live integration behavior is recorded as accepted residual risk because the deterministic retry path has automated coverage and real-device first-audible UAT passed.

## Automated Checks

Final command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

Result:

- PASS: `BiliMusicTests` - 41 tests, 0 failures.
- PASS: `BiliMusicUITests` - 6 tests, 0 failures.
- PASS: Full test session exited with `TEST SUCCEEDED`.
- PASS: Release simulator build completed with `CODE_SIGNING_ALLOWED=NO`.

## Verification Metadata

**Verification approach:** Goal-backward from ROADMAP Phase 01 success criteria plus SUMMARY evidence.
**Must-haves source:** `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`, and `01-01` through `01-05` summaries.
**Automated checks:** 47 passed, 0 failed.
**Human checks required:** 0 remaining; 1 passed; 1 accepted residual risk.
**Total verification time:** 71 seconds for final automated full-suite command.

---
*Verified: 2026-06-26T07:38:02Z*
*Verifier: Codex*
