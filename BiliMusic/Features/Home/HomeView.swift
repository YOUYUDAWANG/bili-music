import SwiftUI

/// 首页推荐:不用 B 站首页 feed(那是大杂烩)。种子优先从你的 B 站收藏夹随机抽取,
/// 再用「相关推荐」扩展,音乐关键词兜底。未登录/无收藏夹时回退到当前在播 + 最近缓存。
struct HomeView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var tracks: [Track] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var shownBVIDs: Set<String> = []

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
                            .onAppear { engine.schedulePreload(track) }
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
                                           description: Text(CookieStore.isLoggedIn
                                               ? "在 B 站收藏些喜欢的歌,这里会按收藏夹给你推荐"
                                               : "去设置扫码登录,即可用你的收藏夹生成推荐"))
                }
            }
            .task {
                if tracks.isEmpty { await load() }
            }
        }
    }

    /// 取一批推荐；累计 shownBVIDs 去重，超过 80 个就清空重来。
    private func load() async {
        loading = true
        defer { loading = false }
        errorMessage = nil
        if shownBVIDs.count >= 80 { shownBVIDs = [] }
        let result = await RecommendationEngine().recommendations(
            mode: .home,
            context: .init(current: engine.current, queue: engine.queue, excludedBVIDs: shownBVIDs),
            limit: 30)
        if result.isEmpty {
            errorMessage = CookieStore.isLoggedIn ? "暂时没有找到合适的音乐推荐" : nil
        } else {
            shownBVIDs.formUnion(result.map(\.bvid))
            tracks = result
            engine.preload(tracks: result)
        }
    }
}
