import SwiftUI

/// 首页推荐:不用 B 站首页 feed(那是大杂烩)。种子优先从你的 B 站收藏夹随机抽取,
/// 再用「相关推荐」扩展,音乐关键词兜底。未登录/无收藏夹时回退到当前在播 + 最近缓存。
struct HomeView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var tracks: [Track] = []
    @State private var loading = false
    @State private var loadingMore = false
    @State private var hasMore = true
    @State private var errorMessage: String?
    @State private var shownKeys: Set<TrackKey> = []
    /// 每次加载/换一批时递增,驱动 loadMore 重新触发
    @State private var loadGeneration = 0

    private let pageSize = 20
    /// 首次加载的最小目标条数——少于此数自动追加加载
    private let initialTarget = 40

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
                                TrackRow(track: track, isPlaying: engine.current.map { track.key.matches($0) } ?? false)
                            }
                            .buttonStyle(.plain)
                        }
                        // 加载更多指示器 — 用 task 替代 onAppear,生命周期更可靠
                        if hasMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .id("loadMore-\(loadGeneration)")
                                .task { await loadMore() }
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
                    Task { await refresh() }
                } label: {
                    Label("换一批", systemImage: "arrow.clockwise")
                }
                .disabled(loading || loadingMore)
            }
            .refreshable { await refresh() }
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

    /// 首次加载:取 initialTarget 首,不够就继续追加
    private func load() async {
        loading = true
        defer { loading = false }
        errorMessage = nil
        tracks = []
        shownKeys = []
        hasMore = true
        loadGeneration += 1

        let result = await fetch(offset: 0)
        if result.isEmpty {
            errorMessage = CookieStore.isLoggedIn ? "暂时没有找到合适的音乐推荐" : nil
            hasMore = false
            return
        }
        shownKeys.formUnion(result.map(\.key))
        tracks = result
        engine.preload(tracks: result, limit: 3, delay: .milliseconds(700))

        // 第一次加载不够屏幕高度 → 继续追加
        if tracks.count < initialTarget {
            await appendMore(target: initialTarget)
        }
    }

    /// 换一批:重建推荐池,排除已展示的歌曲
    private func refresh() async {
        loading = true
        defer { loading = false }
        errorMessage = nil
        if shownKeys.count >= 80 { shownKeys = [] }

        let result = await fetch(offset: 0, excluding: shownKeys)
        if result.isEmpty {
            if shownKeys.isEmpty {
                errorMessage = CookieStore.isLoggedIn ? "暂时没有找到合适的音乐推荐" : nil
                hasMore = false
            } else {
                shownKeys = []
                return await refresh()
            }
        } else {
            shownKeys.formUnion(result.map(\.key))
            tracks = result
            hasMore = true
            loadGeneration += 1
            engine.preload(tracks: result, limit: 3, delay: .milliseconds(700))

            if tracks.count < initialTarget {
                await appendMore(target: initialTarget)
            }
        }
    }

    /// 翻页加载更多
    private func loadMore() async {
        guard hasMore, !loading, !loadingMore, !tracks.isEmpty else { return }
        loadingMore = true
        defer { loadingMore = false }

        let result = await fetch(offset: tracks.count)
        if result.isEmpty {
            hasMore = false
        } else {
            tracks += result
        }
    }

    /// 持续追加直到达到 target 或池子耗尽
    private func appendMore(target: Int) async {
        while tracks.count < target && hasMore {
            guard !loadingMore else { return }
            loadingMore = true
            let result = await fetch(offset: tracks.count)
            loadingMore = false
            if result.isEmpty {
                hasMore = false
            } else {
                tracks += result
            }
        }
    }

    /// 统一请求入口
    private func fetch(offset: Int, excluding excludedKeys: Set<TrackKey> = []) async -> [Track] {
        await RecommendationEngine().recommendations(
            mode: .home,
            context: .init(current: engine.current, queue: engine.queue, excludedKeys: excludedKeys),
            limit: pageSize, offset: offset)
    }
}
