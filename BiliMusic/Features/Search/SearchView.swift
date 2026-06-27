//
//  SearchView.swift
//  BiliMusic
//
//  Created by 蓝发双马尾大小姐 on 2025/7/1.
//

import SwiftUI

struct SearchView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.isSearching) private var isSearching
    @State private var query = ""
    @State private var store = SearchStore()
    @State private var preparingTrackKey: TrackKey?
    @State private var searchResultTapTrigger = 0
    @AppStorage("searchHistory") private var searchHistoryData = "[]"

    private var history: PlaybackHistoryStore { .shared }
    private var cache: CacheStore { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                searchContent
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
            }
            .accessibilityIdentifier("searchList")
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "歌名或艺人"
            ) {
                searchSuggestions
            }
            .onSubmit(of: .search) {
                submitSearch()
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .task {
            await store.loadHistory()
            Task(priority: .background) {
                await history.loadIfNeeded()
                await cache.loadIfNeeded()
            }
        }
        .onChange(of: searchHistoryData) {
            store.reloadHistoryIfNeeded()
        }
        .onChange(of: query) { _, newValue in
            store.queryDidChange(newValue)
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recentTracks: [Track] {
        Array(history.entries.prefix(6).map(\.track))
    }

    private var cachedTracks: [Track] {
        Array(cache.entries.prefix(6).map(\.track))
    }

    private var localContent: SearchLocalContent {
        SearchLocalContent(
            historyTerms: store.searchHistory,
            recentTracks: recentTracks,
            cachedTracks: cachedTracks)
    }

    @ViewBuilder
    private var searchContent: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            if trimmedQuery.isEmpty {
                let content = localContent
                if isSearching {
                    focusedSearchContent(content)
                } else if content.recentTracks.isEmpty && content.cachedTracks.isEmpty {
                    MusicStatusBlock(
                        systemImage: "magnifyingglass",
                        title: "搜索音乐",
                        message: "输入歌名、艺人或来源，查找适合播放的音乐内容。"
                    )
                } else {
                    if !content.historyTerms.isEmpty {
                        historySection(content.historyTerms)
                    }
                    trackSection(title: "最近播放", subtitle: "继续听上次打开过的歌曲", tracks: content.recentTracks)
                    trackSection(title: "已缓存", subtitle: "离线也能播放", tracks: content.cachedTracks)
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
    }

    @ViewBuilder
    private var searchSuggestions: some View {
        let content = localContent
        if store.historyLoaded, !content.historyTerms.isEmpty {
            ForEach(content.historyTerms, id: \.self) { term in
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

    @ViewBuilder
    private func focusedSearchContent(_ content: SearchLocalContent) -> some View {
        if !content.historyTerms.isEmpty {
            historySection(content.historyTerms)
        } else {
            MusicStatusBlock(
                systemImage: "clock",
                title: "还没有搜索历史",
                message: "输入歌名或艺人后按搜索，结果会从这里开始加载。"
            )
        }
    }

    private var loadingRow: some View {
        MusicLoadingBlock(title: "正在搜索音乐...")
    }

    private func errorRow(_ message: String) -> some View {
        MusicStatusBlock(
            systemImage: "exclamationmark.triangle",
            title: "搜索失败",
            message: message
        ) {
            Text("重试")
        } action: {
            store.retryCurrentSearch { tracks in
                engine.preload(tracks: tracks, limit: 2, delay: .milliseconds(500))
            }
        }
    }

    private var noResultsRow: some View {
        MusicStatusBlock(
            systemImage: "music.note.list",
            title: "没有找到音乐结果",
            message: "当前只显示音乐内容，可以放宽过滤查看更多结果。"
        ) {
            Text("更多结果")
        } action: {
            store.broadenCurrentSearch { tracks in
                engine.preload(tracks: tracks, limit: 2, delay: .milliseconds(500))
            }
        }
    }

    @ViewBuilder
    private func historySection(_ terms: [String]) -> some View {
        if !terms.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MusicSectionHeader(title: "最近搜索")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(terms, id: \.self) { term in
                            Button {
                                query = term
                                submitSearch()
                            } label: {
                                Label(term, systemImage: "clock")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .frame(height: 34)
                                    .background(AppTheme.background, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        Button(role: .destructive) {
                            store.clearHistory()
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 34)
                                .background(AppTheme.background, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    @ViewBuilder
    private func resultSections(_ sections: SearchResultSections) -> some View {
        if let bestMatch = sections.bestMatch {
            trackSection(title: "最佳匹配", subtitle: nil, tracks: [bestMatch])
        }
        let remainingTracks = sections.songs + sections.mvs
        trackSection(title: "音乐结果", subtitle: "\(remainingTracks.count) 首", tracks: remainingTracks)
    }

    @ViewBuilder
    private func trackSection(title: String, subtitle: String? = nil, tracks: [Track]) -> some View {
        if !tracks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MusicSectionHeader(title: title, subtitle: subtitle)
                LazyVStack(spacing: 8) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        Button {
                            searchResultTapTrigger += 1
                            if store.shouldShowResults(query: query) {
                                playSearchResult(track)
                            } else {
                                play(tracks: tracks, startAt: index, selected: track)
                            }
                        } label: {
                            searchResultRow(track: track)
                        }
                        .contentShape(Rectangle())
                        .buttonStyle(MusicRowButtonStyle())
                        .sensoryFeedback(.intent(.lightImpact), trigger: searchResultTapTrigger)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var paginationControl: some View {
        VStack(spacing: 10) {
            if store.loadingMore {
                MusicLoadingBlock(title: "正在加载更多...")
                    .frame(minHeight: 96)
            } else if let message = store.loadMoreErrorMessage {
                VStack(spacing: 8) {
                    Text("加载更多失败")
                        .font(.caption.weight(.semibold))
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        Task {
                            await store.loadMore { tracks in
                                engine.preload(tracks: tracks, limit: 1, delay: .milliseconds(700))
                            }
                        }
                    } label: {
                        Text("重试加载")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 84)
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Text("没有更多结果")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    private func searchResultRow(track: Track) -> some View {
        MusicTrackRow(
            track: track,
            isPlaying: engine.current.map { track.key.matches($0) } ?? false,
            showsMenu: false,
            isLoading: isPreparing(track)
        )
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
        store.submitSearch(text) { tracks in
            engine.preload(tracks: tracks, limit: 2, delay: .milliseconds(500))
        }
    }

}
