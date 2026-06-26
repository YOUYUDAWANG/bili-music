---
status: testing
phase: 01-playback-critical-path-and-responsiveness
source: [01-VERIFICATION.md]
started: 2026-06-26T07:26:33Z
updated: 2026-06-26T07:43:28Z
---

## Current Test

number: 1
name: Real iPhone First-Audible Playback
expected: |
  Install on the user's iPhone, cold-launch, tap a first Home/Search track, and confirm the selected track becomes current immediately and audio begins before lyrics, recommendations, MV, artwork, history, or cache enrichment visibly blocks the path.
awaiting: user response

## Tests

### 1. Real iPhone First-Audible Playback
expected: Install on the user's iPhone, cold-launch, tap a first Home/Search track, and confirm the selected track becomes current immediately and audio begins before lyrics, recommendations, MV, artwork, history, or cache enrichment visibly blocks the path.
result: [pending]

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
- Launch the app from Xcode and filter for both `playback-diagnostics` and `AUTOPLAY state=`.
- This validates the playback startup chain with timestamps, but it does not replace the manual tap test because `AUTOPLAY_BV` resolves the BV into a track before `PlayerEngine.play(tracks:startAt:)` starts diagnostics.

### 2. Real Bilibili Expired Prepared Stream Retry
expected: Use a real playable BVID with a prepared remote stream that has expired or returns a CDN/AVPlayer failure if feasible; the app invalidates the prepared stream, resolves one fresh stream, and requests playback without a second user tap.
result: [pending]

diagnostic_steps:

1. Use a real playable BVID that can be preloaded by Home/Search/queue recommendation.
2. If feasible, let the prepared media URL age until Bilibili's CDN rejects it, or reproduce a CDN/AVPlayer failure with an otherwise playable prepared stream.
3. Tap the track once.
4. Watch `playback-diagnostics` for the same `bvid`.
5. Confirm the failed prepared attempt is followed by a fresh stream resolution and a play request without another user tap.

pass_if:

- The app invalidates the prepared remote value after the failure.
- The next successful `sourceResolved` event uses `source=freshRemote`.
- Playback reaches `checkpoint=playRequested` and then `checkpoint=firstPlaying` without a second tap.
- The app does not loop retries indefinitely.

skip_condition:

- If no reproducible expired/unauthorized prepared-stream failure can be produced against real Bilibili CDN behavior, leave this pending rather than fabricating the result. The deterministic retry path is already covered by `PreparedStreamRetryTests`; this UAT exists only for real CDN integration confidence.

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps

[none yet]
