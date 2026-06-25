import SwiftUI

/// 首页推荐:不用 B 站首页 feed(那是大杂烩)。种子优先从你的 B 站收藏夹随机抽取,
/// 再用「相关推荐」扩展,音乐关键词兜底。未登录/无收藏夹时回退到当前在播 + 最近缓存。
struct HomeView: View {
    @Environment(PlayerEngine.self) private var engine
    @Binding var showSettings: Bool
    @State private var tracks: [Track] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var trackTapTrigger = 0
    @State private var refreshTrigger = 0

    init(showSettings: Binding<Bool> = .constant(false)) {
        _showSettings = showSettings
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppTheme.error).font(.caption)
                }
                if !tracks.isEmpty {
                    Section {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            Button {
                                trackTapTrigger += 1
                                Task { await engine.play(tracks: tracks, startAt: index) }
                            } label: {
                                TrackRow(track: track, isPlaying: engine.current.map { track.key.matches($0) } ?? false)
                            }
                            .buttonStyle(.plain)
                            .sensoryFeedback(.intent(.lightImpact), trigger: trackTapTrigger)
                        }
                    } header: {
                        Text("为你推荐")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .hideMiniPlayerOnScroll()
            .scrollContentBackground(.hidden)
            .background(AppTheme.groupedBackground)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        refreshTrigger += 1
                        Task { await load() }
                    } label: {
                        Label("换一批", systemImage: "arrow.clockwise")
                    }
                    .disabled(loading)
                    .sensoryFeedback(.intent(.selection), trigger: refreshTrigger)
                    
                    Menu {
                        Button {
                            showSettings = true
                        } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
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

    /// 取一批推荐：排除「最近 3 小时已在首页推过」的曲目(跨重启生效)。
    /// 若排除集把候选掏空了就放宽一次,保证首页不空。
    private func load() async {
        loading = true
        defer { loading = false }
        errorMessage = nil
        let excluded = RecentHomeFeedStore.shared.recentKeys()
        var result = await fetch(excluding: excluded)
        if result.isEmpty, !excluded.isEmpty {
            result = await fetch(excluding: [])
        }
        if result.isEmpty {
            errorMessage = CookieStore.isLoggedIn ? "暂时没有找到合适的音乐推荐" : nil
        } else {
            RecentHomeFeedStore.shared.record(result.map(\.bvid))
            tracks = result
            engine.preload(tracks: result, limit: 3, delay: .milliseconds(700))
        }
    }

    private func fetch(excluding excluded: Set<TrackKey>) async -> [Track] {
        await RecommendationEngine().recommendations(
            mode: .home,
            context: .init(current: engine.current, queue: engine.queue, excludedKeys: excluded),
            limit: 30)
    }
}
