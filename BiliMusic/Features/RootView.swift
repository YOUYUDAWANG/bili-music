import LNPopupUI
import SwiftUI
import UIKit

/// 根视图：系统 TabView 由 LNPopupUI 承载 Apple Music 式浮动播放条与交互式全屏转场。
struct RootView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPopupBarPresented = false
    @State private var isPopupOpen = false
    @State private var showSettings = false
    @State private var selectedTab = 0

    var body: some View {
        baseTabs
            .popup(isBarPresented: $isPopupBarPresented, isPopupOpen: $isPopupOpen) {
                PlayerPopupSurface(
                    isPopupOpen: $isPopupOpen
                )
            }
            .popupInteractionStyle(.automatic)
            .popupBarStyle(.floatingCompact)
            .popupBarInheritsBottomBarMetrics(true)
            .popupCloseButtonStyle(.grabber)
            .popupCloseButtonPositioning(.center)
            .popupContentAllowsContentTransition(true)
            .popupBarProgressViewStyle(.none)
            .popupBarShineEnabled(false)
            .popupBarCustomizer { popupBar in
                popupBar.accessibilityIdentifier = "miniPlayer"
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onAppear {
                syncPopupPresentation()
            }
            .onChange(of: selectedTab) { _, _ in
                engine.isMiniPlayerHidden = false
            }
            .onChange(of: engine.current?.id) { _, trackID in
                if trackID == nil {
                    isPopupOpen = false
                }
                syncPopupPresentation()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    Task {
                        await AppResourceCleanup.handleBackgrounding(engine: engine)
                    }
                case .inactive:
                    engine.prepareForInactiveSnapshot()
                case .active:
                    Task {
                        await engine.handleScenePhase(isBackground: false)
                    }
                @unknown default:
                    break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { notification in
                AppResourceCleanup.handleMemoryWarning(notification, engine: engine)
            }
            .task {
                Task(priority: .utility) {
                    await WBISigner.prewarm()
                }
                await BiliSessionStore.shared.refreshFromNav()
                await LibraryStore.shared.loadIfNeeded()
                await CacheStore.shared.loadIfNeeded()
                await PlaybackHistoryStore.shared.loadIfNeeded()
#if DEBUG
                if UITestFixtures.enabled {
                    engine.installUITestFixture(
                        tracks: UITestFixtures.startsWithoutCurrentTrack ? [] : UITestFixtures.homeTracks,
                        startAt: 0
                    )
                    isPopupBarPresented = engine.current != nil
                    if ProcessInfo.processInfo.environment["BILIMUSIC_UITEST_OPEN_FULL_PLAYER"] != nil {
                        isPopupOpen = true
                    }
                } else {
                    await engine.restorePersistedQueueIfNeeded()
                    isPopupBarPresented = engine.current != nil
                    await CacheStore.shared.enforceRetentionLimit()
                }
#else
                await engine.restorePersistedQueueIfNeeded()
                isPopupBarPresented = engine.current != nil
                await CacheStore.shared.enforceRetentionLimit()
#endif
                if let bv = ProcessInfo.processInfo.environment["AUTOPLAY_BV"] {
#if DEBUG
                    PlaybackDiagnostics.DebugRecentEventStore.shared.clear()
#endif
                    await engine.play(bvid: bv)
                    isPopupBarPresented = engine.current != nil
                    if ProcessInfo.processInfo.environment["AUTOPLAY_OPEN_FULL_PLAYER"] != nil {
                        isPopupOpen = true
                    }
                    NSLog("AUTOPLAY state=\(String(describing: engine.state)) track=\(engine.current?.title ?? "nil")")
#if DEBUG
                    for event in PlaybackDiagnostics.DebugRecentEventStore.shared.snapshot() {
                        NSLog("AUTOPLAY_DIAGNOSTIC \(event.description)")
                    }
#endif
                    if ProcessInfo.processInfo.environment["AUTOPLAY_TEST_NEXT"] != nil {
                        await engine.playNext()
                        NSLog("AUTOPLAY_NEXT state=\(String(describing: engine.state)) track=\(engine.current?.title ?? "nil")")
                    }
                }
            }
    }

    private var baseTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("音乐", systemImage: "square.grid.2x2", value: 0) {
                HomeView(
                    showSettings: $showSettings,
                    openPlayer: openPopupPlayer
                )
            }

            Tab("收藏夹", systemImage: "rectangle.stack", value: 1) {
                FavoritesView()
            }

            Tab("缓存", systemImage: "arrow.down.circle", value: 2) {
                LibraryView()
            }

            Tab("搜索", systemImage: "magnifyingglass", value: 3, role: .search) {
                SearchView()
            }
        }
        .tint(AppTheme.accent)
        .tabBarMinimizeBehavior(engine.current == nil ? .never : .onScrollDown)
    }

    private func syncPopupPresentation() {
        isPopupBarPresented = engine.current != nil
    }

    private func openPopupPlayer() {
        guard engine.current != nil else { return }
        isPopupBarPresented = true
        isPopupOpen = true
    }
}

/// 把高频播放状态更新限制在 popup 内容内部，避免根 TabView 跟随播放器重建。
private struct PlayerPopupSurface: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.popupBarPlacement) private var popupBarPlacement
    @Binding var isPopupOpen: Bool

    var body: some View {
        NowPlayingView(isPresented: isPopupOpen)
        .popupContentBackgroundColor(.black)
        .popupItem {
            PopupItem(
                id: engine.current?.id ?? "no-current-track",
                verbatimTitle: display?.title ?? "正在播放",
                verbatimSubtitle: display?.artist,
                image: popupImage,
                progress: nil,
                buttons: {
                ToolbarItem(placement: .popupBar) {
                    HStack(spacing: popupBarPlacement == .inline ? 0 : 18) {
                        Button {
                            engine.togglePlayPause()
                        } label: {
                            Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .accessibilityLabel(engine.state == .playing ? "暂停" : "播放")

                        if popupBarPlacement != .inline {
                            Button {
                                Task { await engine.playNext() }
                            } label: {
                                Image(systemName: "forward.fill")
                            }
                            .disabled(!engine.hasNext)
                            .accessibilityLabel("下一首")
                        }
                    }
                }
            })
        }
    }

    private var display: TrackTitleFormatter.DisplayMetadata? {
        engine.current.map { TrackTitleFormatter.displayMetadata(for: $0, clean: true) }
    }

    private var popupImage: PopupItemImageType {
        if let image = engine.currentCoverImage {
            return PopupItemImage(Image(uiImage: image), aspectRatio: 16 / 9, contentMode: .fill)
        }
        return PopupItemImage(Image(systemName: "music.note"), contentMode: .fit)
    }
}

@MainActor
enum AppResourceCleanup {
    static func handleBackgrounding(engine: PlayerEngine) async {
        engine.restoreCurrentArtworkFromImageCache()
        ImageMemoryCache.shared.releaseReloadableImages()
        try? await CacheStore.shared.flush()
        await PlaybackHistoryStore.shared.flush()
        await LibraryStore.shared.flush()
        await RecommendationMemory.shared.flush()
        await engine.flushPlaybackQueue()
        await engine.handleScenePhase(isBackground: true)
    }

    static func handleMemoryWarning(_ notification: Notification, engine: PlayerEngine? = nil) {
        guard notification.name == UIApplication.didReceiveMemoryWarningNotification else { return }
        engine?.restoreCurrentArtworkFromImageCache()
        ImageMemoryCache.shared.releaseReloadableImages()
    }
}
