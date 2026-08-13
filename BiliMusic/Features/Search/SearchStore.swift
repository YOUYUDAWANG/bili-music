import Foundation
import Observation

struct SearchLocalContent: Equatable {
    let historyTerms: [String]
    let recentTracks: [Track]
    let cachedTracks: [Track]

    var isEmpty: Bool {
        historyTerms.isEmpty && recentTracks.isEmpty && cachedTracks.isEmpty
    }

    init(
        historyTerms: [String],
        recentTracks: [Track],
        cachedTracks: [Track],
        historyLimit: Int = 8,
        trackLimit: Int = 6
    ) {
        self.historyTerms = Array(historyTerms.prefix(historyLimit))
        self.recentTracks = Self.deduped(recentTracks, excluding: [], limit: trackLimit)
        self.cachedTracks = Self.deduped(cachedTracks, excluding: self.recentTracks.map(\.key), limit: trackLimit)
    }

    private static func deduped(_ tracks: [Track], excluding excluded: [TrackKey], limit: Int) -> [Track] {
        var seen = excluded
        var result: [Track] = []
        for track in tracks {
            guard !seen.contains(where: { $0.matches(track) }) else { continue }
            result.append(track)
            seen.append(track.key)
            if result.count == limit { break }
        }
        return result
    }
}

@Observable
@MainActor
final class SearchStore {
    typealias SearchPageProvider = @Sendable (_ keyword: String, _ page: Int, _ musicOnly: Bool) async throws -> [Track]

    private(set) var results: [Track] = []
    private(set) var sections: SearchResultSections?
    private(set) var searchHistory: [String] = []
    private(set) var searching = false
    private(set) var errorMessage: String?
    private(set) var loadMoreErrorMessage: String?
    private(set) var historyLoaded = false
    private(set) var resultsQuery = ""
    private(set) var hasMoreResults = false
    private(set) var loadingMore = false
    /// 缓存命中后仍会静默发起后台刷新;刷新期间 `searching` 保持 false,
    /// 用这个标志阻止 loadMore 与后台刷新并发写 results(重复 bvid / nextPage 错位)。
    private(set) var refreshingFromCache = false
    private(set) var mode: SearchResultMode = .music
    private(set) var activeQuery = ""
    private(set) var localContent = SearchLocalContent(historyTerms: [], recentTracks: [], cachedTracks: [])

    private var searchTask: Task<Void, Never>?
    private var activeSearchID = UUID()
    private var historyLoadID = UUID()
    private var activeKeywords: [String] = []
    private var nextPage = 1
    private var resultCache: [SearchCacheKey: SearchCachedSnapshot] = [:]
    private var resultCacheOrder: [SearchCacheKey] = []
    private static let resultCacheLimit = 12
    /// 与 SearchView.swift 的 @AppStorage("searchHistory") 保持一致(后续统一收敛到此常量)
    static let searchHistoryKey = "searchHistory"
    private let historyKey = SearchStore.searchHistoryKey
    private let searchPage: SearchPageProvider

    init() {
        self.searchPage = { keyword, page, musicOnly in
            try await SearchStore.defaultSearchPage(keyword: keyword, page: page, musicOnly: musicOnly)
        }
    }

    init(searchPageForTesting searchPage: @escaping SearchPageProvider) {
        self.searchPage = searchPage
    }

    func loadHistory() async {
        guard !historyLoaded else { return }
        let loadID = UUID()
        historyLoadID = loadID
        let raw = UserDefaults.standard.string(forKey: historyKey) ?? "[]"
        let decoded = await Self.decodeSearchHistory(raw)
        guard historyLoadID == loadID else { return }
        searchHistory = decoded
        historyLoaded = true
        refreshLocalContentHistory()
    }

    func reloadHistoryIfNeeded() {
        guard historyLoaded else { return }
        let raw = UserDefaults.standard.string(forKey: historyKey) ?? "[]"
        let loadID = UUID()
        historyLoadID = loadID
        Task { [weak self] in
            let decoded = await Self.decodeSearchHistory(raw)
            guard let self, self.historyLoadID == loadID else { return }
            self.searchHistory = decoded
            self.refreshLocalContentHistory()
        }
    }

    func clearHistory() {
        historyLoadID = UUID()
        historyLoaded = true
        searchHistory = []
        refreshLocalContentHistory()
        UserDefaults.standard.set("[]", forKey: historyKey)
    }

    func loadLocalContent(history: PlaybackHistoryStore, cache: CacheStore) async {
        await loadHistory()
        await history.loadIfNeeded()
        await cache.loadIfNeeded()
        refreshLocalContent(history: history, cache: cache)
    }

    func refreshLocalContent(history: PlaybackHistoryStore, cache: CacheStore) {
        localContent = SearchLocalContent(
            historyTerms: searchHistory,
            recentTracks: history.entries.map(\.track),
            cachedTracks: cache.entries.map(\.track))
    }

    func queryDidChange(_ query: String) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            if mode != .music {
                mode = .music
            }
        } else if text != resultsQuery {
            let shouldReset = !resultsQuery.isEmpty || !results.isEmpty || !activeQuery.isEmpty
            if mode != .music {
                mode = .music
            }
            guard shouldReset else {
                // 首个字符:state 已在默认值,不触发无意义的 @Observable 写入
                return
            }
            resetTransientState(cancelTask: true)
        }
    }

    func submitSearch(_ query: String, preload: @escaping @MainActor ([Track]) -> Void) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searchTask?.cancel()
        let searchID = UUID()
        let requestMode = mode
        let hadCachedResults = restoreCachedResultsIfAvailable(for: text)
        if !hadCachedResults {
            resetTransientState(cancelTask: false)
        }
        activeSearchID = searchID
        activeQuery = text
        searching = !hadCachedResults
        refreshingFromCache = hadCachedResults
        loadMoreErrorMessage = nil
        rememberSearch(text)
        searchTask = Task { [weak self] in
            await self?.search(text: text, mode: requestMode, searchID: searchID, preload: preload)
        }
    }

    func loadMoreIfNeeded(preload: @escaping @MainActor ([Track]) -> Void) async {
        await loadMore(preload: preload)
    }

    func loadMore(preload: @escaping @MainActor ([Track]) -> Void) async {
        guard shouldShowResults(query: resultsQuery),
              hasMoreResults,
              !searching,
              !refreshingFromCache,
              !loadingMore,
              !activeKeywords.isEmpty else { return }
        await loadMorePage(preload: preload)
    }

    private func loadMorePage(preload: @escaping @MainActor ([Track]) -> Void) async {
        let text = resultsQuery
        let requestMode = mode
        let searchID = activeSearchID
        loadingMore = true
        loadMoreErrorMessage = nil
        defer {
            if activeSearchID == searchID, resultsQuery == text, mode == requestMode {
                loadingMore = false
            }
        }

        do {
            var pageStart = nextPage
            var excluded = Set(results.map(\.bvid))
            var loaded: [Track] = []
            var stillHasRawResults = false

            // 严格音乐过滤后,某一批可能全被丢弃;连续跳过几批,避免底部看起来卡住。
            for _ in 0..<3 {
                // 30 页上限在循环内就生效,避免连跳空批时越界请求到 30 页之后
                guard pageStart <= 30 else { break }
                let batch = try await Self.searchBatch(
                    searchPage: searchPage,
                    keywords: activeKeywords,
                    pages: pageStart...(pageStart + 1),
                    query: text,
                    mode: requestMode,
                    excluding: excluded)
                pageStart += 2
                stillHasRawResults = batch.rawCount > 0
                guard stillHasRawResults else { break }
                if !batch.tracks.isEmpty {
                    loaded = batch.tracks
                    loaded.forEach { excluded.insert($0.bvid) }
                    break
                }
            }

            guard !Task.isCancelled,
                  activeSearchID == searchID,
                  resultsQuery == text,
                  mode == requestMode else { return }
            nextPage = pageStart
            hasMoreResults = stillHasRawResults && nextPage <= 30
            if !loaded.isEmpty {
                results.append(contentsOf: loaded)
                sections = SearchResultSections.make(from: results)
                cacheCurrentSnapshot()
                preload(loaded)
            }
        } catch {
            guard activeSearchID == searchID, resultsQuery == text, mode == requestMode else { return }
            loadMoreErrorMessage = error.localizedDescription
            hasMoreResults = true
        }
    }

    @discardableResult
    func restoreCachedResultsIfAvailable(for query: String) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = SearchCacheKey(query: text, mode: mode)
        guard let snapshot = resultCache[key] else { return false }
        touchResultCacheKey(key)
        results = snapshot.tracks
        sections = SearchResultSections.make(from: snapshot.tracks)
        resultsQuery = text
        activeQuery = text
        activeKeywords = snapshot.activeKeywords
        nextPage = snapshot.nextPage
        hasMoreResults = snapshot.hasMoreResults
        errorMessage = nil
        loadMoreErrorMessage = nil
        searching = false
        refreshingFromCache = false
        loadingMore = false
        return true
    }

    func setMode(_ newMode: SearchResultMode, query: String) {
        guard mode != newMode else { return }
        mode = newMode
        resetTransientState(cancelTask: true)
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            activeQuery = text
            _ = restoreCachedResultsIfAvailable(for: text)
        }
    }

    func retryCurrentSearch(preload: @escaping @MainActor ([Track]) -> Void) {
        let text = activeQuery.isEmpty ? resultsQuery : activeQuery
        submitSearch(text, preload: preload)
    }

    func broadenCurrentSearch(preload: @escaping @MainActor ([Track]) -> Void) {
        let text = activeQuery.isEmpty ? resultsQuery : activeQuery
        setMode(.expanded, query: text)
        submitSearch(text, preload: preload)
    }

    func storeCachedSnapshotForTesting(query: String, mode: SearchResultMode, snapshot: SearchCachedSnapshot) {
        storeCachedSnapshot(snapshot, for: SearchCacheKey(query: query, mode: mode))
    }

    func shouldShowSearchHistory() -> Bool {
        historyLoaded && results.isEmpty && !searchHistory.isEmpty && !searching && resultsQuery.isEmpty
    }

    func shouldShowEmptyState(searchFocused: Bool) -> Bool {
        historyLoaded && !searchFocused && results.isEmpty && searchHistory.isEmpty && !searching && errorMessage == nil && resultsQuery.isEmpty
    }

    func shouldShowNoResults(query: String) -> Bool {
        !searching
            && results.isEmpty
            && !resultsQuery.isEmpty
            && query.trimmingCharacters(in: .whitespacesAndNewlines) == resultsQuery
            && errorMessage == nil
    }

    func shouldShowResults(query: String) -> Bool {
        !searching
            && !results.isEmpty
            && query.trimmingCharacters(in: .whitespacesAndNewlines) == resultsQuery
    }

    private func resetTransientState(cancelTask: Bool) {
        if cancelTask {
            searchTask?.cancel()
        }
        activeSearchID = UUID()
        searching = false
        refreshingFromCache = false
        errorMessage = nil
        loadMoreErrorMessage = nil
        results = []
        sections = nil
        resultsQuery = ""
        activeQuery = ""
        activeKeywords = []
        nextPage = 1
        hasMoreResults = false
        loadingMore = false
    }

    private static func decodeSearchHistory(_ raw: String) async -> [String] {
        await Task.detached(priority: .utility) {
            (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? []
        }.value
    }

    private func rememberSearch(_ text: String) {
        historyLoadID = UUID()
        if !historyLoaded {
            let raw = UserDefaults.standard.string(forKey: historyKey) ?? "[]"
            searchHistory = (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? []
        }
        historyLoaded = true
        var items = searchHistory.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        items.insert(text, at: 0)
        items = Array(items.prefix(20))
        searchHistory = items
        refreshLocalContentHistory()
        if let data = try? JSONEncoder().encode(items),
           let string = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(string, forKey: historyKey)
        }
    }

    private func refreshLocalContentHistory() {
        localContent = SearchLocalContent(
            historyTerms: searchHistory,
            recentTracks: localContent.recentTracks,
            cachedTracks: localContent.cachedTracks)
    }

    private func search(text: String, mode requestMode: SearchResultMode, searchID: UUID, preload: @escaping @MainActor ([Track]) -> Void) async {
        defer {
            if activeSearchID == searchID, activeQuery == text, mode == requestMode {
                searching = false
                refreshingFromCache = false
            }
        }
        do {
            let keywords = Self.searchKeywords(for: text)
            let pageStart = 1
            let pageCount = 3
            let batch = try await Self.searchBatch(
                searchPage: searchPage,
                keywords: keywords,
                pages: pageStart...(pageStart + pageCount - 1),
                query: text,
                mode: requestMode)

            guard !Task.isCancelled,
                  activeSearchID == searchID,
                  activeQuery == text,
                  mode == requestMode else { return }
            results = batch.tracks
            sections = SearchResultSections.make(from: batch.tracks)
            resultsQuery = text
            activeQuery = text
            activeKeywords = keywords
            nextPage = pageStart + pageCount
            hasMoreResults = batch.rawCount > 0 && nextPage <= 30
            cacheCurrentSnapshot()
            preload(batch.tracks)
        } catch {
            guard !Task.isCancelled,
                  activeSearchID == searchID,
                  activeQuery == text,
                  mode == requestMode else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func cacheCurrentSnapshot() {
        guard !resultsQuery.isEmpty else { return }
        let key = SearchCacheKey(query: resultsQuery, mode: mode)
        let snapshot = SearchCachedSnapshot(
            tracks: results,
            nextPage: nextPage,
            activeKeywords: activeKeywords,
            hasMoreResults: hasMoreResults)
        storeCachedSnapshot(snapshot, for: key)
    }

    private func storeCachedSnapshot(_ snapshot: SearchCachedSnapshot, for key: SearchCacheKey) {
        resultCache[key] = snapshot
        touchResultCacheKey(key)
        while resultCacheOrder.count > Self.resultCacheLimit {
            let evicted = resultCacheOrder.removeFirst()
            resultCache[evicted] = nil
        }
    }

    private func touchResultCacheKey(_ key: SearchCacheKey) {
        resultCacheOrder.removeAll { $0 == key }
        resultCacheOrder.append(key)
    }

    private struct SearchBatch {
        let tracks: [Track]
        let rawCount: Int
    }

    private struct SearchPageResult: Sendable {
        let order: Int
        let tracks: [Track]?
        let errorMessage: String?
    }

    private struct SearchPageFailure: LocalizedError, Sendable {
        let message: String
        var errorDescription: String? { message }
    }

    private static func searchBatch(
        searchPage: @escaping SearchPageProvider,
        keywords: [String],
        pages: ClosedRange<Int>,
        query: String,
        mode: SearchResultMode,
        excluding excluded: Set<String> = []
    ) async throws -> SearchBatch {
        let pageResults = await withTaskGroup(of: SearchPageResult.self) { group in
            for (keywordIndex, keyword) in keywords.enumerated() {
                for page in pages {
                    let order = keywordIndex * 1_000 + page
                    group.addTask {
                        do {
                            return SearchPageResult(
                                order: order,
                                tracks: try await searchPage(keyword, page, mode.usesBiliMusicOnlySearch),
                                errorMessage: nil)
                        } catch {
                            return SearchPageResult(
                                order: order,
                                tracks: nil,
                                errorMessage: error.localizedDescription)
                        }
                    }
                }
            }
            var results: [SearchPageResult] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.order < $1.order }
        }
        let successfulPages = pageResults.compactMap(\.tracks)
        guard !successfulPages.isEmpty else {
            throw SearchPageFailure(
                message: pageResults.compactMap(\.errorMessage).first ?? "搜索请求失败")
        }
        let pageItems = successfulPages.flatMap { $0 }
        let filtered = await Task.detached(priority: .userInitiated) {
            dedupeSearchTracks(pageItems
                .filter { !excluded.contains($0.bvid) }
                .filter { MusicFilter.isSearchResult($0, query: query, mode: mode) })
        }.value
        return SearchBatch(tracks: filtered, rawCount: pageItems.count)
    }

    private static func defaultSearchPage(keyword: String, page: Int, musicOnly: Bool) async throws -> [Track] {
        let client = BiliClient()
        return try await client.search(keyword: keyword, page: page, musicOnly: musicOnly)
            .map(Track.init(search:))
    }

    private static func searchKeywords(for text: String) -> [String] {
        let compact = text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        guard compact != text, compact.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil else {
            return [text]
        }
        return [compact, text]
    }
}

private func dedupeSearchTracks(_ tracks: [Track]) -> [Track] {
    var seen = Set<String>()
    return tracks.filter { track in
        guard !seen.contains(track.bvid) else { return false }
        seen.insert(track.bvid)
        return true
    }
}
