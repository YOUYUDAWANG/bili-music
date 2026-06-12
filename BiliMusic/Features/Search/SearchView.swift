import SwiftUI

struct SearchView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var query = ""
    @State private var results: [Track] = []
    @State private var searchHistory: [String] = []
    @State private var searching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var activeSearchID = UUID()
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
                    if results.isEmpty, !searchHistory.isEmpty, !searching {
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
                    } else if results.isEmpty && searchHistory.isEmpty {
                        ContentUnavailableView("搜点什么吧", systemImage: "music.note.list")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }

                    if !results.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, track in
                                Button {
                                    Task { await engine.play(tracks: results, startAt: index) }
                                } label: {
                                    TrackRow(track: track, isPlaying: engine.current?.bvid == track.bvid)
                                        .padding(.horizontal, 14)
                                }
                                .buttonStyle(.plain)
                                if index != results.count - 1 {
                                    Divider().padding(.leading, 84)
                                }
                            }
                        }
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(AppTheme.groupedBackground)
        .task {
            searchHistory = decodeSearchHistory()
            await WBISigner.prewarm()
        }
        .onChange(of: searchHistoryData) {
            searchHistory = decodeSearchHistory()
        }
        .onChange(of: query) {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchTask?.cancel()
                activeSearchID = UUID()
                searching = false
                errorMessage = nil
                results = []
            }
        }
    }

    private func decodeSearchHistory() -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(searchHistoryData.utf8))) ?? []
    }

    private func submitSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searchTask?.cancel()
        let searchID = UUID()
        activeSearchID = searchID
        results = []
        errorMessage = nil
        searching = true
        rememberSearch(text)
        searchTask = Task { await search(text: text, searchID: searchID) }
    }

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

    private func search(text: String, searchID: UUID) async {
        defer {
            if activeSearchID == searchID {
                searching = false
            }
        }
        do {
            let client = BiliClient()
            let keywords = searchKeywords(for: text)
            let pages = try await withThrowingTaskGroup(of: (Int, [BiliClient.SearchItem]).self) { group in
                for (keywordIndex, keyword) in keywords.enumerated() {
                    for page in 1...3 {
                        group.addTask {
                            (keywordIndex * 10 + page, try await client.search(keyword: keyword, page: page))
                        }
                    }
                }
                var byPage: [(Int, [BiliClient.SearchItem])] = []
                for try await pageItems in group {
                    byPage.append(pageItems)
                }
                return byPage
                    .sorted { $0.0 < $1.0 }
                    .flatMap(\.1)
            }
            guard !Task.isCancelled else { return }
            let filtered = await Task.detached(priority: .userInitiated) {
                dedupe(pages.map(Track.init(search:)).filter { MusicFilter.isSearchResultMusic($0, query: text) })
            }.value
            guard !Task.isCancelled, activeSearchID == searchID else { return }
            results = filtered
            engine.preload(tracks: filtered)
        } catch {
            guard !Task.isCancelled, activeSearchID == searchID else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func searchKeywords(for text: String) -> [String] {
        let compact = text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        guard compact != text, compact.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil else {
            return [text]
        }
        return [compact, text]
    }
}

private func dedupe(_ tracks: [Track]) -> [Track] {
    var seen = Set<String>()
    return tracks.filter { track in
        guard !seen.contains(track.bvid) else { return false }
        seen.insert(track.bvid)
        return true
    }
}

struct TrackRow: View {
    let track: Track
    var isPlaying = false

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: track.coverURL) { image in
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
}
