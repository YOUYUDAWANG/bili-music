# Research: Performance Architecture

## Component Boundaries

Keep `PlayerEngine` as the `@MainActor` app-facing facade, but stop letting it own every side effect. Its job should be queue/current-track state, playback commands, and UI-observable playback state. Split first around the code that currently runs through `PlayerEngine.startCurrent` and `schedulePostPlaybackWork`.

Recommended boundaries:

| Component | Isolation | Responsibility |
|-----------|-----------|----------------|
| `PlayerEngine` | `@MainActor` | Public commands: play, pause, seek, queue changes, exposed UI state. No recommendation/search/network fan-out. |
| `PlaybackCore` | `@MainActor` | AVPlayer item creation, observer lifecycle, `playImmediately`, pause/seek, buffer-state translation. Extract from `startPlayback`. |
| `PlaybackStartupPipeline` | async service, called by `PlayerEngine` | Resolve exactly one playable source for the current track: local cache, prepared audio, remote audio, or MV stream. Returns `PreparedPlayback`. |
| `StreamResolver` | actor, not `@MainActor` | Short-lived playurl cache, in-flight task coalescing, cid/duration fill, stream TTL invalidation. Current `StreamResolver` is logically an actor already but is main-actor bound. |
| `PlaybackEnrichmentScheduler` | actor | Generation-guarded, cancellable noncritical work: cover, lyrics, MV availability, queue prefetch, radio prefetch, auto-cache. |
| `RequestGate` / `BiliRequestCoordinator` | actor | Bounded concurrency and request coalescing across Bilibili calls. Separate high-priority playback/media gate from low-priority search/recommendation/image work. |
| `SearchStore` | `@MainActor` | Search UI state machine only. Move request batching/filtering into `SearchService`. |
| `SearchService` | actor/service | Bounded search pages, tokenized results, partial failure behavior, music filtering off the main actor. |
| `RecommendationStore` | `@MainActor` facade + actor worker | Owns recommendation refresh state for Home and Now Playing. Does not clear lists on unrelated playback changes. |
| `RecommendationEngine` | mostly pure/service | Candidate building/scoring only. Network fan-out goes through `RequestGate`. |
| `ImageLoadCoordinator` | actor | Keep coalescing by URL; add target-size downsampling and avoid image decode on the main actor. |

The first split should be `PlayerEngine` critical path, not `NowPlayingView`. `NowPlayingView` is large, but the performance risk starts earlier: `startCurrent` currently mixes source resolution, AVPlayer startup, history writes, and scheduling enrichment. Stabilize that boundary before UI decomposition.

## Critical Path vs Enrichment

Critical path means the work required between a user tap and audible playback:

1. Accept play intent.
2. Set queue/current/generation.
3. Resolve playable URL:
   - cache hit: local file only;
   - stream hit: prepared playurl only;
   - miss: `pageList` only if cid/duration missing, then `audioStream`.
4. Build `AVPlayerItem`.
5. Call `playImmediately(atRate:)`.
6. Publish minimal state: current track, loading/playing, duration/quality if known.

Everything else is enrichment and must not be awaited before sound:

| Work | Current area | Recommendation |
|------|--------------|----------------|
| Playback history | `PlaybackHistoryStore.shared.record(track)` in `startCurrent` | Enqueue after `playImmediately`. Keep idempotent per generation. Flush later. |
| Cover art | `loadCover` in `schedulePostPlaybackWork` | Utility-priority enrichment. Never blocks state `.playing`. |
| Lyrics | `loadLyrics` | Delayed and cancellable; no UI error for no match. |
| MV availability/prepared video | `prepareVideoIfUseful` | Only after audio is stable or when user explicitly opens MV/fullscreen. |
| Queue/radio prefetch | `prefetchUpcomingTracks` | Bounded to 1-2 concurrent streams and cancelled on generation change. |
| Auto-cache | `DownloadManager.download` | Serial/background-style work, delayed until track has played for a while and network policy allows it. |
| Related recommendations | `NowPlayingView` / `RecommendationEngine` | Trigger when recommendation page is visible or explicitly refreshed. Mark stale; do not clear during playback startup. |
| Images in lists | `CachedAsyncImage` | Coalesced, downsampled, utility priority. Never requested from playback startup. |

Use a generation token consistently. The app already has `playbackGeneration`; preserve that concept and pass it into enrichment jobs. Any async result must check both generation and current `TrackKey` before mutating UI state.

## Data Flow Recommendations

Playback startup:

```text
User tap
  -> PlayerEngine.play(...)
  -> PlayerEngine creates PlaybackIntent + generation
  -> PlaybackStartupPipeline.prepare(intent)
      -> CacheLookup.entry(track)
      -> StreamResolver.cachedAudio(track)
      -> StreamResolver.prepareAudio(track, quality) if needed
  -> PlaybackCore.replaceAndPlay(prepared)
  -> PlayerEngine publishes .playing
  -> PlaybackEnrichmentScheduler.didStart(track, generation)
```

Stream resolver cache:

- Keep cache keyed by `TrackKey(bvid, cid)` plus fallback `TrackKey(bvid, nil)` for unresolved tracks.
- Keep in-flight coalescing: if preload is already resolving a stream, playback should await the same task rather than issue a second request.
- Move resolver mutable dictionaries off the main actor into an actor.
- On failed resolution, remove the in-flight task immediately.
- Keep playurl TTL short and memory-only. Do not persist playurl URLs.
- Add separate cache entries for audio and MV streams; do not let MV preparation consume the audio startup lane.

Bounded concurrency:

- Replace unbounded `withTaskGroup` loops in search/recommendations/favorites with a small bounded runner.
- Suggested caps:
  - audio playback resolution: 1 high-priority active startup, 2-3 preloads;
  - search pages: 3 concurrent requests max;
  - recommendations/related: 2-3 concurrent seeds max;
  - favorites folder sync: 2 concurrent folders max;
  - images: rely on `URLSessionConfiguration.httpMaximumConnectionsPerHost` and URL coalescing.
- Route all Bilibili calls through a request coordinator that can coalesce by key:
  - `pageList:bvid`
  - `audioStream:bvid:cid:quality`
  - `videoStream:bvid:cid`
  - `related:bvid`
  - `search:keyword:page:mode`
  - `favItems:folder:page`
  - `lyrics:title:artist:duration`

Search store state machine:

```swift
enum SearchState {
    case idle(historyLoaded: Bool)
    case editing(query: String)
    case searching(id: UUID, query: String, mode: SearchResultMode, cached: SearchCachedSnapshot?)
    case showing(query: String, mode: SearchResultMode, snapshot: SearchCachedSnapshot)
    case loadingMore(query: String, mode: SearchResultMode, snapshot: SearchCachedSnapshot)
    case failed(query: String, mode: SearchResultMode, message: String, partial: SearchCachedSnapshot?)
}
```

Rules:

- Every network result carries the search id/query/mode that produced it.
- Old results are ignored, never merged.
- Loading more preserves existing results on failure and shows an error affordance instead of silently disabling pagination.
- Filtering/deduping runs off the main actor and returns value arrays.
- Preload callback is delayed until after UI state is committed, and uses the low-priority preload lane.

Recommendation refresh isolation:

- `NowPlayingView` should not own recommendation task orchestration directly.
- Introduce `NowPlayingRecommendationStore` with:
  - current displayed tracks;
  - `isLoading`;
  - `isStale`;
  - `shownRecommendationKeys`;
  - explicit `refresh(reason:)`.
- On track change:
  - if recommendations page is not visible, mark stale only;
  - if visible, refresh after playback startup has completed or after a short debounce;
  - never clear the old list before the new list is ready unless the user explicitly refreshes.
- Home recommendations should use a separate store and cache key. Home refresh must not share lifecycle with Now Playing related-panel refresh.

Actor/main-actor boundaries:

- UI-observed state stays `@MainActor`: `PlayerEngine`, `SearchStore`, recommendation stores, view models.
- Mutable caches/coordinators become actors: stream resolver, request coordinator, recommendation pool cache, image load coordinator.
- Pure logic stays nonisolated and testable: queue policy, scoring, music filtering, search sectioning.
- Use `Task.detached` only for CPU-bound work that captures no UI state, such as JSON decode, scoring, image decode/downsample.
- Prefer structured tasks for child work so cancellation and priority propagate. Detached tasks require manual cancellation/priority handling.

## Build Order

1. Instrument playback startup first.
   - Add signposts or lightweight timing around tap, source resolution start/end, AVPlayer item creation, `playImmediately`, first `.playing`.
   - This creates a baseline before refactoring.
2. Extract `PlaybackCore` from `PlayerEngine.startPlayback`.
   - Keep behavior identical.
   - Tests can fake the player boundary later.
   - This is low-risk because it isolates AVPlayer observer lifecycle without changing resolver behavior.
3. Extract `PlaybackStartupPipeline`.
   - Move cache/prepared/remote resolution out of `startCurrent`.
   - Return a value like `PreparedPlayback(track:url:isLocal:quality:bandwidth:mode)`.
   - Keep `PlayerEngine` responsible only for generation checks and state publication.
4. Convert `StreamResolver` to an actor.
   - Preserve the existing coalescing and 90-minute memory TTL.
   - Add tests for duplicate awaits, expiry, fallback key behavior, and failed-task cleanup.
5. Introduce `PlaybackEnrichmentScheduler`.
   - Move cover, lyrics, MV preparation, queue prefetch, and auto-cache out of `PlayerEngine`.
   - Make each job independently cancellable and generation-guarded.
   - History write can move into this scheduler or into a small `PlaybackEventSink`.
6. Add `RequestGate` and update fan-out callers.
   - Start with `RecommendationEngine.relatedCandidates`, `artistSearchCandidates`, `fallbackSearchCandidates`, and `favoriteSeeds`.
   - Then update `SearchStore.searchBatch`.
   - Keep the playback stream path on a separate high-priority lane.
7. Refactor `SearchStore` into state machine + `SearchService`.
   - This addresses stale result mixing, first-focus churn, pagination failure, and unbounded page fan-out.
8. Isolate recommendations from player UI.
   - Add `NowPlayingRecommendationStore`.
   - Move recommendation task state out of `NowPlayingView`.
   - Keep old recommendation content visible while refreshes run.
9. Split `BiliClient` by API domain only after the performance boundaries exist.
   - Keep one shared transport/header/cookie layer.
   - Move methods into `PlaybackClient`, `SearchClient`, `RecommendationClient`, `FavoritesClient`, and `LoginClient` when tests can cover each domain.

## Test Seams

Add protocols at the new boundaries, not across every call site.

Playback:

- `PlaybackCoreProtocol`
  - `replaceAndPlay(prepared:)`
  - `pause()`
  - `seek(to:)`
  - exposes simulated state changes for tests.
- `MediaSourceResolving`
  - cache hit, prepared hit, remote miss, MV fallback, stream failure.
- `PlaybackEventRecording`
  - history record is called after startup, not before.
- Tests:
  - cached track starts without network;
  - prepared stream starts without duplicate network;
  - remote stream uses at most pageList + audioStream;
  - lyrics/recommendations/images are not awaited before `replaceAndPlay`;
  - rapid track switch cancels old enrichment and ignores old results.

Stream resolver:

- Fake `BiliClient` with controllable latency.
- Tests:
  - two concurrent prepares for same unresolved track share one task;
  - resolved cid writes both exact and fallback keys;
  - expired cache is removed;
  - failed task is removed and later retry works;
  - playback await can reuse a preload in flight.

Request gate:

- Fake clock or controllable async barriers.
- Tests:
  - max concurrent requests never exceeds cap;
  - identical request keys coalesce;
  - cancelling one waiter does not cancel a shared request still awaited by playback;
  - high-priority playback lane is not blocked behind recommendation fan-out.

Search:

- `SearchClientProtocol`.
- Tests:
  - old query result cannot mutate current query;
  - mode switch invalidates in-flight results;
  - loading more failure preserves current results and exposes retry/error state;
  - strict music filtering remains applied on every page;
  - result cache has a bounded size/TTL.

Recommendations:

- `RecommendationProviding`.
- Tests:
  - track change marks Now Playing recommendations stale without clearing visible tracks;
  - refresh while page hidden does not run network work;
  - refresh while visible coalesces repeated triggers;
  - home refresh and Now Playing related refresh do not cancel each other.

Images:

- `ImageFetching` and `ImageDecoding`.
- Tests:
  - same URL coalesces;
  - decode/downsample happens off main actor;
  - failed image does not poison cache forever unless intentionally negative-cached.

## Sources

- Swift Documentation: Concurrency, actors, structured tasks, and `MainActor`: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/
- Swift standard library concurrency docs: https://github.com/swiftlang/swift/tree/main/stdlib/public/Concurrency
- Apple Developer Documentation: SwiftUI `View.task`: https://developer.apple.com/documentation/swiftui/view/task%28name%3Apriority%3Afile%3Aline%3A_%3A%29
- Apple Developer Documentation: SwiftUI performance analysis: https://developer.apple.com/documentation/swiftui/performance-analysis
- Apple Developer Documentation: Improving app responsiveness: https://developer.apple.com/documentation/xcode/improving-app-responsiveness
- Apple Developer Documentation: `AVPlayer.automaticallyWaitsToMinimizeStalling`: https://developer.apple.com/documentation/avfoundation/avplayer/automaticallywaitstominimizestalling
- Apple Developer Documentation: `AVPlayer.playImmediately(atRate:)`: https://developer.apple.com/documentation/avfoundation/avplayer/playimmediately%28atrate%3A%29
- Apple Developer Documentation: `AVPlayerItem.preferredForwardBufferDuration`: https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredforwardbufferduration
- Apple Developer Documentation: `URLSessionConfiguration`: https://developer.apple.com/documentation/foundation/urlsessionconfiguration
- Apple Developer Documentation: `URLCache`: https://developer.apple.com/documentation/foundation/urlcache
