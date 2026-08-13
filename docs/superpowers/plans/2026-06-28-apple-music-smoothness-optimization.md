# Apple Music Smoothness Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make daily playback feel closer to Apple Music by removing collection-driven UI fanout, stabilizing player transitions, reducing first-focus/search jank, and unifying visual language without slowing first sound.

**Architecture:** Keep the current SwiftUI app and `PlayerEngine` playback critical path intact. Move expensive collection, recommendation, search-local-content, and presentation calculations out of hot SwiftUI body paths into small deterministic helpers or stores with focused tests. Prefer native iOS scrolling/animation physics where they can replace hand-written gesture math.

**Tech Stack:** SwiftUI, Swift 5.10, XCTest, existing Xcode project, no new third-party dependencies.

## Global Constraints

- Music must start quickly; playback startup remains higher priority than lyrics, recommendations, MV, artwork, cache work, and UI polish.
- Do not reintroduce custom bottom TabBar; keep system `TabView` and `tabViewBottomAccessory`.
- Title cleaning is experimental and defaults off; UI must preserve raw Bilibili title/UP when the setting is disabled.
- Keep Bilibili private API changes isolated behind existing API/client boundaries.
- Add or preserve regression tests for each performance-sensitive behavior changed here.
- Do not broaden API/auth/cache rewrites unless directly required for this smoothness work.

---

## Already Applied Before This Plan

- `TrackTitleFormatter.shouldCleanListTitles` now defaults to `false`.
- `SettingsView` uses `@AppStorage(... ) = false` for `cleanListTitles`.
- `SearchModelsTests` includes a regression proving no stored preference means raw title/UP are displayed.

---

### Task 1: Cap Collection Rendering Fanout

**Files:**
- Create: `BiliMusic/Features/Player/PlayerListWindow.swift`
- Create: `BiliMusicTests/PlayerListWindowTests.swift`
- Modify: `BiliMusic/Features/Player/NowPlayingView.swift:1010-1369`
- Modify: `BiliMusic/Features/Player/NowPlayingView.swift:1639-1664`

**Interfaces:**
- Consumes: `Track`, `TrackKey`, `currentPlaylistTracks`, `engine.queue`, `engine.current`.
- Produces: `PlayerListWindow.items(tracks:current:maxRows:) -> [PlayerListWindow.Item]` and `PlayerListWindow.positionText(tracks:current:) -> String`.

- [ ] **Step 1: Write the failing window-budget tests**

Create `BiliMusicTests/PlayerListWindowTests.swift`:

```swift
import XCTest
@testable import BiliMusic

final class PlayerListWindowTests: XCTestCase {
    func testLargeCollectionOnlyReturnsVisibleWindowAroundCurrentTrack() {
        let tracks = (0..<300).map {
            Track(bvid: "BV\($0)", title: "Song \($0)", artist: "UP",
                  coverURL: nil, duration: 180)
        }
        let items = PlayerListWindow.items(tracks: tracks, current: tracks[150], maxRows: 7)

        XCTAssertLessThanOrEqual(items.count, 7)
        XCTAssertTrue(items.contains { $0.index == 150 })
        XCTAssertEqual(items.first?.index, 147)
        XCTAssertEqual(items.last?.index, 153)
    }

    func testWindowClampsAtCollectionStartAndEnd() {
        let tracks = (0..<20).map {
            Track(bvid: "BV\($0)", title: "Song \($0)", artist: "UP",
                  coverURL: nil, duration: 180)
        }

        XCTAssertEqual(
            PlayerListWindow.items(tracks: tracks, current: tracks[0], maxRows: 5).map(\.index),
            [0, 1, 2, 3, 4])
        XCTAssertEqual(
            PlayerListWindow.items(tracks: tracks, current: tracks[19], maxRows: 5).map(\.index),
            [15, 16, 17, 18, 19])
    }

    func testPositionTextUsesCurrentIndexWhenAvailable() {
        let tracks = (0..<3).map {
            Track(bvid: "BV\($0)", title: "Song \($0)", artist: "UP",
                  coverURL: nil, duration: 180)
        }

        XCTAssertEqual(PlayerListWindow.positionText(tracks: tracks, current: tracks[1]), "2/3")
        XCTAssertEqual(PlayerListWindow.positionText(tracks: tracks, current: nil), "3 首")
    }
}
```

- [ ] **Step 2: Run the new test and verify it fails**

Run:

```bash
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/PlayerListWindowTests
```

Expected: fails because `PlayerListWindow` does not exist.

- [ ] **Step 3: Implement the list-window helper**

Create `BiliMusic/Features/Player/PlayerListWindow.swift`:

```swift
import Foundation

enum PlayerListWindow {
    struct Item: Equatable, Identifiable {
        let index: Int
        let track: Track
        var id: String { track.id }
    }

    static func items(tracks: [Track], current: Track?, maxRows: Int) -> [Item] {
        guard maxRows > 0, !tracks.isEmpty else { return [] }
        let limit = min(maxRows, tracks.count)
        let currentIndex = current.flatMap { current in
            tracks.firstIndex { $0.key.matches(current) }
        } ?? 0
        let leading = limit / 2
        let proposedStart = currentIndex - leading
        let start = min(max(0, proposedStart), max(0, tracks.count - limit))
        return (start..<(start + limit)).map { Item(index: $0, track: tracks[$0]) }
    }

    static func positionText(tracks: [Track], current: Track?) -> String {
        guard let current,
              let index = tracks.firstIndex(where: { $0.key.matches(current) }) else {
            return "\(tracks.count) 首"
        }
        return "\(index + 1)/\(tracks.count)"
    }
}
```

- [ ] **Step 4: Replace full collection previews with windowed previews**

In `NowPlayingView`, update `currentPlaylistPositionText` to call:

```swift
PlayerListWindow.positionText(tracks: currentPlaylistTracks, current: engine.current)
```

Update `currentPlaylistBottomPanel(maxRows:)` and `currentPlaylistPanel` so their preview rows iterate only:

```swift
let previewItems = PlayerListWindow.items(
    tracks: currentPlaylistTracks,
    current: engine.current,
    maxRows: maxRows)

ForEach(previewItems) { item in
    guardedPlayerRowButton {
        Task { await playCurrentPlaylistTrack(at: item.index) }
    } label: {
        compactPlaylistRow(track: item.track, index: item.index)
            .id(item.track.id)
    }
}
```

Remove `ScrollViewReader` and automatic `scrollCurrentPlaylist` from the center bottom preview. Keep full scrolling only on the dedicated queue page.

- [ ] **Step 5: Make the dedicated queue page lazy and avoid duplicate collection panels**

In `queueList`, change the full queue body from `VStack(spacing: 0)` to `LazyVStack(spacing: 0)`. When `engine.queue.map(\.key)` equals `currentPlaylistTracks.map(\.key)`, render either the playlist panel or the queue list, not both.

- [ ] **Step 6: Run focused tests**

Run:

```bash
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/PlayerListWindowTests
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicUITests/PlayerChromeUITests
```

Expected: both pass. Manual check: a 300-song collection should render only a small bottom preview and remain scrollable on the queue page.

- [ ] **Step 7: Commit**

```bash
git add BiliMusic/Features/Player/PlayerListWindow.swift BiliMusic/Features/Player/NowPlayingView.swift BiliMusicTests/PlayerListWindowTests.swift
git commit -m "perf: cap now playing collection previews"
```

---

### Task 2: Stabilize Player Appearance After First Sound

**Files:**
- Modify: `BiliMusic/Player/PlayerEngine.swift:940-971`
- Modify: `BiliMusic/Features/Player/NowPlayingView.swift:207-254`
- Test: `BiliMusicTests/PlaybackCriticalPathTests.swift`

**Interfaces:**
- Consumes: existing `schedulePostPlaybackWork`, `scheduleCurrentPlaylistLookup`, `scheduleRecommendationLoad`.
- Produces: post-start UI enrichment that cannot mutate large visible surfaces during the first second of playback.

- [ ] **Step 1: Add a test that post-start enrichment stays delayed**

In `PlaybackCriticalPathTests`, add an assertion that first-playing occurs before playlist lookup, recommendations, lyrics, artwork, and MV preparation are scheduled into visible UI state.

- [ ] **Step 2: Split visible and non-visible enrichment**

Keep `PlayerEngine.startCurrent` focused on audio. After first playing:

```swift
schedulePostPlaybackWork(for: source.track, generation: generation, resumeAt: resumeAt)
prefetchUpcomingTracks()
```

but ensure `NowPlayingView` only starts playlist lookup when the full player is visible and recommendations only load when the recommendation page is opened or explicitly marked stale.

- [ ] **Step 3: Disable silent auto-switch to MV**

Change `prepareVideoIfUseful` so Wi-Fi preference prepares the MV stream and sets `videoAvailable`, but does not automatically change `playbackMode` after music has started. User action on the MV button should perform the switch.

- [ ] **Step 4: Run playback and player tests**

Run:

```bash
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/PlaybackCriticalPathTests
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicUITests/PlayerChromeUITests
```

Expected: first-sound tests pass and the player no longer changes source by itself after audio starts.

- [ ] **Step 5: Commit**

```bash
git add BiliMusic/Player/PlayerEngine.swift BiliMusic/Features/Player/NowPlayingView.swift BiliMusicTests/PlaybackCriticalPathTests.swift
git commit -m "perf: keep player enrichment off the first second"
```

---

### Task 3: Replace Hand-Written Page Physics With Native Paging

**Files:**
- Modify: `BiliMusic/Features/Player/NowPlayingView.swift:445-481`
- Modify: `BiliMusic/Features/Player/NowPlayingView.swift:1710-1759`
- Test: `BiliMusicUITests/PlayerChromeUITests.swift`

**Interfaces:**
- Consumes: `PlayerPage`, `selectedPage`, `queueList`, `nowPlayingPage`, `recommendationsList`.
- Produces: native horizontal paging with fewer custom gesture conflicts.

- [ ] **Step 1: Extend UI tests for side-page movement**

Add assertions that swiping left from center lands on recommendations, swiping right lands on queue, and vertical scrolling inside list pages does not change tracks or minimize the player.

- [ ] **Step 2: Replace HStack offset paging**

Use iOS-native horizontal scroll paging:

```swift
ScrollView(.horizontal) {
    LazyHStack(spacing: 0) {
        horizontalListPage(accessibilityIdentifier: "playerQueuePage") { queueList }
            .containerRelativeFrame(.horizontal)
            .id(PlayerPage.queue.rawValue)
        nowPlayingPage(coverSize: coverSize, isLandscape: isLandscape)
            .containerRelativeFrame(.horizontal)
            .id(PlayerPage.nowPlaying.rawValue)
        horizontalListPage(accessibilityIdentifier: "playerRecommendationsPage") { recommendationsList }
            .containerRelativeFrame(.horizontal)
            .id(PlayerPage.recommendations.rawValue)
    }
    .scrollTargetLayout()
}
.scrollTargetBehavior(.paging)
.scrollPosition(id: Binding(
    get: { selectedPage },
    set: { selectedPage = $0 ?? PlayerPage.nowPlaying.rawValue }
))
```

Preserve progress-scrub ownership and center-body dismiss ownership.

- [ ] **Step 3: Remove obsolete page drag state**

Delete `pageDragOffset`, `suppressPageSwipeForScrub` only if no longer needed, and `pageSwipeGesture(width:)` once native paging owns horizontal movement.

- [ ] **Step 4: Run gesture tests**

Run:

```bash
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicUITests/PlayerChromeUITests
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/PlayerGesturePolicyTests
```

Expected: gestures pass; player pages feel closer to system paging.

- [ ] **Step 5: Commit**

```bash
git add BiliMusic/Features/Player/NowPlayingView.swift BiliMusicUITests/PlayerChromeUITests.swift
git commit -m "ui: use native paging in now playing"
```

---

### Task 4: Make Mini-to-Full Player a Coherent Transition

**Files:**
- Modify: `BiliMusic/Features/RootView.swift:24-48`
- Modify: `BiliMusic/Features/RootView.swift:372-480`
- Modify: `BiliMusic/Features/Player/NowPlayingView.swift:483-562`
- Test: `BiliMusicUITests/PlayerChromeUITests.swift`

**Interfaces:**
- Consumes: existing `playerTransition` namespace, `renderedPlayerOpenProgress`, mini artwork, full artwork.
- Produces: one perceived player object with matched artwork/title movement.

- [ ] **Step 1: Add screenshot-state UI checks**

Extend the player chrome UI test to open and close the player twice and assert mini artwork and full artwork both exist after the transition.

- [ ] **Step 2: Apply matched geometry to artwork and title**

Use the existing namespace:

```swift
.matchedGeometryEffect(id: "playerArtwork", in: namespace)
```

on mini artwork and full artwork, and:

```swift
.matchedGeometryEffect(id: "playerTitle", in: namespace)
```

on the mini title/full title where layout permits.

- [ ] **Step 3: Remove per-frame DEBUG drag logging**

Remove or gate the `NSLog` calls in `handleMiniOpenDragChanged` so DEBUG drag testing does not produce artificial jank.

- [ ] **Step 4: Run player UI tests**

Run:

```bash
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicUITests/PlayerChromeUITests
```

Expected: tests pass; transition no longer looks like two unrelated layers crossfading.

- [ ] **Step 5: Commit**

```bash
git add BiliMusic/Features/RootView.swift BiliMusic/Features/Player/NowPlayingView.swift BiliMusicUITests/PlayerChromeUITests.swift
git commit -m "ui: smooth mini player expansion"
```

---

### Task 5: Precompute Search-Focus Local Content

**Files:**
- Modify: `BiliMusic/Features/Search/SearchStore.swift:38-111`
- Modify: `BiliMusic/Features/Search/SearchView.swift:46-78`
- Test: `BiliMusicTests/SearchStoreTests.swift`

**Interfaces:**
- Consumes: `PlaybackHistoryStore`, `CacheStore`, `SearchLocalContent`.
- Produces: `SearchStore.localContent` snapshot that updates outside the search-field focus path.

- [ ] **Step 1: Add local-content snapshot tests**

Test that focusing an empty query does not start search, does not clear results, and reads an already prepared `SearchLocalContent`.

- [ ] **Step 2: Move local content into SearchStore**

Add:

```swift
private(set) var localContent = SearchLocalContent(historyTerms: [], recentTracks: [], cachedTracks: [])

func loadLocalContent(history: PlaybackHistoryStore, cache: CacheStore) async {
    await loadHistory()
    await history.loadIfNeeded()
    await cache.loadIfNeeded()
    localContent = SearchLocalContent(
        historyTerms: searchHistory,
        recentTracks: Array(history.entries.prefix(6).map(\.track)),
        cachedTracks: Array(cache.entries.prefix(6).map(\.track)))
}
```

In `SearchView`, replace computed `localContent` with `store.localContent`.

- [ ] **Step 3: Keep focus path local**

Ensure `.onChange(of: query)` still only calls `store.queryDidChange(newValue)` and never starts Bilibili search until `.onSubmit`.

- [ ] **Step 4: Run search tests**

Run:

```bash
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/SearchStoreTests
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/SearchModelsTests
```

Expected: search focus state remains local and stable.

- [ ] **Step 5: Commit**

```bash
git add BiliMusic/Features/Search/SearchStore.swift BiliMusic/Features/Search/SearchView.swift BiliMusicTests/SearchStoreTests.swift
git commit -m "perf: precompute search focus content"
```

---

### Task 6: Unify Daily List Rows and Player Palette Stability

**Files:**
- Modify: `BiliMusic/Design/UIComponents.swift:232-337`
- Modify: `BiliMusic/Design/TrackRow.swift:5-160`
- Modify: `BiliMusic/Design/AppTheme.swift:47-87`
- Modify: `BiliMusic/Player/PlayerEngine.swift:1311-1335`
- Test: `BiliMusicTests/SearchModelsTests.swift`

**Interfaces:**
- Consumes: `TrackTitleFormatter`, `PlayerArtworkPalette`, `CachedAsyncImage`.
- Produces: one shared row style and less abrupt artwork-palette changes.

- [ ] **Step 1: Introduce one row visual API**

Make `TrackRow` the canonical row and give it appearances:

```swift
enum Appearance {
    case standard
    case prominent
    case player
}
```

Migrate `MusicTrackRow` call sites to `TrackRow(appearance: .prominent)` and remove duplicated row sizing logic from `UIComponents.swift`.

- [ ] **Step 2: Cache display metadata per row input**

Add a tiny in-memory formatter cache keyed by `TrackKey + cleanListTitles` so large list rendering does not repeatedly parse the same title.

- [ ] **Step 3: Make palette updates less jumpy**

Keep `PlayerArtworkPalette.from(_:)`, but reduce saturation and crossfade the background at the view layer:

```swift
.animation(.easeInOut(duration: 0.25), value: engine.currentArtworkPalette)
```

Only update palette after confirming the image belongs to the current track.

- [ ] **Step 4: Run row/title tests and player UI tests**

Run:

```bash
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/SearchModelsTests
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicUITests/PlayerChromeUITests
```

Expected: title-cleaning behavior stays opt-in; rows look consistent across home/search/library/favorites/player.

- [ ] **Step 5: Commit**

```bash
git add BiliMusic/Design/UIComponents.swift BiliMusic/Design/TrackRow.swift BiliMusic/Design/AppTheme.swift BiliMusic/Player/PlayerEngine.swift BiliMusicTests/SearchModelsTests.swift
git commit -m "ui: unify music row and palette behavior"
```

---

## Verification Gate

Before calling the smoothness pass complete, run:

```bash
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/SearchModelsTests
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/SearchStoreTests
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicTests/PlayerGesturePolicyTests
xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BiliMusicUITests/PlayerChromeUITests
```

Manual real-device checks:

- Open a track with a large collection; interacting with play/pause, progress, and page swipes should not stutter after the collection appears.
- Open and close the full player three times; artwork should not flash white or duplicate.
- Focus Search for the first time after app launch; keyboard and local history should appear without a visible freeze.
- Play audio first, then tap MV; MV should switch by user action and should not auto-switch after the music starts.
- With title cleaning off, Home/Search/Library/Favorites/Player rows should show original Bilibili titles and UP names.

## Self-Review

- Spec coverage: collection lag, Apple Music-like transition, search focus, visual cohesion, palette stability, title-cleaning default, and playback priority are each mapped to a task.
- Placeholder scan: no task relies on unspecified follow-up work.
- Type consistency: new helper names are consistent across tasks: `PlayerListWindow`, `PlayerListWindow.Item`, `items(tracks:current:maxRows:)`, and `positionText(tracks:current:)`.
