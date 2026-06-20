import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "search")

/// 搜索页：本地 TextField + 搜索历史 + 分页结果。多关键词并发查询、严格音乐过滤、忽略过期响应。
struct SearchView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var query = ""
    @State private var results: [Track] = []
    @State private var searchHistory: [String] = []
    @State private var searching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var activeSearchID = UUID()
    @State private var historyLoaded = false
    @State private var resultsQuery = ""
    @State private var activeKeywords: [String] = []
    @State private var nextPage = 1
    @State private var hasMoreResults = false
    @State private var loadingMore = false
    @FocusState private var searchFocused: Bool
    @AppStorage("searchHistory") private var searchHistoryData = "[]"

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("搜索")
                    .font(.largeTitle.weight(.bold))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("歌名或 UP 主", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($searchFocused)
                        .onSubmit { submitSearch() }
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if shouldShowSearchHistory {
                        Text("搜索历史")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 6)
                        VStack(spacing: 0) {
                            ForEach(searchHistory, id: \.self) { term in
                                Button {
                                    query = term
                                    submitSearch()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 24)
                                        Text(term)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 46)
                                }
                                .buttonStyle(.plain)
                                if term != searchHistory.last {
                                    Divider().padding(.leading, 50)
                                }
                            }
                            Button {
                                searchHistory = []
                                searchHistoryData = "[]"
                            } label: {
                                HStack {
                                    Text("清空搜索历史")
                                        .foregroundStyle(.red)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 46)
                            }
                            .buttonStyle(.plain)
                        }
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                    }

                    if searching {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 36)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    } else if shouldShowEmptyState {
                        ContentUnavailableView("搜点什么吧", systemImage: "music.note.list")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if shouldShowNoResults {
                        ContentUnavailableView("没有找到音乐结果", systemImage: "music.note.list")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }

                    if shouldShowResults {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, track in
                                Button {
                                    Task { await engine.play(tracks: results, startAt: index) }
                                } label: {
                                    TrackRow(track: track, isPlaying: engine.current?.bvid == track.bvid)
                                        .padding(.horizontal, 14)
                                }
                                .buttonStyle(.plain)
                                .onAppear { engine.schedulePreload(track) }
                                if index != results.count - 1 {
                                    Divider().padding(.leading, 84)
                                }
                                if index >= results.count - 6 {
                                    Color.clear
                                        .frame(height: 1)
                                        .onAppear {
                                            Task { await loadMoreIfNeeded() }
                                        }
                                }
                            }
                            if loadingMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                            } else if !hasMoreResults {
                                Text("没有更多结果")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                        }
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(AppTheme.groupedBackground)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            guard !historyLoaded else { return }
            try? await Task.sleep(for: .milliseconds(180))
            searchHistory = decodeSearchHistory()
            historyLoaded = true
        }
        .onChange(of: searchHistoryData) {
            guard historyLoaded else { return }
            searchHistory = decodeSearchHistory()
        }
        .onChange(of: query) {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                searchTask?.cancel()
                activeSearchID = UUID()
                searching = false
                errorMessage = nil
                results = []
                resultsQuery = ""
                activeKeywords = []
                nextPage = 1
                hasMoreResults = false
                loadingMore = false
            } else if text != resultsQuery {
                searchTask?.cancel()
                activeSearchID = UUID()
                searching = false
                errorMessage = nil
                results = []
                activeKeywords = []
                nextPage = 1
                hasMoreResults = false
                loadingMore = false
            }
        }
    }

    /// 从持久化字符串解码搜索历史。
    private func decodeSearchHistory() -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(searchHistoryData.utf8))) ?? []
    }

    /// 是否展示「搜索历史」区。
    private var shouldShowSearchHistory: Bool {
        historyLoaded && results.isEmpty && !searchHistory.isEmpty && !searching && resultsQuery.isEmpty
    }

    /// 是否展示初始空状态。
    private var shouldShowEmptyState: Bool {
        historyLoaded && !searchFocused && results.isEmpty && searchHistory.isEmpty && !searching && errorMessage == nil && resultsQuery.isEmpty
    }

    /// 是否展示「没有结果」。
    private var shouldShowNoResults: Bool {
        !searching
            && results.isEmpty
            && !resultsQuery.isEmpty
            && query.trimmingCharacters(in: .whitespacesAndNewlines) == resultsQuery
            && errorMessage == nil
    }

    /// 是否展示结果列表。
    private var shouldShowResults: Bool {
        !searching
            && !results.isEmpty
            && query.trimmingCharacters(in: .whitespacesAndNewlines) == resultsQuery
    }

    /// 提交搜索：重置状态、记历史、起一个可取消的搜索任务。
    private func submitSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searchFocused = false
        searchTask?.cancel()
        let searchID = UUID()
        activeSearchID = searchID
        results = []
        resultsQuery = ""
        activeKeywords = []
        nextPage = 1
        hasMoreResults = false
        loadingMore = false
        errorMessage = nil
        searching = true
        rememberSearch(text)
        searchTask = Task { await search(text: text, searchID: searchID) }
    }

    /// 把搜索词记入历史（去重置顶，上限 20）。
    private func rememberSearch(_ text: String) {
        var items = searchHistory.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        items.insert(text, at: 0)
        items = Array(items.prefix(20))
        searchHistory = items
        if let data = try? JSONEncoder().encode(items),
           let string = String(data: data, encoding: .utf8) {
            searchHistoryData = string
        }
    }

    /// 执行首批搜索（多关键词 × 多页并发），用 searchID 忽略过期响应。
    private func search(text: String, searchID: UUID) async {
        defer {
            if activeSearchID == searchID {
                searching = false
            }
        }
        do {
            let client = BiliClient()
            let keywords = searchKeywords(for: text)
            let pageStart = 1
            let pageCount = 3
            let batch = try await searchBatch(
                client: client,
                keywords: keywords,
                pages: pageStart...(pageStart + pageCount - 1),
                query: text)
            
            guard !Task.isCancelled else { return }
            guard !Task.isCancelled, activeSearchID == searchID else { return }
            results = batch.tracks
            resultsQuery = text
            activeKeywords = keywords
            nextPage = pageStart + pageCount
            hasMoreResults = batch.rawCount > 0 && nextPage <= 30
            engine.preload(tracks: batch.tracks)
        } catch {
            guard !Task.isCancelled, activeSearchID == searchID else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// 滚到底部时加载更多；严格过滤可能整批被丢，故连试几批避免底部卡住。
    private func loadMoreIfNeeded() async {
        guard shouldShowResults,
              hasMoreResults,
              !searching,
              !loadingMore,
              !activeKeywords.isEmpty else { return }

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
                let batch = try await searchBatch(
                    client: client,
                    keywords: activeKeywords,
                    pages: pageStart...(pageStart + 1),
                    query: text,
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
                engine.preload(tracks: loaded)
            }
        } catch {
            guard activeSearchID == searchID, resultsQuery == text else { return }
            hasMoreResults = false
        }
    }

    /// 一批搜索结果：过滤后的曲目 + 原始条数（判断是否还有更多）。
    private struct SearchBatch {
        let tracks: [Track]
        let rawCount: Int
    }

    /// 并发查询多关键词多页，合并 → 去重 → 严格音乐过滤（过滤在后台线程）。
    private func searchBatch(
        client: BiliClient,
        keywords: [String],
        pages: ClosedRange<Int>,
        query: String,
        excluding excluded: Set<String> = []
    ) async throws -> SearchBatch {
        let pageItems = try await withThrowingTaskGroup(of: [BiliClient.SearchItem].self) { group in
            for keyword in keywords {
                for page in pages {
                    group.addTask {
                        try await client.search(keyword: keyword, page: page, musicOnly: true)
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
            dedupe(pageItems.map(Track.init(search:))
                .filter { !excluded.contains($0.bvid) }
                .filter { MusicFilter.isSearchResultMusic($0, query: query) })
        }.value
        return SearchBatch(tracks: filtered, rawCount: pageItems.count)
    }

    /// 为查询词生成关键词变体（纯英数时额外尝试去空格版）。
    private func searchKeywords(for text: String) -> [String] {
        let compact = text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        guard compact != text, compact.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil else {
            return [text]
        }
        return [compact, text]
    }
}

/// 按 bvid 去重，保留首次出现顺序。
private func dedupe(_ tracks: [Track]) -> [Track] {
    var seen = Set<String>()
    return tracks.filter { track in
        guard !seen.contains(track.bvid) else { return false }
        seen.insert(track.bvid)
        return true
    }
}

/// 通用曲目行：封面 + 标题 + UP 主 + 时长，播放中高亮。各列表复用。
struct TrackRow: View {
    let track: Track
    var isPlaying = false

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: thumbnailURL(track.coverURL, size: 160)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    AppTheme.secondaryBackground
                    Image(systemName: "music.note").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(isPlaying ? AppTheme.accent : .primary)
                HStack(spacing: 6) {
                    if isPlaying {
                        Image(systemName: "waveform").font(.caption2).foregroundStyle(AppTheme.accent)
                    }
                    Text(track.artist)
                    Text(format(track.duration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isPlaying ? AppTheme.accent : .secondary)
                .frame(width: 28, height: 28)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    /// 秒数格式化为 mm:ss / h:mm:ss。
    private func format(_ seconds: Int) -> String {
        seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// 给 B 站封面拼上缩略图缩放参数。
    private func thumbnailURL(_ url: URL?, size: Int) -> URL? {
        guard let url else { return nil }
        let raw = url.absoluteString
        guard raw.contains("hdslb.com"), !raw.contains("@") else { return url }
        return URL(string: raw + "@\(size)w_\(size)h_1c.webp")
    }
}
