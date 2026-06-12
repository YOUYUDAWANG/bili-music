import SwiftUI

/// 首页推荐:不用 B 站首页 feed,只从歌曲相关推荐/音乐搜索里取内容,避免推荐页变成大杂烩。
struct HomeView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var tracks: [Track] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var keywordIndex = 0

    private let fallbackKeywords = [
        "华语音乐 MV",
        "日语歌 翻唱",
        "粤语歌 live",
        "纯音乐 piano",
        "动漫 OST 音乐",
    ]

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
                if !tracks.isEmpty {
                    Section {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            Button {
                                Task { await engine.play(tracks: tracks, startAt: index) }
                            } label: {
                                TrackRow(track: track, isPlaying: engine.current?.bvid == track.bvid)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("为你推荐")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.groupedBackground)
            .navigationTitle("推荐")
            .toolbar {
                Button {
                    Task { await load() }
                } label: {
                    Label("换一批", systemImage: "arrow.clockwise")
                }
                .disabled(loading)
            }
            .refreshable { await load() }
            .overlay {
                if loading && tracks.isEmpty { ProgressView() }
                else if tracks.isEmpty && errorMessage == nil {
                    ContentUnavailableView("还没有音乐推荐", systemImage: "music.note.list",
                                           description: Text("播放或缓存几首歌后,这里会更像你的音乐电台"))
                }
            }
            .task {
                if tracks.isEmpty { await load() }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        errorMessage = nil
        do {
            var collected: [Track] = []

            for seed in recommendationSeeds() {
                let related = try await BiliClient().related(bvid: seed.bvid)
                    .map(Track.init(related:))
                    .filter(MusicFilter.isStrictMusic)
                collected.append(contentsOf: related)
                if collected.count >= 20 { break }
            }

            if collected.count < 12 {
                let keyword = fallbackKeywords[keywordIndex % fallbackKeywords.count]
                keywordIndex += 1
                let searched = try await BiliClient().search(keyword: keyword)
                    .map(Track.init(search:))
                    .filter(MusicFilter.isStrictMusic)
                collected.append(contentsOf: searched)
            }

            collected = dedupe(collected).filter { track in
                engine.current?.bvid != track.bvid
            }
            tracks = collected
            engine.preload(tracks: collected)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recommendationSeeds() -> [Track] {
        var seeds: [Track] = []
        if let current = engine.current {
            seeds.append(current)
        }
        seeds.append(contentsOf: CacheStore.shared.entries.prefix(4).map(\.track))
        return dedupe(seeds)
    }

    private func dedupe(_ input: [Track]) -> [Track] {
        var seen = Set<String>()
        return input.filter { track in
            guard !seen.contains(track.bvid) else { return false }
            seen.insert(track.bvid)
            return true
        }
    }
}
