import SwiftUI

struct RootView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var showFullPlayer = false

    var body: some View {
        TabView {
            withMiniBar(HomeView())
                .tabItem { Label("推荐", systemImage: "music.house") }
            withMiniBar(SearchView())
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            withMiniBar(FavoritesView())
                .tabItem { Label("收藏", systemImage: "star") }
            withMiniBar(LibraryView())
                .tabItem { Label("缓存", systemImage: "arrow.down.circle") }
            withMiniBar(SettingsView())
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .sheet(isPresented: $showFullPlayer) {
            NowPlayingView()
        }
        .task {
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
                MiniPlayerBar(showFullPlayer: $showFullPlayer)
            }
        }
    }
}
