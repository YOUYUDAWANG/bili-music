import SwiftUI

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
