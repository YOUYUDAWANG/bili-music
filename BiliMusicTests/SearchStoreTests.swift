import XCTest
@testable import BiliMusic

final class SearchStoreTests: XCTestCase {
    private let historyKey = "searchHistory"
    private var previousHistoryValue: String?
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        // 快照真实搜索历史,tearDown 恢复,保证测试不破坏宿主数据。
        previousHistoryValue = UserDefaults.standard.string(forKey: historyKey)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bili-music-search-store-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let previousHistoryValue {
            UserDefaults.standard.set(previousHistoryValue, forKey: historyKey)
        } else {
            UserDefaults.standard.removeObject(forKey: historyKey)
        }
        previousHistoryValue = nil
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        super.tearDown()
    }

    /// 注入隔离的 history/cache 实例:全部落在临时目录,不碰 CacheStore.shared /
    /// PlaybackHistoryStore.shared 的真实 Documents 数据。
    @MainActor
    private func makeIsolatedStores() async -> (history: PlaybackHistoryStore, cache: CacheStore) {
        let history = PlaybackHistoryStore(
            fileURLForTesting: tempDir.appendingPathComponent("playback-history.json"))
        let cache = CacheStore(
            indexURLForTesting: tempDir.appendingPathComponent("cache_index.json"),
            audioDirForTesting: tempDir.appendingPathComponent("audio", isDirectory: true))
        await history.loadIfNeeded()
        await cache.loadIfNeeded()
        return (history, cache)
    }

    @MainActor
    func testLoadLocalContentPreparesSnapshotFromHistoryAndCache() async {
        let (history, cache) = await makeIsolatedStores()

        UserDefaults.standard.set(#"["晴天","七里香","稻香"]"#, forKey: historyKey)
        history.record(makeTrack(bvid: "BVRECENT001", title: "最近播放"))
        history.record(makeTrack(bvid: "BVSAME001", title: "最近重复"))
        cache.addForTesting(makeCachedEntry(track: makeTrack(bvid: "BVSAME001", title: "缓存重复")))
        cache.addForTesting(makeCachedEntry(track: makeTrack(bvid: "BVCACHE001", title: "已缓存")))

        let store = SearchStore()

        await store.loadLocalContent(history: history, cache: cache)

        XCTAssertEqual(store.localContent.historyTerms, ["晴天", "七里香", "稻香"])
        XCTAssertEqual(store.localContent.recentTracks.map(\.bvid), ["BVSAME001", "BVRECENT001"])
        XCTAssertEqual(store.localContent.cachedTracks.map(\.bvid), ["BVCACHE001"])
    }

    @MainActor
    func testLoadLocalContentKeepsPreparedResultsIdleAndIntact() async {
        let (history, cache) = await makeIsolatedStores()

        UserDefaults.standard.set(#"["晴天"]"#, forKey: historyKey)
        history.record(makeTrack(bvid: "BVRECENT001", title: "最近播放"))

        let expected = makeTrack(bvid: "BVRESULT001", title: "已准备结果")
        let store = SearchStore(searchPageForTesting: { _, _, _ in
            XCTFail("loadLocalContent should not start Bilibili search work")
            return []
        })
        restoreSearch(store, query: "晴天", tracks: [expected], nextPage: 4, hasMoreResults: true)

        await store.loadLocalContent(history: history, cache: cache)

        XCTAssertEqual(store.resultsQuery, "晴天")
        XCTAssertEqual(store.results.map(\.bvid), ["BVRESULT001"])
        XCTAssertFalse(store.searching)
        XCTAssertEqual(store.localContent.historyTerms, ["晴天"])
        XCTAssertEqual(store.localContent.recentTracks.map(\.bvid), ["BVRECENT001"])
    }

    @MainActor
    func testTopHistoryReplayDoesNotBumpContentRevisionWhenVisibleProjectionIsUnchanged() async {
        let (history, cache) = await makeIsolatedStores()

        UserDefaults.standard.set(#"["晴天"]"#, forKey: historyKey)
        history.record(makeTrack(bvid: "BVRECENT001", title: "第一次播放"))
        history.record(makeTrack(bvid: "BVRECENT002", title: "第二次播放"))
        history.record(makeTrack(bvid: "BVRECENT002", title: "第二次播放"))

        let store = SearchStore()
        await store.loadLocalContent(history: history, cache: cache)
        let initialRevision = history.contentRevision

        history.record(makeTrack(bvid: "BVRECENT002", title: "第二次播放"))

        store.refreshLocalContent(history: history, cache: cache)

        XCTAssertEqual(history.contentRevision, initialRevision)
        XCTAssertEqual(store.localContent.historyTerms, ["晴天"])
        XCTAssertEqual(store.localContent.recentTracks.map(\.bvid), ["BVRECENT002", "BVRECENT001"])
        XCTAssertEqual(store.localContent.recentTracks.first?.title, "第二次播放")
        XCTAssertTrue(store.localContent.cachedTracks.isEmpty)
    }

    @MainActor
    func testNonTopHistoryReplayBumpsContentRevisionWhenVisibleProjectionReorders() async {
        let (history, cache) = await makeIsolatedStores()

        UserDefaults.standard.set(#"["晴天"]"#, forKey: historyKey)
        history.record(makeTrack(bvid: "BVRECENT001", title: "第一次播放"))
        history.record(makeTrack(bvid: "BVRECENT002", title: "第二次播放"))

        let store = SearchStore()
        await store.loadLocalContent(history: history, cache: cache)
        let initialRevision = history.contentRevision

        history.record(makeTrack(bvid: "BVRECENT001", title: "重播后更新标题"))

        store.refreshLocalContent(history: history, cache: cache)

        XCTAssertGreaterThan(history.contentRevision, initialRevision)
        XCTAssertEqual(store.localContent.recentTracks.map(\.bvid), ["BVRECENT001", "BVRECENT002"])
        XCTAssertEqual(store.localContent.recentTracks.first?.title, "重播后更新标题")
    }

    @MainActor
    func testReplacingCacheEntryWithSameTrackProjectionDoesNotBumpContentRevision() async {
        let (history, cache) = await makeIsolatedStores()

        let first = makeTrack(bvid: "BVCACHE001", title: "旧缓存 1")
        let second = makeTrack(bvid: "BVCACHE002", title: "旧缓存 2")
        cache.addForTesting(makeCachedEntry(track: first))
        cache.addForTesting(makeCachedEntry(track: second))

        let store = SearchStore()
        await store.loadLocalContent(history: history, cache: cache)
        let initialRevision = cache.contentRevision

        cache.addForTesting(makeCachedEntry(track: second, fileName: "BVCACHE002-v2.m4a", fileSize: 2048))

        store.refreshLocalContent(history: history, cache: cache)

        XCTAssertEqual(cache.contentRevision, initialRevision)
        XCTAssertEqual(store.localContent.cachedTracks.map(\.bvid), ["BVCACHE002", "BVCACHE001"])
        XCTAssertEqual(store.localContent.cachedTracks.first?.title, "旧缓存 2")
    }

    @MainActor
    func testCacheEntryBeyondTopSixStillBumpsRevisionWhenRecentTracksExposeIt() async {
        let (history, cache) = await makeIsolatedStores()

        let recentTracks = (1...6).map { index in
            makeTrack(bvid: String(format: "BVCACHE%03d", index), title: "最近 \(index)")
        }
        recentTracks.forEach { history.record($0) }

        let visibleCacheTracks = (7...12).map { index in
            makeTrack(bvid: String(format: "BVCACHE%03d", index), title: "缓存 \(index)")
        }
        let hiddenCacheTracks = (1...6).map { index in
            makeTrack(bvid: String(format: "BVCACHE%03d", index), title: "缓存 \(index)")
        }

        visibleCacheTracks.forEach { cache.addForTesting(makeCachedEntry(track: $0)) }
        hiddenCacheTracks.forEach { cache.addForTesting(makeCachedEntry(track: $0)) }

        let store = SearchStore()
        await store.loadLocalContent(history: history, cache: cache)
        let initialRevision = cache.contentRevision

        cache.addForTesting(makeCachedEntry(track: makeTrack(bvid: "BVCACHE007", title: "缓存 7 改版")))

        store.refreshLocalContent(history: history, cache: cache)

        XCTAssertGreaterThan(cache.contentRevision, initialRevision)
        XCTAssertEqual(
            store.localContent.cachedTracks.map(\.bvid),
            ["BVCACHE007", "BVCACHE012", "BVCACHE011", "BVCACHE010", "BVCACHE009", "BVCACHE008"])
        XCTAssertEqual(store.localContent.cachedTracks.first?.title, "缓存 7 改版")
    }

    @MainActor
    func testReplacingCacheEntryWithChangedTrackProjectionBumpsContentRevision() async {
        let (history, cache) = await makeIsolatedStores()

        let first = makeTrack(bvid: "BVCACHE001", title: "旧缓存 1")
        let second = makeTrack(bvid: "BVCACHE002", title: "旧缓存 2")
        cache.addForTesting(makeCachedEntry(track: first))
        cache.addForTesting(makeCachedEntry(track: second))

        let store = SearchStore()
        await store.loadLocalContent(history: history, cache: cache)
        let initialRevision = cache.contentRevision

        cache.addForTesting(makeCachedEntry(track: makeTrack(bvid: "BVCACHE001", title: "替换后的缓存 1")))

        store.refreshLocalContent(history: history, cache: cache)

        XCTAssertGreaterThan(cache.contentRevision, initialRevision)
        XCTAssertEqual(store.localContent.cachedTracks.map(\.bvid), ["BVCACHE001", "BVCACHE002"])
        XCTAssertEqual(store.localContent.cachedTracks.first?.title, "替换后的缓存 1")
    }

    @MainActor
    func testEmptyQueryDoesNotClearPreparedResultsOrStartSearch() async {
        let (history, cache) = await makeIsolatedStores()

        UserDefaults.standard.set(#"["晴天"]"#, forKey: historyKey)
        history.record(makeTrack(bvid: "BVRECENT001", title: "最近播放"))
        cache.addForTesting(makeCachedEntry(track: makeTrack(bvid: "BVCACHE001", title: "已缓存")))

        let expected = makeTrack(bvid: "BVRESULT001", title: "已准备结果")
        let store = SearchStore(searchPageForTesting: { _, _, _ in
            XCTFail("queryDidChange on an empty query should stay local and idle")
            return []
        })
        await store.loadLocalContent(history: history, cache: cache)
        restoreSearch(store, query: "晴天", tracks: [expected], nextPage: 4, hasMoreResults: true)
        let prepared = store.localContent

        store.queryDidChange("")

        XCTAssertEqual(store.localContent, prepared)
        XCTAssertFalse(store.searching)
        XCTAssertEqual(store.results.map(\.bvid), ["BVRESULT001"])
        XCTAssertNotNil(store.sections)
        XCTAssertEqual(store.resultsQuery, "晴天")
        XCTAssertEqual(store.activeQuery, "晴天")
    }

    @MainActor
    func testInitialSearchKeepsSuccessfulPagesWhenOnePageFails() async {
        let store = SearchStore(searchPageForTesting: { _, page, _ in
            if page == 2 {
                throw SearchStoreFixtureError.pageUnavailable
            }
            return [
                makeTrack(
                    bvid: "BVSEARCH00\(page)",
                    title: "周杰伦 晴天 官方 MV \(page)")
            ]
        })

        store.submitSearch("晴天", preload: { _ in })
        for _ in 0..<200 where store.searching {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(store.searching)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(Set(store.results.map(\.bvid)), ["BVSEARCH001", "BVSEARCH003"])
    }

    @MainActor
    func testInitialSearchShowsFirstPageBeforeLaterPagesFinish() async {
        let gate = SearchPageGate()
        let store = SearchStore(searchPageForTesting: { _, page, _ in
            if page == 2 {
                await gate.wait()
                return [
                    makeTrack(
                        bvid: "BVSEARCH002",
                        title: "周杰伦 晴天 官方 MV 2")
                ]
            }
            return [
                makeTrack(
                    bvid: "BVSEARCH00\(page)",
                    title: "周杰伦 晴天 官方 MV \(page)")
            ]
        })

        store.submitSearch("晴天", preload: { _ in })
        await waitBounded(description: "first search page should appear while still searching") {
            !store.results.isEmpty && store.searching
        }

        XCTAssertTrue(store.searching)
        XCTAssertEqual(store.results.map(\.bvid), ["BVSEARCH001"])
        XCTAssertFalse(store.results.contains { $0.bvid == "BVSEARCH002" })
        XCTAssertTrue(store.shouldShowResults(query: "晴天"))

        await gate.open()
        for _ in 0..<200 where store.searching {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(store.searching)
        XCTAssertEqual(Set(store.results.map(\.bvid)), ["BVSEARCH001", "BVSEARCH002", "BVSEARCH003"])
        XCTAssertTrue(store.hasMoreResults)
    }

    @MainActor
    func testKnownCIDNeverFallsBackToAnotherCachedPart() async {
        let (_, cache) = await makeIsolatedStores()
        let cachedTrack = Track(
            bvid: "BVMULTIPART",
            cid: 1001,
            title: "P1",
            artist: "Artist",
            coverURL: nil,
            duration: 180)
        cache.addForTesting(makeCachedEntry(track: cachedTrack))

        let differentPart = Track(
            bvid: "BVMULTIPART",
            cid: 1002,
            title: "P2",
            artist: "Artist",
            coverURL: nil,
            duration: 180)
        let unresolvedDifferentPart = Track(
            bvid: "BVMULTIPART",
            title: "Unknown",
            artist: "Artist",
            coverURL: nil,
            duration: 180)
        let unresolvedMatchingPart = Track(
            bvid: "BVMULTIPART",
            title: "P1",
            artist: "Artist",
            coverURL: nil,
            duration: 180)

        XCTAssertNil(cache.entry(for: differentPart))
        XCTAssertNil(cache.entry(for: unresolvedDifferentPart))
        XCTAssertEqual(cache.entry(for: unresolvedMatchingPart)?.cid, 1001)

        cache.addForTesting(makeCachedEntry(track: differentPart))
        XCTAssertNil(cache.entry(for: unresolvedMatchingPart))
    }
}

private enum SearchStoreFixtureError: LocalizedError {
    case pageUnavailable

    var errorDescription: String? { "page unavailable" }
}

@MainActor
private func restoreSearch(
    _ store: SearchStore,
    query: String,
    mode: SearchResultMode = .music,
    tracks: [Track],
    nextPage: Int,
    hasMoreResults: Bool
) {
    store.storeCachedSnapshotForTesting(
        query: query,
        mode: mode,
        snapshot: SearchCachedSnapshot(
            tracks: tracks,
            nextPage: nextPage,
            activeKeywords: [query],
            hasMoreResults: hasMoreResults))
    if mode != .music {
        store.setMode(mode, query: query)
    }
    XCTAssertTrue(store.restoreCachedResultsIfAvailable(for: query))
}

private func makeCachedEntry(
    track: Track,
    fileName: String? = nil,
    fileSize: Int64 = 1024
) -> CachedEntry {
    CachedEntry(
        bvid: track.bvid,
        cid: track.cid ?? 1,
        title: track.title,
        artist: track.artist,
        coverURL: track.coverURL?.absoluteString,
        duration: track.duration,
        fileName: fileName ?? "\(track.bvid).m4a",
        fileSize: fileSize,
        downloadedAt: Date(),
        quality: nil)
}

private func makeTrack(
    typeID: Int? = 3,
    bvid: String,
    title: String,
    artist: String = "周杰伦",
    duration: Int = 269
) -> Track {
    Track(typeID: typeID, bvid: bvid, title: title, artist: artist, coverURL: nil, duration: duration)
}

actor SearchPageGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let waiters = waiters
        self.waiters = []
        waiters.forEach { $0.resume() }
    }
}

@MainActor
private func waitBounded(
    description: String,
    timeout: TimeInterval = 5,
    until condition: @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    var yields = 0
    while !condition() {
        yields += 1
        if yields > 20_000 || Date() > deadline {
            XCTFail("timed out: \(description)")
            return
        }
        await Task.yield()
    }
}
