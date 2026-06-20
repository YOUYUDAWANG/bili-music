import SwiftUI

/// app 入口。创建全局唯一的 `PlayerEngine`，并通过 environment 注入整棵视图树。
@main
struct BiliMusicApp: App {
    @State private var engine = PlayerEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
        }
    }
}
