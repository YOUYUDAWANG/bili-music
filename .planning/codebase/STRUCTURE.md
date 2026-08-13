# Codebase Structure

**Analysis Date:** 2026-06-26

## Directory Layout

```text
bilibili-music/
+-- BiliMusic/                     # iOS app source target
|   +-- App/                       # SwiftUI app entry
|   +-- API/                       # Bilibili and LRCLIB clients
|   +-- Auth/                      # Keychain-backed Cookie store
|   +-- Cache/                     # Offline audio cache and downloads
|   +-- Design/                    # Theme, image loader, reusable UI
|   +-- Features/                  # SwiftUI screens and feature stores
|   |   +-- Favorites/             # Favorite folders as playlists
|   |   +-- Home/                  # Recommendation home feed
|   |   +-- Library/               # Local cache library
|   |   +-- Player/                # Full-screen player UI
|   |   +-- Search/                # Search UI, store, and models
|   |   +-- Settings/              # Account, preferences, history
|   +-- Player/                    # Playback domain and recommendation logic
|   +-- Support/                   # Fixtures and support helpers
|   +-- Assets.xcassets/           # App icon assets
|   +-- Info.plist                 # Generated target Info.plist path from XcodeGen
+-- BiliMusicTests/                # Unit tests
+-- BiliMusicUITests/              # UI tests
+-- scripts/                       # Python API verification scripts
+-- docs/superpowers/              # Planning/design reference docs
+-- .github/                       # PR template and CI workflow
+-- .planning/codebase/            # GSD mapper output
+-- project.yml                    # XcodeGen project definition
+-- README.md                      # User-facing build and feature summary
+-- ARCHITECTURE.md                # Repo-level architecture guide
```

## Directory Purposes

**`BiliMusic/App/`:**
- Purpose: App bootstrap.
- Contains: The `@main` SwiftUI `App` implementation.
- Key files: `BiliMusic/App/BiliMusicApp.swift`, `BiliMusic/App/CLAUDE.md`

**`BiliMusic/API/`:**
- Purpose: External HTTP clients and API DTOs.
- Contains: Bilibili client, WBI signer, LRCLIB lyrics client, nested response models.
- Key files: `BiliMusic/API/BiliClient.swift`, `BiliMusic/API/WBISigner.swift`, `BiliMusic/API/LyricsClient.swift`, `BiliMusic/API/CLAUDE.md`

**`BiliMusic/Auth/`:**
- Purpose: Login Cookie storage and parsing.
- Contains: Static Keychain-backed `CookieStore`.
- Key files: `BiliMusic/Auth/CookieStore.swift`, `BiliMusic/Auth/CLAUDE.md`

**`BiliMusic/Cache/`:**
- Purpose: Offline audio cache state and download orchestration.
- Contains: JSON cache index store, audio directory mapping, download manager, progress watcher.
- Key files: `BiliMusic/Cache/CacheStore.swift`, `BiliMusic/Cache/DownloadManager.swift`, `BiliMusic/Cache/CLAUDE.md`

**`BiliMusic/Design/`:**
- Purpose: Shared visual primitives and reusable UI support.
- Contains: Semantic theme, cached async image, haptics, shared row, small reusable controls.
- Key files: `BiliMusic/Design/AppTheme.swift`, `BiliMusic/Design/CachedAsyncImage.swift`, `BiliMusic/Design/TrackRow.swift`, `BiliMusic/Design/UIComponents.swift`, `BiliMusic/Design/Haptics.swift`, `BiliMusic/Design/CLAUDE.md`

**`BiliMusic/Features/`:**
- Purpose: User-facing SwiftUI features and feature-specific state.
- Contains: Root tab shell plus feature folders for home, search, favorites, library, player, and settings.
- Key files: `BiliMusic/Features/RootView.swift`（tab shell + mini/全屏播放器浮层；`LibraryTabView.swift` 已删除，其职责并入 RootView 与 `Features/Library/LibraryView.swift`）

**`BiliMusic/Features/Home/`:**
- Purpose: Recommendation feed.
- Contains: `HomeView` and recent recommendation de-duplication store.
- Key files: `BiliMusic/Features/Home/HomeView.swift`, `BiliMusic/Features/Home/RecentHomeFeedStore.swift`, `BiliMusic/Features/Home/CLAUDE.md`

**`BiliMusic/Features/Search/`:**
- Purpose: Bilibili search experience.
- Contains: SwiftUI screen, `@Observable` search store, search cache key/snapshot/section models.
- Key files: `BiliMusic/Features/Search/SearchView.swift`, `BiliMusic/Features/Search/SearchStore.swift`, `BiliMusic/Features/Search/SearchModels.swift`, `BiliMusic/Features/Search/CLAUDE.md`

**`BiliMusic/Features/Favorites/`:**
- Purpose: Favorite folders as playlists and favorite mutation state.
- Contains: Favorite folder views and singleton `FavoriteManager`.
- Key files: `BiliMusic/Features/Favorites/FavoritesView.swift`, `BiliMusic/Features/Favorites/FavoriteManager.swift`, `BiliMusic/Features/Favorites/CLAUDE.md`

**`BiliMusic/Features/Library/`:**
- Purpose: Cached-track browsing and cache management UI.
- Contains: `LibraryView` and local sort/search/delete behavior.
- Key files: `BiliMusic/Features/Library/LibraryView.swift`, `BiliMusic/Features/Library/CLAUDE.md`

**`BiliMusic/Features/Player/`:**
- Purpose: Full-screen player UI and player-specific sheets/controls.
- Contains: LNPopup-hosted now-playing surface, playback controls, a three-state queue/playlist/recommendation drawer, lyrics/MV/playlist/favorite/download sheets, and list-window pure helpers.
- Key files: `BiliMusic/Features/Player/NowPlayingView.swift`, `BiliMusic/Features/Player/PlayerControlViews.swift`, `BiliMusic/Features/Player/PlayerSheetViews.swift`, `BiliMusic/Features/Player/PlayerListWindow.swift`, `BiliMusic/Features/Player/CLAUDE.md`

**`BiliMusic/Features/Settings/`:**
- Purpose: Settings, login, quality, cache policy, MV preference, and history UI.
- Contains: `SettingsView` with nested account/history/QR login views.
- Key files: `BiliMusic/Features/Settings/SettingsView.swift`, `BiliMusic/Features/Settings/CLAUDE.md`

**`BiliMusic/Player/`:**
- Purpose: Playback domain, media integration, recommendations, filters, history, and network reachability.
- Contains: `PlayerEngine`, `Track`, `TrackKey`, queue controller, recommendation engine, music filter, stream resolver, network monitor, playback history store.
- Key files: `BiliMusic/Player/PlayerEngine.swift`, `BiliMusic/Player/StreamResolver.swift`, `BiliMusic/Player/RecommendationEngine.swift`, `BiliMusic/Player/MusicFilter.swift`, `BiliMusic/Player/QueueController.swift`, `BiliMusic/Player/AudioCDNSelector.swift`, `BiliMusic/Player/PlaybackDiagnostics.swift`, `BiliMusic/Player/NetworkMonitor.swift`, `BiliMusic/Player/PlaybackHistoryStore.swift`, `BiliMusic/Player/CLAUDE.md`

**`BiliMusic/Support/`:**
- Purpose: Debug and UI-test fixtures.
- Contains: Static fixture data guarded by debug/test paths.
- Key files: `BiliMusic/Support/UITestFixtures.swift`

**`BiliMusic/Assets.xcassets/`:**
- Purpose: Asset catalog for app icons.
- Contains: App icon images and asset catalog JSON.
- Key files: `BiliMusic/Assets.xcassets/AppIcon.appiconset/Contents.json`, `BiliMusic/Assets.xcassets/AppIcon.appiconset/icon-1024.png`

**`BiliMusicTests/`:**
- Purpose: Unit tests for pure logic and model behavior.
- Contains: Search model/store/filter tests.
- Key files: `BiliMusicTests/SearchModelsTests.swift`, `BiliMusicTests/CLAUDE.md`

**`BiliMusicUITests/`:**
- Purpose: UI tests using deterministic fixture paths.
- Contains: Player chrome UI tests.
- Key files: `BiliMusicUITests/PlayerChromeUITests.swift`

**`scripts/`:**
- Purpose: Standalone API verification utilities.
- Contains: Python scripts that verify audio playurl and search/recommendation API assumptions.
- Key files: `scripts/verify_audio.py`, `scripts/verify_search_rcmd.py`

**`.github/`:**
- Purpose: Repository automation and contribution metadata.
- Contains: PR template and simulator compile workflow.
- Key files: `.github/workflows/build.yml`, `.github/pull_request_template.md`

**`docs/superpowers/`:**
- Purpose: Planning and design notes.
- Contains: Search UX spec and implementation plan documents.
- Key files: `docs/superpowers/specs/2026-06-23-search-ux-design.md`, `docs/superpowers/plans/2026-06-23-search-ux-implementation.md`

**`.planning/codebase/`:**
- Purpose: Generated GSD codebase maps used by planning/execution agents.
- Contains: Stack, integration, architecture, structure, convention, testing, and concern maps when generated.
- Key files: `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/STRUCTURE.md`

## Key File Locations

**Entry Points:**
- `BiliMusic/App/BiliMusicApp.swift`: SwiftUI `@main` app entry and `PlayerEngine` environment injection.
- `BiliMusic/Features/RootView.swift`: Main app shell, tabs, mini/full player, settings sheet, startup tasks, background flushes.
- `BiliMusic/Player/PlayerEngine.swift`: Playback action entry points such as `play(tracks:startAt:)`, `playRadio(seed:)`, `playNext()`, and `startCurrent`.
- `BiliMusic/Features/Search/SearchStore.swift`: Search operation entry point via `submitSearch(_:preload:)`.
- `.github/workflows/build.yml`: CI compile entry point.

**Configuration:**
- `project.yml`: XcodeGen configuration for app, unit-test, and UI-test targets.
- `BiliMusic/Info.plist`: Info.plist path configured by `project.yml`.
- `README.md`: Build steps and high-level product scope.
- `CLAUDE.md`: Repo-level architecture and working constraints.
- `BiliMusic/*/CLAUDE.md`: Module-level responsibilities and constraints.
- `BiliMusic.xcodeproj/`: Generated local Xcode project.

**Core Logic:**
- `BiliMusic/API/BiliClient.swift`: Bilibili API gateway, headers, response envelope handling, quality options, QR login, favorites, search, related, playlists.
- `BiliMusic/API/WBISigner.swift`: WBI signing and prewarm behavior.
- `BiliMusic/API/LyricsClient.swift`: LRCLIB search, match, and LRC parsing.
- `BiliMusic/Auth/CookieStore.swift`: Keychain Cookie persistence and parsed login values.
- `BiliMusic/Cache/CacheStore.swift`: Cache index, audio file mapping, load/save/flush/remove behavior.
- `BiliMusic/Cache/DownloadManager.swift`: Whole-track downloads and progress.
- `BiliMusic/Player/PlayerEngine.swift`: AVPlayer integration, queue state, playback mode, preloading, remote commands.
- `BiliMusic/Player/StreamResolver.swift`: cid/duration resolution and short-lived audio stream cache.
- `BiliMusic/Player/RecommendationEngine.swift`: Home, radio, and related-panel recommendation generation.
- `BiliMusic/Player/MusicFilter.swift`: Music-content heuristics.
- `BiliMusic/Player/QueueController.swift`: Pure queue operations.
- `BiliMusic/Player/PlaybackHistoryStore.swift`: Playback history persistence.

**Feature UI:**
- `BiliMusic/Features/Home/HomeView.swift`: Recommendation list and refresh.
- `BiliMusic/Features/Search/SearchView.swift`: Search screen and result rows.
- `BiliMusic/Features/Favorites/FavoritesView.swift`: Favorite folders and details.
- `BiliMusic/Features/Library/LibraryView.swift`: Cached library.
- `BiliMusic/Features/Settings/SettingsView.swift`: Settings and account flows.
- `BiliMusic/Features/Player/NowPlayingView.swift`: Full-screen now-playing experience.
- `BiliMusic/Features/Player/PlayerControlViews.swift`: Player control subviews.
- `BiliMusic/Features/Player/PlayerSheetViews.swift`: Player sheets and playlist/lyrics/MV support.

**Shared UI:**
- `BiliMusic/Design/AppTheme.swift`: Semantic color/theme constants.
- `BiliMusic/Design/CachedAsyncImage.swift`: Image memory/disk/network loading.
- `BiliMusic/Design/TrackRow.swift`: Shared track row.
- `BiliMusic/Design/UIComponents.swift`: Small shared UI controls.
- `BiliMusic/Design/Haptics.swift`: Haptic helpers.

**Testing:**
- `BiliMusicTests/SearchModelsTests.swift`: Unit tests for search models/store/filter behavior.
- `BiliMusicUITests/PlayerChromeUITests.swift`: UI tests for player chrome behavior.
- `BiliMusic/Support/UITestFixtures.swift`: Fixture tracks used by debug/UI-test paths.

**Verification Scripts:**
- `scripts/verify_audio.py`: Verifies bvid -> video info -> cid -> playurl -> download path.
- `scripts/verify_search_rcmd.py`: Verifies WBI search, home recommendation feed, and related-video APIs.

## Naming Conventions

**Files:**
- Swift type files use PascalCase matching the primary type: `BiliMusic/Player/PlayerEngine.swift`, `BiliMusic/API/BiliClient.swift`, `BiliMusic/Features/Search/SearchStore.swift`.
- Feature screens use `*View.swift`: `BiliMusic/Features/Home/HomeView.swift`, `BiliMusic/Features/Settings/SettingsView.swift`.
- Observable or persistent state owners use `*Store.swift` or `*Manager.swift`: `BiliMusic/Features/Search/SearchStore.swift`, `BiliMusic/Cache/CacheStore.swift`, `BiliMusic/Features/Favorites/FavoriteManager.swift`.
- Shared domain helpers use noun names: `BiliMusic/Player/MusicFilter.swift`, `BiliMusic/Player/QueueController.swift`, `BiliMusic/Player/StreamResolver.swift`.
- Module instruction docs are named `CLAUDE.md` in the module directory.
- Verification scripts use snake_case Python filenames: `scripts/verify_audio.py`, `scripts/verify_search_rcmd.py`.

**Directories:**
- Top-level Swift target directories are role-based: `BiliMusic/API/`, `BiliMusic/Player/`, `BiliMusic/Cache/`, `BiliMusic/Design/`.
- Feature directories are product-feature based and nested under `BiliMusic/Features/`: `Search`, `Favorites`, `Library`, `Player`, `Settings`, `Home`.
- Test target directories mirror Xcode target names: `BiliMusicTests/`, `BiliMusicUITests/`.
- Generated or local tooling directories stay outside `BiliMusic/`: `BiliMusic.xcodeproj/`, `build/`, `.codegraph/`, `.planning/`.

## Where to Add New Code

**New Feature:**
- Primary UI code: Add a folder under `BiliMusic/Features/<FeatureName>/` with a `*View.swift` file.
- Feature state: Add a colocated `*Store.swift` when state goes beyond local `@State`, following `BiliMusic/Features/Search/SearchStore.swift`.
- Root navigation: Wire the feature into `BiliMusic/Features/RootView.swift` if it needs a top-level tab, sheet, or overlay.
- Tests: Add pure logic tests in `BiliMusicTests/`; add UI-flow tests in `BiliMusicUITests/` only when fixture-driven UI coverage is appropriate.

**New Bilibili Endpoint:**
- Implementation: Add the method and response DTOs to `BiliMusic/API/BiliClient.swift`.
- Signing: Use `BiliMusic/API/WBISigner.swift` for WBI endpoints.
- Auth: Read login state through `BiliMusic/Auth/CookieStore.swift`; do not parse Cookie in features.
- Verification: Add or update a script in `scripts/` when the endpoint shape is uncertain.

**New Playback Behavior:**
- Implementation: Add queue/playback state and user actions to `BiliMusic/Player/PlayerEngine.swift`.
- Pure queue operations: Add deterministic index/list logic to `BiliMusic/Player/QueueController.swift`.
- Stream preparation: Add audio playurl/cid behavior to `BiliMusic/Player/StreamResolver.swift`.
- Player UI: Add controls or sheets under `BiliMusic/Features/Player/`.

**New Recommendation or Filtering Logic:**
- Recommendation selection: Add sources/scoring to `BiliMusic/Player/RecommendationEngine.swift`.
- Music classification: Add heuristics to `BiliMusic/Player/MusicFilter.swift`.
- Home de-duplication: Use `BiliMusic/Features/Home/RecentHomeFeedStore.swift`.
- Tests: Add deterministic filter/model tests to `BiliMusicTests/SearchModelsTests.swift` or a new unit-test file.

**New Cached Data:**
- Track audio files and index entries: Use `BiliMusic/Cache/CacheStore.swift` and `BiliMusic/Cache/DownloadManager.swift`.
- Playback history: Use `BiliMusic/Player/PlaybackHistoryStore.swift`.
- Feature-specific small JSON state: Add a colocated store near the feature, following `BiliMusic/Features/Home/RecentHomeFeedStore.swift`.
- Lightweight preferences: Use `UserDefaults` from the owning feature/store and document the key in the module doc.

**New Component/Module:**
- Feature-specific component: Keep it next to the feature under `BiliMusic/Features/<FeatureName>/`.
- Cross-feature presentational component: Add it to `BiliMusic/Design/`.
- Cross-feature domain/service helper: Add it to `BiliMusic/Player/`, `BiliMusic/API/`, `BiliMusic/Cache/`, or `BiliMusic/Auth/` according to responsibility.
- Module instructions: Add/update the module `CLAUDE.md` when conventions or constraints change.

**Utilities:**
- Shared UI helpers: `BiliMusic/Design/`
- Debug fixtures: `BiliMusic/Support/`
- API verification helpers: `scripts/`
- Planning artifacts: `docs/superpowers/` or `.planning/`, depending on the workflow artifact type.

## Special Directories

**`BiliMusic.xcodeproj/`:**
- Purpose: Local Xcode project generated from `project.yml`.
- Generated: Yes.
- Committed: No in the tracked file set.

**`build/`:**
- Purpose: Local Xcode build outputs and derived data.
- Generated: Yes.
- Committed: No in the tracked file set.

**`.codegraph/`:**
- Purpose: Local CodeGraph index used for source exploration.
- Generated: Yes.
- Committed: No in the tracked file set.

**`.planning/codebase/`:**
- Purpose: Generated GSD codebase intelligence documents.
- Generated: Yes.
- Committed: Intended as planning artifacts when selected by the orchestrator.

**`.ccg/`:**
- Purpose: Local task metadata from CCG workflows.
- Generated: Yes.
- Committed: Not present in the tracked file set.

**`.claude/`:**
- Purpose: Claude/GSD metadata and settings.
- Generated: Mixed; repository tracks `.claude/index.json`.
- Committed: Partially.

**`BiliMusic/Assets.xcassets/`:**
- Purpose: App icon catalog used by the app target.
- Generated: No.
- Committed: Yes.

**`docs/superpowers/`:**
- Purpose: Human-readable specs and implementation plans.
- Generated: Workflow-authored documentation.
- Committed: Yes.

---

*Structure analysis: 2026-06-26*
