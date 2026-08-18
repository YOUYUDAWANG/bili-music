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
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $query,
                placement: .automatic,
                prompt: "歌名或艺人"
            ) {
                searchSuggestions
            }
            .onSubmit(of: .search) {
                submitSearch()
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .sensoryFeedback(.intent(.lightImpact), trigger: searchResultTapTrigger)
        .task {
            await store.loadLocalContent(history: history, cache: cache)
        }
        .onChange(of: searchHistoryData) {
            store.reloadHistoryIfNeeded()
            store.refreshLocalContent(history: history, cache: cache)
        }
        .onChange(of: history.contentRevision) {
            store.refreshLocalContent(history: history, cache: cache)
        }
        .onChange(of: cache.contentRevision) {
            store.refreshLocalContent(history: history, cache: cache)
        }
        .onChange(of: query) { _, newValue in
            store.queryDidChange(newValue)
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var searchContent: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            if trimmedQuery.isEmpty {
                let content = store.localContent
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
                    coverShelf(title: "最近播放", subtitle: "继续听上次打开过的歌曲", tracks: content.recentTracks)
                    coverShelf(title: "已缓存", subtitle: "离线也能播放", tracks: content.cachedTracks)
                }
            } else if store.shouldShowResults(query: query), let sections = store.sections {
                resultSections(sections)
                if store.searching {
                    loadingRow
                } else {
                    paginationControl
                }
            } else if store.searching {
                loadingRow
            } else if let errorMessage = store.errorMessage {
                errorRow(errorMessage)
            } else if store.shouldShowNoResults(query: query) {
                noResultsRow
            }
        }
    }

    @ViewBuilder
    private var searchSuggestions: some View {
        let content = store.localContent
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
                VStack(spacing: 0) {
                    ForEach(Array(terms.prefix(8).enumerated()), id: \.element) { index, term in
                        Button {
                            query = term
                            submitSearch()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                Text(term)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 46)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(MusicRowButtonStyle())

                        if index != min(terms.count, 8) - 1 {
                            Divider()
                                .padding(.leading, 34)
                        }
                    }

                    Button(role: .destructive) {
                        store.clearHistory()
                    } label: {
                        Label("清除搜索历史", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 46)
                    }
                    .buttonStyle(.plain)
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
                LazyVStack(spacing: 0) {
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

                        if index != tracks.indices.last {
                            Divider()
                                .padding(.leading, 84)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func coverShelf(title: String, subtitle: String? = nil, tracks: [Track]) -> some View {
        if !tracks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MusicSectionHeader(title: title, subtitle: subtitle)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 10) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            Button {
                                searchResultTapTrigger += 1
                                play(tracks: tracks, startAt: index, selected: track)
                            } label: {
                                MagazineTrackTile(
                                    track: track,
                                    isPlaying: engine.current.map { track.key.matches($0) } ?? false)
                                    .frame(width: 196)
                            }
                            .buttonStyle(MusicRowButtonStyle())
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("searchShelf-\(title)")
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
                        Label("重试加载", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 96)
            } else if store.hasMoreResults {
                Button {
                    Task {
                        await store.loadMore { tracks in
                            engine.preload(tracks: tracks, limit: 1, delay: .milliseconds(700))
                        }
                    }
                } label: {
                    Label("加载更多", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
            } else {
                Text("没有更多结果")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    private func searchResultRow(track: Track) -> some View {
        TrackRow(
            track: track,
            isPlaying: engine.current.map { track.key.matches($0) } ?? false,
            showsTrailingIcon: false,
            isLoading: isPreparing(track),
            appearance: .prominent
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
