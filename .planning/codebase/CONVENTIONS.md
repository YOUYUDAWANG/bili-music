# Coding Conventions

**Analysis Date:** 2026-06-26

## Naming Patterns

**Files:**
- Use one primary Swift type per file and name the file after that type: `BiliMusic/API/BiliClient.swift`, `BiliMusic/Features/Search/SearchStore.swift`, `BiliMusic/Design/TrackRow.swift`.
- SwiftUI view files end in `View.swift` when they own a screen or large surface: `BiliMusic/Features/Home/HomeView.swift`, `BiliMusic/Features/Player/NowPlayingView.swift`, `BiliMusic/Features/Settings/SettingsView.swift`.
- State and persistence files use role suffixes: `BiliMusic/Cache/CacheStore.swift`, `BiliMusic/Features/Favorites/FavoriteManager.swift`, `BiliMusic/Player/PlaybackHistoryStore.swift`, `BiliMusic/Cache/DownloadManager.swift`.
- Pure domain helper files use nouns that describe the rule set: `BiliMusic/Player/MusicFilter.swift`, `BiliMusic/Player/QueueController.swift`, `BiliMusic/API/WBISigner.swift`.
- Tests use `*Tests.swift`: `BiliMusicTests/SearchModelsTests.swift`, `BiliMusicUITests/PlayerChromeUITests.swift`.

**Functions:**
- Use lowerCamelCase and verb phrases for actions: `submitSearch(_:preload:)` in `BiliMusic/Features/Search/SearchStore.swift`, `play(tracks:startAt:queueMode:)` in `BiliMusic/Player/PlayerEngine.swift`, `audioStream(bvid:cid:preferredQuality:)` in `BiliMusic/API/BiliClient.swift`.
- Use clear predicate names for Boolean checks: `shouldShowResults(query:)` in `BiliMusic/Features/Search/SearchStore.swift`, `isSearchResult(_:query:mode:)` in `BiliMusic/Player/MusicFilter.swift`, `waitForExistence(timeout:)` assertions in `BiliMusicUITests/PlayerChromeUITests.swift`.
- Mark test-only helpers explicitly in the function name or access path: `storeCachedSnapshotForTesting(query:mode:snapshot:)` in `BiliMusic/Features/Search/SearchStore.swift`, `UITestFixtures.enabled` in `BiliMusic/Support/UITestFixtures.swift`.
- Use argument labels that explain domain meaning: `prepareAudio(for:preferredQuality:)` in `BiliMusic/Player/StreamResolver.swift`, `upPlaylistContaining(bvid:mid:maxPlaylists:maxPages:)` in `BiliMusic/API/BiliClient.swift`.

**Variables:**
- Use lowerCamelCase with domain terms: `activeSearchID`, `resultCache`, and `hasMoreResults` in `BiliMusic/Features/Search/SearchStore.swift`; `queueIndex`, `playedKeys`, and `playbackGeneration` in `BiliMusic/Player/PlayerEngine.swift`.
- Keep constants grouped in private nested enums for UI metrics and animation values: `Metrics` and `Motion` in `BiliMusic/Features/RootView.swift`.
- Use `shared` for app-level singletons: `CacheStore.shared` in `BiliMusic/Cache/CacheStore.swift`, `FavoriteManager.shared` in `BiliMusic/Features/Favorites/FavoriteManager.swift`, `PlaybackHistoryStore.shared` in `BiliMusic/Player/PlaybackHistoryStore.swift`.

**Types:**
- Use PascalCase for structs, classes, enums, and nested models: `Track`, `TrackKey`, and `PlayerEngine.State` in `BiliMusic/Player/PlayerEngine.swift`; `BiliClient.APIError` and `BiliClient.VideoInfo` in `BiliMusic/API/BiliClient.swift`.
- Use lowerCamelCase enum cases: `SearchResultMode.music` in `BiliMusic/Features/Search/SearchModels.swift`, `PlayerEngine.QueueMode.repeatOne` in `BiliMusic/Player/PlayerEngine.swift`, `BiliClient.VideoStreamProfile.fullscreen` in `BiliMusic/API/BiliClient.swift`.
- Use `final class` for observable mutable owners: `SearchStore` in `BiliMusic/Features/Search/SearchStore.swift`, `PlayerEngine` in `BiliMusic/Player/PlayerEngine.swift`, `PlayerChromeUITests` in `BiliMusicUITests/PlayerChromeUITests.swift`.

## Code Style

**Formatting:**
- Formatting is governed by Xcode/Swift style and the compiler settings in `project.yml`; no `.swift-format`, `.swiftformat`, or `.swiftlint.yml` config is present in the repository root.
- Use 4-space indentation, same-line opening braces, and vertical spacing between major logical blocks, matching `BiliMusic/Features/Search/SearchStore.swift` and `BiliMusic/API/BiliClient.swift`.
- Prefer Swift trailing-closure syntax for SwiftUI and async callbacks: `CachedAsyncImage(url:) { image in ... } placeholder: { ... }` in `BiliMusic/Design/TrackRow.swift`, `Task { [weak self] in ... }` in `BiliMusic/Features/Search/SearchStore.swift`.
- Use SwiftUI modifier chains with one modifier per line when modifiers are non-trivial, as in `BiliMusic/Features/RootView.swift` and `BiliMusic/Features/Search/SearchView.swift`.
- Keep compact ternaries only for small formatting helpers, such as `format(_:)` in `BiliMusic/Design/TrackRow.swift`.
- Keep generated Xcode project settings in `project.yml`; run `xcodegen generate` after adding Swift files under `BiliMusic/`, `BiliMusicTests/`, or `BiliMusicUITests/`.

**Linting:**
- No lint tool is configured. Treat Swift compiler errors, Xcode warnings, and focused code review as the enforcement mechanism for `BiliMusic/*.swift`, `BiliMusicTests/*.swift`, and `BiliMusicUITests/*.swift`.
- Keep `SWIFT_VERSION: "5.10"` aligned with `project.yml` for all three targets: `BiliMusic`, `BiliMusicTests`, and `BiliMusicUITests`.

## Import Organization

**Order:**
1. Import Apple/system frameworks first; examples include `Foundation` and `OSLog` in `BiliMusic/API/BiliClient.swift`, `SwiftUI` in `BiliMusic/Features/RootView.swift`, and `AVKit` before `SwiftUI` in `BiliMusic/Features/Player/NowPlayingView.swift`.
2. Import `Observation` only in mutable model/store files that use `@Observable`, such as `BiliMusic/Features/Search/SearchStore.swift`, `BiliMusic/Cache/CacheStore.swift`, and `BiliMusic/Player/NetworkMonitor.swift`.
3. Test files import `XCTest` first; unit tests then use `@testable import BiliMusic` as shown in `BiliMusicTests/SearchModelsTests.swift`.

**Path Aliases:**
- Not applicable. The app is a single Xcode target configured by `project.yml`, and product Swift files under `BiliMusic/` use direct type visibility rather than custom module path aliases.

## Error Handling

**Patterns:**
- Use `async throws` for recoverable API and stream operations: `get(_:)`, `postVoid(_:form:)`, `audioStream(bvid:cid:preferredQuality:)`, and `videoStream(bvid:cid:profile:)` in `BiliMusic/API/BiliClient.swift`.
- Represent Bilibili API failures with `BiliClient.APIError: LocalizedError` in `BiliMusic/API/BiliClient.swift`; UI-facing callers surface `error.localizedDescription`, such as `state = .failed(error.localizedDescription)` in `BiliMusic/Player/PlayerEngine.swift`.
- Use `guard` for precondition exits and stale async result protection: `restoreCachedResultsIfAvailable(for:)` and `loadMore(preload:)` in `BiliMusic/Features/Search/SearchStore.swift`, `jump(to:)` in `BiliMusic/Player/PlayerEngine.swift`.
- Use cancellation and generation checks around long-lived tasks: `searchTask?.cancel()`, `activeSearchID`, and `Task.isCancelled` in `BiliMusic/Features/Search/SearchStore.swift`; preload task cancellation in `BiliMusic/Player/PlayerEngine.swift`.
- Use `try?` only for best-effort side effects where failure does not block the user path: directory creation in `BiliMusic/Cache/CacheStore.swift`, audio session setup in `BiliMusic/Player/PlayerEngine.swift`, and persistence cleanup in `BiliMusic/Cache/CacheStore.swift`.
- Keep fallback loops local and explicit, as in `videoStream(bvid:cid:profile:)` in `BiliMusic/API/BiliClient.swift`, where individual quality failures continue to lower quality candidates before throwing.

## Logging

**Framework:** `OSLog.Logger` for app code; `NSLog` for debug/autoplay probes; `print` for standalone Python verification scripts.

**Patterns:**
- Define one private logger per subsystem/category at file scope: `category: "network"` in `BiliMusic/API/BiliClient.swift`, `category: "player"` in `BiliMusic/Player/PlayerEngine.swift`, `category: "cache"` in `BiliMusic/Cache/CacheStore.swift`, and `category: "recommend"` in `BiliMusic/Player/RecommendationEngine.swift`.
- Use `.debug` logs for timing and diagnostic data, such as GET/POST latency in `BiliMusic/API/BiliClient.swift` and cache load duration in `BiliMusic/Cache/CacheStore.swift`.
- Keep `NSLog` probes behind debug/test flows in `BiliMusic/Features/RootView.swift`, including `AUTOPLAY_BV`, `AUTOPLAY_TEST_NEXT`, and mini-player drag diagnostics.
- Use script `print` output only in `scripts/verify_audio.py` and `scripts/verify_search_rcmd.py`; do not copy those print-style diagnostics into app code.

## Comments

**When to Comment:**
- Comment external protocol quirks, API hazards, and non-obvious timing constraints: request headers and percent-encoding warnings in `BiliMusic/API/BiliClient.swift`, stream URL TTL in `BiliMusic/Player/StreamResolver.swift`, and preload throttling in `BiliMusic/Player/PlayerEngine.swift`.
- Use comments to explain user-visible interaction thresholds and gesture choices in SwiftUI surfaces, such as mini-player opening metrics in `BiliMusic/Features/RootView.swift` and player dismissal thresholds in `BiliMusic/Features/Player/NowPlayingView.swift`.
- Preserve concise Chinese domain comments when editing nearby code, because existing comments in `BiliMusic/API/BiliClient.swift`, `BiliMusic/Player/PlayerEngine.swift`, and `BiliMusic/Features/Search/SearchStore.swift` document product-specific Bilibili behavior.

**JSDoc/TSDoc:**
- Not applicable. Swift code uses `///` doc comments for public or central APIs, such as `BiliClient.headers` in `BiliMusic/API/BiliClient.swift`, `TrackRow` in `BiliMusic/Design/TrackRow.swift`, and player operations in `BiliMusic/Player/PlayerEngine.swift`.

## Function Design

**Size:** Keep UI body composition in computed properties and private helpers when a view grows. Use `baseTabs`, `systemTabs`, and gesture helpers in `BiliMusic/Features/RootView.swift` as the model.

**Parameters:** Prefer typed domain parameters over raw dictionaries at module boundaries. Use `Track`, `TrackKey`, `SearchResultMode`, and `BiliClient.VideoStreamProfile` in `BiliMusic/Player/PlayerEngine.swift`, `BiliMusic/Features/Search/SearchModels.swift`, and `BiliMusic/API/BiliClient.swift`.

**Return Values:** Return domain values or tuples when a small transport result is enough, such as `(url: URL, quality: Int, bandwidth: Int)` in `BiliMusic/API/BiliClient.swift`; return structs for persisted or reusable state, such as `SearchCachedSnapshot` in `BiliMusic/Features/Search/SearchModels.swift`.

**Concurrency:** Mark UI/state owners with `@MainActor` when they mutate observable state: `SearchStore` in `BiliMusic/Features/Search/SearchStore.swift`, `PlayerEngine` in `BiliMusic/Player/PlayerEngine.swift`, and UI tests in `BiliMusicUITests/PlayerChromeUITests.swift`.

**Pure Logic:** Put reusable deterministic logic in stateless enums or structs: `QueueController` in `BiliMusic/Player/QueueController.swift`, `MusicFilter` in `BiliMusic/Player/MusicFilter.swift`, and `SearchResultSections` in `BiliMusic/Features/Search/SearchModels.swift`.

## Module Design

**Exports:** App code relies on internal Swift access by default inside the `BiliMusic` module. Use `private` and `private(set)` to constrain mutation in stores like `SearchStore` in `BiliMusic/Features/Search/SearchStore.swift` and cache internals in `BiliMusic/Cache/CacheStore.swift`.

**Barrel Files:** Not applicable. There are no Swift barrel files; add new code to the owning module directory and list it through `project.yml` generation rather than creating aggregate exports.

**State Pattern:** Use `@Observable` plus dependency injection through SwiftUI environment for global playback state: `PlayerEngine` is created in `BiliMusic/App/BiliMusicApp.swift` and consumed with `@Environment(PlayerEngine.self)` in views like `BiliMusic/Features/RootView.swift` and `BiliMusic/Design/TrackRow.swift`.

**Singleton Pattern:** Use singleton stores only for process-wide services that persist or coordinate shared state: `CacheStore.shared` in `BiliMusic/Cache/CacheStore.swift`, `DownloadManager.shared` in `BiliMusic/Cache/DownloadManager.swift`, `FavoriteManager.shared` in `BiliMusic/Features/Favorites/FavoriteManager.swift`, and `NetworkMonitor.shared` in `BiliMusic/Player/NetworkMonitor.swift`.

**Test Hooks:** Keep test hooks isolated behind explicit names or debug conditions: `UITestFixtures` in `BiliMusic/Support/UITestFixtures.swift`, `storeCachedSnapshotForTesting` in `BiliMusic/Features/Search/SearchStore.swift`, and `#if DEBUG` fixture installation in `BiliMusic/Player/PlayerEngine.swift`.

---

*Convention analysis: 2026-06-26*
