# Phase 1: Playback Critical Path and Responsiveness - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-26
**Phase:** 1-Playback Critical Path and Responsiveness
**Areas discussed:** First playback critical path, Search focus experience, Recommendation and image background work, Completion standard and tests

---

## First Playback Critical Path

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal path | Set current track, use cache/prepared stream or resolve one fresh stream, create AVPlayer item, and request playback. | ✓ |
| Include basic metadata | Allow basic metadata/artwork/history work to block first playback. | |
| Wait for richer artwork or lyrics | Delay playback until richer media data is ready. | |

**User's choice:** Recommended option.
**Notes:** User previously emphasized that making music audible is the first priority; all enrichment must lose to first sound.

| Option | Description | Selected |
|--------|-------------|----------|
| Discard and retry once | If a prepared stream is expired/unauthorized, drop it and resolve one fresh stream before failing. | ✓ |
| Show error immediately | Surface failure when the prepared stream cannot be used. | |
| Try cache or lower quality first | Attempt alternate fallback ordering before retrying the stream. | |

**User's choice:** Recommended option.
**Notes:** One automatic retry preserves responsiveness without hiding persistent failures.

---

## Search Focus Experience

| Option | Description | Selected |
|--------|-------------|----------|
| Search history only | Focused empty search shows only prior query terms. | |
| Search history + recent playback + cached songs | Focused empty search stays local while offering useful suggestions. | ✓ |
| Search history + recent playback + cached songs + favorite seeds | Also includes favorite-folder-derived suggestions. | |

**User's choice:** Recommended option.
**Notes:** Favorite-folder seed suggestions were excluded from Phase 1 to avoid adding account/favorite work to the focus path.

| Option | Description | Selected |
|--------|-------------|----------|
| Only on submit | Bilibili search starts only after explicit search submission. | ✓ |
| After debounce while typing | Network search may run after a typing delay. | |
| On focus via prefetch | Search page may prefetch on focus. | |

**User's choice:** Recommended option.
**Notes:** User reported severe lag specifically when first tapping the search field, so the focus path must be network-free and cheap.

---

## Recommendation and Image Background Work

| Option | Description | Selected |
|--------|-------------|----------|
| Run all enrichment in sequence | History, artwork, lyrics, recommendations, MV, queue prefetch, and auto-cache can all start after playback begins. | |
| Run history/artwork/lyrics; lazy-load recommendations and MV | Keep light/current-track enrichment after sound, but defer recommendation and MV work until their surfaces are opened or explicitly requested. | ✓ |
| Run only history; everything else lazy-loads | Defer nearly all enrichment. | |

**User's choice:** `2b`; the user explicitly selected this option and accepted recommendations for the rest.
**Notes:** This is the one non-default answer from the batch. It means recommendations and MV should not merely be delayed by sleeps; they should be triggered by relevant surfaces/user intent where practical.

| Option | Description | Selected |
|--------|-------------|----------|
| Keep list stable, mark stale | Do not clear or replace visible Home recommendations during first playback. | ✓ |
| Refresh in background and replace when ready | Allow background refresh to update the visible list. | |
| Clear and reload immediately | Reset recommendations on first playback. | |

**User's choice:** Recommended option.
**Notes:** Directly addresses the bug where opening the app and first tapping a song makes recommendations flash/change.

| Option | Description | Selected |
|--------|-------------|----------|
| Images can appear late; playback and scroll first | Deprioritize images broadly. | |
| Images should appear as fast as possible | Maximize image loading speed even if it competes with interaction. | |
| First-screen images first, remaining images delayed or low concurrency | Keep visible content useful while limiting background image work. | ✓ |

**User's choice:** Recommended option.
**Notes:** The target is bounded image work, not perfect instant artwork.

---

## Completion Standard and Tests

| Option | Description | Selected |
|--------|-------------|----------|
| Subjective feel plus existing tests | Rely mostly on manual feel and current test coverage. | |
| Metrics/logging plus key tests | Add measurable timing/logging and focused regression checks for the critical paths. | ✓ |
| Strict real-device budgets plus Instruments and full automation | Require deeper profiling and strict device budgets before completion. | |

**User's choice:** Recommended option.
**Notes:** The project is a personal iPhone app, so strict release-lab gates are too heavy for Phase 1, but regressions need to be visible.

---

## the agent's Discretion

- Exact logging format and metric names.
- Exact helper extraction boundaries for `PlayerEngine`, `SearchStore`, recommendation work, and image loading.
- Exact XCTest/XCUITest split, as long as the critical behaviors are covered.

## Deferred Ideas

None from this discussion batch.
