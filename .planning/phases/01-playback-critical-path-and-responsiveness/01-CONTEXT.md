# Phase 1: Playback Critical Path and Responsiveness - Context

**Gathered:** 2026-06-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 1 delivers the fast, stable daily music path: tapping a track should make it current immediately and request playback after only the minimum source resolution work, while search focus, recommendation refreshes, image loading, memory cleanup, and post-start media enrichment stop interfering with first sound.

This phase does not redesign discovery quality, player gestures, queue pages, favorite-folder UX, MV polish, or cache/auth hardening except where a narrow change is required to protect first playback, search-focus responsiveness, recommendation stability, or image memory behavior.

</domain>

<decisions>
## Implementation Decisions

### First Playback Critical Path
- **D-01:** First playback may block only on the minimal path: set the current track state, use a local cache entry or prepared stream when available, resolve one necessary `cid`/`playurl` when needed, create the `AVPlayer` item, and request playback.
- **D-02:** Lyrics, artwork, MV probing, recommendation loading, queue/radio prefetch, auto-cache, and other enrichment cannot be awaited before the playback request.
- **D-03:** If a prepared remote stream appears expired or unauthorized, discard it and retry source resolution once. Only surface failure after the retry also fails.
- **D-04:** Tap-to-play diagnostics should expose timing checkpoints for tap, current-track assignment, source resolution, AVPlayer item creation, play request, and first observed playing state so regressions are measurable.

### Search Focus Experience
- **D-05:** Focusing the search field with an empty query should remain local and cheap.
- **D-06:** Empty focused search should show local search history, recent playback, and cached songs. Favorite-folder seed suggestions are intentionally excluded from Phase 1.
- **D-07:** Bilibili search requests may start only after explicit user submission, such as tapping keyboard search. Focus alone and normal typing must not perform network work.

### Recommendation and Background Work
- **D-08:** After sound starts, history, artwork, and lyrics may run as post-start work. Recommendation and MV work should wait until the user opens the relevant page or explicitly triggers it.
- **D-09:** Starting the first song after app launch must keep the existing Home recommendation list stable. It may be marked stale internally, but must not clear, auto-refresh, flash, or replace visible recommendations on the first playback path.
- **D-10:** Recommendation work should remain lower priority than direct playback startup and should not compete with first playback for network, main-actor time, or image decoding.

### Image and Memory Guardrails
- **D-11:** Image loading should prioritize first-screen visible images. Remaining images should be delayed, lower priority, or concurrency-capped.
- **D-12:** Scrolling and playback responsiveness outrank image completeness; images can appear late if needed to keep the app responsive.
- **D-13:** Decoded image memory should stay bounded, with a path to release reloadable image/media data on memory pressure or backgrounding without losing playback state.

### Completion Standard and Tests
- **D-14:** Phase 1 is complete only when behavior is observable through metrics/logging plus focused regression checks, not just by subjective feel.
- **D-15:** Regression coverage should include at least: search focus doing no network/expensive work, first playback not awaiting post-start enrichment, Home recommendations not resetting on first playback, and bounded image/memory behavior.

### the agent's Discretion

The agent may choose the exact instrumentation shape, log category names, internal helper boundaries, and test seams, as long as they preserve the existing SwiftUI app structure and avoid broad rewrites. Narrow collaborators or small protocols are acceptable when they directly make the first-play/search/recommendation/image behavior testable.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Product Scope and Requirements
- `.planning/PROJECT.md` — Product identity, core value, active requirements, constraints, and key decisions.
- `.planning/REQUIREMENTS.md` — v1 requirements and traceability; Phase 1 covers `PLAY-01` through `PLAY-05`, `SRCH-01`, `SRCH-02`, `RECO-01`, `RECO-04`, and `MEM-01` through `MEM-03`.
- `.planning/ROADMAP.md` — Phase boundary, success criteria, and sequence.
- `.planning/STATE.md` — Current planning state and accumulated concerns.
- `.planning/research/SUMMARY.md` — Prior research summary for Bilibili API and app behavior assumptions.

### Codebase Maps
- `.planning/codebase/ARCHITECTURE.md` — Current component responsibilities, data flow, and integration points.
- `.planning/codebase/CONCERNS.md` — Known playback, search, recommendation, image, persistence, and testing risks.
- `.planning/codebase/TESTING.md` — Existing XCTest/XCUITest patterns, fixtures, and verification commands.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BiliMusic/Player/PlayerEngine.swift` — Owns queue state, `AVPlayer`, source resolution, playback generation checks, playback mode, post-playback work, history, and prefetch. Phase 1 should protect `play(...)`/`startCurrent(...)` first.
- `BiliMusic/Player/StreamResolver.swift` — Resolves missing `cid`/duration and caches prepared audio streams. This is the right place to handle prepared-stream invalidation and one retry without persisting short-lived URLs.
- `BiliMusic/Features/Search/SearchStore.swift` — Owns search query state, history, result cache, submit, pagination, and preloading callbacks. Phase 1 should keep focus/empty-query state local and cheap.
- `BiliMusic/Features/Home/HomeView.swift` and `BiliMusic/Player/RecommendationEngine.swift` — Own Home recommendation loading, candidate building, scoring, cache, and preloading. Phase 1 should prevent first playback from clearing or replacing visible Home recommendations.
- `BiliMusic/Design/CachedAsyncImage.swift` — Provides shared image loading, URL coalescing, `NSCache`, and URLCache. Phase 1 should add priority/downsampling/memory-pressure guardrails here rather than duplicating image loaders.
- `BiliMusic/Player/PlaybackHistoryStore.swift`, `BiliMusic/Cache/CacheStore.swift`, and `BiliMusic/Features/Home/RecentHomeFeedStore.swift` — Existing persistence stores that can support local search suggestions and recommendation stability.

### Established Patterns
- App-wide playback state is a single `@Observable @MainActor` `PlayerEngine` injected through SwiftUI environment.
- Feature-specific UI state stays in stores such as `SearchStore`; long-lived persistence stores are mostly singleton boundaries.
- Network access should remain behind `BiliClient`, `WBISigner`, `LyricsClient`, or existing service boundaries.
- Media stream URLs are short-lived and must not be persisted; cache should persist track identity and local files instead.
- `TrackKey` and partial `cid` matching are fragile; cache, queue, and retry work must account for multi-part Bilibili videos.
- Existing tests use XCTest, `@testable import BiliMusic`, simple inline `Track` fixtures, and UI fixture mode through `BILIMUSIC_UITEST_FIXTURE`.

### Integration Points
- Playback starts from Home, Search, Favorites, Library, history, queue, and test/debug paths by calling `PlayerEngine.play(...)`.
- `PlayerEngine.startCurrent(...)` currently resolves MV/cache/prepared/fresh sources, starts playback, records history, and schedules post-playback work.
- `schedulePostPlaybackWork(...)` currently sequences cover, lyrics, MV preparation, prefetch, and optional auto-cache with sleeps and generation guards; Phase 1 should keep this off the critical path and split/lazy-load where needed.
- `SearchStore.queryDidChange(...)` and `submitSearch(...)` are the key seams for search focus behavior, stale-result prevention, and local suggestions.
- `RecommendationEngine.makeSnapshot(...)` can touch cache, history, favorite IDs, and folders; this must not run on first playback unless explicitly requested by a recommendation surface.
- `CachedAsyncImage` currently coalesces URL loads and bounds cache count/cost, but still decodes full `UIImage(data:)` responses and has no explicit memory-pressure release path.

</code_context>

<specifics>
## Specific Ideas

- Product priority is explicit: if playback startup conflicts with recommendation, lyrics, MV, UI polish, image loading, or cache work, first sound wins.
- Search focus should feel instant because it displays only already-local data until the user submits a query.
- Home recommendations should not visually change as a side effect of the first song tap after app launch.
- Images may load progressively or late; the user prefers responsiveness over immediate image completeness.
- Phase 1 should produce enough logging/tests to tell whether future changes regress first playback or search focus.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 1 scope. Discovery music-only ranking, search pagination, related-list behavior, player gestures/layout density, favorite-folder selection, collection queue context, MV/fullscreen polish, and broader API/auth/cache hardening remain in later roadmap phases unless a narrow dependency is required for Phase 1 stability.

</deferred>

---

*Phase: 1-Playback Critical Path and Responsiveness*
*Context gathered: 2026-06-26*
