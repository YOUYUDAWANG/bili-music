# Phase 01: playback-critical-path-and-responsiveness - Pattern Map

**Mapped:** 2026-06-26
**Files analyzed:** 17
**Analogs found:** 17 / 17

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `BiliMusic/Player/PlayerEngine.swift` | service | event-driven | `BiliMusic/Player/PlayerEngine.swift` | exact |
| `BiliMusic/Player/StreamResolver.swift` | service | request-response | `BiliMusic/Player/StreamResolver.swift` | exact |
| `BiliMusic/Player/PlaybackDiagnostics.swift` | utility | event-driven | `BiliMusic/Player/StreamResolver.swift` | role-match |
| `BiliMusic/Features/Search/SearchView.swift` | component | request-response | `BiliMusic/Features/Search/SearchView.swift` | exact |
| `BiliMusic/Features/Search/SearchStore.swift` | store | request-response | `BiliMusic/Features/Search/SearchStore.swift` | exact |
| `BiliMusic/Features/Home/HomeView.swift` | component | request-response | `BiliMusic/Features/Home/HomeView.swift` | exact |
| `BiliMusic/Player/RecommendationEngine.swift` | service | batch | `BiliMusic/Player/RecommendationEngine.swift` | exact |
| `BiliMusic/Design/CachedAsyncImage.swift` | component/provider | file-I/O | `BiliMusic/Design/CachedAsyncImage.swift` | exact |
| `BiliMusic/Features/RootView.swift` | component/provider | event-driven | `BiliMusic/Features/RootView.swift` | exact |
| `BiliMusic/Support/UITestFixtures.swift` | utility | transform | `BiliMusic/Support/UITestFixtures.swift` | exact |
| `BiliMusicTests/PlaybackCriticalPathTests.swift` | test | event-driven | `BiliMusicTests/SearchModelsTests.swift` | role-match |
| `BiliMusicTests/PlaybackDiagnosticsTests.swift` | test | event-driven | `BiliMusicTests/SearchModelsTests.swift` | role-match |
| `BiliMusicTests/PreparedStreamRetryTests.swift` | test | request-response | `BiliMusicTests/SearchModelsTests.swift` | role-match |
| `BiliMusicTests/SearchFocusTests.swift` | test | request-response | `BiliMusicTests/SearchModelsTests.swift` | exact role |
| `BiliMusicTests/RecommendationSchedulingTests.swift` | test | batch | `BiliMusicTests/SearchModelsTests.swift` | role-match |
| `BiliMusicTests/ImageCacheTests.swift` | test | file-I/O | `BiliMusicTests/SearchModelsTests.swift` | role-match |
| `BiliMusicUITests/PlayerChromeUITests.swift` | test | event-driven | `BiliMusicUITests/PlayerChromeUITests.swift` | exact |

## Pattern Assignments

### `BiliMusic/Player/PlayerEngine.swift` (service, event-driven)

**Analog:** `BiliMusic/Player/PlayerEngine.swift`

**Imports and logging pattern** (lines 1-7):
```swift
import AVFoundation
import MediaPlayer
import Observation
import OSLog
import UIKit

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "player")
```

**Immediate current-track assignment pattern** (lines 175-193):
```swift
func play(tracks: [Track], startAt index: Int, queueMode: QueueMode? = nil) async {
#if DEBUG
    if UITestFixtures.enabled {
        installUITestFixture(tracks: tracks, startAt: index)
        return
    }
#endif
    prefetchTask?.cancel()
    queuePrefetchTask?.cancel()
    autoMVTask?.cancel()
    queue = tracks
    queueIndex = index
    playedKeys = []
    manualPlaybackModeOverride = nil
    if let queueMode {
        self.queueMode = queueMode
    }
    playbackMode = preferredModeForNewTrack()
    await startCurrent()
}
```

**Critical source resolution pattern** (lines 452-521):
```swift
private func startCurrent(resumeAt: Double = 0) async {
    isMiniPlayerHidden = false
    guard var track = current else { return }
    let generation = UUID()
    playbackGeneration = generation
    state = .loading
    currentTime = resumeAt
    lyrics = []
    videoAvailable = false
    currentAudioQuality = nil
    currentAudioBandwidth = nil
    autoMVTask?.cancel()
    postPlaybackTask?.cancel()
    queuePrefetchTask?.cancel()
    do {
        let url: URL
        let isLocal: Bool
        if playbackMode == .mv {
            if track.cid == nil {
                track = try await fillPlaybackPage(for: track)
                queue[queueIndex] = track
            }
            if let prepared = preparedVideoStream(for: track), prepared.cid == track.cid {
                url = prepared.url
            } else {
                url = try await client.videoStream(bvid: track.bvid, cid: track.cid!)
                preparedVideoStreams[track.key] = PreparedVideoStream(
                    url: url, cid: track.cid!, fetchedAt: Date())
            }
            isLocal = false
            videoAvailable = true
        } else if let cached = CacheStore.shared.entry(for: track) {
            track.cid = cached.cid
            track.duration = cached.duration
            queue[queueIndex] = track
            url = CacheStore.audioDir.appendingPathComponent(cached.fileName)
            isLocal = true
            currentAudioQuality = cached.quality
            currentAudioBandwidth = nil
        } else if let prepared = streamResolver.cachedAudio(for: track) {
            track.cid = prepared.cid
            track.duration = prepared.duration
            queue[queueIndex] = track
            url = prepared.url
            isLocal = false
            currentAudioQuality = prepared.quality
            currentAudioBandwidth = prepared.bandwidth
        } else {
            let prepared = try await streamResolver.prepareAudio(
                for: track,
                preferredQuality: Self.playbackQuality)
            track.cid = prepared.cid
            track.duration = prepared.duration
            queue[queueIndex] = track
            url = prepared.url
            isLocal = false
            currentAudioQuality = prepared.quality
            currentAudioBandwidth = prepared.bandwidth
        }
        guard playbackGeneration == generation, current.map({ track.key.matches($0) }) ?? false else { return }
        startPlayback(url: url, isLocal: isLocal, resumeAt: resumeAt)
        try? AVAudioSession.sharedInstance().setActive(true)
        state = .playing
        let shouldRecordHistory = resumeAt < 1 || !playedKeys.contains(track.key)
        playedKeys.insert(track.key)
        if shouldRecordHistory {
            PlaybackHistoryStore.shared.record(track)
        }
        schedulePostPlaybackWork(for: track, generation: generation, isLocal: isLocal)
    } catch {
```

**Error handling pattern** (lines 522-531):
```swift
    } catch {
        guard playbackGeneration == generation else { return }
        if playbackMode == .mv {
            videoAvailable = false
            playbackMode = .music
            await startCurrent(resumeAt: resumeAt)
            return
        }
        state = .failed(error.localizedDescription)
    }
}
```

**AVPlayer item and observer pattern** (lines 701-724, 735-791):
```swift
private func startPlayback(url: URL, isLocal: Bool = false, resumeAt: Double = 0) {
    let generation = playbackGeneration
    if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    statusObserver?.invalidate()
    bufferObserver?.invalidate()
    player?.pause()
    player?.replaceCurrentItem(with: nil)
    timeObserver = nil
    endObserver = nil
    statusObserver = nil
    bufferObserver = nil
    wantsPlayback = true
    let asset = isLocal
        ? AVURLAsset(url: url)
        : AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": BiliClient.headers])
    let item = AVPlayerItem(asset: asset)
    item.preferredForwardBufferDuration = isLocal ? 0 : 30
    item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = false
    self.player = player
    // ...
    statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
        Task { @MainActor in
            guard let self else { return }
            switch player.timeControlStatus {
            case .playing:
                self.state = .playing
            case .paused:
                self.state = self.wantsPlayback ? .loading : .paused
            case .waitingToPlayAtSpecifiedRate:
                self.state = .loading
            @unknown default:
                break
            }
        }
    }
    // ...
    if resumeAt > 0 {
        player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
    }
    player.playImmediately(atRate: 1)
    updateNowPlayingInfo()
}
```

**Post-start enrichment pattern** (lines 663-689):
```swift
private func schedulePostPlaybackWork(for track: Track, generation: UUID, isLocal: Bool) {
    postPlaybackTask?.cancel()
    postPlaybackTask = Task(priority: .utility) { [weak self, track, generation, isLocal] in
        guard let self else { return }

        try? await Task.sleep(for: .milliseconds(900))
        guard self.isCurrent(track, generation: generation) else { return }
        await self.loadCover(for: track, generation: generation)

        try? await Task.sleep(for: .milliseconds(900))
        guard self.isCurrent(track, generation: generation) else { return }
        await self.loadLyrics(for: track, generation: generation)

        try? await Task.sleep(for: .milliseconds(900))
        guard self.isCurrent(track, generation: generation) else { return }
        await self.prepareVideoIfUseful(for: track, generation: generation)

        try? await Task.sleep(for: .milliseconds(600))
        guard self.isCurrent(track, generation: generation) else { return }
        await self.prefetchUpcomingTracks()

        if !isLocal, UserDefaults.standard.bool(forKey: "autoCache") {
            try? await Task.sleep(for: .seconds(8))
            guard self.isCurrent(track, generation: generation) else { return }
            await DownloadManager.shared.download(track: track)
        }
    }
}
```

Planner notes:
- Keep `queue`/`queueIndex` assignment before any source resolution.
- Add diagnostics checkpoints around the existing `play`, source-resolution branches, `AVPlayerItem` creation, `playImmediately`, and first `.playing` observer.
- Add prepared-stream retry as a narrow extension of the prepared-audio branch and `startPlayback` failure/status handling; do not persist remote playurl values.
- Move history recording off the pre-play request path if tests prove it competes with first sound.

---

### `BiliMusic/Player/StreamResolver.swift` (service, request-response)

**Analog:** `BiliMusic/Player/StreamResolver.swift`

**Imports and logger pattern** (lines 1-8):
```swift
import Foundation
import OSLog

private let streamLog = Logger(subsystem: "com.fubuki.BiliMusic", category: "stream")

/// 负责把 Track 解析成可播放的音频流,并维护短期 playurl 缓存。
/// URL 有时效,只做内存级预取,不持久化。
@MainActor
```

**Prepared stream cache and invalidation pattern** (lines 27-53):
```swift
func cachedAudio(for track: Track) -> PreparedAudioStream? {
    let key = track.key
    let fallbackKey = TrackKey(bvid: track.bvid, cid: nil)
    guard let prepared = preparedStreams[key] ?? preparedStreams[fallbackKey] else { return nil }
    if Date().timeIntervalSince(prepared.fetchedAt) < 90 * 60 {
        return prepared
    }
    preparedStreams[key] = nil
    preparedStreams[fallbackKey] = nil
    preparingStreams[key] = nil
    preparingStreams[fallbackKey] = nil
    return nil
}

func invalidateAudio(for track: Track) {
    preparedStreams[track.key] = nil
    preparingStreams[track.key] = nil
    if track.cid != nil {
        let fallbackKey = TrackKey(bvid: track.bvid, cid: nil)
        preparedStreams[fallbackKey] = nil
        preparingStreams[fallbackKey] = nil
    }
}
```

**Coalesced source resolution pattern** (lines 55-99):
```swift
func prepareAudio(for track: Track, preferredQuality: Int) async throws -> PreparedAudioStream {
    if let prepared = cachedAudio(for: track) {
        return prepared
    }
    if let task = preparingStreams[track.key] {
        return try await task.value
    }

    let task = Task<PreparedAudioStream, Error> { [client] in
        let start = CFAbsoluteTimeGetCurrent()
        let meta = try await Self.resolveCidDuration(
            client: client,
            bvid: track.bvid,
            cid: track.cid,
            duration: track.duration)
        let stream = try await client.audioStream(
            bvid: track.bvid,
            cid: meta.cid,
            preferredQuality: preferredQuality)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        streamLog.debug("prepare audio(bvid:\(track.bvid)) \(elapsed, format: .fixed(precision: 1))ms")
        return PreparedAudioStream(
            url: stream.url,
            cid: meta.cid,
            duration: meta.duration,
            quality: stream.quality,
            bandwidth: stream.bandwidth,
            fetchedAt: Date())
    }

    preparingStreams[track.key] = task
    do {
        let prepared = try await task.value
        let resolvedKey = TrackKey(bvid: track.bvid, cid: prepared.cid)
        preparedStreams[resolvedKey] = prepared
        if resolvedKey != track.key {
            preparedStreams[track.key] = prepared
        }
        preparingStreams[track.key] = nil
        return prepared
    } catch {
        preparingStreams[track.key] = nil
        throw error
    }
}
```

Planner notes:
- Extend this resolver or its call site to expose source kind: `.localCache`, `.preparedRemote`, `.freshRemote`.
- Retry logic should call `invalidateAudio(for:)` once for `.preparedRemote` playback failure and then re-run fresh resolution.
- Diagnostics may log bvid, cid, source kind, quality, and durations; never log Cookie headers or full stream URLs.

---

### `BiliMusic/Player/PlaybackDiagnostics.swift` (utility, event-driven)

**Analog:** `BiliMusic/Player/StreamResolver.swift` for OSLog style, plus `PlayerEngine.startPlayback` for checkpoint locations.

**Logger category pattern** (source `BiliMusic/Player/StreamResolver.swift`, lines 1-5):
```swift
import Foundation
import OSLog

private let streamLog = Logger(subsystem: "com.fubuki.BiliMusic", category: "stream")
```

**Playback-state checkpoint seam** (source `BiliMusic/Player/PlayerEngine.swift`, lines 735-747):
```swift
statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
    Task { @MainActor in
        guard let self else { return }
        switch player.timeControlStatus {
        case .playing:
            self.state = .playing
        case .paused:
            self.state = self.wantsPlayback ? .loading : .paused
        case .waitingToPlayAtSpecifiedRate:
            self.state = .loading
        @unknown default:
            break
        }
```

Planner notes:
- New file should be a small value-type or `@MainActor` helper that records tap, current assignment, source resolution, item creation, play request, and first observed `.playing`.
- Use existing `Logger(subsystem: "com.fubuki.BiliMusic", category: "...")`.
- Keep diagnostics injectable/testable, with a no-op/default sink for production and an in-memory sink for tests.
- Security rule from validation: no Cookie, request headers, or full stream URLs in diagnostic output.

---

### `BiliMusic/Features/Search/SearchView.swift` (component, request-response)

**Analog:** `BiliMusic/Features/Search/SearchView.swift`

**SwiftUI searchable pattern** (lines 22-49):
```swift
var body: some View {
    NavigationStack {
        List {
            searchContent
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("searchList")
        .scrollContentBackground(.hidden)
        .background(AppTheme.groupedBackground)
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "歌名或 UP 主"
        ) {
            searchSuggestions
        }
        .searchScopes(searchModeBinding, activation: .onSearchPresentation) {
            ForEach(SearchResultMode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
                    .accessibilityIdentifier("searchScope_\(mode.rawValue)")
            }
        }
        .onSubmit(of: .search) {
            submitSearch()
        }
```

**Current typing-triggered network pattern to remove** (lines 65-77):
```swift
.onChange(of: query) { _, newValue in
    store.queryDidChange(newValue)
    debounceTask?.cancel()

    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    if store.restoreCachedResultsIfAvailable(for: trimmed) { return }
    debounceTask = Task {
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        await MainActor.run { debouncedSearch() }
    }
}
```

**Local empty-query content pattern** (lines 84-137):
```swift
private var recentTracks: [Track] {
    Array(history.entries.prefix(6).map(\.track))
}

@ViewBuilder
private var searchContent: some View {
    if trimmedQuery.isEmpty {
        if !recentTracks.isEmpty {
            trackSection(title: "最近播放", tracks: recentTracks)
        } else {
            unavailableRow {
                ContentUnavailableView(
                    "搜索音乐",
                    systemImage: "magnifyingglass",
                    description: Text("输入歌名或 UP 主查找音乐内容")
                )
            }
        }
    } else if store.searching {
        loadingRow
    } else if let errorMessage = store.errorMessage {
        errorRow(errorMessage)
    } else if store.shouldShowNoResults(query: query) {
        noResultsRow
    } else if store.shouldShowResults(query: query), let sections = store.sections {
        resultSections(sections)
        paginationControl
    }
}

@ViewBuilder
private var searchSuggestions: some View {
    if store.historyLoaded, !store.searchHistory.isEmpty {
        ForEach(Array(store.searchHistory.prefix(8)), id: \.self) { term in
            Label(term, systemImage: "clock")
                .searchCompletion(term)
        }
        Button(role: .destructive) {
            store.clearHistory()
        } label: {
            Label("清空搜索历史", systemImage: "trash")
        }
    }
}
```

**Explicit submit-only network pattern** (lines 289-303):
```swift
private func submitSearch() {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    store.submitSearch(text) { tracks in
        engine.preload(tracks: tracks, limit: 2, delay: .milliseconds(500))
    }
}

private func debouncedSearch() {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    store.submitSearch(text) { tracks in
        engine.preload(tracks: tracks, limit: 2, delay: .milliseconds(500))
    }
}
```

Planner notes:
- Remove or disable `debouncedSearch()` and the task scheduled from `.onChange(of: query)`.
- Keep `.onChange` limited to `store.queryDidChange(newValue)` and cheap local state.
- Add cached-song local section from `CacheStore.shared.entries.map(\.track)` beside recent playback.
- Do not preload result images or Bilibili search on focus/typing.

---

### `BiliMusic/Features/Search/SearchStore.swift` (store, request-response)

**Analog:** `BiliMusic/Features/Search/SearchStore.swift`

**Observable store pattern** (lines 1-16):
```swift
import Foundation
import Observation

@Observable
@MainActor
final class SearchStore {
    private(set) var results: [Track] = []
    private(set) var sections: SearchResultSections?
    private(set) var searchHistory: [String] = []
    private(set) var searching = false
    private(set) var errorMessage: String?
    private(set) var historyLoaded = false
    private(set) var resultsQuery = ""
    private(set) var hasMoreResults = false
    private(set) var loadingMore = false
    private(set) var mode: SearchResultMode = .music
```

**Cheap query-change pattern** (lines 46-63):
```swift
func queryDidChange(_ query: String) {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty {
        guard mode != .music || !resultsQuery.isEmpty || !results.isEmpty || !activeQuery.isEmpty else { return }
        mode = .music
        resetTransientState(cancelTask: true)
    } else if text != resultsQuery {
        let shouldReset = !resultsQuery.isEmpty || !results.isEmpty || !activeQuery.isEmpty
        if mode != .music {
            mode = .music
        }
        guard shouldReset else {
            return
        }
        resetTransientState(cancelTask: true)
    }
}
```

**Explicit submit/network pattern** (lines 65-81):
```swift
func submitSearch(_ query: String, preload: @escaping @MainActor ([Track]) -> Void) {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    searchTask?.cancel()
    let searchID = UUID()
    let hadCachedResults = restoreCachedResultsIfAvailable(for: text)
    if !hadCachedResults {
        resetTransientState(cancelTask: false)
    }
    activeSearchID = searchID
    activeQuery = text
    searching = !hadCachedResults
    rememberSearch(text)
    searchTask = Task { [weak self] in
        await self?.search(text: text, searchID: searchID, preload: preload)
    }
}
```

**Reset pattern** (lines 210-225):
```swift
private func resetTransientState(cancelTask: Bool) {
    if cancelTask {
        searchTask?.cancel()
    }
    activeSearchID = UUID()
    searching = false
    errorMessage = nil
    results = []
    sections = nil
    resultsQuery = ""
    activeQuery = ""
    activeKeywords = []
    nextPage = 1
    hasMoreResults = false
    loadingMore = false
}
```

Planner notes:
- Keep `queryDidChange` local and deterministic.
- If tests need network-call assertions, add a narrow injectable search client or closure seam rather than calling Bilibili.
- Search focus tests should assert `searching == false`, no `searchTask` side effects if exposed through a test seam, and local suggestions are derived from stores.

---

### `BiliMusic/Features/Home/HomeView.swift` (component, request-response)

**Analog:** `BiliMusic/Features/Home/HomeView.swift`

**State and row tap pattern** (lines 1-35):
```swift
import SwiftUI

struct HomeView: View {
    @Environment(PlayerEngine.self) private var engine
    @Binding var showSettings: Bool
    @State private var tracks: [Track] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var trackTapTrigger = 0
    @State private var refreshTrigger = 0

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppTheme.error).font(.caption)
                }
                if !tracks.isEmpty {
                    Section {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            Button {
                                trackTapTrigger += 1
                                Task { await engine.play(tracks: tracks, startAt: index) }
                            } label: {
                                TrackRow(track: track, isPlaying: engine.current.map { track.key.matches($0) } ?? false)
                            }
                            .accessibilityIdentifier("homeTrackRow\(index)")
                            .buttonStyle(.plain)
```

**Load/replace-visible-list pattern** (lines 68-109):
```swift
.refreshable { await load() }
.overlay {
    if loading && tracks.isEmpty { ProgressView() }
    else if tracks.isEmpty && errorMessage == nil {
        ContentUnavailableView("还没有音乐推荐", systemImage: "music.note.list",
                               description: Text(CookieStore.isLoggedIn
                                   ? "在 B 站收藏些喜欢的歌,这里会按收藏夹给你推荐"
                                   : "去设置扫码登录,即可用你的收藏夹生成推荐"))
    }
}
.task {
    if tracks.isEmpty { await load() }
}

private func load() async {
#if DEBUG
    if UITestFixtures.enabled {
        errorMessage = nil
        tracks = UITestFixtures.homeTracks
        engine.preload(tracks: tracks, limit: 0, delay: .zero)
        return
    }
#endif
    loading = true
    defer { loading = false }
    errorMessage = nil
    let excluded = RecentHomeFeedStore.shared.recentKeys()
    var result = await fetch(excluding: excluded)
    if result.isEmpty, !excluded.isEmpty {
        result = await fetch(excluding: [])
    }
    if result.isEmpty {
        errorMessage = CookieStore.isLoggedIn ? "暂时没有找到合适的音乐推荐" : nil
    } else {
        RecentHomeFeedStore.shared.record(result.map(\.bvid))
        tracks = result
        engine.preload(tracks: result, limit: 3, delay: .milliseconds(700))
    }
}
```

**Recommendation fetch pattern** (lines 112-117):
```swift
private func fetch(excluding excluded: Set<TrackKey>) async -> [Track] {
    await RecommendationEngine().recommendations(
        mode: .home,
        context: .init(current: engine.current, queue: engine.queue, excludedKeys: excluded),
        limit: 30)
}
```

Planner notes:
- First playback from a Home row must not call `load()` or mutate `tracks`.
- If recommendations become stale from playback history changes, keep that stale marker internal until manual refresh.
- Preserve current behavior that error text can appear above existing rows without replacing the list.

---

### `BiliMusic/Player/RecommendationEngine.swift` (service, batch)

**Analog:** `BiliMusic/Player/RecommendationEngine.swift`

**Imports/cache actor pattern** (lines 1-35):
```swift
import Foundation
import OSLog

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "recommend")

private struct ScoredTrack {
    let track: Track
    let score: Int
}

private actor RecommendationPoolCache {
    static let shared = RecommendationPoolCache()

    private var values: [String: (date: Date, pool: [ScoredTrack])] = [:]
    private let ttl: TimeInterval = 8 * 60

    func pool(for key: String) -> [ScoredTrack]? {
        guard let cached = values[key],
              Date().timeIntervalSince(cached.date) < ttl else {
            values[key] = nil
            return nil
        }
        return cached.pool
    }

    func store(_ pool: [ScoredTrack], for key: String) {
        values[key] = (Date(), pool)
        if values.count > 24, let oldest = values.min(by: { $0.value.date < $1.value.date })?.key {
            values.removeValue(forKey: oldest)
        }
    }
}
```

**Recommendation request/batch pattern** (lines 93-116):
```swift
func recommendations(mode: Mode, context: Context, limit: Int = 24) async -> [Track] {
    let snapshot = await Self.makeSnapshot(mode: mode)
    let cacheKey = Self.cacheKey(mode: mode, context: context, snapshot: snapshot)

    if mode != .radio, let cached = await RecommendationPoolCache.shared.pool(for: cacheKey) {
        let usable = Self.usable(cached, mode: mode, snapshot: snapshot)
        let available = usable.filter { !Self.contains(context.excludedKeys, matching: $0.track) }
        if available.count >= limit || (context.excludedKeys.isEmpty && !available.isEmpty) {
            return Self.select(from: usable, mode: mode, excluded: context.excludedKeys, limit: limit)
        }
    }

    let candidates = await buildCandidates(mode: mode, context: context, snapshot: snapshot)
    let pool = await Task.detached(priority: .userInitiated) {
        Self.scoredPool(candidates, mode: mode, context: context, snapshot: snapshot)
    }.value
    if mode != .radio {
        await RecommendationPoolCache.shared.store(pool, for: cacheKey)
    }
    let usable = Self.usable(pool, mode: mode, snapshot: snapshot)
    return Self.select(from: usable, mode: mode, excluded: context.excludedKeys, limit: limit)
}
```

**Snapshot pattern to gate away from first playback** (lines 282-300):
```swift
@MainActor
private static func makeSnapshot(mode: Mode) async -> Snapshot {
    await CacheStore.shared.loadIfNeeded()
    await PlaybackHistoryStore.shared.loadIfNeeded()
    if mode != .radio {
        await FavoriteManager.shared.syncAllFavoriteIDs()
    }
    let historyEntries = PlaybackHistoryStore.shared.entries
    let cacheEntries = CacheStore.shared.entries
    let favoriteBVIDs = FavoriteManager.shared.favoriteBVIDs
    let favoriteFolder = await favoriteFolderSnapshot(mode: mode)
    return Snapshot(
        historyTracks: historyEntries.map(\.track),
        recentKeys: Set(historyEntries.prefix(mode == .radio ? 20 : 8).map(\.key)),
        cachedTracks: cacheEntries.map(\.track),
        cachedKeys: Set(cacheEntries.map(\.key)),
        favoriteBVIDs: favoriteBVIDs,
        favoriteFolder: favoriteFolder)
}
```

Planner notes:
- Do not invoke `RecommendationEngine.recommendations(mode: .home, ...)` from first playback.
- If scheduling changes are needed, gate Home work behind `HomeView.load()`/manual refresh and Now Playing related work behind the related surface.
- Consider lowering detached scoring priority for Home refresh if it can compete with playback; do not rely on priority alone as the guard.

---

### `BiliMusic/Design/CachedAsyncImage.swift` (component/provider, file-I/O)

**Analog:** `BiliMusic/Design/CachedAsyncImage.swift`

**Memory cache pattern** (lines 1-28):
```swift
import SwiftUI
import UIKit

@MainActor
final class ImageMemoryCache {
    static let shared = ImageMemoryCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL, cost: Int? = nil) {
        cache.setObject(image, forKey: url as NSURL, cost: cost ?? Self.memoryCost(for: image))
    }

    static func memoryCost(for image: UIImage) -> Int {
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        return max(1, width * height * 4)
    }
}
```

**In-flight coalescing and URLCache pattern** (lines 30-73):
```swift
actor ImageLoadCoordinator {
    static let shared = ImageLoadCoordinator()

    private let session: URLSession
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "BiliMusicImages")
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 12
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)
    }

    func image(for url: URL, headers: [String: String] = BiliClient.headers) async -> UIImage? {
        if let task = inFlight[url] {
            return await task.value
        }

        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let session = session
        let task = Task<UIImage?, Never>(priority: .utility) {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    return nil
                }
                return await Task.detached(priority: .utility) {
                    UIImage(data: data)
                }.value
            } catch {
                return nil
            }
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        return image
    }
}
```

**View load pattern** (lines 97-113):
```swift
@MainActor
private func load() async {
    guard let url else {
        image = nil
        return
    }
    if let cached = ImageMemoryCache.shared.image(for: url) {
        image = cached
        return
    }
    guard let decoded = await ImageLoadCoordinator.shared.image(for: url, headers: headers),
          !Task.isCancelled else {
        return
    }
    ImageMemoryCache.shared.insert(decoded, for: url)
    image = decoded
}
```

**Stable thumbnail dimensions pattern** (source `BiliMusic/Design/TrackRow.swift`, lines 13-22):
```swift
CachedAsyncImage(url: thumbnailURL(track.coverURL, size: 160)) { image in
    image.resizable().aspectRatio(contentMode: .fill)
} placeholder: {
    ZStack {
        AppTheme.secondaryBackground
        Image(systemName: "music.note").font(.caption).foregroundStyle(.secondary)
    }
}
.frame(width: 64, height: 36)
.clipShape(RoundedRectangle(cornerRadius: 5))
```

Planner notes:
- Add target-size-aware decode/downsampling before `ImageMemoryCache.shared.insert`.
- Preserve `inFlight` coalescing and stable row frames.
- Add explicit `removeAll`/release hook to `ImageMemoryCache`.
- If target size becomes part of the cache key, avoid breaking existing plain-URL callers abruptly; introduce a small key type or overload.

---

### `BiliMusic/Features/RootView.swift` (component/provider, event-driven)

**Analog:** `BiliMusic/Features/RootView.swift`

**Background lifecycle pattern** (lines 69-77):
```swift
.onChange(of: scenePhase) { _, phase in
    if phase == .background {
        Task {
            await CacheStore.shared.flush()
            await PlaybackHistoryStore.shared.flush()
            await engine.handleScenePhase(isBackground: true)
        }
    }
}
```

**Startup/prewarm pattern** (lines 78-88):
```swift
.task {
    Task(priority: .utility) {
        await WBISigner.prewarm()
    }
    await CacheStore.shared.loadIfNeeded()
    await PlaybackHistoryStore.shared.loadIfNeeded()
#if DEBUG
    if UITestFixtures.enabled {
        engine.installUITestFixture(tracks: UITestFixtures.homeTracks, startAt: 0)
    }
#endif
```

**Playback background handling pattern** (source `BiliMusic/Player/PlayerEngine.swift`, lines 442-448):
```swift
func handleScenePhase(isBackground: Bool) async {
    guard isBackground else { return }
    autoMVTask?.cancel()
    guard playbackMode == .mv, state == .playing else { return }
    playbackMode = .music
    await startCurrent(resumeAt: currentTime)
}
```

Planner notes:
- Add image cache release to the existing background task in `RootView`, after or beside existing store flushes.
- Keep playback state untouched: image cleanup must not clear `PlayerEngine.current`, queue, or player item.
- Memory warning notification handling can be installed inside `CachedAsyncImage.swift`/`ImageMemoryCache`, but background cleanup belongs here.

---

### `BiliMusic/Support/UITestFixtures.swift` (utility, transform)

**Analog:** `BiliMusic/Support/UITestFixtures.swift`

**Fixture environment pattern** (lines 1-20):
```swift
import Foundation

enum UITestFixtures {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["BILIMUSIC_UITEST_FIXTURE"] == "1"
    }

    static let homeTracks: [Track] = [
        Track(typeID: 3, bvid: "BVUITEST001", cid: 1001, title: "Fixture Song One", artist: "UI Test", coverURL: nil, duration: 211),
        Track(typeID: 3, bvid: "BVUITEST002", cid: 1002, title: "Fixture Song Two", artist: "UI Test", coverURL: nil, duration: 197),
        Track(typeID: 193, bvid: "BVUITEST003", cid: 1003, title: "Fixture MV Three", artist: "UI Test", coverURL: nil, duration: 243),
        Track(typeID: 3, bvid: "BVUITEST004", cid: 1004, title: "Fixture Song Four", artist: "UI Test", coverURL: nil, duration: 188),
        Track(typeID: 3, bvid: "BVUITEST005", cid: 1005, title: "Fixture Song Five", artist: "UI Test", coverURL: nil, duration: 224),
        Track(typeID: 3, bvid: "BVUITEST006", cid: 1006, title: "Fixture Song Six", artist: "UI Test", coverURL: nil, duration: 205),
        Track(typeID: 3, bvid: "BVUITEST007", cid: 1007, title: "Fixture Song Seven", artist: "UI Test", coverURL: nil, duration: 199),
        Track(typeID: 3, bvid: "BVUITEST008", cid: 1008, title: "Fixture Song Eight", artist: "UI Test", coverURL: nil, duration: 231),
```

**Player fixture installation pattern** (source `BiliMusic/Player/PlayerEngine.swift`, lines 535-556):
```swift
#if DEBUG
func installUITestFixture(tracks: [Track], startAt index: Int = 0) {
    preloadTask?.cancel()
    prefetchTask?.cancel()
    queuePrefetchTask?.cancel()
    autoMVTask?.cancel()
    postPlaybackTask?.cancel()
    player?.pause()
    player = nil
    queue = tracks
    queueIndex = min(max(index, 0), max(tracks.count - 1, 0))
    playedKeys = []
    manualPlaybackModeOverride = nil
    playbackMode = .music
    queueMode = .sequential
    state = tracks.isEmpty ? .idle : .paused
    currentTime = 0
    lyrics = []
    videoAvailable = !tracks.isEmpty
    currentAudioQuality = nil
    currentAudioBandwidth = nil
    isMiniPlayerHidden = false
}
#endif
```

Planner notes:
- Extend fixtures only if UI tests need deterministic local search/cached rows.
- Keep fixture data static and network-free.
- Preserve `BILIMUSIC_UITEST_FIXTURE=1` as the single switch.

---

### `BiliMusicTests/PlaybackCriticalPathTests.swift` (test, event-driven)

**Analog:** `BiliMusicTests/SearchModelsTests.swift`

**XCTest target pattern** (source `BiliMusicTests/SearchModelsTests.swift`, lines 1-4):
```swift
import XCTest
@testable import BiliMusic

final class SearchModelsTests: XCTestCase {
```

**MainActor async/store test pattern** (source `BiliMusicTests/SearchModelsTests.swift`, lines 47-66):
```swift
@MainActor
func testSearchStoreRestoresCachedSnapshot() {
    let store = SearchStore()
    let track = Track(typeID: 3, bvid: "BV1", title: "晴天", artist: "周杰伦",
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
```

Planner notes:
- Create focused unit tests for PLAY-01, PLAY-02, and PLAY-05 using fake seams around source resolution, item creation/play request, diagnostics sink, and post-start enrichment.
- Follow existing inline `Track(...)` fixture style.
- Keep tests network-free and AVPlayer-free where possible; use injected collaborators rather than real Bilibili streams.

---

### `BiliMusicTests/PlaybackDiagnosticsTests.swift` (test, event-driven)

**Analog:** `BiliMusicTests/SearchModelsTests.swift`; source pattern above.

**Test naming/assertion pattern** (source `BiliMusicTests/SearchModelsTests.swift`, lines 68-86):
```swift
@MainActor
func testChangingModeClearsTransientResultsForSameQuery() {
    let store = SearchStore()
    store.setMode(.expanded, query: "晴天")

    XCTAssertEqual(store.mode, .expanded)
    XCTAssertTrue(store.results.isEmpty)
    XCTAssertFalse(store.hasMoreResults)
}

@MainActor
func testChangingQueryAfterMoreResultsReturnsToMusicMode() {
    let store = SearchStore()
    store.setMode(.expanded, query: "晴天")

    store.queryDidChange("七里香")

    XCTAssertEqual(store.mode, .music)
}
```

Planner notes:
- Assert ordered checkpoints and sanitized payloads.
- Include a regression that diagnostic messages do not include full URLs, `Cookie`, or header names.
- Prefer value-level assertions over OSLog scraping.

---

### `BiliMusicTests/PreparedStreamRetryTests.swift` (test, request-response)

**Analog:** `BiliMusicTests/SearchModelsTests.swift` plus `BiliMusic/Player/StreamResolver.swift`.

**Invalidation behavior to cover** (source `BiliMusic/Player/StreamResolver.swift`, lines 45-53):
```swift
func invalidateAudio(for track: Track) {
    preparedStreams[track.key] = nil
    preparingStreams[track.key] = nil
    if track.cid != nil {
        let fallbackKey = TrackKey(bvid: track.bvid, cid: nil)
        preparedStreams[fallbackKey] = nil
        preparingStreams[fallbackKey] = nil
    }
}
```

Planner notes:
- Test the one-retry contract: prepared remote failure invalidates once, resolves fresh once, then surfaces failure if the retry fails.
- Assert short-lived URLs are not written to `CacheStore` or any persisted fixture.
- Use fake resolver/player item status seam; do not depend on real CDN expiry.

---

### `BiliMusicTests/SearchFocusTests.swift` (test, request-response)

**Analog:** `BiliMusicTests/SearchModelsTests.swift`

**Existing SearchStore query test pattern** (source `BiliMusicTests/SearchModelsTests.swift`, lines 78-86):
```swift
@MainActor
func testChangingQueryAfterMoreResultsReturnsToMusicMode() {
    let store = SearchStore()
    store.setMode(.expanded, query: "晴天")

    store.queryDidChange("七里香")

    XCTAssertEqual(store.mode, .music)
}
```

**Store behavior under test** (source `BiliMusic/Features/Search/SearchStore.swift`, lines 46-63):
```swift
func queryDidChange(_ query: String) {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty {
        guard mode != .music || !resultsQuery.isEmpty || !results.isEmpty || !activeQuery.isEmpty else { return }
        mode = .music
        resetTransientState(cancelTask: true)
    } else if text != resultsQuery {
        let shouldReset = !resultsQuery.isEmpty || !results.isEmpty || !activeQuery.isEmpty
        if mode != .music {
            mode = .music
        }
        guard shouldReset else {
            return
        }
        resetTransientState(cancelTask: true)
    }
}
```

Planner notes:
- Prefer a new `SearchFocusTests.swift` over expanding `SearchModelsTests.swift`, because Phase 1 introduces behavior tests around focus/typing and local suggestions.
- Assert focus/typing does not call Bilibili search. If needed, add a fake search client counter seam.
- Assert local sections can be built from search history, playback history, and cache entries.

---

### `BiliMusicTests/RecommendationSchedulingTests.swift` (test, batch)

**Analog:** `BiliMusicTests/SearchModelsTests.swift` plus `BiliMusic/Player/RecommendationEngine.swift`.

**Recommendation work that must be gated** (source `BiliMusic/Player/RecommendationEngine.swift`, lines 93-116):
```swift
func recommendations(mode: Mode, context: Context, limit: Int = 24) async -> [Track] {
    let snapshot = await Self.makeSnapshot(mode: mode)
    let cacheKey = Self.cacheKey(mode: mode, context: context, snapshot: snapshot)
    // cache hit and candidate build omitted
    let candidates = await buildCandidates(mode: mode, context: context, snapshot: snapshot)
    let pool = await Task.detached(priority: .userInitiated) {
        Self.scoredPool(candidates, mode: mode, context: context, snapshot: snapshot)
    }.value
    if mode != .radio {
        await RecommendationPoolCache.shared.store(pool, for: cacheKey)
    }
    let usable = Self.usable(pool, mode: mode, snapshot: snapshot)
    return Self.select(from: usable, mode: mode, excluded: context.excludedKeys, limit: limit)
}
```

Planner notes:
- Test that first playback scheduling does not call Home recommendation refresh or `makeSnapshot(mode: .home)`.
- Use an injected scheduler/engine seam if implementation introduces one.
- Keep radio next-track behavior separate; Phase 1 Home stability should not break radio.

---

### `BiliMusicTests/ImageCacheTests.swift` (test, file-I/O)

**Analog:** `BiliMusicTests/SearchModelsTests.swift` plus `BiliMusic/Design/CachedAsyncImage.swift`.

**Cache-cost behavior to test** (source `BiliMusic/Design/CachedAsyncImage.swift`, lines 19-27):
```swift
func insert(_ image: UIImage, for url: URL, cost: Int? = nil) {
    cache.setObject(image, forKey: url as NSURL, cost: cost ?? Self.memoryCost(for: image))
}

static func memoryCost(for image: UIImage) -> Int {
    let width = Int(image.size.width * image.scale)
    let height = Int(image.size.height * image.scale)
    return max(1, width * height * 4)
}
```

Planner notes:
- Add tests for memory cost, target-size downsample key behavior, duplicate in-flight coalescing if a seam is exposed, and `removeAll`/release hook.
- UIKit image tests may need `@MainActor`; keep image data synthetic and local.

---

### `BiliMusicUITests/PlayerChromeUITests.swift` (test, event-driven)

**Analog:** `BiliMusicUITests/PlayerChromeUITests.swift`

**UI fixture launch pattern** (lines 6-11):
```swift
override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["-searchHistory", "[]"]
    app.launchEnvironment["BILIMUSIC_UITEST_FIXTURE"] = "1"
    app.launch()
}
```

**Home list stability assertion pattern** (lines 79-91):
```swift
@MainActor
func testTappingRecommendationKeepsHomeListStable() throws {
    let firstRow = app.buttons["homeTrackRow0"]
    XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "Fixture recommendation row should be visible.")
    let frameBefore = firstRow.frame

    firstRow.tap()

    let miniPlayer = element("miniPlayer")
    XCTAssertTrue(miniPlayer.waitForExistence(timeout: 3), "Tapping a recommendation should start the fixture player.")
    XCTAssertTrue(firstRow.waitForExistence(timeout: 2), "The recommendation list should not disappear after tapping a song.")
    XCTAssertEqual(firstRow.frame.minY, frameBefore.minY, accuracy: 12, "The recommendation list should not jump after tapping a song.")
}
```

**Element helper pattern** (lines 112-114):
```swift
private func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
}
```

Planner notes:
- Extend this file for RECO-01 rather than creating a second UI test harness.
- Use existing `homeTrackRow0`, `miniPlayer`, and fixture mode.
- For search focus UI smoke, keep assertions around system search field existence and absence of loading copy unless unit tests already cover the no-network path.

## Shared Patterns

### Playback Critical Path

**Source:** `BiliMusic/Player/PlayerEngine.swift`
**Apply to:** `PlayerEngine`, playback diagnostics tests, prepared retry tests

Use the `play(tracks:startAt:)` queue assignment lines 175-193, source-resolution chain lines 452-521, and `startPlayback` item creation/play request lines 701-724 and 788-792 as the protected path. Anything not required to build the first `AVPlayerItem` and request playback belongs after `playImmediately`.

### Short-Lived Remote URL Handling

**Source:** `BiliMusic/Player/StreamResolver.swift`
**Apply to:** `StreamResolver`, `PlayerEngine`, prepared retry tests

```swift
func cachedAudio(for track: Track) -> PreparedAudioStream? {
    let key = track.key
    let fallbackKey = TrackKey(bvid: track.bvid, cid: nil)
    guard let prepared = preparedStreams[key] ?? preparedStreams[fallbackKey] else { return nil }
    if Date().timeIntervalSince(prepared.fetchedAt) < 90 * 60 {
        return prepared
    }
    preparedStreams[key] = nil
    preparedStreams[fallbackKey] = nil
    preparingStreams[key] = nil
    preparingStreams[fallbackKey] = nil
    return nil
}
```

Remote playurls stay memory-only. Retry invalidates memory entries and resolves again; cache persistence remains bvid/cid/local-file based.

### Search Submit-Only Rule

**Source:** `BiliMusic/Features/Search/SearchView.swift`, `BiliMusic/Features/Search/SearchStore.swift`
**Apply to:** Search view/store and search focus tests

The only network trigger should be `.onSubmit(of: .search) { submitSearch() }` at lines 47-49. `.onChange(of: query)` should keep only cheap local state changes after Phase 1.

### Local Search Suggestions

**Source:** `BiliMusic/Features/Search/SearchView.swift`, `BiliMusic/Cache/CacheStore.swift`, `BiliMusic/Player/PlaybackHistoryStore.swift`
**Apply to:** Search focus UI and store tests

```swift
private var recentTracks: [Track] {
    Array(history.entries.prefix(6).map(\.track))
}
```

```swift
struct CachedEntry: Codable, Identifiable, Equatable {
    let bvid: String
    let cid: Int
    let title: String
    let artist: String
    let coverURL: String?
    let duration: Int
    // ...
    var track: Track {
        Track(bvid: bvid, cid: cid, title: title, artist: artist,
              coverURL: coverURL.flatMap(URL.init(string:)), duration: duration)
    }
}
```

Use `PlaybackHistoryStore.shared.entries` and `CacheStore.shared.entries` after their existing background `loadIfNeeded()` calls.

### Home Recommendation Stability

**Source:** `BiliMusic/Features/Home/HomeView.swift`
**Apply to:** HomeView, RecommendationEngine scheduling, UI tests

Do not clear `tracks` on playback. Existing `load()` replaces `tracks` only after a nonempty result and shows errors without blanking existing rows. Preserve that shape and block playback-triggered Home refresh.

### Image Memory and Coalescing

**Source:** `BiliMusic/Design/CachedAsyncImage.swift`
**Apply to:** CachedAsyncImage, RootView cleanup, ImageCacheTests

Preserve:
- `NSCache` count/cost limits at lines 8-12.
- `inFlight: [URL: Task<UIImage?, Never>]` coalescing at lines 33-50.
- `URLSessionConfiguration` cache and `httpMaximumConnectionsPerHost = 6` at lines 36-45.

Add:
- target-size decode/downsample before cache insert,
- explicit decoded-image release,
- background/memory-pressure cleanup without touching playback state.

### Background Persistence/Cleanup

**Source:** `BiliMusic/Features/RootView.swift`, `BiliMusic/Cache/CacheStore.swift`, `BiliMusic/Player/PlaybackHistoryStore.swift`
**Apply to:** RootView and image cache cleanup

```swift
.onChange(of: scenePhase) { _, phase in
    if phase == .background {
        Task {
            await CacheStore.shared.flush()
            await PlaybackHistoryStore.shared.flush()
            await engine.handleScenePhase(isBackground: true)
        }
    }
}
```

Add image cache release to this task. Keep store flushes and playback background handling intact.

### XCTest and XcodeGen

**Source:** `BiliMusicTests/SearchModelsTests.swift`, `project.yml`
**Apply to:** All new unit test files

```swift
import XCTest
@testable import BiliMusic

final class SearchModelsTests: XCTestCase {
```

`project.yml` includes whole test directories, so adding new `.swift` files under the existing test folders should not require project file edits:

```yaml
30  BiliMusicTests:
31    type: bundle.unit-test
32    platform: iOS
33    sources: [BiliMusicTests]
40  BiliMusicUITests:
41    type: bundle.ui-testing
42    platform: iOS
43    sources: [BiliMusicUITests]
```

## No Analog Found

None. New files have role-match analogs:
- `PlaybackDiagnostics.swift` should copy OSLog and checkpoint style from `StreamResolver.swift` and `PlayerEngine.swift`.
- New unit tests should copy `SearchModelsTests.swift`.
- UI stability coverage should extend `PlayerChromeUITests.swift`.

## Metadata

**Analog search scope:** `BiliMusic/Player`, `BiliMusic/Features/Search`, `BiliMusic/Features/Home`, `BiliMusic/Design`, `BiliMusic/Features/RootView.swift`, `BiliMusic/Support`, `BiliMusicTests`, `BiliMusicUITests`, `project.yml`

**Files scanned:** CodeGraph found relevant symbols across playback, search, Home, image, root, support, and test files; shell inventory found existing test files `BiliMusicTests/SearchModelsTests.swift` and `BiliMusicUITests/PlayerChromeUITests.swift`.

**Pattern extraction date:** 2026-06-26

**Notes for planner:**
- Keep Phase 1 scoped to first sound, search focus, Home stability, and image memory guardrails.
- Do not pull broad API/auth/cache rewrites into this phase.
- Existing source files may be dirty; implementation should preserve user changes and touch only phase-scoped files.
