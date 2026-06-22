import SwiftUI

struct SearchView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var query = ""
    @State private var store = SearchStore()
    @State private var preparingTrackKey: TrackKey?
    @FocusState private var searchFocused: Bool
    @AppStorage("searchHistory") private var searchHistoryData = "[]"

    private var history: PlaybackHistoryStore { .shared }
    private var cache: CacheStore { .shared }

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
            }
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if store.shouldShowSearchHistory() && trimmedQuery.isEmpty {
                        Text("搜索历史")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 6)
                        VStack(spacing: 0) {
                            ForEach(store.searchHistory, id: \.self) { term in
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
                                if term != store.searchHistory.last {
                                    Divider().padding(.leading, 50)
                                }
                            }
                            Button {
                                store.clearHistory()
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

                    landingContent

                    if isTypingUnsubmittedQuery {
                        typingPrompt
                    }

                    if store.searching {
                        HStack(spacing: 10) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("正在搜索音乐...")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    } else if let errorMessage = store.errorMessage {
                        VStack(spacing: 10) {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .font(.caption)
                            Button("重试") {
                                store.retryCurrentSearch { tracks in
                                    engine.preload(tracks: tracks, limit: 2, delay: .milliseconds(500))
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else if store.shouldShowEmptyState(searchFocused: searchFocused) && !hasLandingContent {
                        ContentUnavailableView("搜点什么吧", systemImage: "music.note.list")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if store.shouldShowNoResults(query: query) {
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
                    }

                    if store.shouldShowResults(query: query) {
                        searchResultsView
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(AppTheme.groupedBackground)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            await store.loadHistory()
            await history.loadIfNeeded()
            await cache.loadIfNeeded()
        }
        .onChange(of: searchHistoryData) {
            store.reloadHistoryIfNeeded()
        }
        .onChange(of: query) {
            store.queryDidChange(query)
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTypingUnsubmittedQuery: Bool {
        !trimmedQuery.isEmpty && trimmedQuery != store.resultsQuery && !store.searching
    }

    private var recentTracks: [Track] {
        Array(history.entries.prefix(6).map(\.track))
    }

    private var cachedTracks: [Track] {
        Array(cache.entries.prefix(6).map(\.track))
    }

    private var hasLandingContent: Bool {
        trimmedQuery.isEmpty && (!recentTracks.isEmpty || !cachedTracks.isEmpty)
    }

    @ViewBuilder
    private var landingContent: some View {
        if trimmedQuery.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                landingSection(title: "最近播放", systemImage: "clock.fill", tracks: recentTracks)
                landingSection(title: "已缓存", systemImage: "arrow.down.circle.fill", tracks: cachedTracks)
            }
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var searchResultsView: some View {
        let sections = SearchResultSections.make(from: store.results)
        VStack(alignment: .leading, spacing: 16) {
            if let bestMatch = sections.bestMatch {
                searchSection(title: "最佳匹配", tracks: [bestMatch])
            }
            searchSection(title: "歌曲", tracks: sections.songs)
            searchSection(title: "MV", tracks: sections.mvs)
            paginationControl
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func searchSection(title: String, tracks: [Track]) -> some View {
        if !tracks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader(title)
                VStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        Button {
                            playSearchResult(track)
                        } label: {
                            searchResultRow(track: track)
                                .padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain)
                        if index != tracks.count - 1 {
                            Divider().padding(.leading, 84)
                        }
                    }
                }
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func landingSection(title: String, systemImage: String, tracks: [Track]) -> some View {
        if !tracks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.accent)
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 20)
                VStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        Button {
                            play(tracks: tracks, startAt: index, selected: track)
                        } label: {
                            searchResultRow(track: track)
                                .padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain)
                        if index != tracks.count - 1 {
                            Divider().padding(.leading, 84)
                        }
                    }
                }
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
    }

    private var paginationControl: some View {
        Group {
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
        }
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

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

    private func searchResultRow(track: Track) -> some View {
        HStack(spacing: 14) {
            TrackRow(
                track: track,
                isPlaying: engine.current.map { track.key.matches($0) } ?? false,
                showsTrailingIcon: false)
            if isPreparing(track) {
                ProgressView()
                    .scaleEffect(0.75)
            }
        }
    }

    private func isPreparing(_ track: Track) -> Bool {
        preparingTrackKey.map { $0.matches(track) } ?? false
    }

    private func playSearchResult(_ track: Track) {
        guard let index = store.results.firstIndex(where: { $0.key.matches(track) }) else { return }
        play(tracks: store.results, startAt: index, selected: track)
    }

    private func play(tracks: [Track], startAt index: Int, selected track: Track) {
        let key = track.key
        preparingTrackKey = key
        Task {
            await engine.play(tracks: tracks, startAt: index)
            await MainActor.run {
                if preparingTrackKey?.matches(track) == true {
                    preparingTrackKey = nil
                }
            }
        }
    }

    private func submitSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searchFocused = false
        store.submitSearch(text) { tracks in
            engine.preload(tracks: tracks, limit: 2, delay: .milliseconds(500))
        }
    }
}

struct TrackRow: View {
    let track: Track
    var isPlaying = false
    var showsTrailingIcon = true

    var body: some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: thumbnailURL(track.coverURL, size: 160)) { image in
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
            if showsTrailingIcon {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isPlaying ? AppTheme.accent : .secondary)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func format(_ seconds: Int) -> String {
        seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func thumbnailURL(_ url: URL?, size: Int) -> URL? {
        guard let url else { return nil }
        let raw = url.absoluteString
        guard raw.contains("hdslb.com"), !raw.contains("@") else { return url }
        return URL(string: raw + "@\(size)w_\(size)h_1c.webp")
    }
}
