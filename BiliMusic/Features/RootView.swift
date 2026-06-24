import SwiftUI

/// 根视图：底部 tab + 自定义全屏播放器浮层（从 mini bar 上滑出现）。
struct RootView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase
    @State private var showFullPlayer = false
    @State private var isDraggingFullPlayer = false
    @State private var openPlayerTranslation: CGFloat = 0
    @State private var showSettings = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TabView {
                    miniBarWrapper(HomeView())
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showSettings = true
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                        .tabItem { Label("推荐", systemImage: "music.note.house.fill") }
                    miniBarWrapper(SearchView())
                        .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                    miniBarWrapper(LibraryTabView())
                        .tabItem { Label("资料库", systemImage: "rectangle.stack.fill") }
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
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

    /// MiniPlayerBar 作为每个 tab 内容的安全区域底边距，确保内容不被 tab bar 遮挡。
    private func miniBarWrapper(_ content: some View) -> some View {
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
