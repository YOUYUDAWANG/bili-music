//
//  SearchView.swift
//  BiliMusic
//
//  Created by 蓝发双马尾大小姐 on 2025/7/1.
//

import SwiftUI

struct SearchView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var query = ""
    @State private var store = SearchStore()
    @State private var preparingTrackKey: TrackKey?
    @State private var debounceTask: Task<Void, Never>?
    @State private var searchResultTapTrigger = 0
    @AppStorage("searchHistory") private var searchHistoryData = "[]"

    private var history: PlaybackHistoryStore { .shared }
    private var cache: CacheStore { .shared }

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
            .scrollDismissesKeyboard(.immediately)
        }
        .task {
            await store.loadHistory()
            Task(priority: .background) {
                await history.loadIfNeeded()
                await cache.loadIfNeeded()
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .onChange(of: searchHistoryData) {
            store.reloadHistoryIfNeeded()
        }
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
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

    private var searchModeBinding: Binding<SearchResultMode> {
        Binding {
            store.mode
        } set: { mode in
            store.setMode(mode, query: query)
            guard !trimmedQuery.isEmpty else { return }
            submitSearch()
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

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.82)
            Text("正在搜索音乐...")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 68)
        .listRowSeparator(.hidden)
    }

    private func errorRow(_ message: String) -> some View {
        VStack(spacing: 10) {
            Text(message)
                .foregroundStyle(AppTheme.error)
                .font(.caption)
                .multilineTextAlignment(.center)
            Button("重试") {
                store.retryCurrentSearch { tracks in
                    engine.preload(tracks: tracks, limit: 2, delay: .milliseconds(500))
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .listRowSeparator(.hidden)
    }

    private var noResultsRow: some View {
        unavailableRow {
            ContentUnavailableView {
                Label("没有找到音乐结果", systemImage: "music.note.list")
            } description: {
                Text("当前只显示音乐内容，可以查看更多结果。")
            } actions: {
                Button("更多结果") {
                    store.broadenCurrentSearch { tracks in
                        engine.preload(tracks: tracks, limit: 2, delay: .milliseconds(500))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultSections(_ sections: SearchResultSections) -> some View {
        if let bestMatch = sections.bestMatch {
            trackSection(title: "最佳匹配", tracks: [bestMatch])
        }
        trackSection(title: "歌曲", tracks: sections.songs)
        trackSection(title: "MV", tracks: sections.mvs)
    }

    @ViewBuilder
    private func trackSection(title: String, tracks: [Track]) -> some View {
        if !tracks.isEmpty {
            Section(title) {
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
                    .buttonStyle(.plain)
                    .sensoryFeedback(.intent(.lightImpact), trigger: searchResultTapTrigger)
                }
            }
        }
    }

    @ViewBuilder
    private var paginationControl: some View {
        Section {
            if store.loadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 48)
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
        HStack(spacing: 10) {
            TrackRow(
                track: track,
                isPlaying: engine.current.map { track.key.matches($0) } ?? false,
                showsTrailingIcon: false
            )
            if isPreparing(track) {
                ProgressView()
                    .scaleEffect(0.75)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func unavailableRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 220)
            .listRowInsets(EdgeInsets(top: 24, leading: 0, bottom: 24, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
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

    private func debouncedSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.submitSearch(text) { tracks in
            engine.preload(tracks: tracks, limit: 2, delay: .milliseconds(500))
        }
    }
}
