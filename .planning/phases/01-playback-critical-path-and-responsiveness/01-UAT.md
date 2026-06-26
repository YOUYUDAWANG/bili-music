---
status: testing
phase: 01-playback-critical-path-and-responsiveness
source: [01-VERIFICATION.md]
started: 2026-06-26T07:26:33Z
updated: 2026-06-26T07:26:33Z
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

### 2. Real Bilibili Expired Prepared Stream Retry
expected: Use a real playable BVID with a prepared remote stream that has expired or returns a CDN/AVPlayer failure if feasible; the app invalidates the prepared stream, resolves one fresh stream, and requests playback without a second user tap.
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps

[none yet]
