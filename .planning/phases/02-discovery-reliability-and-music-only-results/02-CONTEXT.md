# Phase 2: Discovery Reliability and Music-Only Results - Context

**Gathered:** 2026-06-26
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase makes discovery trustworthy: Search, pagination, Home recommendations, and Now Playing related recommendations must stay scoped to the active user intent, avoid stale-result leakage, preserve visible lists during failures, and keep default surfaces music-only.

The phase does not redesign the full player, rewrite Bilibili API/auth/cache layers, or add new music features beyond the discovery stability requirements already mapped to Phase 2.

</domain>

<decisions>
## Implementation Decisions

### Search Result Scope

- **D-01:** Default search is strict music-only. It should use Bilibili music-category search where available and still apply app-side filtering on every fetched page.
- **D-02:** The Search screen should not expose a separate MV search mode. MV-like results can appear inside the music result set only when they pass the music filter.
- **D-03:** The Search field does not need BV/link parsing in Phase 2. Focused empty state should show only local history/suggestions/recent/cache content and must not trigger remote work.
- **D-04:** Remote results must be accepted only when they match the active query, active mode, and current request identity. Late results from older searches or older mode/page work must be ignored.

### Pagination and Expanded Results

- **D-05:** Loading more appends to the existing result list. A later page failure must not clear or replace existing results.
- **D-06:** If a page filters down to zero music results but raw results still exist, the store may advance through a small bounded number of additional pages to avoid looking stuck.
- **D-07:** The "更多结果" affordance belongs in empty/low-result states, not as a first-class default mode. Expanded results may relax category strictness but must still reject obvious non-music content.
- **D-08:** Pagination should expose retry state for the failed load-more operation without forcing the user to resubmit the whole search.

### Recommendation State

- **D-09:** Home recommendations and Now Playing related recommendations are separate visible states. Refreshing one must not clear, reorder, or cancel the other.
- **D-10:** Tapping a track from the player recommendation list must not immediately refresh, scramble, or clear that visible recommendation list. Refresh should happen only through explicit refresh or when the user leaves/re-enters the recommendation context.
- **D-11:** Home recommendation refresh remains explicit: initial Home load and manual refresh. Playback side effects must not refresh Home recommendations.
- **D-12:** Now Playing related recommendations should be keyed by the current track and visible panel lifecycle, not by every playback side effect.

### Music-Only Recommendation Quality

- **D-13:** Recommendation sources must use the same music-only principles as Search: Bilibili music category when using search, app-side `MusicFilter`, duration bounds, title/artist heuristics, and explicit rejection of games, commentary, tutorials, films, clips, and generic Bilibili content.
- **D-14:** Favorite-folder seeds remain a strong Home source, especially the user-selected music favorites folder. Related-video recommendations should be filtered before scoring and again before display.
- **D-15:** It is acceptable for strict filtering to return fewer results. Fewer relevant songs are better than a large mixed Bilibili feed.

### Performance Guardrails

- **D-16:** Discovery work cannot enter the playback first-sound critical path. Search preloading and recommendation refreshes must stay bounded and lower priority than direct playback.
- **D-17:** Search should avoid unnecessary fan-out: page/keyword requests should be bounded, preserve partial successes where possible, and avoid dropping all useful results because one page failed.

### the agent's Discretion

The agent may choose the exact state-token shape, retry representation, and small helper abstractions as long as the user-visible behavior above holds and the implementation stays close to existing `SearchStore`, `MusicFilter`, and `RecommendationEngine` patterns.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Scope

- `.planning/PROJECT.md` — Product identity, core value, validated state, and active requirements.
- `.planning/REQUIREMENTS.md` — Phase 2 requirement IDs: `SRCH-03`, `SRCH-04`, `SRCH-05`, `RECO-02`, `RECO-03`, `RECO-05`.
- `.planning/ROADMAP.md` — Phase 2 goal, success criteria, and Phase 3/v2 boundaries.
- `.planning/STATE.md` — Current phase and accumulated decisions from Phase 1.

### Codebase Maps

- `.planning/codebase/ARCHITECTURE.md` — Existing search, recommendation, player, API, and persistence responsibilities.
- `.planning/codebase/CONVENTIONS.md` — SwiftUI, `@Observable`, singleton store, error handling, and test-hook conventions.
- `.planning/codebase/TESTING.md` — Unit/UI test patterns and existing fixture mechanisms.
- `.planning/codebase/CONCERNS.md` — Known search pagination, recommendation fan-out, and API fragility concerns.

### Source Areas

- `BiliMusic/Features/Search/SearchStore.swift` — Search state, request identity, caching, pagination, and filtering entry point.
- `BiliMusic/Features/Search/SearchView.swift` — Search UI, local empty/focused state, result rows, retry, and pagination affordances.
- `BiliMusic/Features/Search/SearchModels.swift` — Search modes, cache keys, cached snapshots, and result sections.
- `BiliMusic/Player/MusicFilter.swift` — Central music-only filtering heuristics.
- `BiliMusic/Player/RecommendationEngine.swift` — Home, radio, and related-panel candidate sourcing, scoring, caching, and music filtering.
- `BiliMusic/Features/Home/HomeView.swift` — Home recommendation lifecycle and visible list stability.
- `BiliMusic/Player/PlayerEngine.swift` — Related recommendation loading, playback side effects, and first-sound guardrails.
- `BiliMusic/Features/Player/PlayerSheetViews.swift` and `BiliMusic/Features/Player/NowPlayingView.swift` — Player recommendation list surfaces.
- `BiliMusic/API/BiliClient.swift` — Bilibili `search(keyword:page:musicOnly:)` and `related(bvid:)` boundaries.
- `BiliMusicTests/SearchModelsTests.swift` and `BiliMusicUITests/PlayerChromeUITests.swift` — Existing regression-test style for search and player chrome behavior.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `SearchStore.activeSearchID`, `activeQuery`, `resultsQuery`, `mode`, `nextPage`, and `resultCache` already provide most of the structure needed for stale-result rejection and cached result restoration.
- `SearchCacheKey` already normalizes query + mode; extend or complement this with page/request identity rather than inventing a separate search subsystem.
- `MusicFilter.isSearchResult(_:query:mode:)` is the central filtering boundary and should remain the single app-side rule set for search result acceptance.
- `RecommendationEngine.Mode` already separates `.home`, `.radio`, and `.relatedPanel`; use that split to keep visible recommendation state separated.
- `RecommendationSchedulingPolicy.home(trigger:)` already distinguishes initial Home load and manual refresh and keeps Home scoring at `.utility` priority.

### Established Patterns

- Feature-local mutable state belongs in `@Observable @MainActor` stores such as `SearchStore`.
- Pure deterministic rules belong in stateless helpers such as `MusicFilter` and `SearchResultSections`, with unit tests.
- App-wide playback and visible recommendation effects should preserve `PlayerEngine` generation/current-track guards and must not re-enter the protected playback startup path.
- Network decoding and filtering can run off the main actor using detached tasks, but UI state application must return to the main actor with identity checks.

### Integration Points

- Search changes attach at `SearchStore.submitSearch`, `SearchStore.search`, `SearchStore.loadMorePage`, and `SearchStore.searchBatch`.
- Search UI changes attach at focused empty state, no-result state, retry row, and pagination control in `SearchView`.
- Recommendation changes attach at `RecommendationEngine.recommendations`, Home load/refresh in `HomeView`, and Now Playing related list loading in the player UI/engine boundary.
- Tests should extend `SearchModelsTests` for store identity/filtering/pagination behavior and `PlayerChromeUITests` or a focused unit seam for recommendation list stability.

</code_context>

<specifics>
## Specific Ideas

- User-visible discovery should feel like a music app, not a general Bilibili search page.
- Search should prioritize relevant music even if that means fewer results.
- The old MV search surface is considered unnecessary; MV is a playable presentation mode, not a discovery mode for Phase 2.
- Recommendation refresh should feel stable: tapping a recommendation plays it, but the list should not visually jump at that moment.

</specifics>

<deferred>
## Deferred Ideas

- Full player layout density, mini-player drag animation, and left/right player pages belong to Phase 3.
- Favorite folder long-press selection, collection queue context, MV/music source switching polish, current audio bitrate display, and full play-mode polish remain v2/player-feature scope unless narrowly required for discovery stability.
- Typed API/auth/cache hardening remains v2, except for narrow error handling needed to preserve search pagination or recommendation stability.

</deferred>

---

*Phase: 2-Discovery Reliability and Music-Only Results*
*Context gathered: 2026-06-26*
