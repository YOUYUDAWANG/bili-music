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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if let errorMessage {
                        MusicStatusBlock(
                            systemImage: "exclamationmark.triangle",
                            title: "推荐暂时不可用",
                            message: errorMessage
                        ) {
                            Text("重试")
                        } action: {
                            Task { await load(trigger: .manualRefresh) }
                        }
                    }

                    if !tracks.isEmpty {
                        featuredSection
                        queueSection
                    } else if loading {
                        MusicLoadingBlock(title: "正在准备音乐推荐...")
                    } else if errorMessage == nil {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .accessibilityIdentifier("homeList")
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle("推荐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        refreshTrigger += 1
                        Task { await load(trigger: .manualRefresh) }
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
            .refreshable { await load(trigger: .manualRefresh) }
            .task {
                if tracks.isEmpty { await load(trigger: .initialHomeLoad) }
            }
        }
    }

    @ViewBuilder
    private var featuredSection: some View {
        if let first = tracks.first {
            VStack(alignment: .leading, spacing: 10) {
                MusicSectionHeader(
                    title: "为你推荐",
                    subtitle: loading ? "正在换一批" : "来自你的音乐收藏和相似歌曲",
                    actionTitle: "换一批"
                ) {
                    refreshTrigger += 1
                    Task { await load(trigger: .manualRefresh) }
                }

                Button {
                    trackTapTrigger += 1
                    Task { await engine.play(tracks: tracks, startAt: 0) }
                } label: {
                    FeaturedTrackCard(
                        track: first,
                        isPlaying: engine.current.map { first.key.matches($0) } ?? false
                    )
                }
                .accessibilityIdentifier("homeTrackRow0")
                .buttonStyle(.plain)
                .sensoryFeedback(.intent(.lightImpact), trigger: trackTapTrigger)
            }
        }
    }

    private var emptyState: some View {
        MusicStatusBlock(
            systemImage: "music.note.list",
            title: "还没有音乐推荐",
            message: CookieStore.isLoggedIn
                ? "在 B 站收藏一些喜欢的歌，这里会按你的音乐口味生成推荐。"
                : "去设置扫码登录，即可用你的收藏夹生成推荐。"
        ) {
            Text(CookieStore.isLoggedIn ? "换一批" : "打开设置")
        } action: {
            if CookieStore.isLoggedIn {
                Task { await load(trigger: .manualRefresh) }
            } else {
                showSettings = true
            }
        }
    }

    @ViewBuilder
    private var queueSection: some View {
        let remaining = Array(tracks.dropFirst())
        if !remaining.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MusicSectionHeader(title: "接下来", subtitle: "\(remaining.count) 首歌")
                LazyVStack(spacing: 8) {
                    ForEach(Array(remaining.enumerated()), id: \.element.id) { offset, track in
                        let index = offset + 1
                        Button {
                            trackTapTrigger += 1
                            Task { await engine.play(tracks: tracks, startAt: index) }
                        } label: {
                            MusicTrackRow(
                                track: track,
                                isPlaying: engine.current.map { track.key.matches($0) } ?? false
                            )
                        }
                        .accessibilityIdentifier("homeTrackRow\(index)")
                        .buttonStyle(.plain)
                        .sensoryFeedback(.intent(.lightImpact), trigger: trackTapTrigger)
                    }
                }
            }
        }
    }

    /// 取一批推荐：排除「最近 3 小时已在首页推过」的曲目(跨重启生效)。
    /// 若排除集把候选掏空了就放宽一次,保证首页不空。
    private func load(trigger: RecommendationSchedulingPolicy.Trigger = .manualRefresh) async {
#if DEBUG
        if UITestFixtures.enabled {
            errorMessage = nil
            tracks = UITestFixtures.homeTracks
            engine.preload(tracks: tracks, limit: 0, delay: .zero)
            return
        }
#endif
        let policy = RecommendationSchedulingPolicy.home(trigger: trigger)
        loading = true
        defer { loading = false }
        errorMessage = nil
        let excluded = RecentHomeFeedStore.shared.recentKeys()
        var result = await fetch(excluding: excluded, policy: policy)
        if result.isEmpty, !excluded.isEmpty {
            result = await fetch(excluding: [], policy: policy)
        }
        if result.isEmpty {
            errorMessage = CookieStore.isLoggedIn ? "暂时没有找到合适的音乐推荐" : nil
        } else {
            RecentHomeFeedStore.shared.record(result.map(\.bvid))
            tracks = result
            engine.preload(tracks: result, limit: 3, delay: .milliseconds(700))
        }
    }

    private func fetch(excluding excluded: Set<TrackKey>, policy: RecommendationSchedulingPolicy) async -> [Track] {
        await RecommendationEngine().recommendations(
            mode: .home,
            context: .init(current: engine.current, queue: engine.queue, excludedKeys: excluded),
            limit: 30,
            policy: policy)
    }
}
