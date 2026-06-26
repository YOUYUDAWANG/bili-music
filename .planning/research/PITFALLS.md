# Research: Pitfalls and Failure Modes

**Project:** Bilibili Music  
**Domain:** Personal iOS SwiftUI music app using AVPlayer, Bilibili private web APIs, local cache, and Swift concurrency  
**Researched:** 2026-06-26  
**Overall confidence:** MEDIUM. Apple platform behavior is primary-source backed; Bilibili private API behavior is inherently less certain because the endpoints are undocumented.

## Critical Pitfalls

| Pitfall | Failure Mode | Warning Signs | Prevention Strategy | Roadmap Phase | Confidence |
|---------|--------------|---------------|---------------------|---------------|------------|
| First playback path does too much | Tap-to-sound waits behind stream resolution, cid lookup, recommendation refresh, lyrics, artwork, history writes, MV checks, or cache work. | First play takes ~5s; `PlayerEngine` stays loading; network burst starts after tap; recommendation or artwork tasks start before audible playback. | Make playback start the critical path: cache lookup -> stream resolve -> `AVPlayerItem` readiness -> play. Defer lyrics, recommendations, images, history flush, auto-cache, and MV enrichment until after first audio. Instrument tap-to-first-audio. | Phase 1: Playback Critical Path | MEDIUM |
| AVPlayer readiness and buffering are treated as black boxes | The player appears hung while AVPlayer is waiting, buffering, or preparing an item. | `AVPlayerItem.status` remains unknown; `timeControlStatus` is waiting; `reasonForWaitingToPlay` indicates buffering; retry works but feels random. | Observe player/item readiness explicitly. Use AVFoundation readiness signals, short-lived stream caching, and optional preroll for likely next tracks. Tune `automaticallyWaitsToMinimizeStalling` only with measurements, because reducing startup delay can increase stalls. | Phase 1: Playback Critical Path | MEDIUM |
| SwiftUI main-thread work blocks focus and gesture response | Search focus, list updates, and player drag compete with synchronous filtering, sorting, decoding, persistence, or broad observable updates. | First search field focus freezes; drag hitches; SwiftUI body recalculations spike; user-action work exceeds ~100ms; scrolling drops frames. | Keep view bodies cheap. Move expensive search prep, WBI prewarm, cache load, image decode, filtering, and persistence off focus/body paths. Narrow observable invalidations and profile with SwiftUI/Instruments. | Phase 1: Responsiveness Baseline | MEDIUM |
| Huge network images and decoded bitmaps cause memory pressure | Cover art is decoded at full source size and retained across rows/player screens. | App killed under memory pressure; memory climbs while scrolling; large cover URLs cause spikes; image cache evictions do not recover enough memory. | Downsample network images to display size with ImageIO-style transforms before caching. Track cache cost, clear reloadable images/media on memory warnings/background, and cap concurrent image decodes. | Phase 1: Memory Stabilization | MEDIUM |
| Unbounded task fan-out overloads device and Bilibili | Search, recommendation, favorite sync, related videos, and preload launch too many concurrent network tasks. | Bursts of Bilibili requests; 403/429/timeout; battery/network spikes; search or recommendations return late or empty; memory grows during task groups. | Add bounded concurrency per domain, request coalescing, dedupe by `TrackKey`, and partial-success handling. Do not let recommendation/search fan-out run on the playback critical path. | Phase 2: Search and Recommendation Reliability | MEDIUM |
| Stale async results overwrite current state | Old search, recommendation, playlist lookup, lyrics, or prefetch results publish after the active query/track changed. | Results from prior query appear; recommendation panel refreshes when playback starts; lyrics/artwork mismatch current track; old page appends after new search. | Use generation tokens for query, page, and playback. Cancel old tasks, check cancellation inside child tasks, and publish only when identity still matches current state. | Phase 2: Async Correctness | MEDIUM |
| Search pagination pollutes music results | Later pages or expanded keywords reintroduce non-music videos, duplicates, old query results, or MVs in song sections. | Commentary/gameplay appears; duplicate BVIDs; raw count high but filtered count unstable; load-more silently stops. | Apply `MusicFilter` to every page and mode. Track `query + mode + page` identity, preserve partial page successes, expose retry state, and test non-music rejection with fixtures. | Phase 2: Search Quality | MEDIUM |
| Network and API errors collapse into empty state | HTTP errors, auth failures, rate limits, captive portal HTML, decode drift, and cancellation look like `[]`, `nil`, or generic decode failures. | Empty recommendations/search without explanation; 401 looks like normal failure; 429/5xx hidden; logs show decode errors for non-JSON responses. | Inspect `HTTPURLResponse.statusCode` before decoding. Introduce typed errors for transport, HTTP, Bilibili API code, auth expired, rate limited, cancellation, and decode drift. Add retry/backoff only for safe transient cases. | Phase 3: API Boundary Hardening | MEDIUM |
| Bilibili private API and WBI signing drift | Undocumented web endpoints change schema, signing keys, required headers, or response codes. | Search/feed/favorites break while app still builds; WBI key parse fails; playurl returns unexpected structure; community scripts need updates. | Keep all endpoint parsing and WBI signing isolated behind API-domain clients. Add fixture decode tests, live smoke scripts, fallback UI, and a clear "API changed" diagnostic. Never duplicate signing logic outside the API boundary. | Phase 3: Private API Resilience | MEDIUM |
| Cookie expiry and auth state diverge | Stored cookies remain in Keychain and UI says logged in, but Bilibili rejects favorites, high quality, or personalized APIs. | Favorites return 401/403; QR login appears valid but mutations fail; recommendations degrade silently; user must manually log out. | Store cookies in Keychain, but validate auth on launch/resume and normalize auth failures globally. Clear invalid session state, prompt relogin, and never attach cookies to non-allowlisted hosts from API-returned URLs. | Phase 3: Auth Lifecycle | MEDIUM |
| Cache index corruption loses offline library | JSON index and audio files diverge after failed writes, moves, deletes, app termination, or schema changes. | Library empty after restart while files exist; orphaned audio files; duplicate cache rows; failed downloads leave partial state; disk fills unexpectedly. | Use versioned cache index envelopes, atomic writes, backup-on-corruption, repair scan from `Documents/audio`, quota/free-space checks, orphan cleanup, and explicit download failure UI. | Phase 3: Cache Reliability | MEDIUM |
| Player dismissal gesture steals scroll/list gestures | Full-player vertical drag conflicts with recommendation list scroll, queue scroll, horizontal pages, and progress scrubbing. | Scrolling dismisses player; drag feels sticky; scrubber changes pages; list momentum triggers minimize; UI tests pass only with fixture coordinates. | Restrict dismissal to a grab zone or top chrome, gate by scroll offset and drag direction, use SwiftUI gesture masks deliberately, and add UI tests for list scroll vs dismissal vs scrub/page gestures. | Phase 4: Player Interaction Polish | MEDIUM |

## Warning Signs

- Playback: p95 tap-to-first-audio above 1s, first play much slower than second play, `AVPlayerItem.status` stays unknown, or playback starts only after recommendation/artwork/lyrics logs complete.
- SwiftUI: search focus or player drag causes visible hangs, body recalculation bursts, main-thread user-action work above ~100ms, or continuous gestures miss display frames.
- Memory: memory climbs while scrolling covers, app receives memory warnings, image cache cost grows without recovery, or iOS terminates the app under pressure.
- Async: old search pages append to new queries, recommendation lists refresh when playback starts, or lyrics/artwork belong to a previous track.
- API/auth: decode errors on HTTP errors, silent empty search/recommendation states, 401/403 while UI says logged in, or sudden WBI/playurl failures.
- Cache: offline library differs from files on disk, partial downloads remain, JSON decode failure clears state, or disk usage has no visible cap.
- Gestures: recommendation/queue scrolling dismisses the player, progress scrubbing triggers page swipes, or downward drags work differently by list position.

## Prevention Strategies

1. Define a playback startup budget and protect it. The only required first-play work should be identity resolution, cache/stream resolution, player item preparation, and play.
2. Treat all enrichment as post-playback: recommendations, lyrics, artwork, MV probing, history persistence, queue prefetch, and auto-cache must be cancellable and generation-guarded.
3. Keep SwiftUI state updates narrow. Avoid running filtering, sorting, JSON load/save, image decode, or network prewarm from `body`, focus callbacks, or continuous gesture updates.
4. Bound concurrency everywhere Bilibili is involved. Use small per-feature limits, request coalescing, dedupe keys, and partial-success UI instead of unbounded task groups.
5. Make API failures typed and visible. Check HTTP status before decode, preserve server/API codes, distinguish auth expiry from transient failure, and log enough context to diagnose endpoint drift.
6. Make cache persistence repairable. Use atomic writes, versioned JSON, backups, orphan scans, quota checks, and explicit failed-download states.
7. Downsample and evict images aggressively. Network cover art should be transformed to display size before memory caching, and reloadable media/image data should be released under pressure.
8. Design gestures as an interaction contract. Dismiss only from deliberate surfaces, gate against scroll offset/direction, and test the queue/recommendation/scrubber/page combinations.

## Phase Mapping

| Phase | Address First | Pitfalls Covered | Exit Criteria |
|-------|---------------|------------------|---------------|
| Phase 1: Playback Critical Path and Responsiveness | First playback, AVPlayer readiness, SwiftUI focus freeze, image memory pressure | Playback path overload, AVPlayer black box, main-thread blocking, huge images | Measured tap-to-first-audio; no recommendation refresh on first play; search focus has no visible freeze; memory warning cleanup exists. |
| Phase 2: Search and Recommendation Reliability | Search pagination, music filtering, stale async results, bounded fan-out | Task fan-out, stale async writes, search pollution, recommendation refresh coupling | Query/page generation guards; bounded concurrent requests; non-music fixture tests; load-more has partial success/error handling. |
| Phase 3: API/Auth/Cache Hardening | Bilibili boundary, Cookie lifecycle, network error taxonomy, cache repair | API error flattening, private API drift, cookie expiry, cache corruption | Typed `BiliClient` errors; auth-expired relogin path; fixture decode tests for endpoints; cache index repair and quota policy. |
| Phase 4: Player Interaction Polish and Regression Coverage | Full-player gestures, list scrolling, scrubber/page conflicts | Gesture dismissal conflicts, UI hitches from interaction coupling | UI tests cover dismissal zone, queue/recommendation scrolling, progress scrubbing, and page swiping without accidental minimize. |

## Sources

- Apple Developer Documentation: AVPlayer: https://developer.apple.com/documentation/avfoundation/avplayer
- Apple Developer Documentation: AVPlayerItem status: https://developer.apple.com/documentation/avfoundation/avplayeritem/status-swift.property
- Apple Developer Documentation: `automaticallyWaitsToMinimizeStalling`: https://developer.apple.com/documentation/avfoundation/avplayer/automaticallywaitstominimizestalling
- Apple Developer Documentation: `preroll(atRate:completionHandler:)`: https://developer.apple.com/documentation/avfoundation/avplayer/preroll%28atrate%3Acompletionhandler%3A%29
- Apple Developer Documentation: Observing playback state in SwiftUI: https://developer.apple.com/documentation/avfoundation/observing-playback-state-in-swiftui
- Apple Developer Documentation: Improving app responsiveness: https://developer.apple.com/documentation/xcode/improving-app-responsiveness
- Apple Developer Documentation: Understanding and improving SwiftUI performance: https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance
- Apple Developer Documentation: Responding to memory warnings: https://developer.apple.com/documentation/uikit/responding-to-memory-warnings
- Apple Developer Documentation: Making changes to reduce memory use: https://developer.apple.com/documentation/xcode/making-changes-to-reduce-memory-use
- Apple Developer Documentation: URLSession: https://developer.apple.com/documentation/foundation/urlsession
- Apple Developer Documentation: HTTPURLResponse: https://developer.apple.com/documentation/foundation/httpurlresponse
- Apple Developer Documentation: URLSessionTask cancellation: https://developer.apple.com/documentation/foundation/urlsessiontask/cancel%28%29
- Apple Developer Documentation: Task cancellation: https://developer.apple.com/documentation/swift/task/checkcancellation%28%29
- Apple Developer Documentation: Throwing task groups: https://developer.apple.com/documentation/swift/withthrowingtaskgroup%28of%3Areturning%3Aisolation%3Abody%3A%29
- Apple Developer Documentation: Keychain Services: https://developer.apple.com/documentation/security/keychain-services
- Apple Developer Documentation: SwiftUI simultaneous gestures: https://developer.apple.com/documentation/swiftui/view/simultaneousgesture%28_%3Aincluding%3A%29
- Apple Developer Documentation: SwiftUI high-priority gestures: https://developer.apple.com/documentation/swiftui/view/highprioritygesture%28_%3Aincluding%3A%29
- SocialSisterYi Bilibili API collect, WBI signing: https://github.com/SocialSisterYi/bilibili-API-collect/blob/master/docs/misc/sign/wbi.md
- Local project context: `.planning/PROJECT.md`, `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/CONCERNS.md`, `.planning/codebase/TESTING.md`
