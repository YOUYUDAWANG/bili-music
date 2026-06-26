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
    private(set) var activeQuery = ""

    private var searchTask: Task<Void, Never>?
    private var activeSearchID = UUID()
    private var activeKeywords: [String] = []
    private var nextPage = 1
    private var resultCache: [SearchCacheKey: SearchCachedSnapshot] = [:]
    private let historyKey = "searchHistory"

    func loadHistory() async {
        guard !historyLoaded else { return }
        let raw = UserDefaults.standard.string(forKey: historyKey) ?? "[]"
        searchHistory = await Self.decodeSearchHistory(raw)
        historyLoaded = true
    }

    func reloadHistoryIfNeeded() {
        guard historyLoaded else { return }
        let raw = UserDefaults.standard.string(forKey: historyKey) ?? "[]"
        Task {
            searchHistory = await Self.decodeSearchHistory(raw)
        }
    }

    func clearHistory() {
        searchHistory = []
        UserDefaults.standard.set("[]", forKey: historyKey)
    }

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

    func loadMoreIfNeeded(preload: @escaping @MainActor ([Track]) -> Void) async {
        await loadMore(preload: preload)
    }

    func loadMore(preload: @escaping @MainActor ([Track]) -> Void) async {
        guard shouldShowResults(query: resultsQuery),
              hasMoreResults,
              !searching,
              !loadingMore,
              !activeKeywords.isEmpty else { return }
        await loadMorePage(preload: preload)
    }

    private func loadMorePage(preload: @escaping @MainActor ([Track]) -> Void) async {
        let text = resultsQuery
        let searchID = activeSearchID
        loadingMore = true
        defer { loadingMore = false }

        do {
            let client = BiliClient()
            var pageStart = nextPage
            var excluded = Set(results.map(\.bvid))
            var loaded: [Track] = []
            var stillHasRawResults = false

            // 严格音乐过滤后,某一批可能全被丢弃;连续跳过几批,避免底部看起来卡住。
            for _ in 0..<3 {
                let batch = try await Self.searchBatch(
                    client: client,
                    keywords: activeKeywords,
                    pages: pageStart...(pageStart + 1),
                    query: text,
                    mode: mode,
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
                  resultsQuery == text else { return }
            nextPage = pageStart
            hasMoreResults = stillHasRawResults && nextPage <= 30
            if !loaded.isEmpty {
                results.append(contentsOf: loaded)
                cacheCurrentSnapshot()
                preload(loaded)
            }
        } catch {
            guard activeSearchID == searchID, resultsQuery == text else { return }
            hasMoreResults = false
        }
    }

    @discardableResult
    func restoreCachedResultsIfAvailable(for query: String) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = SearchCacheKey(query: text, mode: mode)
        guard let snapshot = resultCache[key] else { return false }
        results = snapshot.tracks
        sections = SearchResultSections.make(from: snapshot.tracks)
        resultsQuery = text
        activeQuery = text
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
        resultCache[SearchCacheKey(query: query, mode: mode)] = snapshot
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

    private static func decodeSearchHistory(_ raw: String) async -> [String] {
        await Task.detached(priority: .utility) {
            (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? []
        }.value
    }

    private func rememberSearch(_ text: String) {
        var items = searchHistory.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        items.insert(text, at: 0)
        items = Array(items.prefix(20))
        searchHistory = items
        if let data = try? JSONEncoder().encode(items),
           let string = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(string, forKey: historyKey)
        }
    }

    private func search(text: String, searchID: UUID, preload: @escaping @MainActor ([Track]) -> Void) async {
        defer {
            if activeSearchID == searchID {
                searching = false
            }
        }
        do {
            let client = BiliClient()
            let keywords = Self.searchKeywords(for: text)
            let pageStart = 1
            let pageCount = 3
            let batch = try await Self.searchBatch(
                client: client,
                keywords: keywords,
                pages: pageStart...(pageStart + pageCount - 1),
                query: text,
                mode: mode)

            guard !Task.isCancelled, activeSearchID == searchID else { return }
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
            guard !Task.isCancelled, activeSearchID == searchID else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func cacheCurrentSnapshot() {
        guard !resultsQuery.isEmpty else { return }
        resultCache[SearchCacheKey(query: resultsQuery, mode: mode)] = SearchCachedSnapshot(
            tracks: results,
            nextPage: nextPage,
            activeKeywords: activeKeywords,
            hasMoreResults: hasMoreResults)
    }

    private struct SearchBatch {
        let tracks: [Track]
        let rawCount: Int
    }

    private static func searchBatch(
        client: BiliClient,
        keywords: [String],
        pages: ClosedRange<Int>,
        query: String,
        mode: SearchResultMode,
        excluding excluded: Set<String> = []
    ) async throws -> SearchBatch {
        let pageItems = try await withThrowingTaskGroup(of: [BiliClient.SearchItem].self) { group in
            for keyword in keywords {
                for page in pages {
                    group.addTask {
                        try await client.search(
                            keyword: keyword,
                            page: page,
                            musicOnly: mode.usesBiliMusicOnlySearch)
                    }
                }
            }
            var allItems: [BiliClient.SearchItem] = []
            for try await items in group {
                allItems.append(contentsOf: items)
            }
            return allItems
        }
        let filtered = await Task.detached(priority: .userInitiated) {
            dedupeSearchTracks(pageItems.map(Track.init(search:))
                .filter { !excluded.contains($0.bvid) }
                .filter { MusicFilter.isSearchResult($0, query: query, mode: mode) })
        }.value
        return SearchBatch(tracks: filtered, rawCount: pageItems.count)
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
