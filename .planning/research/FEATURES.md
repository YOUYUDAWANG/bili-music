# Research: Music App UX Features

**Project:** Bilibili Music  
**Domain:** Personal iPhone SwiftUI music app using Bilibili content  
**Researched:** 2026-06-26  
**Overall confidence:** MEDIUM. External claims are grounded in current Apple HIG, Apple Developer, Apple Support, and SwiftUI docs; codebase fit is grounded in `.planning/PROJECT.md`, `.planning/codebase/*`, and CodeGraph exploration.

## Table Stakes

These are the behaviors that make the app feel like a polished iPhone music app. Missing or weak versions of these should block roadmap phases before adding more discovery features.

| Feature | Recommendation for This Codebase | Why Expected | Complexity | Notes |
|---------|----------------------------------|--------------|------------|-------|
| Fast first playback | Treat the first tap on a track as the critical path: update current track UI immediately, check `CacheStore` first, resolve the audio stream, call AVPlayer playback, then run lyrics, recommendations, artwork prefetch, MV preparation, history writes, queue prefetch, and auto-cache after sound starts. | Apple HIG Loading/Launching guidance favors showing useful content quickly; this app's stated core value is making music start quickly and reliably. | High | Add instrumentation around tap-to-audible. Target cached playback under 1s and normal Wi-Fi network playback under 3s as product budgets, not hard guarantees. |
| Native search focus | Opening Search or tapping the search field must be instant: keyboard/focus and local suggestions appear before any Bilibili network call. Search should not freeze while WBI prewarm, history decode, cache projection, or recommendation work runs. | Search is a primary content-finding pattern in Apple HIG and WWDC26 search guidance. | Medium | Use `.searchable`/focus state with cheap local state. No API request on focus alone. |
| Search history and suggestions | Show recent searches and local suggestions while the query is empty or focused. Selecting a suggestion should fill the query and submit predictably. Provide clear-all and per-item delete later if history grows. | Apple HIG recommends helpful shortcuts near search; SwiftUI provides `searchSuggestions` and `searchCompletion` for selectable suggestions. | Medium | Suggestions should come from recent searches, recent playback, favorites, and cached tracks before remote suggestions. Keep history local for privacy. |
| Music-only results by default | Search, Home, related recommendations, radio, and collection entry points should default to music-only content. MV results are allowed, but should remain in a clearly labeled MV section or mode. | A music app is expected to return songs, albums, music videos, playlists, and relevant recommendations, not generic video search. | Medium | Continue using `musicOnly=true`, `tids=3`, `MusicFilter`, duration/title heuristics, and sectioning. Never mix stale results from an older query into the current results. |
| Search result playback | Tapping a search row should start playback immediately without requiring a detail page. The player/mini-player should reflect the selected track while the stream resolves. | Music apps optimize for play intent; search is a direct path to listening. | Medium | Show preparing state for the selected row only. Preload nearby results after the current track starts. |
| Persistent mini-player | A compact player should remain available above tabs whenever a track exists, with artwork, title, play/pause, and next where space permits. Tap or drag opens the full player. | Apple Music uses a MiniPlayer-to-Now-Playing model; Apple Support docs describe tapping MiniPlayer to open Now Playing. | Medium | Keep mini-player stable and non-jumpy. Do not hide it during search or navigation unless playback is fully stopped. |
| Full now-playing surface | Full player should prioritize artwork/MV, title/artist, progress, transport controls, lyrics, queue, favorite, download, and mode switch. Space should be dense and balanced, closer to Apple Music than YouTube Music. | Music apps are control surfaces people revisit constantly; layout waste and gesture conflict are felt immediately. | High | Reduce bottom whitespace. Use stable dimensions for artwork/control stacks. Respect Reduce Motion. |
| Queue / Playing Next | The player must expose the current queue, upcoming songs, current item, remove, jump, and eventually reorder. Manual queue state must be separate from radio/autoplay. | Apple Music's queue shows upcoming songs, lets users reorder/remove, and includes AutoPlay separately. | Medium | Keep the current left player page as queue/current playlist. Add "Play Next" and "Play Later/Add to Queue" actions when feasible. |
| Recommendations / AutoPlay surface | Recommendations belong in an explicit related/AutoPlay/radio surface, not as a hidden mutation of the manual queue. Tapping a recommendation should not refresh or scramble the list immediately. | Apple Music separates queue from AutoPlay-like similar songs. | Medium | Keep the right player page for recommendations. Mark recommendations stale and refresh after track change or explicit refresh, not on every tap. |
| Lyrics affordance when absent | If no synced lyrics are available, the lyrics control should be disabled or secondary and should not open a misleading lyric sheet. Never show Bilibili auto subtitles as fallback lyrics. | Apple Music exposes lyrics when available and notes time-synced lyrics are not available for every song. | Low | Clear stale lyrics on track change. States: loading, available, unavailable. Unavailable should be calm, not an error. |
| MV/music switch | Expose Music/MV as an explicit segmented or pill control only when a video stream is available or being checked. Audio must start first; MV preparation must not block first playback. | Apple Music treats music videos as music content, while this app has Bilibili-specific audio/MV duality. | High | Keep only one AV playback path active. If "prefer MV on Wi-Fi" remains, switch only after audio is already playing and preserve time position. |
| Favorites and cache interaction | Favorite and cache are independent states: heart means saved to Bilibili favorite folder; download means offline cache. Quick tap should use the default/last favorite folder; long press or menu chooses a folder. | Apple Music separates favorite, library, and download/offline concepts; favorites can influence recommendations. | High | Auth failures must show "login expired / re-login" instead of generic API failure. Download progress and failure reason must be visible. |
| System playback continuity | Lock screen, Control Center, route changes, interruptions, and remote controls must stay correct. | Apple Developer MediaPlayer docs define Now Playing info and remote command center as the system integration path. | Medium | Existing `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` wiring should be protected by regression tests. |

## Differentiators Worth Keeping

These are valuable because they make Bilibili Music more than a thin Apple Music clone. Keep them, but do not let them block fast first playback.

| Feature | Value Proposition | Complexity | Recommendation |
|---------|-------------------|------------|----------------|
| Bilibili music extraction | Turns Bilibili videos, MVs, covers, and collections into a music-first listening library. | High | Keep music filtering centralized in `MusicFilter` and API clients. Treat non-music suppression as a quality feature, not a nice-to-have. |
| Music/MV dual mode | Bilibili content often has meaningful video; quick audio-first listening plus optional MV is a strong differentiator. | High | Preserve, but make it explicit and defer MV stream checks until after audio starts. |
| Favorite folders as playlists | Reuses the user's Bilibili organization without building a separate playlist backend. | Medium | Keep default favorite and folder-picker flows. Add clear auth-expired handling before expanding features. |
| Offline cache library | Personal, cache-first playback is more useful than a generic history page. | High | Keep the Library as cached music, with quota, delete, failure, and offline verification work in later phases. |
| Queue + related pages in the player | Left queue / right recommendations maps well to repeated listening and keeps discovery close to playback. | Medium | Keep the structure; stabilize refresh rules and gesture conflicts. |
| LRCLIB lyrics with no subtitle fallback | Avoids bad Bilibili auto-caption lyric mismatches while still supporting real synced lyrics. | Medium | Keep strict matching and unavailable state. Add diagnostics only for developer debugging. |
| Bilibili collection recognition | Starting a song from an UP collection should preserve that collection as the queue context. | Medium | Keep as a roadmap item after playback/search stabilization. It improves continuity without adding a backend. |

## Anti-Features / Defer

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Full Bilibili client features | Comments, danmaku, feeds, profiles, uploads, live, and social surfaces dilute the music product and add API fragility. | Keep app scope to search, playback, favorites, collections, cache, lyrics, queue, and recommendations. |
| YouTube Music-style video-first discovery | The stated direction is closer to Apple Music; video-heavy feeds make first playback slower and mix non-music content. | Use dense music lists and optional MV affordances. |
| Auto-switching to MV before audio starts | Violates the core value: sound first. It also risks double playback and layout churn. | Start audio, prepare MV in the background, then allow explicit switch. |
| Generic Bilibili search by default | Produces noisy results and undermines trust in the app as a music tool. | Default to music-only. Offer "More Bilibili results" only as a deliberate escape hatch if needed. |
| Bilibili subtitles as lyric fallback | Auto subtitles are often not lyrics and can show wrong content. | Use LRCLIB-only synced lyrics; show unavailable otherwise. |
| Hidden queue mutation by recommendations | Users lose control when related tracks silently replace or reorder manual queues. | Keep manual queue and radio/AutoPlay separate, with visible mode state. |
| Social playlists / profile sharing | Out of scope for a personal sideload app and adds data model, privacy, and backend complexity. | Reuse Bilibili folders and local queue/cache state. |
| Automatic downloads without quota | Can fill device storage and make playback feel unreliable later. | Add explicit download, progress, errors, quota, and cleanup before automatic caching. |
| Heavy onboarding or marketing screens | The app should open into usable music, not a landing page. | Put setup/login in Settings and only prompt when a gated action needs auth. |

## Interaction Recommendations

### First Playback

1. On tap, set the selected track as current immediately and render preparing/mini-player state.
2. Resolve in this order: cached file, already prepared stream, fresh audio stream.
3. Start AVPlayer before lyrics, recommendations, MV stream checks, high-res artwork, queue prefetch, history persistence, or auto-cache.
4. Keep `playbackGeneration` guards around every enrichment task so rapid track changes cannot update stale UI.
5. Use AVPlayer buffering settings deliberately. `automaticallyWaitsToMinimizeStalling` and `preferredForwardBufferDuration` are playback-start tradeoff controls; choose values based on measured tap-to-audible and stall behavior, not defaults by accident.

### Search

1. Search focus should be local and synchronous-feeling: focus, keyboard, recent searches, and suggestions first; network later.
2. Empty search state should show: recent searches, cached/favorite suggestions, and maybe "recently played"; it should not show a blank list.
3. Query submission should have a stable search identity. If query A is in flight and query B starts, query A must not update results.
4. "More results" and pagination must keep the same music-only filtering rules as the first page.
5. Keep sections simple: Best Match, Songs, MV. Avoid many weak categories until result quality is solved.

### Player Transition and Layout

1. Mini-player tap opens full Now Playing; drag-up can supplement that, but tap must remain the reliable path.
2. Swipe-down dismissal should only activate from player chrome/non-list areas. Queue and recommendation lists need their own scroll gestures.
3. Artwork/MV, progress, and controls should use fixed responsive dimensions so lyrics/download/favorite state changes do not reflow the whole player.
4. Keep the full player dense: no large bottom void, no decorative cards around the main player, no oversized marketing-style headers.
5. Haptics should confirm user actions, not background state changes.

### Queue and Recommendations

1. Treat the left player page as "Queue / Current Playlist" and the right page as "Related / AutoPlay".
2. Manual queue actions: jump to item, remove, play next, play later/add to queue; reorder can come after stabilization.
3. Radio mode should be visually distinct from a normal playlist queue.
4. Recommendations can be marked stale after track change, but should refresh on explicit action or after playback is stable, not during the first-play path.
5. Tapping a related track should start that track and preserve the recommendation context long enough for the user to continue browsing.

### Lyrics

1. Clear lyrics immediately on track change and show loading only while lookup is active.
2. If no lyrics are found, set a durable unavailable state. Do not leave the lyrics button looking active.
3. If the user taps an unavailable lyrics affordance, show a short unavailable state, not a modal error.
4. Never display Bilibili subtitles in the lyrics UI unless a future phase explicitly creates a separate "subtitles" feature.

### MV / Music

1. Default to Music mode for fastest listening.
2. Show MV as disabled/loading/available based on stream state.
3. Never run simultaneous audio and video playback for the same track.
4. If switching to MV, preserve current time and playback intent.
5. If MV fails, fall back to Music without disrupting the queue.

### Cache and Favorites

1. Use separate icons and state machines: favorite, cached, downloading, download failed, login required.
2. Favorite quick action should use last/default folder; long press or menu chooses another folder.
3. Cache actions should not imply favorite, and favorite actions should not imply cache.
4. Offline cache library should verify files exist before showing playable state.
5. Auth-expired errors should invalidate favorite write state and route the user to re-login.

## Implications for Requirements

Add or sharpen the milestone requirements as follows:

| Requirement Area | Roadmap Implication | Suggested Acceptance Check |
|------------------|---------------------|----------------------------|
| Stable playback | First-play critical path must exclude lyrics, recommendations, MV, artwork prewarm, auto-cache, and heavy history writes. | Tap-to-audible measured for cached and uncached tracks; enrichment tasks begin only after playback starts. |
| Search UX | First focus cannot block on network or heavy local work; empty state must show recent/suggested music. | Tap Search and search field opens keyboard/suggestions immediately; no Bilibili request until query submit/type threshold. |
| Search correctness | Search results must be query-scoped and music-only. | Rapidly type A then B; no A results appear under B. Pagination preserves music-only filter. |
| Result quality | Music-only filtering applies across Search, Home, Related, Radio, favorites/collections, and cache suggestions. | Non-music videos are excluded or pushed behind explicit MV/escape-hatch surfaces. |
| Player layout | Now Playing should be dense and stable, with no excessive bottom void. | Snapshot/UI test on small and large iPhones verifies no overlap, no empty control gap, and stable controls while lyrics/MV/cache states change. |
| Gesture polish | Mini-to-full transition and dismissal must not fight list scrolling. | Swipe-down over queue/recommendation list scrolls the list; swipe-down over player chrome dismisses. |
| Queue/recommendations | Manual queue and radio/autoplay are separate models. | Enabling radio/related playback does not silently overwrite a manually assembled queue. |
| Lyrics unavailable | No-lyrics state is a first-class state, not an error. | Track with no LRCLIB match shows inactive/unavailable lyrics affordance and never shows stale previous lyrics. |
| MV/music | MV is optional and explicit; music playback wins. | Audio starts even if MV stream is slow/unavailable; switching to MV preserves time and does not double-play. |
| Cache/favorites | Favorite and cache are independent, visible, and recoverable. | Favorite without cache, cache without favorite, download failure, and auth-expired favorite write each have distinct UI states. |

Recommended phase ordering:

1. **Playback critical path and player state cleanup** - required before MV, recommendations, cache, and lyrics polish can feel reliable.
2. **Search focus and result correctness** - fixes the user's reported bad search UX and improves every discovery path.
3. **Player layout and gesture pass** - brings the app closer to Apple Music and removes daily-use friction.
4. **Queue/recommendation model clarification** - separates manual listening from radio/autoplay.
5. **Cache/favorites reliability** - adds quota, offline checks, auth lifecycle, and folder selection polish.

Testing implications:

- Add unit tests for `SearchStore` query identity, pagination, music-only filtering, and history/suggestion behavior.
- Add unit tests for `QueueController` plus radio/manual queue separation.
- Add focused tests or instrumentation around `PlayerEngine` start path so post-playback enrichment cannot regress first playback.
- Add UI tests for mini-player expansion, full-player dismissal, unavailable lyrics, and cache/favorite state display.

## Sources

| Source | URL | Used For | Confidence |
|--------|-----|----------|------------|
| Apple HIG: Search fields | https://developer.apple.com/design/human-interface-guidelines/search-fields | Search field purpose and expected use for content collections. | MEDIUM |
| Apple HIG: Searching | https://developer.apple.com/design/human-interface-guidelines/searching | Search as an in-app content-finding pattern. | MEDIUM |
| Apple WWDC26: Design intuitive search experiences | https://developer.apple.com/videos/play/wwdc2026/292/ | Current Apple guidance that search is a key navigation/content discovery model. | MEDIUM |
| SwiftUI: Suggesting search terms / `searchSuggestions` / `searchCompletion` | https://developer.apple.com/documentation/swiftui/suggesting-search-terms | Search suggestions and completion behavior. | MEDIUM |
| Apple HIG: Loading | https://developer.apple.com/design/human-interface-guidelines/loading | Avoiding blank/static waits; showing useful state quickly. | MEDIUM |
| Apple HIG: Launching | https://developer.apple.com/design/human-interface-guidelines/launching | Streamlined entry into the app experience. | MEDIUM |
| Apple HIG: Playing audio | https://developer.apple.com/design/human-interface-guidelines/playing-audio | Audio experience expectations and device-context adaptation. | MEDIUM |
| Apple HIG: Gestures | https://developer.apple.com/design/human-interface-guidelines/gestures | Standard gesture expectations; custom gestures should supplement familiar actions. | MEDIUM |
| Apple HIG: Buttons | https://developer.apple.com/design/human-interface-guidelines/buttons | Buttons as immediate action controls. | MEDIUM |
| Apple Developer: AVPlayer `automaticallyWaitsToMinimizeStalling` | https://developer.apple.com/documentation/avfoundation/avplayer/automaticallywaitstominimizestalling | Playback startup/stalling tradeoff. | MEDIUM |
| Apple Developer: AVPlayerItem `preferredForwardBufferDuration` | https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredforwardbufferduration | Forward buffering behavior. | MEDIUM |
| Apple Developer: `MPNowPlayingInfoCenter` | https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter | Lock screen / Now Playing metadata integration. | MEDIUM |
| Apple Developer: `MPRemoteCommandCenter` | https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter | Remote controls from system surfaces and accessories. | MEDIUM |
| Apple Support: Use the music player controls on iPhone | https://support.apple.com/guide/iphone/use-the-music-player-controls-iph676daac9b/ios | MiniPlayer, Now Playing, lyrics button, queue button, playback destination expectations. | MEDIUM |
| Apple Support: Queue up your music on iPhone | https://support.apple.com/guide/iphone/queue-up-your-music-ipha4521ef7d/ios | Playing Next, queue reorder/remove, Play Next/Play Later, AutoPlay. | MEDIUM |
| Apple Support: Search for music on iPhone | https://support.apple.com/guide/iphone/search-for-music-iph4b506b24d/ios | Music-app search as a user-facing behavior. | MEDIUM |
| Apple Support: Show song credits and lyrics on iPhone | https://support.apple.com/guide/iphone/show-song-credits-and-lyrics-iphb9bf483aa/ios | Lyrics availability and offline lyrics expectation for downloaded tracks. | MEDIUM |
| Apple Support: Add music to iPhone and listen offline | https://support.apple.com/guide/iphone/add-music-and-listen-offline-iph0cff2d191/ios | Add/download/offline separation and storage management. | MEDIUM |
| Apple Support: Mark items as favorites in Apple Music on iPhone | https://support.apple.com/guide/iphone/mark-items-as-favorites-iphbb0f5ff34/ios | Favorite behavior and optional add-to-library interaction. | MEDIUM |
| Apple Support: Tell Apple Music what you enjoy on iPhone | https://support.apple.com/guide/iphone/tell-apple-music-what-you-enjoy-iph744ea4009/ios | Favorite/Suggest Less as recommendation feedback. | MEDIUM |
| Apple Support: Get personalized recommendations in Music on iPhone | https://support.apple.com/guide/iphone/get-personalized-recommendations-iph2b1748696/ios | Recommendations based on user preferences/history. | MEDIUM |
| Apple Support: Find new music with Apple Music on iPhone | https://support.apple.com/guide/iphone/find-new-music-iph2c41e6189/ios | Music videos as part of music discovery. | MEDIUM |
| Local project context | `.planning/PROJECT.md`, `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/STRUCTURE.md`, `.planning/codebase/CONCERNS.md`, CodeGraph exploration of Search/Player/Cache/Favorites symbols | Codebase-specific recommendations and phase implications. | HIGH |
