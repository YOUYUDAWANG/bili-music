<!-- refreshed: 2026-06-26 -->
# Architecture

**Analysis Date:** 2026-06-26

## System Overview

```text
+-------------------------------------------------------------+
|                     SwiftUI Application                      |
|            `BiliMusic/App/BiliMusicApp.swift`                |
+------------------+------------------+-----------------------+
| Root shell       | Feature views    | Player UI             |
| `BiliMusic/      | `BiliMusic/      | `BiliMusic/Features/  |
| Features/        | Features/*`      | Player/*`             |
| RootView.swift`  |                  |                       |
+--------+---------+---------+--------+-----------+-----------+
         |                   |                    |
         v                   v                    v
+-------------------------------------------------------------+
|                 Observable state and domain services          |
| `BiliMusic/Player/PlayerEngine.swift`                        |
| `BiliMusic/Player/RecommendationEngine.swift`                |
| `BiliMusic/Features/Search/SearchStore.swift`                |
+------------------+------------------+-----------------------+
         |                   |                    |
         v                   v                    v
+-------------------------------------------------------------+
| API, persistence, and platform boundaries                     |
| `BiliMusic/API/BiliClient.swift`                             |
| `BiliMusic/Cache/CacheStore.swift`                           |
| `BiliMusic/Auth/CookieStore.swift`                           |
+------------------+------------------+-----------------------+
         |                   |                    |
         v                   v                    v
+-------------------------------------------------------------+
| Bilibili HTTP APIs, LRCLIB, AVPlayer, Keychain, Documents     |
| `scripts/verify_audio.py`, `scripts/verify_search_rcmd.py`   |
+-------------------------------------------------------------+
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| App entry | Creates the single app-wide `PlayerEngine` and injects it into the SwiftUI environment. | `BiliMusic/App/BiliMusicApp.swift` |
| Root shell | Owns tab navigation, mini-player accessory, full-player presentation, startup loading, WBI prewarm, scene-phase flushes, and debug autoplay. | `BiliMusic/Features/RootView.swift` |
| Home | Builds recommendation batches and records recently shown tracks. | `BiliMusic/Features/Home/HomeView.swift`, `BiliMusic/Features/Home/RecentHomeFeedStore.swift` |
| Search | Manages search history, result cache, mode switching, paging, result sectioning, and preloading. | `BiliMusic/Features/Search/SearchView.swift`, `BiliMusic/Features/Search/SearchStore.swift`, `BiliMusic/Features/Search/SearchModels.swift` |
| Favorites | Presents Bilibili favorite folders as playlists and owns favorite CRUD state. | `BiliMusic/Features/Favorites/FavoritesView.swift`, `BiliMusic/Features/Favorites/FavoriteManager.swift` |
| Library | Presents local cached audio with search, sort, delete, clear, and offline playback. | `BiliMusic/Features/Library/LibraryView.swift` |
| Settings | Owns account login, QR login, quality preferences, cache policy, MV preference, and playback history views. | `BiliMusic/Features/Settings/SettingsView.swift` |
| Player UI | Presents full-screen now-playing, controls, lyrics, MV, queue, related recommendations, collection sheets, and player subviews. | `BiliMusic/Features/Player/NowPlayingView.swift`, `BiliMusic/Features/Player/PlayerControlViews.swift`, `BiliMusic/Features/Player/PlayerSheetViews.swift` |
| Playback engine | Owns queue, current track, AVPlayer, playback state, audio/MV switching, preloading, remote commands, now-playing info, and post-playback work. | `BiliMusic/Player/PlayerEngine.swift` |
| Stream resolver | Resolves missing cid/duration and caches short-lived playurl audio streams in memory. | `BiliMusic/Player/StreamResolver.swift` |
| Recommendation engine | Selects home, radio, and related-panel tracks from favorites, related videos, history, cache, and search fallback. | `BiliMusic/Player/RecommendationEngine.swift` |
| Queue controller | Provides pure queue index, append, and remove operations. | `BiliMusic/Player/QueueController.swift` |
| Music filter | Centralizes duration, type, title, and query heuristics for music-only filtering. | `BiliMusic/Player/MusicFilter.swift` |
| API client | Owns all Bilibili HTTP calls, required headers, Cookie injection, envelope decoding, quality options, QR login, favorites, search, related, and playlist APIs. | `BiliMusic/API/BiliClient.swift` |
| WBI signing | Signs WBI endpoints and prewarms cached mixin keys. | `BiliMusic/API/WBISigner.swift` |
| Lyrics | Matches and parses LRCLIB lyrics for the current track. | `BiliMusic/API/LyricsClient.swift` |
| Auth storage | Stores and parses the complete Bilibili Cookie in Keychain. | `BiliMusic/Auth/CookieStore.swift` |
| Cache index | Stores offline cache metadata and maps `TrackKey` to local files. | `BiliMusic/Cache/CacheStore.swift` |
| Download manager | Downloads complete tracks with progress and writes cache entries. | `BiliMusic/Cache/DownloadManager.swift` |
| Design system | Supplies semantic colors, rows, image loading, haptics, and shared UI pieces. | `BiliMusic/Design/AppTheme.swift`, `BiliMusic/Design/TrackRow.swift`, `BiliMusic/Design/CachedAsyncImage.swift`, `BiliMusic/Design/UIComponents.swift`, `BiliMusic/Design/Haptics.swift` |
| Test fixtures | Supplies deterministic fixture tracks for UI-test/debug paths. | `BiliMusic/Support/UITestFixtures.swift` |

## Pattern Overview

**Overall:** Single-target SwiftUI application with MVVM-style feature views, `@Observable` stores, and service structs/classes at the app boundary.

**Key Characteristics:**
- Use `BiliMusic/App/BiliMusicApp.swift` as the only `@main` entry point.
- Use `PlayerEngine` from the SwiftUI environment for app-wide playback state.
- Keep network access in `BiliMusic/API/BiliClient.swift`, `BiliMusic/API/WBISigner.swift`, and `BiliMusic/API/LyricsClient.swift`.
- Keep persistent local app state in singleton stores such as `CacheStore.shared`, `FavoriteManager.shared`, `PlaybackHistoryStore.shared`, and `RecentHomeFeedStore.shared`.
- Keep feature-specific transient state inside feature views or feature stores, especially `SearchStore`.
- Model tracks with value types in `BiliMusic/Player/PlayerEngine.swift`; do not introduce an ORM or database layer for current data.

## Layers

**App Shell:**
- Purpose: Application entry, environment injection, root tab layout, player overlay, startup jobs, and background flushes.
- Location: `BiliMusic/App/`, `BiliMusic/Features/RootView.swift`
- Contains: `BiliMusicApp`, `RootView`, tab selection, mini/full player presentation.
- Depends on: `BiliMusic/Player/PlayerEngine.swift`, `BiliMusic/Cache/CacheStore.swift`, `BiliMusic/Player/PlaybackHistoryStore.swift`, `BiliMusic/API/WBISigner.swift`
- Used by: The operating system through SwiftUI `App`.

**Feature UI:**
- Purpose: User-facing screens and feature-specific view state.
- Location: `BiliMusic/Features/`
- Contains: `HomeView`, `SearchView`, `FavoritesView`, `LibraryView`, `SettingsView`, `NowPlayingView`, and player subviews.
- Depends on: `PlayerEngine`, feature stores, `BiliClient`, cache/favorite stores, design components.
- Used by: `BiliMusic/Features/RootView.swift`.

**Player Domain:**
- Purpose: Playback state, AVPlayer integration, queue behavior, recommendations, stream resolution, network reachability, and history.
- Location: `BiliMusic/Player/`
- Contains: `Track`, `TrackKey`, `PlayerEngine`, `QueueController`, `RecommendationEngine`, `MusicFilter`, `StreamResolver`, `NetworkMonitor`, `PlaybackHistoryStore`.
- Depends on: `AVFoundation`, `MediaPlayer`, `Observation`, `BiliMusic/API/BiliClient.swift`, `BiliMusic/Cache/CacheStore.swift`.
- Used by: All feature screens that show or start playback.

**API Boundary:**
- Purpose: Encapsulate external HTTP protocols and response models.
- Location: `BiliMusic/API/`
- Contains: `BiliClient`, `WBISigner`, `LyricsClient`, Bilibili DTOs, API errors, quality options.
- Depends on: `Foundation`, `OSLog`, `BiliMusic/Auth/CookieStore.swift`.
- Used by: Player, search, favorites, recommendations, settings, downloads, and player sheets.

**Persistence Boundary:**
- Purpose: Persist Cookie, cache index/files, home de-duplication, playback history, search history, user preferences, and image cache.
- Location: `BiliMusic/Auth/`, `BiliMusic/Cache/`, `BiliMusic/Player/PlaybackHistoryStore.swift`, `BiliMusic/Features/Home/RecentHomeFeedStore.swift`, `BiliMusic/Design/CachedAsyncImage.swift`
- Contains: Keychain access, JSON files in Documents, audio files in Documents/audio, UserDefaults preferences, URLCache/NSCache image cache.
- Depends on: `Foundation`, `Security`, `Observation`, `OSLog`.
- Used by: App startup, background flushes, playback, library, settings, home, favorites, and search.

**Design and Support:**
- Purpose: Shared presentation primitives and deterministic UI-test data.
- Location: `BiliMusic/Design/`, `BiliMusic/Support/`
- Contains: Semantic theme, image loader, track row, haptics, small UI components, UI-test fixtures.
- Depends on: `SwiftUI`, `Foundation`, `BiliClient.headers` for image requests.
- Used by: Feature screens and player UI.

**Verification and Project Tooling:**
- Purpose: Generate/build the Xcode project and verify Bilibili API assumptions.
- Location: `project.yml`, `.github/workflows/build.yml`, `scripts/`
- Contains: XcodeGen target definitions, simulator compile workflow, Python API verification scripts.
- Depends on: XcodeGen, Xcode, Python standard library.
- Used by: Local development and CI.

## Data Flow

### Primary Playback Path

1. App launch creates one `PlayerEngine` and injects it with `.environment(engine)` (`BiliMusic/App/BiliMusicApp.swift:5`).
2. `RootView` mounts feature tabs and the mini-player accessory (`BiliMusic/Features/RootView.swift:31`, `BiliMusic/Features/RootView.swift:135`).
3. A feature view starts playback by calling `engine.play(tracks:startAt:)`, for example home rows in `BiliMusic/Features/Home/HomeView.swift:29` or search rows in `BiliMusic/Features/Search/SearchView.swift:276`.
4. `PlayerEngine.play(tracks:startAt:queueMode:)` replaces queue state, clears played keys, selects playback mode, and calls `startCurrent` (`BiliMusic/Player/PlayerEngine.swift:175`).
5. `PlayerEngine.startCurrent` checks playback mode and resolves the media source (`BiliMusic/Player/PlayerEngine.swift:452`).
6. In MV mode, `startCurrent` fills cid when needed and calls `BiliClient.videoStream` (`BiliMusic/Player/PlayerEngine.swift:469`, `BiliMusic/API/BiliClient.swift:227`).
7. In music mode, `startCurrent` uses `CacheStore.shared.entry(for:)` before network resolution (`BiliMusic/Player/PlayerEngine.swift:483`, `BiliMusic/Cache/CacheStore.swift:103`).
8. If no cache entry exists, `startCurrent` reuses a prepared stream or calls `StreamResolver.prepareAudio` (`BiliMusic/Player/PlayerEngine.swift:492`, `BiliMusic/Player/StreamResolver.swift`).
9. `StreamResolver` uses `BiliClient.audioStream` to fetch a short-lived audio URL (`BiliMusic/API/BiliClient.swift:188`).
10. `PlayerEngine.startPlayback` starts AVPlayer and `PlaybackHistoryStore.shared.record` persists play history (`BiliMusic/Player/PlayerEngine.swift:513`, `BiliMusic/Player/PlayerEngine.swift:519`).
11. Post-playback work loads cover art, lyrics, useful video streams, queue/radio prefetches, and optional auto-cache (`BiliMusic/Player/PlayerEngine.swift:663`).

### Search Path

1. `SearchView` owns UI input and delegates state to `SearchStore` (`BiliMusic/Features/Search/SearchView.swift`, `BiliMusic/Features/Search/SearchStore.swift:6`).
2. `SearchStore.submitSearch(_:preload:)` trims input, restores cache when available, records history, and launches a search task (`BiliMusic/Features/Search/SearchStore.swift:65`).
3. `SearchStore.searchBatch` queries `BiliClient.search(keyword:page:musicOnly:)` and filters results through `MusicFilter.isSearchResult` (`BiliMusic/Features/Search/SearchStore.swift:292`, `BiliMusic/API/BiliClient.swift:314`).
4. `SearchResultSections` groups best match, songs, and MV results for `SearchView` (`BiliMusic/Features/Search/SearchModels.swift`).
5. `SearchStore` calls the preload callback so `PlayerEngine` can prepare upcoming audio (`BiliMusic/Features/Search/SearchStore.swift:136`, `BiliMusic/Player/PlayerEngine.swift:217`).

### Recommendation and Radio Path

1. `HomeView.load()` asks `RecommendationEngine` for home recommendations and passes excluded recent keys (`BiliMusic/Features/Home/HomeView.swift:86`, `BiliMusic/Features/Home/HomeView.swift:112`).
2. `RecommendationEngine.recommendations(mode:context:limit:)` builds and scores candidate pools (`BiliMusic/Player/RecommendationEngine.swift:93`).
3. Candidate sources include favorites, related videos, playback history, cache, and search terms in the player/recommendation layer (`BiliMusic/Player/RecommendationEngine.swift`).
4. `RecentHomeFeedStore.shared.record` writes shown bvids for the home de-duplication window (`BiliMusic/Features/Home/HomeView.swift:106`, `BiliMusic/Features/Home/RecentHomeFeedStore.swift`).
5. Radio advancement calls `RecommendationEngine.nextRadioTrack` after the fast related-video path (`BiliMusic/Player/PlayerEngine.swift:588`).

### Cache and Download Path

1. Startup calls `CacheStore.shared.loadIfNeeded()` from `RootView.task` (`BiliMusic/Features/RootView.swift:78`, `BiliMusic/Cache/CacheStore.swift:73`).
2. Playback checks the cache first through `CacheStore.shared.entry(for:)` (`BiliMusic/Player/PlayerEngine.swift:483`, `BiliMusic/Cache/CacheStore.swift:103`).
3. Download actions call `DownloadManager.shared.download(track:)` (`BiliMusic/Cache/DownloadManager.swift:35`).
4. `DownloadManager` fills missing cid, calls `BiliClient.audioStream`, downloads with `URLSession.download(for:delegate:)`, moves the file to `CacheStore.audioDir`, and adds a `CachedEntry` (`BiliMusic/Cache/DownloadManager.swift:43`, `BiliMusic/Cache/DownloadManager.swift:57`, `BiliMusic/Cache/DownloadManager.swift:67`, `BiliMusic/Cache/DownloadManager.swift:75`).
5. Background scene phase flushes cache and playback history (`BiliMusic/Features/RootView.swift:69`).

### Authentication and Favorites Path

1. `SettingsView` presents QR login and account settings (`BiliMusic/Features/Settings/SettingsView.swift:5`).
2. QR login calls `BiliClient.qrCodeGenerate()` and `BiliClient.qrCodePoll(key:)` (`BiliMusic/API/BiliClient.swift:404`, `BiliMusic/API/BiliClient.swift:416`).
3. A successful login writes the complete Cookie through `CookieStore.cookie` (`BiliMusic/Auth/CookieStore.swift`).
4. `BiliClient` attaches Cookie automatically to all requests when present (`BiliMusic/API/BiliClient.swift:58`).
5. `FavoriteManager` calls favorite folder, item, and mutation APIs and keeps a cached set of favorite bvids (`BiliMusic/Features/Favorites/FavoriteManager.swift`).

**State Management:**
- App-wide playback state lives in one environment-injected `PlayerEngine` (`BiliMusic/App/BiliMusicApp.swift:6`).
- Long-lived local stores are singleton or static boundaries: `CacheStore.shared`, `DownloadManager.shared`, `FavoriteManager.shared`, `PlaybackHistoryStore.shared`, `RecentHomeFeedStore.shared`, `NetworkMonitor.shared`, and `CookieStore`.
- Feature-local state stays in SwiftUI `@State` or feature stores such as `SearchStore`.
- Preferences use `UserDefaults` keys such as `playbackQuality`, `downloadQuality`, `autoCache`, `preferMVOnWiFi`, `recommendFolderId`, `searchHistory`, and `lastFavoriteFolderId`.

## Key Abstractions

**Track and TrackKey:**
- Purpose: Identify playable Bilibili media and avoid bvid-only collisions across multi-part videos.
- Examples: `BiliMusic/Player/PlayerEngine.swift:11`, `BiliMusic/Player/PlayerEngine.swift:28`
- Pattern: Value types shared across views, player, cache, favorites, search, and recommendations.

**PlayerEngine:**
- Purpose: Single source of truth for queue, current track, playback state, AVPlayer, lyrics, quality, MV/music mode, remote commands, and post-playback work.
- Examples: `BiliMusic/Player/PlayerEngine.swift:72`
- Pattern: `@Observable @MainActor` object injected through SwiftUI environment.

**BiliClient:**
- Purpose: HTTP gateway and DTO namespace for Bilibili APIs.
- Examples: `BiliMusic/API/BiliClient.swift:7`
- Pattern: Lightweight struct with shared headers/session and nested response models.

**Observable Stores:**
- Purpose: Encapsulate state that several views need to observe.
- Examples: `BiliMusic/Features/Search/SearchStore.swift:6`, `BiliMusic/Cache/CacheStore.swift:32`, `BiliMusic/Cache/DownloadManager.swift:10`, `BiliMusic/Features/Favorites/FavoriteManager.swift:7`
- Pattern: `@Observable @MainActor` classes for UI-bound state; detached tasks for encode/decode work.

**Pure Controllers and Filters:**
- Purpose: Keep deterministic logic out of views and mutable stores.
- Examples: `BiliMusic/Player/QueueController.swift`, `BiliMusic/Player/MusicFilter.swift`, `BiliMusic/Features/Search/SearchModels.swift`
- Pattern: Static functions, value types, and tests where practical.

## Entry Points

**Application:**
- Location: `BiliMusic/App/BiliMusicApp.swift:4`
- Triggers: iOS launches the SwiftUI app.
- Responsibilities: Create `PlayerEngine`, mount `RootView`, inject engine.

**Root View:**
- Location: `BiliMusic/Features/RootView.swift:31`
- Triggers: `WindowGroup` content.
- Responsibilities: Render tabs, mini player, full player, settings sheet, startup tasks, scene phase handling.

**Playback Start:**
- Location: `BiliMusic/Player/PlayerEngine.swift:175`
- Triggers: Home, search, favorites, library, history, queue, and debug autoplay.
- Responsibilities: Replace queue, set playback mode, resolve current track, start AVPlayer.

**Search Submission:**
- Location: `BiliMusic/Features/Search/SearchStore.swift:65`
- Triggers: Search UI submit, retry, broaden, or mode switch.
- Responsibilities: Manage active search identity, history, cache restore, async search, paging, preloading.

**Recommendation Loading:**
- Location: `BiliMusic/Features/Home/HomeView.swift:86`, `BiliMusic/Player/RecommendationEngine.swift:93`
- Triggers: Home task, refresh, radio advancement, related panel.
- Responsibilities: Gather candidates, score/filter, sample recommendations, avoid recent duplicates.

**Download:**
- Location: `BiliMusic/Cache/DownloadManager.swift:35`
- Triggers: Now-playing/library/download actions and optional auto-cache after playback.
- Responsibilities: Resolve stream, download with progress, move file, write cache index.

**CI Build:**
- Location: `.github/workflows/build.yml`
- Triggers: Pull requests and pushes to `main` that touch app, project, or workflow files.
- Responsibilities: Install XcodeGen, generate `BiliMusic.xcodeproj`, build simulator target without signing.

## Architectural Constraints

- **Threading:** UI-observed state is main-actor bound in `PlayerEngine`, `SearchStore`, `CacheStore`, `DownloadManager`, `FavoriteManager`, `NetworkMonitor`, and `RecentHomeFeedStore`; JSON decode/encode and network work use `Task`, `Task.detached`, `URLSession`, or delegate callbacks.
- **Global state:** Use only established globals for app-wide concerns: `PlayerEngine` environment, `CacheStore.shared`, `DownloadManager.shared`, `FavoriteManager.shared`, `PlaybackHistoryStore.shared`, `RecentHomeFeedStore.shared`, `NetworkMonitor.shared`, `CookieStore`, `ImageMemoryCache.shared`, and `ImageLoadCoordinator.shared`.
- **Circular imports:** Not detected in the Swift source; files rely on same-target symbol visibility and framework imports rather than module-to-module imports.
- **Network boundary:** All Bilibili app calls go through `BiliMusic/API/BiliClient.swift`; scripts in `scripts/` are verification utilities, not production paths.
- **Headers:** Any Bilibili media or image request must carry `BiliClient.headers` from `BiliMusic/API/BiliClient.swift:19`.
- **Stream URLs:** Do not persist media stream URLs; `PlayerEngine` and `StreamResolver` treat playurl output as short-lived (`BiliMusic/Player/PlayerEngine.swift:492`, `BiliMusic/Player/StreamResolver.swift`).
- **Track identity:** Cache, queue de-duplication, and favorite/history matching must account for `TrackKey` and cid where available (`BiliMusic/Player/PlayerEngine.swift:11`, `BiliMusic/Cache/CacheStore.swift:103`).
- **Generated project:** `project.yml` is the source for Xcode target definitions; regenerate `BiliMusic.xcodeproj` after target or source layout changes.
- **Secrets:** Environment files and credentials are not part of the scanned source; auth is persisted through Keychain in `BiliMusic/Auth/CookieStore.swift`.

## Anti-Patterns

### Network Calls From Feature Views

**What happens:** Feature views can create `BiliClient` for feature-specific loads, but request construction, headers, envelope parsing, signing, and DTOs belong in `BiliMusic/API/BiliClient.swift`.
**Why it's wrong:** Duplicating URL construction or headers outside the API layer risks CDN 403s, inconsistent Cookie behavior, and repeated response models.
**Do this instead:** Add endpoint methods to `BiliMusic/API/BiliClient.swift` and call them from stores/views such as `BiliMusic/Features/Search/SearchStore.swift` or `BiliMusic/Features/Favorites/FavoriteManager.swift`.

### Persisting Playurl Results

**What happens:** Audio and video stream URLs are temporary results of `BiliClient.audioStream` and `BiliClient.videoStream`.
**Why it's wrong:** Persisted stream URLs expire and break offline or later playback.
**Do this instead:** Persist bvid/cid and cache files through `BiliMusic/Cache/CacheStore.swift`; resolve fresh URLs through `BiliMusic/Player/StreamResolver.swift` or `BiliMusic/API/BiliClient.swift` when playing.

### BVID-Only Cache Matching

**What happens:** Bilibili videos can have multiple cid pages under one bvid.
**Why it's wrong:** A bvid-only cache hit can play the wrong part of a multi-part video.
**Do this instead:** Use `TrackKey` and `CacheStore.entry(for:)`; only use `entry(bvid:)` compatibility behavior when the cache store proves the bvid is unambiguous (`BiliMusic/Cache/CacheStore.swift:103`, `BiliMusic/Cache/CacheStore.swift:120`).

### Feature Logic Inside Reusable UI Rows

**What happens:** Reusable row/components can display tracks and progress, but playback, recommendation, cache, and favorite mutations belong to their feature/store owner.
**Why it's wrong:** Putting side effects into `BiliMusic/Design/TrackRow.swift` or `BiliMusic/Design/UIComponents.swift` makes list reuse unpredictable.
**Do this instead:** Keep row views presentational and trigger actions from feature views such as `BiliMusic/Features/Home/HomeView.swift`, `BiliMusic/Features/Search/SearchView.swift`, or `BiliMusic/Features/Library/LibraryView.swift`.

## Error Handling

**Strategy:** Throw typed/localized errors at service boundaries, catch at feature/player boundaries, and expose user-facing error strings through observable state.

**Patterns:**
- `BiliClient.APIError` carries Bilibili `code` and `message` (`BiliMusic/API/BiliClient.swift:33`).
- `BiliClient.get` and `postVoid` reject non-zero API responses and invalid URLs (`BiliMusic/API/BiliClient.swift:51`, `BiliMusic/API/BiliClient.swift:73`).
- `PlayerEngine.startCurrent` falls back from MV to music mode before surfacing failure (`BiliMusic/Player/PlayerEngine.swift:522`).
- `DownloadManager.download(track:)` records `lastError` and clears progress in `defer` (`BiliMusic/Cache/DownloadManager.swift:35`).
- Feature stores/views expose `errorMessage` for UI rendering, for example `SearchStore` and `HomeView` (`BiliMusic/Features/Search/SearchStore.swift:11`, `BiliMusic/Features/Home/HomeView.swift:10`).

## Cross-Cutting Concerns

**Logging:** Use `OSLog.Logger` categories in network, player, stream, cache, download, recommendation, history, and lyrics files (`BiliMusic/API/BiliClient.swift`, `BiliMusic/Player/PlayerEngine.swift`, `BiliMusic/Cache/CacheStore.swift`, `BiliMusic/Player/RecommendationEngine.swift`).

**Validation:** API responses validate envelope codes in `BiliClient`; search/music validity runs through `MusicFilter` and `SearchResultSections`; cache validity checks that indexed audio files still exist during load (`BiliMusic/API/BiliClient.swift:65`, `BiliMusic/Player/MusicFilter.swift`, `BiliMusic/Features/Search/SearchModels.swift`, `BiliMusic/Cache/CacheStore.swift:91`).

**Authentication:** `CookieStore` owns Keychain persistence and parsed Cookie values; `BiliClient` injects Cookie automatically when present (`BiliMusic/Auth/CookieStore.swift`, `BiliMusic/API/BiliClient.swift:58`).

**Persistence:** JSON files in Documents are used for cache index, playback history, and home recent feed; UserDefaults are used for lightweight preferences and search/default-folder state (`BiliMusic/Cache/CacheStore.swift`, `BiliMusic/Player/PlaybackHistoryStore.swift`, `BiliMusic/Features/Home/RecentHomeFeedStore.swift`, `BiliMusic/Features/Search/SearchStore.swift`, `BiliMusic/Features/Favorites/FavoriteManager.swift`).

**Media Integration:** `PlayerEngine` owns AVAudioSession, AVPlayer, MPNowPlayingInfoCenter, MPRemoteCommandCenter, audio/MV mode switching, and scene-phase background behavior (`BiliMusic/Player/PlayerEngine.swift`).

**UI Consistency:** Shared colors, image loading, row layout, haptics, and small controls live in `BiliMusic/Design/`; feature views should reuse those before adding local duplicates.

---

*Architecture analysis: 2026-06-26*
