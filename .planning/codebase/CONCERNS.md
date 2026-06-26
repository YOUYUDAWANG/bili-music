# Codebase Concerns

**Analysis Date:** 2026-06-26

## Tech Debt

**Playback and player UI concentration:**
- Issue: Playback state, queue policy, AVPlayer lifecycle, media mode switching, lyrics, artwork, prefetch, background behavior, remote commands, and history writes live in one `@MainActor` type.
- Files: `BiliMusic/Player/PlayerEngine.swift` (906 lines), `BiliMusic/Features/Player/NowPlayingView.swift` (1103 lines), `BiliMusic/Features/RootView.swift` (531 lines)
- Impact: Small playback changes can affect background audio, MV fallback, queue advancement, preloading, lock-screen metadata, and the full-player gesture surface.
- Fix approach: Split `BiliMusic/Player/PlayerEngine.swift` into focused collaborators for AV playback, queue/radio policy, media enrichment, and remote commands before adding more playback features.

**API client owns transport, endpoint schemas, login, favorites, feed, playlists, and stream selection:**
- Issue: `BiliClient` is both the HTTP transport and the typed schema namespace for unrelated API domains.
- Files: `BiliMusic/API/BiliClient.swift` (707 lines), `BiliMusic/API/WBISigner.swift`, `BiliMusic/Features/Favorites/FavoriteManager.swift`
- Impact: Endpoint changes in one Bilibili domain increase risk for search, login, favorites, recommendations, and stream playback.
- Fix approach: Keep one shared transport helper, then move domain methods into small clients such as `SearchClient`, `PlaybackClient`, `FavoritesClient`, and `LoginClient` using the same headers/cookie behavior.

**Silent error handling hides real failure modes:**
- Issue: Many network and persistence failures collapse to `nil`, `[]`, or a generic string.
- Files: `BiliMusic/Player/RecommendationEngine.swift:186`, `BiliMusic/Player/RecommendationEngine.swift:208`, `BiliMusic/Player/RecommendationEngine.swift:269`, `BiliMusic/API/LyricsClient.swift:29`, `BiliMusic/API/LyricsClient.swift:65`, `BiliMusic/Cache/CacheStore.swift:87`, `BiliMusic/Features/Home/RecentHomeFeedStore.swift:28`
- Impact: API drift, decode failures, filesystem failures, and rate limits can look like empty recommendations, missing lyrics, or empty cache state.
- Fix approach: Use typed non-fatal diagnostics for expected fallback paths and reserve `try?` for explicitly optional enrichments with debug logging.

**Raw JSON persistence lacks repair and migration paths:**
- Issue: Cache, playback history, and recent-home state are stored as ad hoc JSON files with silent decode/write failure behavior.
- Files: `BiliMusic/Cache/CacheStore.swift:63`, `BiliMusic/Cache/CacheStore.swift:87`, `BiliMusic/Player/PlaybackHistoryStore.swift:68`, `BiliMusic/Features/Home/RecentHomeFeedStore.swift:28`
- Impact: A malformed JSON file can erase in-memory state; audio files can remain in `Documents/audio/` without index entries.
- Fix approach: Add versioned envelopes, backup-on-corruption, and a cache repair pass that scans `BiliMusic/Cache/CacheStore.swift` audio filenames back into index candidates.

**Singleton-coupled global state limits testability:**
- Issue: Core flows reach directly into global singletons and `UserDefaults`.
- Files: `BiliMusic/Cache/CacheStore.swift:33`, `BiliMusic/Cache/DownloadManager.swift:11`, `BiliMusic/Features/Favorites/FavoriteManager.swift:8`, `BiliMusic/Player/NetworkMonitor.swift:9`, `BiliMusic/Player/PlayerEngine.swift:394`
- Impact: Unit tests cannot isolate cache, auth, network, recommendation, and preference state without mutating process-global objects.
- Fix approach: Introduce lightweight protocols and dependency injection at `BiliMusic/App/BiliMusicApp.swift` and keep singleton adapters at the app boundary.

## Known Bugs

**Expired login remains treated as logged in:**
- Symptoms: UI can show an account as logged in while Bilibili requests fail with auth errors.
- Files: `BiliMusic/Auth/CookieStore.swift:60`, `BiliMusic/Features/Settings/SettingsView.swift:98`, `BiliMusic/Features/Favorites/FavoriteManager.swift:151`, `BiliMusic/API/BiliClient.swift:454`, `BiliMusic/API/BiliClient.swift:510`
- Trigger: A stored `SESSDATA` or `bili_jct` expires or is revoked.
- Workaround: User manually logs out from `BiliMusic/Features/Settings/SettingsView.swift` and scans again.

**Search pagination can silently stop:**
- Symptoms: Loading more search results can stop with no visible error row.
- Files: `BiliMusic/Features/Search/SearchStore.swift:138`, `BiliMusic/Features/Search/SearchView.swift:218`
- Trigger: A later search page request throws after initial results exist.
- Workaround: Submit the search again from `BiliMusic/Features/Search/SearchView.swift`.

**Download failures are stored but not displayed:**
- Symptoms: A cache action can fail and the player returns to the idle download button without showing the reason.
- Files: `BiliMusic/Cache/DownloadManager.swift:15`, `BiliMusic/Cache/DownloadManager.swift:81`, `BiliMusic/Features/Player/NowPlayingView.swift:422`
- Trigger: Stream lookup, network download, file move, or disk write failure during `DownloadManager.download(track:)`.
- Workaround: Retry the same download from `BiliMusic/Features/Player/NowPlayingView.swift`.

**HTTP status codes are ignored before JSON decoding:**
- Symptoms: Server 403, 429, 500, captive portal, and CDN HTML responses surface as decode or transport errors instead of actionable API errors.
- Files: `BiliMusic/API/BiliClient.swift:61`, `BiliMusic/API/BiliClient.swift:91`, `BiliMusic/API/LyricsClient.swift:64`, `BiliMusic/API/WBISigner.swift:51`
- Trigger: Non-2xx responses from Bilibili, LRCLIB, or network intermediaries.
- Workaround: Retry after network recovery; code changes should inspect `HTTPURLResponse.statusCode` before decoding.

## Security Considerations

**Broad App Transport Security exception:**
- Risk: The app permits arbitrary loads even though source endpoints are HTTPS-first.
- Files: `BiliMusic/Info.plist`, `project.yml`
- Current mitigation: Most hard-coded API URLs in `BiliMusic/API/BiliClient.swift` and `BiliMusic/API/LyricsClient.swift` use `https://`.
- Recommendations: Remove `NSAllowsArbitraryLoads` or replace it with narrow domain exceptions for known Bilibili CDN hosts.

**Full session cookie is cached in memory and stored without write-result checks:**
- Risk: A `SecItemAdd` failure leaves `CookieStore.cachedCookie` set for the session while persistence silently fails; the full `SESSDATA`, `bili_jct`, and `DedeUserID` string remains in process memory.
- Files: `BiliMusic/Auth/CookieStore.swift:8`, `BiliMusic/Auth/CookieStore.swift:31`, `BiliMusic/Auth/CookieStore.swift:41`, `BiliMusic/Features/Settings/SettingsView.swift:211`
- Current mitigation: Cookie persistence uses Keychain APIs instead of `UserDefaults`.
- Recommendations: Check `SecItemAdd` and `SecItemDelete` statuses, set an explicit `kSecAttrAccessible...ThisDeviceOnly` policy, and clear in-memory state when Keychain writes fail.

**Cookie forwarding lacks host allow-listing for API-returned URLs:**
- Risk: If a remote response supplies a hostile subtitle URL, `subtitleFile(_:)` attaches the Bilibili cookie to that URL.
- Files: `BiliMusic/API/BiliClient.swift:381`, `BiliMusic/API/BiliClient.swift:386`, `BiliMusic/API/BiliClient.swift:388`
- Current mitigation: Subtitle URLs are sourced through Bilibili metadata and the subtitle path has no current UI caller in the indexed app flow.
- Recommendations: Validate host suffixes before setting `Cookie` on any URL not hard-coded in `BiliMusic/API/BiliClient.swift`.

## Performance Bottlenecks

**Recommendation and favorite sync fan out without a concurrency cap:**
- Problem: Recommendation and favorite flows launch task groups across seeds, pages, and folders.
- Files: `BiliMusic/Player/RecommendationEngine.swift:182`, `BiliMusic/Player/RecommendationEngine.swift:205`, `BiliMusic/Player/RecommendationEngine.swift:266`, `BiliMusic/Features/Favorites/FavoriteManager.swift:97`
- Cause: `withTaskGroup` is used directly over dynamic inputs from favorites and recommendation seeds.
- Improvement path: Add bounded concurrency and request coalescing around `BiliMusic/API/BiliClient.swift`.

**Search can issue multiple concurrent API calls per submit or pagination step:**
- Problem: A single search can request multiple pages for multiple derived keywords.
- Files: `BiliMusic/Features/Search/SearchStore.swift:252`, `BiliMusic/Features/Search/SearchStore.swift:300`, `BiliMusic/API/BiliClient.swift:314`
- Cause: `SearchStore.searchBatch` expands keywords and pages into a throwing task group.
- Improvement path: Cap concurrent page fetches, preserve partial successes, and add backoff for 429 or transient failures.

**Library sorting and byte aggregation repeat inside view rendering:**
- Problem: Cache filtering, sorting, and size reduction run from computed properties used by `LibraryView.body`.
- Files: `BiliMusic/Features/Library/LibraryView.swift:13`, `BiliMusic/Features/Library/LibraryView.swift:47`, `BiliMusic/Features/Library/LibraryView.swift:54`
- Cause: `visibleEntries` sorts on access and summary bytes are reduced from visible entries in the view tree.
- Improvement path: Move filtered/sorted cache projections into `CacheStore` or a small view model when cache sizes grow.

**Image loading decodes full responses before caching:**
- Problem: `UIImage(data:)` decodes whatever bytes the URL returns, then stores the full decoded bitmap in `NSCache`.
- Files: `BiliMusic/Design/CachedAsyncImage.swift:23`, `BiliMusic/Design/CachedAsyncImage.swift:58`, `BiliMusic/Design/CachedAsyncImage.swift:62`, `BiliMusic/Features/Player/NowPlayingView.swift:295`
- Cause: Image URLs usually request thumbnails, but the decoder has no downsampling guard if a non-thumbnail URL is passed.
- Improvement path: Decode through ImageIO downsampling sized to the target view before inserting into `ImageMemoryCache`.

## Fragile Areas

**Playback generation and async task choreography:**
- Files: `BiliMusic/Player/PlayerEngine.swift:452`, `BiliMusic/Player/PlayerEngine.swift:663`, `BiliMusic/Player/PlayerEngine.swift:701`, `BiliMusic/Features/Player/NowPlayingView.swift:789`
- Why fragile: Playback, post-playback enrichment, recommendation loading, MV fallback, and preloading all coordinate through task cancellation and `playbackGeneration` checks.
- Safe modification: Preserve generation guards and current-track checks when adding any async playback side effect; add tests around cancellation and rapid track switching.
- Test coverage: No unit tests cover `BiliMusic/Player/PlayerEngine.swift` or `BiliMusic/Player/StreamResolver.swift`.

**Track identity depends on partial `TrackKey` matching:**
- Files: `BiliMusic/Player/PlayerEngine.swift:11`, `BiliMusic/Player/PlayerEngine.swift:23`, `BiliMusic/Cache/CacheStore.swift:103`, `BiliMusic/Player/StreamResolver.swift:27`
- Why fragile: Unknown `cid` values act as wildcards until metadata resolves, so cache, stream, history, and queue logic must distinguish single-part and multi-part BVIDs carefully.
- Safe modification: Keep exact `bvid + cid` identity for persisted cache entries and add regression tests for multi-page Bilibili videos.
- Test coverage: Existing tests in `BiliMusicTests/SearchModelsTests.swift` do not cover `TrackKey.matches(_:)` cache edge cases.

**Recent-home persistence lacks a lifecycle flush:**
- Files: `BiliMusic/Features/Home/RecentHomeFeedStore.swift:61`, `BiliMusic/Features/RootView.swift:69`, `BiliMusic/Features/RootView.swift:72`
- Why fragile: `RecentHomeFeedStore` delays writes by one second, while scene background handling flushes only `CacheStore` and `PlaybackHistoryStore`.
- Safe modification: Add `RecentHomeFeedStore.flush()` and call it beside the existing flushes in `BiliMusic/Features/RootView.swift`.
- Test coverage: No tests cover `BiliMusic/Features/Home/RecentHomeFeedStore.swift`.

**Private Bilibili WBI signing and endpoint behavior:**
- Files: `BiliMusic/API/WBISigner.swift:4`, `BiliMusic/API/WBISigner.swift:8`, `BiliMusic/API/WBISigner.swift:48`, `BiliMusic/API/BiliClient.swift:323`
- Why fragile: Search and feed depend on an unofficial signature algorithm and key extraction from Bilibili `nav` responses.
- Safe modification: Keep WBI signing isolated in `WBISigner`, add fixture tests for known params, and avoid duplicating signing logic elsewhere.
- Test coverage: No tests cover `BiliMusic/API/WBISigner.swift`.

## Scaling Limits

**Audio cache has no quota or eviction policy:**
- Current capacity: Limited by available app Documents storage.
- Limit: `BiliMusic/Cache/DownloadManager.swift:67` downloads whole tracks and `BiliMusic/Cache/CacheStore.swift:58` stores them under `Documents/audio/` with no maximum size.
- Scaling path: Add a user-visible quota, LRU eviction, and free-space checks before moving downloads into `BiliMusic/Cache/CacheStore.audioDir`.

**Search result cache has no size or TTL cap:**
- Current capacity: `BiliMusic/Features/Search/SearchStore.swift:23` grows per `SearchStore` lifetime.
- Limit: Many distinct queries and modes can retain result arrays in memory until the store is released.
- Scaling path: Add an LRU cap to `resultCache` in `BiliMusic/Features/Search/SearchStore.swift`.

**Favorite ID sync scales with folder count:**
- Current capacity: `BiliMusic/Features/Favorites/FavoriteManager.swift:97` starts one task per non-empty folder.
- Limit: Accounts with many folders can trigger large bursts against `BiliMusic/API/BiliClient.swift:502`.
- Scaling path: Batch or limit concurrent folder ID fetches and cache per-folder timestamps.

**Existing bounded stores have fixed limits:**
- Current capacity: Playback history keeps 300 entries in `BiliMusic/Player/PlaybackHistoryStore.swift:39`; recent-home keeps 400 entries in `BiliMusic/Features/Home/RecentHomeFeedStore.swift:16`; image memory cache keeps 240 images or 48 MB in `BiliMusic/Design/CachedAsyncImage.swift:11`.
- Limit: These limits are code constants without settings or telemetry.
- Scaling path: Keep these constants centralized and log eviction pressure before increasing them.

## Dependencies at Risk

**Bilibili private web APIs:**
- Risk: Search, playback streams, QR login, favorites, home feed, playlists, and WBI signing depend on undocumented endpoint shapes.
- Impact: API response changes can break `BiliMusic/API/BiliClient.swift`, `BiliMusic/API/WBISigner.swift`, `BiliMusic/Features/Favorites/FavoriteManager.swift`, and `BiliMusic/Player/RecommendationEngine.swift`.
- Migration plan: Add fixture-based decoding tests for each endpoint model and isolate endpoint-specific parsing behind smaller clients.

**LRCLIB public API:**
- Risk: Lyrics lookup uses `URLSession.shared`, no explicit timeout, no HTTP status handling, and optional decode fallback.
- Impact: Lyrics can disappear silently or post-playback enrichment can spend the default session timeout.
- Migration plan: Give `BiliMusic/API/LyricsClient.swift` its own `URLSessionConfiguration`, check HTTP status, and log no-match versus transport failure separately.

**iOS 26-only UI surface:**
- Risk: Project deployment is iOS 26.0 and the root view uses iOS 26 tab accessory APIs.
- Impact: `project.yml` and `BiliMusic/Features/RootView.swift:104` make older iOS support a structural change rather than a setting tweak.
- Migration plan: Keep the minimum OS explicit in `project.yml`; add availability-gated alternatives only if product scope includes older iOS.

## Missing Critical Features

**Cache quota and eviction:**
- Problem: Downloaded audio accumulates without quota, eviction, free-space checks, or orphan cleanup.
- Blocks: Reliable long-term use of automatic caching from `BiliMusic/Player/PlayerEngine.swift:684` and manual caching from `BiliMusic/Features/Player/NowPlayingView.swift:439`.

**Authentication lifecycle management:**
- Problem: Stored cookies are not actively validated, expired auth is not cleared, and auth errors are not normalized across all API paths.
- Blocks: Predictable login state in `BiliMusic/Features/Settings/SettingsView.swift`, favorites in `BiliMusic/Features/Favorites/FavoriteManager.swift`, and personalized recommendations in `BiliMusic/Player/RecommendationEngine.swift`.

**Resumable or background-safe downloads:**
- Problem: Downloads use `URLSession.shared.download(for:delegate:)` without resume data, a background configuration, or retry policy.
- Blocks: Robust caching for large tracks or unstable connections from `BiliMusic/Cache/DownloadManager.swift`.

**Network abstraction for tests:**
- Problem: `BiliMusic/API/BiliClient.swift`, `BiliMusic/API/LyricsClient.swift`, and `BiliMusic/API/WBISigner.swift` call `URLSession` directly.
- Blocks: Deterministic tests for API errors, status codes, malformed responses, cookie expiry, rate limiting, and offline behavior.

## Test Coverage Gaps

**API and authentication paths:**
- What's not tested: `BiliMusic/API/BiliClient.swift`, `BiliMusic/API/WBISigner.swift`, `BiliMusic/API/LyricsClient.swift`, and `BiliMusic/Auth/CookieStore.swift`.
- Files: `BiliMusicTests/SearchModelsTests.swift`, `BiliMusicUITests/PlayerChromeUITests.swift`
- Risk: Endpoint schema changes, WBI signing drift, Keychain failures, and auth expiry regressions can ship unnoticed.
- Priority: High

**Playback, stream resolution, and downloads:**
- What's not tested: Queue advancement, MV fallback, stream URL expiry, preload deduping, auto-cache, and download failure behavior.
- Files: `BiliMusic/Player/PlayerEngine.swift`, `BiliMusic/Player/StreamResolver.swift`, `BiliMusic/Cache/DownloadManager.swift`
- Risk: Playback regressions can affect the app's primary workflow.
- Priority: High

**Persistence and cache repair:**
- What's not tested: Corrupt JSON, missing files, orphaned files, load-while-mutating merges, delayed saves, and scene-phase flushes.
- Files: `BiliMusic/Cache/CacheStore.swift`, `BiliMusic/Player/PlaybackHistoryStore.swift`, `BiliMusic/Features/Home/RecentHomeFeedStore.swift`, `BiliMusic/Features/RootView.swift`
- Risk: Data loss or stale UI can appear only after app restarts or backgrounding.
- Priority: High

**Recommendation quality and request fan-out:**
- What's not tested: Favorite seed selection, cache keys, scoring, dedupe, exclusion rules, and fallback search behavior.
- Files: `BiliMusic/Player/RecommendationEngine.swift`, `BiliMusic/Features/Favorites/FavoriteManager.swift`, `BiliMusic/Features/Home/HomeView.swift`
- Risk: Recommendation changes can produce duplicates, non-music content, slow refreshes, or empty home results.
- Priority: Medium

**UI tests cover fixture chrome but not real data flows:**
- What's not tested: Real search requests, login, favorites, offline cache playback, download errors, and background audio transitions.
- Files: `BiliMusicUITests/PlayerChromeUITests.swift`, `BiliMusic/Support/UITestFixtures.swift`
- Risk: UI can pass fixture tests while network, auth, and persistence flows fail.
- Priority: Medium

---

*Concerns audit: 2026-06-26*
