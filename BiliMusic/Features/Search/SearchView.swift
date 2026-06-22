import SwiftUI

struct SearchView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var query = ""
    @State private var store = SearchStore()
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
                    if store.shouldShowSearchHistory() {
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

                    if store.searching {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 36)
                    } else if let errorMessage = store.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    } else if store.shouldShowEmptyState(searchFocused: searchFocused) {
                        ContentUnavailableView("搜点什么吧", systemImage: "music.note.list")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if store.shouldShowNoResults(query: query) {
                        ContentUnavailableView("没有找到音乐结果", systemImage: "music.note.list")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }

                    if store.shouldShowResults(query: query) {
                        VStack(spacing: 0) {
                            ForEach(Array(store.results.enumerated()), id: \.element.id) { index, track in
                                Button {
                                    Task { await engine.play(tracks: store.results, startAt: index) }
                                } label: {
                                    TrackRow(track: track, isPlaying: engine.current.map { track.key.matches($0) } ?? false)
                                        .padding(.horizontal, 14)
                                }
                                .buttonStyle(.plain)
                                if index != store.results.count - 1 {
                                    Divider().padding(.leading, 84)
                                }
                                if index >= store.results.count - 6 {
                                    Color.clear
                                        .frame(height: 1)
                                        .onAppear {
                                            Task {
                                                await store.loadMoreIfNeeded { tracks in
                                                    engine.preload(tracks: tracks, limit: 1, delay: .milliseconds(700))
                                                }
                                            }
                                        }
                                }
                            }
                            if store.loadingMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                            } else if !store.hasMoreResults {
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
            await store.loadHistory()
        }
        .onChange(of: searchHistoryData) {
            store.reloadHistoryIfNeeded()
        }
        .onChange(of: query) {
            store.queryDidChange(query)
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
            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isPlaying ? AppTheme.accent : .secondary)
                .frame(width: 28, height: 28)
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
