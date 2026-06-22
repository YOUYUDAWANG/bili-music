import SwiftUI

/// 根视图：底部 tab + 自定义全屏播放器浮层（从 mini bar 上滑出现）。
struct RootView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase
    @State private var showFullPlayer = false
    @State private var isDraggingFullPlayer = false
    @State private var openPlayerTranslation: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TabView {
                    withMiniBar(HomeView())
                        .tabItem { Label("推荐", systemImage: "music.note.house.fill") }
                    withMiniBar(SearchView())
                        .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                    withMiniBar(FavoritesView())
                        .tabItem { Label("收藏", systemImage: "heart.fill") }
                    withMiniBar(LibraryView())
                        .tabItem { Label("缓存", systemImage: "arrow.down.circle.fill") }
                    withMiniBar(SettingsView())
                        .tabItem { Label("设置", systemImage: "gearshape.fill") }
                }
                .tint(AppTheme.accent)

                if showFullPlayer || isDraggingFullPlayer {
                    NowPlayingView {
                        closeFullPlayer()
                    }
                    .offset(y: fullPlayerOffset(height: proxy.size.height))
                    .ignoresSafeArea()
                    .zIndex(10)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task {
                    await CacheStore.shared.flush()
                    await PlaybackHistoryStore.shared.flush()
                    await engine.handleScenePhase(isBackground: true)
                }
            }
        }
        .task {
            Task(priority: .utility) {
                await WBISigner.prewarm()
            }
            await CacheStore.shared.loadIfNeeded()
            await PlaybackHistoryStore.shared.loadIfNeeded()
            // 调试用:simctl launch 注入 AUTOPLAY_BV 即可无交互验证播放链路
            if let bv = ProcessInfo.processInfo.environment["AUTOPLAY_BV"] {
                await engine.play(bvid: bv)
                NSLog("AUTOPLAY state=\(String(describing: engine.state)) track=\(engine.current?.title ?? "nil")")
                if ProcessInfo.processInfo.environment["AUTOPLAY_TEST_NEXT"] != nil {
                    await engine.playNext()
                    NSLog("AUTOPLAY_NEXT state=\(String(describing: engine.state)) track=\(engine.current?.title ?? "nil")")
                }
            }
        }
    }

    /// mini bar 放在 tab 内容的 safe area,这样不会盖住标签栏
    private func withMiniBar(_ content: some View) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if engine.current != nil {
                MiniPlayerBar(
                    showFullPlayer: $showFullPlayer,
                    isDraggingFullPlayer: $isDraggingFullPlayer,
                    openPlayerTranslation: $openPlayerTranslation)
            }
        }
    }

    /// 全屏播放器的纵向偏移：展开为 0，否则停在屏幕下方并随拖动跟手。
    private func fullPlayerOffset(height: CGFloat) -> CGFloat {
        if showFullPlayer {
            return 0
        }
        return max(0, height + openPlayerTranslation)
    }

    /// 收起全屏播放器，回到 mini 模式。
    private func closeFullPlayer() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            showFullPlayer = false
            isDraggingFullPlayer = false
            openPlayerTranslation = 0
        }
    }
}
