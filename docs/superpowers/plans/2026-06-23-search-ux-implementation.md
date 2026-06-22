# Search UX Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make search feel faster and clearer by improving states, result caching, explicit pagination, row feedback, filters, and Apple Music-style result sections.

**Architecture:** Keep the existing SwiftUI app and current Bilibili search API. Move search state and result shaping into small, testable search-specific types, then keep `SearchView` focused on presentation and user actions.

**Tech Stack:** iOS 17, SwiftUI, Swift 5.10, async/await, XCTest, xcodegen.

## Global Constraints

- Do not add BV/link parsing back into the search bar.
- Do not replace the Bilibili search API.
- Do not introduce a database or third-party search library.
- Do not overhaul the global player UI as part of this work.
- Default search remains music-first.
- Query result cache is in-memory only and not persisted across app launches.

---

## File Structure

- Modify `project.yml`: add a `BiliMusicTests` XCTest target.
- Create `BiliMusicTests/SearchModelsTests.swift`: tests pure search models and grouping.
- Create `BiliMusic/Features/Search/SearchModels.swift`: search mode, cache key, cache snapshot, sections, and row state helpers.
- Modify `BiliMusic/Features/Search/SearchStore.swift`: owns mode, cached query results, explicit load-more state, and retry/broaden operations.
- Modify `BiliMusic/Features/Search/SearchView.swift`: renders idle/typing/searching/results/empty/error states, filter control, explicit load-more button, and row tap feedback.
- Modify `BiliMusic/Player/MusicFilter.swift`: add mode-aware search filtering for music, MV, and expanded search.
- Modify `BiliMusic/API/BiliClient.swift`: keep current search API but route `musicOnly` from `SearchResultMode`.

---

### Task 1: Add Search Models and XCTest Target

**Files:**
- Modify: `project.yml`
- Create: `BiliMusic/Features/Search/SearchModels.swift`
- Create: `BiliMusicTests/SearchModelsTests.swift`

**Interfaces:**
- Produces: `SearchResultMode`, `SearchCacheKey`, `SearchCachedSnapshot`, `SearchResultSections`.
- Consumes: existing `Track` and `TrackKey`.

- [ ] **Step 1: Add the test target to `project.yml`**

Add this sibling target next to `BiliMusic`:

```yaml
  BiliMusicTests:
    type: bundle.unit-test
    platform: iOS
    sources: [BiliMusicTests]
    dependencies:
      - target: BiliMusic
    settings:
      base:
        SWIFT_VERSION: "5.10"
        CODE_SIGNING_ALLOWED: NO
```

- [ ] **Step 2: Create `SearchModels.swift`**

```swift
import Foundation

enum SearchResultMode: String, CaseIterable, Identifiable {
    case music
    case mv
    case expanded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: "音乐"
        case .mv: "MV"
        case .expanded: "扩大"
        }
    }

    var usesBiliMusicOnlySearch: Bool {
        switch self {
        case .music, .mv: true
        case .expanded: false
        }
    }
}

struct SearchCacheKey: Hashable {
    let query: String
    let mode: SearchResultMode

    init(query: String, mode: SearchResultMode) {
        self.query = query
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.mode = mode
    }
}

struct SearchCachedSnapshot {
    var tracks: [Track]
    var nextPage: Int
    var activeKeywords: [String]
    var hasMoreResults: Bool
}

struct SearchResultSections {
    var bestMatch: Track?
    var songs: [Track]
    var mvs: [Track]

    static func make(from tracks: [Track]) -> SearchResultSections {
        let best = tracks.first
        let rest = Array(tracks.dropFirst())
        let mvTracks = rest.filter { track in
            track.typeID == 193 || track.title.localizedCaseInsensitiveContains("mv")
        }
        let mvKeys = Set(mvTracks.map(\.key))
        let songs = rest.filter { track in
            !mvKeys.contains { $0.matches(track) }
        }
        return SearchResultSections(bestMatch: best, songs: songs, mvs: mvTracks)
    }
}
```

- [ ] **Step 3: Create failing model tests**

```swift
import XCTest
@testable import BiliMusic

final class SearchModelsTests: XCTestCase {
    func testCacheKeyNormalizesWhitespaceAndCase() {
        let lhs = SearchCacheKey(query: "  Jay   Chou ", mode: .music)
        let rhs = SearchCacheKey(query: "jay chou", mode: .music)
        XCTAssertEqual(lhs, rhs)
    }

    func testModeControlsBiliMusicOnlySearch() {
        XCTAssertTrue(SearchResultMode.music.usesBiliMusicOnlySearch)
        XCTAssertTrue(SearchResultMode.mv.usesBiliMusicOnlySearch)
        XCTAssertFalse(SearchResultMode.expanded.usesBiliMusicOnlySearch)
    }

    func testSectionsPromoteFirstResultAndSplitMV() {
        let best = Track(bvid: "BV1", typeID: 3, title: "晴天", artist: "周杰伦",
                         coverURL: nil, duration: 269)
        let song = Track(bvid: "BV2", typeID: 3, title: "七里香", artist: "周杰伦",
                         coverURL: nil, duration: 295)
        let mv = Track(bvid: "BV3", typeID: 193, title: "稻香 MV", artist: "周杰伦",
                       coverURL: nil, duration: 260)

        let sections = SearchResultSections.make(from: [best, song, mv])

        XCTAssertEqual(sections.bestMatch?.bvid, "BV1")
        XCTAssertEqual(sections.songs.map(\.bvid), ["BV2"])
        XCTAssertEqual(sections.mvs.map(\.bvid), ["BV3"])
    }
}
```

- [ ] **Step 4: Generate the project and run the new tests**

Run:

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project BiliMusic.xcodeproj -scheme BiliMusicTests -destination 'generic/platform=iOS Simulator' test CODE_SIGNING_ALLOWED=NO
```

Expected before implementation is complete: the target exists and model tests compile after `SearchModels.swift` is added.

- [ ] **Step 5: Commit**

```bash
git add project.yml BiliMusic.xcodeproj BiliMusic/Features/Search/SearchModels.swift BiliMusicTests/SearchModelsTests.swift
git commit -m "test: add search model coverage"
```

---

### Task 2: Add SearchStore State, Cache, and Explicit Pagination

**Files:**
- Modify: `BiliMusic/Features/Search/SearchStore.swift`
- Modify: `BiliMusicTests/SearchModelsTests.swift`

**Interfaces:**
- Consumes: `SearchResultMode`, `SearchCacheKey`, `SearchCachedSnapshot`.
- Produces: `mode`, `setMode(_:query:)`, `retryCurrentSearch(preload:)`, `broadenCurrentSearch(preload:)`, `loadMore(preload:)`, `restoreCachedResultsIfAvailable(for:)`.

- [ ] **Step 1: Add store tests for cache restore and mode switching**

Append to `SearchModelsTests.swift`:

```swift
@MainActor
func testSearchStoreRestoresCachedSnapshot() {
    let store = SearchStore()
    let track = Track(bvid: "BV1", typeID: 3, title: "晴天", artist: "周杰伦",
                      coverURL: nil, duration: 269)
    store.storeCachedSnapshotForTesting(
        query: "晴天",
        mode: .music,
        snapshot: SearchCachedSnapshot(
            tracks: [track],
            nextPage: 4,
            activeKeywords: ["晴天"],
            hasMoreResults: true))

    let restored = store.restoreCachedResultsIfAvailable(for: " 晴天 ")

    XCTAssertTrue(restored)
    XCTAssertEqual(store.results.map(\.bvid), ["BV1"])
    XCTAssertTrue(store.hasMoreResults)
}

@MainActor
func testChangingModeClearsTransientResultsForSameQuery() {
    let store = SearchStore()
    store.setMode(.mv, query: "晴天")

    XCTAssertEqual(store.mode, .mv)
    XCTAssertTrue(store.results.isEmpty)
    XCTAssertFalse(store.hasMoreResults)
}
```

- [ ] **Step 2: Add SearchStore properties and cache helpers**

In `SearchStore`, add:

```swift
private(set) var mode: SearchResultMode = .music
private(set) var activeQuery = ""
private var resultCache: [SearchCacheKey: SearchCachedSnapshot] = [:]

@discardableResult
func restoreCachedResultsIfAvailable(for query: String) -> Bool {
    let key = SearchCacheKey(query: query, mode: mode)
    guard let snapshot = resultCache[key] else { return false }
    results = snapshot.tracks
    resultsQuery = key.query
    activeQuery = key.query
    activeKeywords = snapshot.activeKeywords
    nextPage = snapshot.nextPage
    hasMoreResults = snapshot.hasMoreResults
    errorMessage = nil
    searching = false
    loadingMore = false
    return true
}

func setMode(_ newMode: SearchResultMode, query: String) {
    guard mode != newMode else { return }
    mode = newMode
    resetTransientState(cancelTask: true)
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty {
        _ = restoreCachedResultsIfAvailable(for: text)
    }
}

func storeCachedSnapshotForTesting(query: String, mode: SearchResultMode, snapshot: SearchCachedSnapshot) {
    resultCache[SearchCacheKey(query: query, mode: mode)] = snapshot
}
```

- [ ] **Step 3: Update submit/load-more to use cache and mode**

Change `submitSearch` so it restores cached results before starting network work:

```swift
func submitSearch(_ query: String, preload: @escaping @MainActor ([Track]) -> Void) {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    searchTask?.cancel()
    let searchID = UUID()
    activeSearchID = searchID
    let hadCachedResults = restoreCachedResultsIfAvailable(for: text)
    if !hadCachedResults {
        resetTransientState(cancelTask: false)
    }
    searching = !hadCachedResults
    rememberSearch(text)
    searchTask = Task { [weak self] in
        await self?.search(text: text, searchID: searchID, preload: preload)
    }
}
```

Rename `loadMoreIfNeeded` to `loadMore` and keep the guard explicit:

```swift
func loadMore(preload: @escaping @MainActor ([Track]) -> Void) async {
    guard shouldShowResults(query: resultsQuery),
          hasMoreResults,
          !searching,
          !loadingMore,
          !activeKeywords.isEmpty else { return }
    await loadMorePage(preload: preload)
}
```

Move the current body of `loadMoreIfNeeded` into private `loadMorePage(preload:)`.

- [ ] **Step 4: Store snapshots after search and load more**

After first-page results are assigned:

```swift
cacheCurrentSnapshot()
```

After appended load-more results:

```swift
results.append(contentsOf: loaded)
cacheCurrentSnapshot()
preload(loaded)
```

Add:

```swift
private func cacheCurrentSnapshot() {
    guard !resultsQuery.isEmpty else { return }
    resultCache[SearchCacheKey(query: resultsQuery, mode: mode)] = SearchCachedSnapshot(
        tracks: results,
        nextPage: nextPage,
        activeKeywords: activeKeywords,
        hasMoreResults: hasMoreResults)
}
```

- [ ] **Step 5: Add retry and broaden methods**

```swift
func retryCurrentSearch(preload: @escaping @MainActor ([Track]) -> Void) {
    let text = activeQuery.isEmpty ? resultsQuery : activeQuery
    submitSearch(text, preload: preload)
}

func broadenCurrentSearch(preload: @escaping @MainActor ([Track]) -> Void) {
    let text = activeQuery.isEmpty ? resultsQuery : activeQuery
    setMode(.expanded, query: text)
    submitSearch(text, preload: preload)
}
```

- [ ] **Step 6: Run tests and build**

Run:

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project BiliMusic.xcodeproj -scheme BiliMusicTests -destination 'generic/platform=iOS Simulator' test CODE_SIGNING_ALLOWED=NO
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Expected: model/store tests pass and app builds.

- [ ] **Step 7: Commit**

```bash
git add project.yml BiliMusic.xcodeproj BiliMusic/Features/Search/SearchStore.swift BiliMusicTests/SearchModelsTests.swift
git commit -m "feat: cache search results and explicit pagination state"
```

---

### Task 3: Replace Auto Pagination With Clear Search States

**Files:**
- Modify: `BiliMusic/Features/Search/SearchView.swift`

**Interfaces:**
- Consumes: `store.mode`, `store.setMode`, `store.loadMore`, `store.broadenCurrentSearch`, `store.retryCurrentSearch`.
- Produces: clearer idle, typing, searching, result, empty, and error UI.

- [ ] **Step 1: Add local derived state helpers**

Inside `SearchView`, add:

```swift
private var trimmedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
}

private var isTypingUnsubmittedQuery: Bool {
    !trimmedQuery.isEmpty && trimmedQuery != store.resultsQuery && !store.searching
}
```

- [ ] **Step 2: Add filter control below the search field**

Under the search field HStack, add:

```swift
Picker("搜索范围", selection: Binding(
    get: { store.mode },
    set: { mode in store.setMode(mode, query: query) }
)) {
    ForEach(SearchResultMode.allCases) { mode in
        Text(mode.title).tag(mode)
    }
}
.pickerStyle(.segmented)
.padding(.horizontal, 16)
```

- [ ] **Step 3: Replace auto-load sentinel with explicit button**

Remove the `Color.clear.onAppear` block currently used near the bottom of each row. Below the `ForEach`, add:

```swift
if store.loadingMore {
    ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
} else if store.hasMoreResults {
    Button {
        Task {
            await store.loadMore { tracks in
                engine.preload(tracks: tracks, limit: 1, delay: .milliseconds(700))
            }
        }
    } label: {
        Text("加载更多")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
    }
    .buttonStyle(.plain)
} else {
    Text("没有更多结果")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
}
```

- [ ] **Step 4: Render typing and compact loading states**

In the `LazyVStack`, before result rendering, add:

```swift
if isTypingUnsubmittedQuery {
    typingPrompt
}
if store.searching {
    HStack(spacing: 10) {
        ProgressView().scaleEffect(0.8)
        Text("正在搜索音乐…")
            .font(.footnote)
            .foregroundStyle(.secondary)
        Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
}
```

Add this computed view:

```swift
private var typingPrompt: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("按回车搜索 “\(trimmedQuery)”")
            .font(.subheadline.weight(.semibold))
        Text("默认只显示音乐内容，可切换到 MV 或扩大搜索。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
    .padding(.horizontal, 16)
    .padding(.top, 8)
}
```

- [ ] **Step 5: Add retry and broaden actions to empty/error states**

For error state:

```swift
VStack(spacing: 10) {
    Text(errorMessage)
        .font(.caption)
        .foregroundStyle(.red)
    Button("重试") {
        store.retryCurrentSearch { tracks in
            engine.preload(tracks: tracks, limit: 2, delay: .milliseconds(500))
        }
    }
}
.frame(maxWidth: .infinity)
.padding(.vertical, 20)
```

For no-result state:

```swift
ContentUnavailableView {
    Label("没有找到音乐结果", systemImage: "music.note.list")
} description: {
    Text("当前只显示音乐内容，可以扩大搜索范围。")
} actions: {
    Button("扩大搜索") {
        store.broadenCurrentSearch { tracks in
            engine.preload(tracks: tracks, limit: 2, delay: .milliseconds(500))
        }
    }
}
.frame(maxWidth: .infinity)
.padding(.top, 36)
```

- [ ] **Step 6: Run build**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add BiliMusic/Features/Search/SearchView.swift
git commit -m "feat: clarify search states and pagination"
```

---

### Task 4: Add Row Tap Feedback and Remove Fake Ellipsis

**Files:**
- Modify: `BiliMusic/Features/Search/SearchView.swift`

**Interfaces:**
- Consumes: existing `PlayerEngine.play(tracks:startAt:)`.
- Produces: local `preparingTrackKey` row feedback.

- [ ] **Step 1: Add preparing state**

At the top of `SearchView`, add:

```swift
@State private var preparingTrackKey: TrackKey?
```

- [ ] **Step 2: Add row state helper**

```swift
private func isPreparing(_ track: Track) -> Bool {
    preparingTrackKey.map { $0.matches(track) } ?? false
}
```

- [ ] **Step 3: Update search row tap**

Replace the row button action with:

```swift
Button {
    preparingTrackKey = track.key
    Task {
        await engine.play(tracks: store.results, startAt: index)
        preparingTrackKey = nil
    }
} label: {
    searchResultRow(track: track)
        .padding(.horizontal, 14)
}
.buttonStyle(.plain)
```

- [ ] **Step 4: Add a search-specific row wrapper**

Add inside `SearchView`:

```swift
private func searchResultRow(track: Track) -> some View {
    HStack(spacing: 14) {
        TrackRow(
            track: track,
            isPlaying: engine.current.map { track.key.matches($0) } ?? false)
        if isPreparing(track) {
            ProgressView()
                .scaleEffect(0.75)
        }
    }
}
```

Then remove the fake trailing affordance for search by changing `TrackRow` to accept:

```swift
var showsTrailingIcon = true
```

and wrap the existing trailing image:

```swift
if showsTrailingIcon {
    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "ellipsis")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isPlaying ? AppTheme.accent : .secondary)
        .frame(width: 28, height: 28)
}
```

Call it from search as:

```swift
TrackRow(track: track, isPlaying: engine.current.map { track.key.matches($0) } ?? false, showsTrailingIcon: false)
```

- [ ] **Step 5: Run build**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add BiliMusic/Features/Search/SearchView.swift
git commit -m "feat: add search result tap feedback"
```

---

### Task 5: Add Mode-Aware Filtering

**Files:**
- Modify: `BiliMusic/Player/MusicFilter.swift`
- Modify: `BiliMusic/Features/Search/SearchStore.swift`
- Modify: `BiliMusicTests/SearchModelsTests.swift`

**Interfaces:**
- Consumes: `SearchResultMode`.
- Produces: `MusicFilter.isSearchResult(_:query:mode:)`.

- [ ] **Step 1: Add filter tests**

Append:

```swift
func testExpandedSearchStillRejectsObviousNonMusic() {
    let game = Track(bvid: "BV4", typeID: 17, title: "游戏攻略 教程", artist: "UP",
                     coverURL: nil, duration: 300)
    XCTAssertFalse(MusicFilter.isSearchResult(game, query: "晴天", mode: .expanded))
}

func testMVModePrefersMVSignals() {
    let mv = Track(bvid: "BV5", typeID: 193, title: "晴天 Official MV", artist: "周杰伦",
                   coverURL: nil, duration: 269)
    XCTAssertTrue(MusicFilter.isSearchResult(mv, query: "晴天", mode: .mv))
}
```

- [ ] **Step 2: Add mode-aware filter method**

In `MusicFilter`, add:

```swift
static func isSearchResult(_ track: Track, query: String? = nil, mode: SearchResultMode) -> Bool {
    switch mode {
    case .music:
        return isSearchResultMusic(track, query: query)
    case .mv:
        guard isSearchResultMusic(track, query: query) else { return false }
        let text = (track.title + " " + track.artist).lowercased()
        return track.typeID == 193 || text.contains("mv") || text.contains("music video")
    case .expanded:
        guard (45...900).contains(track.duration) else { return false }
        let text = (track.title + " " + track.artist).lowercased()
        if nonMusicHints.contains(where: { text.contains($0.lowercased()) }) {
            return musicHints.contains(where: { text.contains($0.lowercased()) })
        }
        if let query, !isRelevantToSearchQuery(track, query: query) {
            return false
        }
        return true
    }
}
```

- [ ] **Step 3: Route SearchStore search through mode**

In `searchBatch`, add `mode: SearchResultMode` parameter and replace:

```swift
.filter { MusicFilter.isSearchResultMusic($0, query: query) }
```

with:

```swift
.filter { MusicFilter.isSearchResult($0, query: query, mode: mode) }
```

Call BiliClient with:

```swift
try await client.search(keyword: keyword, page: page, musicOnly: mode.usesBiliMusicOnlySearch)
```

- [ ] **Step 4: Pass `mode` from first-page and load-more calls**

Every call to `Self.searchBatch` should include:

```swift
mode: mode
```

- [ ] **Step 5: Run tests and build**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project BiliMusic.xcodeproj -scheme BiliMusicTests -destination 'generic/platform=iOS Simulator' test CODE_SIGNING_ALLOWED=NO
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Expected: tests pass and app builds.

- [ ] **Step 6: Commit**

```bash
git add BiliMusic/Player/MusicFilter.swift BiliMusic/Features/Search/SearchStore.swift BiliMusicTests/SearchModelsTests.swift
git commit -m "feat: add search result filter modes"
```

---

### Task 6: Add Apple Music-Style Result Sections and Landing Content

**Files:**
- Modify: `BiliMusic/Features/Search/SearchView.swift`
- Modify: `BiliMusic/Features/Search/SearchModels.swift`

**Interfaces:**
- Consumes: `SearchResultSections.make(from:)`, `PlaybackHistoryStore.shared.entries`, `CacheStore.shared.entries`.
- Produces: best-match, songs, MV, and landing sections.

- [ ] **Step 1: Add derived sections in SearchView**

```swift
private var resultSections: SearchResultSections {
    SearchResultSections.make(from: store.results)
}
```

- [ ] **Step 2: Replace single result block with sections**

When `store.shouldShowResults(query: query)` is true, render:

```swift
if let best = resultSections.bestMatch {
    resultSection(title: "最佳匹配", tracks: [best])
}
if !resultSections.songs.isEmpty {
    resultSection(title: "歌曲", tracks: resultSections.songs)
}
if !resultSections.mvs.isEmpty {
    resultSection(title: "MV", tracks: resultSections.mvs)
}
```

Add:

```swift
private func resultSection(title: String, tracks: [Track]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 6)
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { offset, track in
                let index = store.results.firstIndex { $0.key.matches(track) } ?? offset
                Button {
                    preparingTrackKey = track.key
                    Task {
                        await engine.play(tracks: store.results, startAt: index)
                        preparingTrackKey = nil
                    }
                } label: {
                    searchResultRow(track: track)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.plain)
                if offset != tracks.count - 1 {
                    Divider().padding(.leading, 84)
                }
            }
        }
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}
```

- [ ] **Step 3: Add landing sections**

When query is empty and not searching, show:

```swift
landingSection(
    title: "最近播放",
    tracks: Array(PlaybackHistoryStore.shared.entries.prefix(6).map(\.track)))
landingSection(
    title: "已缓存",
    tracks: Array(CacheStore.shared.entries.prefix(6).map(\.track)))
```

Add:

```swift
private func landingSection(title: String, tracks: [Track]) -> some View {
    guard !tracks.isEmpty else {
        return AnyView(EmptyView())
    }
    return AnyView(
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 6)
            VStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        Task { await engine.play(tracks: tracks, startAt: index) }
                    } label: {
                        TrackRow(track: track, isPlaying: engine.current.map { track.key.matches($0) } ?? false)
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    )
}
```

- [ ] **Step 4: Ensure stores are loaded on search page entry**

In `.task`, extend the existing history load:

```swift
await store.loadHistory()
await PlaybackHistoryStore.shared.loadIfNeeded()
await CacheStore.shared.loadIfNeeded()
```

- [ ] **Step 5: Run build**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add BiliMusic/Features/Search/SearchView.swift BiliMusic/Features/Search/SearchModels.swift
git commit -m "feat: organize search results into music sections"
```

---

## Self-Review

- Spec coverage: Phase A state model, result cache, explicit load-more, row feedback, filter controls, and broadened fallback are covered by Tasks 2-5. Phase B best match, songs/MV grouping, and landing content are covered by Task 6.
- Scope: The plan is focused on search UX. It does not alter global player architecture, storage choice, or network API beyond routing search mode.
- Type consistency: `SearchResultMode`, `SearchCacheKey`, `SearchCachedSnapshot`, and `SearchResultSections` are defined in Task 1 and consumed by later tasks with matching names.
- Verification: Every task ends with tests or an iOS Simulator build; tasks that modify pure logic include XCTest coverage.
