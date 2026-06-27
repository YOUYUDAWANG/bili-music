import XCTest
@testable import BiliMusic

final class SearchStoreTests: XCTestCase {
    private let historyKey = "searchHistory"

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    @MainActor
    func testLoadLocalContentPreparesSnapshotFromHistoryAndCache() async {
        let previousHistory = UserDefaults.standard.string(forKey: historyKey)
        let history = PlaybackHistoryStore.shared
        let cache = CacheStore.shared
        await prepareSharedLocalStores(history: history, cache: cache)
        defer {
            restoreSearchHistory(previousHistory)
            resetSharedLocalStores(history: history, cache: cache)
        }

        UserDefaults.standard.set(#"["晴天","七里香","稻香"]"#, forKey: historyKey)
        history.record(makeTrack(bvid: "BVRECENT001", title: "最近播放"))
        history.record(makeTrack(bvid: "BVSAME001", title: "最近重复"))
        cache.add(makeCachedEntry(track: makeTrack(bvid: "BVSAME001", title: "缓存重复")))
        cache.add(makeCachedEntry(track: makeTrack(bvid: "BVCACHE001", title: "已缓存")))

        let store = SearchStore()

        await store.loadLocalContent(history: history, cache: cache)

        XCTAssertEqual(store.localContent.historyTerms, ["晴天", "七里香", "稻香"])
        XCTAssertEqual(store.localContent.recentTracks.map(\.bvid), ["BVSAME001", "BVRECENT001"])
        XCTAssertEqual(store.localContent.cachedTracks.map(\.bvid), ["BVCACHE001"])
    }

    @MainActor
    func testLoadLocalContentKeepsPreparedResultsIdleAndIntact() async {
        let previousHistory = UserDefaults.standard.string(forKey: historyKey)
        let history = PlaybackHistoryStore.shared
        let cache = CacheStore.shared
        await prepareSharedLocalStores(history: history, cache: cache)
        defer {
            restoreSearchHistory(previousHistory)
            resetSharedLocalStores(history: history, cache: cache)
        }

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
        let previousHistory = UserDefaults.standard.string(forKey: historyKey)
        let history = PlaybackHistoryStore.shared
        let cache = CacheStore.shared
        await prepareSharedLocalStores(history: history, cache: cache)
        defer {
            restoreSearchHistory(previousHistory)
            resetSharedLocalStores(history: history, cache: cache)
        }

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
        let previousHistory = UserDefaults.standard.string(forKey: historyKey)
        let history = PlaybackHistoryStore.shared
        let cache = CacheStore.shared
        await prepareSharedLocalStores(history: history, cache: cache)
        defer {
            restoreSearchHistory(previousHistory)
            resetSharedLocalStores(history: history, cache: cache)
        }

        UserDefaults.standard.set(#"[\"晴天\"]"#, forKey: historyKey)
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
        let previousHistory = UserDefaults.standard.string(forKey: historyKey)
        let history = PlaybackHistoryStore.shared
        let cache = CacheStore.shared
        await prepareSharedLocalStores(history: history, cache: cache)
        defer {
            restoreSearchHistory(previousHistory)
            resetSharedLocalStores(history: history, cache: cache)
        }

        let first = makeTrack(bvid: "BVCACHE001", title: "旧缓存 1")
        let second = makeTrack(bvid: "BVCACHE002", title: "旧缓存 2")
        cache.add(makeCachedEntry(track: first))
        cache.add(makeCachedEntry(track: second))

        let store = SearchStore()
        await store.loadLocalContent(history: history, cache: cache)
        let initialRevision = cache.contentRevision

        cache.add(makeCachedEntry(track: second, fileName: "BVCACHE002-v2.m4a", fileSize: 2048))

        store.refreshLocalContent(history: history, cache: cache)

        XCTAssertEqual(cache.contentRevision, initialRevision)
        XCTAssertEqual(store.localContent.cachedTracks.map(\.bvid), ["BVCACHE002", "BVCACHE001"])
        XCTAssertEqual(store.localContent.cachedTracks.first?.title, "旧缓存 2")
    }

    @MainActor
    func testReplacingCacheEntryWithChangedTrackProjectionBumpsContentRevision() async {
        let previousHistory = UserDefaults.standard.string(forKey: historyKey)
        let history = PlaybackHistoryStore.shared
        let cache = CacheStore.shared
        await prepareSharedLocalStores(history: history, cache: cache)
        defer {
            restoreSearchHistory(previousHistory)
            resetSharedLocalStores(history: history, cache: cache)
        }

        let first = makeTrack(bvid: "BVCACHE001", title: "旧缓存 1")
        let second = makeTrack(bvid: "BVCACHE002", title: "旧缓存 2")
        cache.add(makeCachedEntry(track: first))
        cache.add(makeCachedEntry(track: second))

        let store = SearchStore()
        await store.loadLocalContent(history: history, cache: cache)
        let initialRevision = cache.contentRevision

        cache.add(makeCachedEntry(track: makeTrack(bvid: "BVCACHE001", title: "替换后的缓存 1")))

        store.refreshLocalContent(history: history, cache: cache)

        XCTAssertGreaterThan(cache.contentRevision, initialRevision)
        XCTAssertEqual(store.localContent.cachedTracks.map(\.bvid), ["BVCACHE001", "BVCACHE002"])
        XCTAssertEqual(store.localContent.cachedTracks.first?.title, "替换后的缓存 1")
    }

    @MainActor
    func testEmptyQueryDoesNotClearPreparedResultsOrStartSearch() async {
        let previousHistory = UserDefaults.standard.string(forKey: historyKey)
        let history = PlaybackHistoryStore.shared
        let cache = CacheStore.shared
        await prepareSharedLocalStores(history: history, cache: cache)
        defer {
            restoreSearchHistory(previousHistory)
            resetSharedLocalStores(history: history, cache: cache)
        }

        UserDefaults.standard.set(#"["晴天"]"#, forKey: historyKey)
        history.record(makeTrack(bvid: "BVRECENT001", title: "最近播放"))
        cache.add(makeCachedEntry(track: makeTrack(bvid: "BVCACHE001", title: "已缓存")))

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
    private func prepareSharedLocalStores(history: PlaybackHistoryStore, cache: CacheStore) async {
        await history.loadIfNeeded()
        await cache.loadIfNeeded()
        history.clear()
        cache.removeAll()
    }

    @MainActor
    private func resetSharedLocalStores(history: PlaybackHistoryStore, cache: CacheStore) {
        history.clear()
        cache.removeAll()
    }

    private func restoreSearchHistory(_ value: String?) {
        if let value {
            UserDefaults.standard.set(value, forKey: historyKey)
        } else {
            UserDefaults.standard.removeObject(forKey: historyKey)
        }
    }
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
