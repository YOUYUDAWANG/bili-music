# Project Research Summary

**Project:** Bilibili Music  
**Date:** 2026-06-26  
**Research scope:** Existing iOS SwiftUI music app performance, playback architecture, Apple Music-style UX, and private Bilibili API risk.

## Key Findings

### Stack

- Keep the stack native: SwiftUI + Observation, AVFoundation/AVKit, MediaPlayer, URLSession, Keychain, UserDefaults, and local Documents storage. No third-party playback framework is justified.
- AVPlayer is not the main architectural problem. The current risk is that `PlayerEngine`, `StreamResolver`, `NowPlayingView`, and API fan-out can put too much work on or near the playback startup path.
- Bilibili media headers should be centralized. Direct AVURLAsset custom-header injection is a pragmatic sideload workaround, not a stable public Apple API surface.
- First-play behavior must be measured. Add instrumentation around tap, stream resolution, item creation, `playImmediately`, and first playing/time tick.

### Table Stakes

- First sound is the product contract. Cache lookup, prepared stream reuse, fresh stream resolution, AVPlayerItem creation, and play are the only critical-path operations.
- Search focus must be local and instant. The keyboard, search history, and suggestions should appear without WBI prewarm, Bilibili requests, heavy filtering, or recommendation work.
- Search, home, related recommendations, radio, collections, and pagination must stay music-only by default.
- Mini-player, Now Playing, queue, recommendations, lyrics, favorite, cache, and MV controls should follow a dense Apple Music-like interaction model.
- Lyrics unavailable, MV unavailable/loading, favorite auth failure, cache failure, and download failure need explicit states instead of misleading active controls or generic errors.

### Architecture

- Keep `PlayerEngine` as the main-actor facade, but split the critical path into smaller services:
  - `PlaybackCore` for AVPlayer lifecycle and readiness.
  - `PlaybackStartupPipeline` for cache/prepared/remote source resolution.
  - actor-backed `StreamResolver` for short-lived playurl cache and in-flight coalescing.
  - `PlaybackEnrichmentScheduler` for lyrics, artwork, MV probing, prefetch, radio, history, and auto-cache.
  - `RequestGate` / `BiliRequestCoordinator` for bounded concurrency and request coalescing.
- Recommendation state should move out of `NowPlayingView`. A visible recommendation list should be marked stale and refreshed explicitly or after playback stabilizes, not cleared on every playback start.
- Search needs query/mode/page identity guards so stale async results cannot append into a newer search.
- Images need downsampling and memory-pressure handling; cover art should not be decoded at arbitrary source size and retained indefinitely.

### Watch Out For

- A five-second first-play delay usually means the first tap is waiting behind enrichment, unbounded fan-out, main-actor work, AVPlayer buffering, or missing prewarm.
- Search field first-focus freeze points to synchronous SwiftUI state expansion, image/list invalidation, history decode, WBI work, or other main-thread work triggered by focus.
- Non-music search results usually come from later pages, expanded keywords, stale query results, or MV/general video sections leaking into song results.
- Recommendation flashes usually mean playback state changes are resetting Home/Now Playing recommendation identity or clearing old results before replacement content is ready.
- Memory kills are likely from image decoding/caching, unbounded result caches, unbounded task groups, or media state retained after dismissal/backgrounding.
- 401 must be treated as auth-expired, not a generic interface error.

## Implications for Roadmap

### Phase 1: Playback Critical Path and Responsiveness

Goal: make the app feel responsive before adding more functionality.

Must address:

- Tap-to-first-audio instrumentation.
- Playback startup path excludes lyrics, recommendations, MV probing, artwork, auto-cache, and heavy history writes.
- Prepared stream invalidation/retry on expired or 403 streams.
- Search focus path becomes local-only and cheap.
- Image downsampling/memory-pressure cleanup begins.
- Recommendation refresh no longer fires or clears Home on first playback.

### Phase 2: Search and Recommendation Reliability

Goal: make discovery trustworthy and music-only.

Must address:

- Search query/mode/page generation guards.
- Pagination with partial success, retry, and no stale-result pollution.
- Strict music filtering on every search page and every recommendation source.
- Bounded concurrency for search, related videos, favorite seeds, and fallback candidates.
- Separate Home recommendation state from Now Playing related recommendations.

### Phase 3: API/Auth/Cache Hardening

Goal: make failures understandable and recoverable.

Must address:

- HTTP status handling before JSON decoding.
- Typed Bilibili/API/auth/rate-limit/decode errors.
- Cookie expiry detection and re-login path.
- Cache index repair, quota/free-space checks, orphan cleanup, and download failure states.
- Fixture decode tests for private API responses and WBI signing assumptions.

### Phase 4: Player Interaction Polish and Regression Coverage

Goal: make the daily player experience feel like a mature iPhone music app.

Must address:

- Dense Apple Music-like Now Playing layout.
- Left player page as current queue/current playlist.
- Right player page as related/recommendations.
- Dismiss gestures scoped away from scrollable lists and progress scrubbing.
- MV/music switch keeps one playback source active and preserves time.
- UI tests for mini-player expansion, down-swipe minimize, queue/recommendation scrolling, lyrics unavailable, and cache/favorite state.

## Requirements Guidance

Recommended v1 requirements should prioritize:

- Playback performance and first-sound latency.
- Search focus responsiveness and result correctness.
- Recommendation refresh isolation.
- Memory and image stability.
- Player gesture correctness.
- Regression tests for the above.

Recommended v2 requirements:

- API-domain split and typed error model.
- Full cache quota/repair system.
- Authentication lifecycle hardening.
- Deeper Apple Music-style visual polish.
- UP collection recognition and full queue context polish.
- Optional documented media resource loader if direct Bilibili header injection becomes unreliable.

## Sources

- `.planning/research/STACK.md`
- `.planning/research/FEATURES.md`
- `.planning/research/ARCHITECTURE.md`
- `.planning/research/PITFALLS.md`
- `.planning/PROJECT.md`
- `.planning/codebase/ARCHITECTURE.md`
- `.planning/codebase/CONCERNS.md`
