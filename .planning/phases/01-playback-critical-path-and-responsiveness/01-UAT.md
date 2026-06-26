---
status: complete
phase: 01-playback-critical-path-and-responsiveness
source: [01-VERIFICATION.md]
started: 2026-06-26T07:26:33Z
updated: 2026-06-26T08:14:37Z
---

## Current Test

none: Phase 01 UAT is closed for Phase 2 entry. One real CDN retry scenario remains documented as accepted residual risk because no reproducible expired or unauthorized Bilibili prepared stream was available.

## Tests

### 1. Real iPhone First-Audible Playback
expected: Install on the user's iPhone, cold-launch, tap a first Home/Search track, and confirm the selected track becomes current immediately and audio begins before lyrics, recommendations, MV, artwork, history, or cache enrichment visibly blocks the path.
result: [passed]
evidence: User reported on 2026-06-26 that the app can run on the target iPhone and tapping a song produces audio in approximately 1-2 seconds.
notes: This satisfies the UAT threshold because repeated fresh-remote starts should not consistently exceed roughly 5 seconds on stable Wi-Fi.

diagnostic_steps:

1. Build a DEBUG run from Xcode onto the target iPhone.
2. Open either Xcode's device console or the macOS Console app, select the iPhone, and filter logs for:
   - subsystem: `com.fubuki.BiliMusic`
   - category: `playback-diagnostics`
3. Cold-launch the app, tap the first Home/Search track once, and do not tap again while it starts.
4. Confirm the UI switches to the selected track immediately.
5. Capture the ordered diagnostics for the same `bvid`:
   - `checkpoint=tap`
   - `checkpoint=currentAssigned`
   - `checkpoint=sourceResolved`
   - `checkpoint=playerItemCreated`
   - `checkpoint=playRequested`
   - `checkpoint=firstPlaying`
6. Record the `elapsedMs` on `checkpoint=firstPlaying`.

pass_if:

- The selected track becomes current before artwork, lyrics, recommendations, MV probing, history write, or cache work finishes.
- Audio starts without requiring a second tap.
- `firstPlaying` appears after `playRequested` for the same `bvid`.
- On stable Wi-Fi, repeated fresh-remote starts do not consistently exceed roughly 5 seconds. Treat any repeated `firstPlaying elapsedMs > 5000` as a performance issue to investigate, even if playback eventually succeeds.

debug_autoplay_optional:

- Add a launch environment variable in the Xcode scheme: `AUTOPLAY_BV=<real playable BV id>`.
- Launch the app from Xcode and look for `AUTOPLAY state=` plus `AUTOPLAY_DIAGNOSTIC checkpoint=...` lines in the Xcode console. These lines mirror the same sanitized recent checkpoint events as `playback-diagnostics`.
- This validates the playback startup chain with timestamps, but it does not replace the manual tap test because `AUTOPLAY_BV` resolves the BV into a track before `PlayerEngine.play(tracks:startAt:)` starts diagnostics.

## Accepted Residual Risk

### Real Bilibili Expired Prepared Stream Retry

The desired real-device scenario is a playable BVID whose prepared remote stream has expired or returns a CDN/AVPlayer failure. The expected behavior is still that the app invalidates the prepared stream, resolves one fresh stream, and requests playback without a second user tap.

This was not directly reproduced against Bilibili CDN behavior. The risk is accepted for Phase 2 entry because:

- The deterministic retry path is covered by `PreparedStreamRetryTests`.
- The user confirmed real iPhone first-audible playback is approximately 1-2 seconds.
- No reproducible expired/unauthorized prepared-stream failure was available during UAT.

If a reproducible real CDN case appears later, use `playback-diagnostics` for the same `bvid` and confirm the stale prepared source is discarded, the next successful source resolution uses `source=freshRemote`, and playback reaches `playRequested` then `firstPlaying` without another tap.

## Summary

total: 2
passed: 1
issues: 0
pending: 0
accepted_risk: 1
skipped: 0
blocked: 0

## Gaps

No blocking Phase 01 gaps. Accepted residual risk is documented above.
