# Phase 2: Discovery Reliability and Music-Only Results - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-26
**Phase:** 2-Discovery Reliability and Music-Only Results
**Areas discussed:** Search result scope, pagination, recommendation state, music-only quality, performance guardrails

---

## Search Result Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Strict music default | Default search only shows music-like results and applies app-side filtering on every page. | yes |
| General Bilibili search | Preserve broad Bilibili video search and rely on user judgment. | no |
| Separate MV search mode | Keep MV as its own search surface. | no |

**User's choice:** The user repeatedly reported that search shows too many non-music results and explicitly asked to remove MV search mode.
**Notes:** Context locks default strict music-only search. MV remains a playback/presentation mode, not a Phase 2 discovery mode.

---

## Pagination

| Option | Description | Selected |
|--------|-------------|----------|
| Append with retry | Load more appends results, preserves existing results on failure, and exposes retry for the failed page. | yes |
| Resubmit whole search | Any pagination failure requires submitting the search again. | no |
| Clear on failure | Failed later pages can clear or replace existing results. | no |

**User's choice:** The user asked for search results to support pagination and more loading, while previous feedback said stale/old results appearing is a serious issue.
**Notes:** Context locks query/mode/page identity checks and no stale result leakage.

---

## Recommendation State

| Option | Description | Selected |
|--------|-------------|----------|
| Separate visible states | Home and Now Playing recommendations keep separate state; tapping a related track does not immediately refresh the visible related list. | yes |
| Shared recommendation state | One recommendation refresh path can update Home and player panels together. | no |
| Refresh on every tap | Related list refreshes immediately whenever a recommendation is played. | no |

**User's choice:** The user reported recommendation lists changing unexpectedly and specifically said tapping a recommendation should not refresh the list until leaving the recommendation view.
**Notes:** Context locks visible-list stability and decouples playback side effects from recommendation refresh.

---

## Music-Only Quality

| Option | Description | Selected |
|--------|-------------|----------|
| Prefer fewer relevant songs | Strict filter can return fewer results rather than filling with unrelated Bilibili videos. | yes |
| Prefer more content | Keep broader feeds even if they contain commentary, games, film, tutorials, or clips. | no |
| Category-only filtering | Trust Bilibili `tids=3` alone. | no |

**User's choice:** The user wants the app to feel like a music app and repeatedly rejected mixed Bilibili content.
**Notes:** Context locks layered filtering: Bilibili music category where possible, app-side `MusicFilter`, duration checks, query relevance, and non-music rejection.

---

## Performance Guardrails

| Option | Description | Selected |
|--------|-------------|----------|
| Playback remains first | Discovery work stays bounded and cannot block first sound. | yes |
| Rich discovery first | Recommendations/search preloading may run aggressively even if playback startup competes for resources. | no |

**User's choice:** The project-level core value remains first-sound speed and playback stability.
**Notes:** Phase 2 work must preserve Phase 1 startup protections and avoid broad API/auth/cache rewrites.

---

## the agent's Discretion

- Exact request identity model for search.
- Exact retry UI representation for load-more failures.
- Exact bounded fan-out limits, as long as discovery stays responsive and playback remains first.

## Deferred Ideas

- Full player layout and gesture polish: Phase 3.
- Favorite folder selection, collection queue, MV/music switching polish, audio bitrate display, and play-mode polish: v2/player-feature scope unless narrowly needed.
- Broad API/auth/cache hardening: v2 unless a narrow error classification is needed for Phase 2 stability.
