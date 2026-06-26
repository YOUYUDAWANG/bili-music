# Research: Stack and Playback Performance

## Key Findings

- Keep the stack native: SwiftUI + Observation for UI, AVFoundation/AVKit for playback, MediaPlayer for Now Playing and remote controls, URLSession for API/download traffic, Keychain/UserDefaults/Documents for local state. No third-party playback framework is justified for this personal iOS app.
- First sound must stay on a narrow path: cache lookup or prepared playurl, AVPlayerItem creation, player replacement, `playImmediately(atRate:)`, Now Playing seed metadata. Artwork, lyrics, recommendations, MV probing, auto-cache, history flushing, image decoding, and favorite sync must remain post-start work.
- Apple's AVPlayer buffering APIs support the current low-latency direction: `automaticallyWaitsToMinimizeStalling = false` and `playImmediately(atRate:)` favor fast starts, while `AVPlayerItem.preferredForwardBufferDuration` trades startup/network pressure against stall protection. Use this as a measured two-phase policy, not a fixed large buffer for every stream.
- Apple's public AVURLAsset initialization options document `AVURLAssetHTTPUserAgentKey`, but not a generic custom-header option. The current `AVURLAsset(url:options: ["AVURLAssetHTTPHeaderFieldsKey": BiliClient.headers])` is a pragmatic sideload-only workaround for Bilibili Referer/User-Agent requirements, not a clean public API contract.
- The biggest codebase risk is actor isolation, not AVPlayer itself. `PlayerEngine` and `StreamResolver` are `@MainActor`; any stream resolution, task-group fan-out, JSON parsing, cache scanning, or image work that accidentally inherits the main actor can make the first tap feel stuck even when URLSession itself is asynchronous.

## Recommended Technical Direction

Use AVPlayer directly and make `PlayerEngine` a thin main-actor facade over smaller services:

1. **Playback core:** Own only AVPlayer/AVPlayerItem lifecycle, observers, stall recovery, seeking, interruption handling, route changes, and time-to-first-audio metrics.
2. **Stream resolution:** Move Bilibili `cid`/playurl preparation into a non-main actor or non-main service with bounded in-flight work, request coalescing, TTL invalidation, and one retry after 403/expired-url failure.
3. **Media session:** Keep Now Playing and `MPRemoteCommandCenter` behavior, but isolate metadata assembly and command registration from queue and stream code.
4. **Post-start enrichment:** Keep cover, lyrics, MV probing, queue prefetch, radio prefetch, and auto-cache delayed and cancellable behind playback-generation checks.

For startup latency, adopt a measured fast-start policy:

- Start local cache files immediately with `AVURLAsset(url:)`, no network headers, and no forward-buffer tuning.
- For remote Bilibili audio, set user intent first (`wantsPlayback = true`, loading state, current track), then construct the item and call `playImmediately(atRate: 1)`.
- Keep `automaticallyWaitsToMinimizeStalling = false` if the priority is first sound, but maintain the existing `timeControlStatus` and `isPlaybackLikelyToKeepUp` recovery observers.
- Revisit `preferredForwardBufferDuration = 30`. Prefer `0`/default or a small value for first start, then raise only after playback has actually begun if stall data shows it helps. A fixed 30-second buffer can compete with visible-row preloads and image/recommendation traffic.
- Add `os_signpost` or structured `Logger` timestamps for tap -> playurl resolved -> item created -> first `.playing` -> first time observer tick. Optimize from those numbers, not perceived delay alone.

For preloading:

- Keep preloading as "resolve and cache short-lived playurl", not "download or create many AVPlayerItems". This matches Bilibili URL expiry and avoids network pressure before first sound.
- Bound all preload fan-out. Visible-row preload should be low priority, delayed, cancellable, and capped lower than direct queue prefetch. Queue-next prefetch should outrank search/home row prefetch.
- Preload the next 1-2 likely tracks after the current track starts. Do not preload five unrelated search rows at the same priority as a user tap.
- Shorten or validate the current 90-minute prepared-stream TTL. If the player or API returns 403/expired behavior, invalidate that prepared stream and resolve once more before surfacing failure.

For HTTP and headers:

- Continue using `URLRequest` + `BiliClient.headers` for Bilibili API calls, image requests, and downloads. Add HTTP status checks before JSON decoding so 401/403/429/5xx do not masquerade as decode failures.
- Treat `URLSessionConfiguration.httpAdditionalHeaders` as a URLSession setting only; it does not make AVPlayer's direct asset loading carry arbitrary headers.
- Keep the undocumented `AVURLAssetHTTPHeaderFieldsKey` string behind one small wrapper if it is required for direct Bilibili streaming in this sideload app. Do not spread the string key across the codebase.
- If direct AVURLAsset header injection becomes unreliable, use a documented custom-resource-loader path with `AVAssetResourceLoaderDelegate` and URLSession-backed requests. Defer this until needed; it is a real complexity increase and can hurt first-sound delivery if rushed.

For background audio and controls:

- Preserve `UIBackgroundModes` audio and `AVAudioSession` category `.playback`. Activate the audio session when playback starts; handle interruptions and route changes explicitly in the playback core.
- Keep Now Playing metadata populated on start with title, artist, duration, elapsed time, and playback rate. Add artwork later when it arrives; do not block playback on image fetch/decode.
- Register play, pause, next, previous, and seek remote commands once. Disable or omit commands that are not valid for the current queue state instead of accepting commands that no-op.
- Do not update Now Playing every 0.5 seconds just because the UI progress timer fires. Update on start, pause/resume, seek, track change, artwork load, and meaningful rate/state changes.

For main-actor performance:

- Keep `PlayerEngine` observable state updates on the main actor, but move network resolution, task-group fan-out, JSON decode, cache repair, image downsampling, and recommendation scoring off the main actor.
- Be careful with `Task {}` created inside `@MainActor` types; use explicit non-main actors or detached work where appropriate so background work does not inherit UI isolation.
- Keep `BiliClient.decode` detached; extend the same principle to any heavy persistence and image-processing paths.
- Keep `PlayerProgressBar` isolated from the full player view. The current pattern of avoiding whole-player re-render on every 0.5-second tick is the right SwiftUI shape.

## Do / Avoid

| Do | Avoid |
|----|-------|
| Use cache-first playback and prepared playurl reuse before resolving a fresh stream. | Fetch lyrics, recommendations, MV streams, artwork, favorites, or auto-cache before first sound. |
| Use `playImmediately(atRate:)` plus stall observers for fast starts. | Rely only on AVPlayer's automatic waiting behavior when the product priority is low startup latency. |
| Tune `preferredForwardBufferDuration` from measured stall/startup data. | Assume a large fixed forward buffer always improves perceived performance. |
| Keep Bilibili media headers centralized and tested on device. | Treat undocumented AVURLAsset header keys as stable public API. |
| Use URLSession requests with explicit headers for downloads and API calls. | Assume URLSession global/header configuration applies to AVPlayer asset loading. |
| Update Now Playing immediately with text metadata, then artwork later. | Decode/fetch artwork before setting `MPNowPlayingInfoCenter.default().nowPlayingInfo`. |
| Register remote commands once and route them through playback intent. | Let command handlers trigger recommendation, lyrics, cache, or UI refresh work. |
| Use non-main actors/services for stream resolution and fan-out. | Let `Task {}` inside `@MainActor` playback types become the default background-work mechanism. |
| Add first-sound instrumentation around the playback path. | Optimize based only on subjective "feels slow" reports. |
| Invalidate expired prepared streams and retry once. | Persist playurl values or keep stale remote URLs as if they were durable track identity. |

## Implications for Roadmap

1. **Phase 1: Playback hot-path instrumentation and guardrails**
   - Add tap-to-first-audio metrics, HTTP status handling, prepared-stream invalidation, and a single centralized media-header wrapper.
   - Keep behavior changes small so regressions are easy to isolate.

2. **Phase 2: Main-actor and preload cleanup**
   - Move `StreamResolver` off the main actor or into a dedicated actor.
   - Add one bounded preload scheduler shared by search/home/queue/radio.
   - Lower preload priority below active playback and direct user taps.

3. **Phase 3: Buffering and stall policy**
   - A/B local/default/small/large `preferredForwardBufferDuration` values on real Bilibili audio.
   - Keep `automaticallyWaitsToMinimizeStalling = false` unless metrics show the stall recovery path costs more than startup wins.

4. **Phase 4: Media session hardening**
   - Split Now Playing and remote-command logic out of `PlayerEngine`.
   - Add interruption and route-change handling, command enablement by queue state, and metadata update tests.

5. **Phase 5: Optional documented resource loading**
   - Only if direct AVURLAsset header injection proves unreliable, introduce `AVAssetResourceLoaderDelegate` for Bilibili streams.
   - Treat this as a spike first; it can easily become a playback rewrite.

## Sources

- Apple Developer Documentation: `AVPlayer.automaticallyWaitsToMinimizeStalling` - https://developer.apple.com/documentation/avfoundation/avplayer/automaticallywaitstominimizestalling
- Apple Developer Documentation: `AVPlayer.playImmediately(atRate:)` - https://developer.apple.com/documentation/avfoundation/avplayer/playimmediately(atrate:)
- Apple Developer Documentation: `AVPlayer.timeControlStatus` - https://developer.apple.com/documentation/avfoundation/avplayer/timecontrolstatus
- Apple Developer Documentation: `AVPlayerItem.preferredForwardBufferDuration` - https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredforwardbufferduration
- Apple Developer Documentation: `AVPlayerItem.isPlaybackLikelyToKeepUp` - https://developer.apple.com/documentation/avfoundation/avplayeritem/isplaybacklikelytokeepup
- Apple Developer Documentation: Loading media data asynchronously - https://developer.apple.com/documentation/avfoundation/loading-media-data-asynchronously
- Apple Developer Documentation: AVURLAsset initialization options - https://developer.apple.com/documentation/avfoundation/avurlasset-initialization-options
- Apple Developer Documentation: `AVURLAssetHTTPUserAgentKey` - https://developer.apple.com/documentation/avfoundation/avurlassethttpuseragentkey
- Apple Developer Documentation: `AVAssetResourceLoaderDelegate` - https://developer.apple.com/documentation/avfoundation/avassetresourceloaderdelegate
- Apple Developer Documentation: Configuring your app for media playback - https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback
- Apple Developer Documentation Archive: Configuring Audio Settings for iOS and tvOS - https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/MediaPlaybackGuide/Contents/Resources/en.lproj/ConfiguringAudioSettings/ConfiguringAudioSettings.html
- Apple Developer Documentation: Becoming a now playable app - https://developer.apple.com/documentation/mediaplayer/becoming-a-now-playable-app
- Apple Developer Documentation: `MPNowPlayingInfoCenter` - https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter
- Apple Developer Documentation: `MPRemoteCommandCenter` - https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter
- Apple Developer Documentation: `URLSessionConfiguration.httpAdditionalHeaders` - https://developer.apple.com/documentation/foundation/urlsessionconfiguration/httpadditionalheaders
- Apple Developer Documentation: Improving app responsiveness - https://developer.apple.com/documentation/xcode/improving-app-responsiveness
- Local project context: `.planning/PROJECT.md`, `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/STACK.md`, `.planning/codebase/CONCERNS.md`
