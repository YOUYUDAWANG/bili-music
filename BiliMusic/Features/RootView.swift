import SwiftUI
import UIKit

/// 根视图：使用系统 TabView + iOS 26 bottom accessory 承载 mini 播放器。
struct RootView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showFullPlayer = false
    @State private var fullPlayerOpenProgress: CGFloat = 0
    @State private var miniOpenDragTranslation: CGFloat?
    @State private var isTrackingMiniOpenDrag = false
    @State private var sharedPlayerTransitionActive = false
    @State private var showSettings = false
    @State private var selectedTab = 0
    @Namespace private var playerTransition

    private enum Motion {
        static let open = Animation.smooth(duration: 0.46, extraBounce: 0.08)
        static let close = Animation.smooth(duration: 0.32, extraBounce: 0.02)
        static let cancel = Animation.smooth(duration: 0.22, extraBounce: 0)
        static let closeRemovalDelay: TimeInterval = 0.34
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                systemTabs
                    .accessibilityHidden(showFullPlayer)

                if engine.current != nil && (showFullPlayer || isMiniOpening || fullPlayerOpenProgress > 0) {
                    Color.black
                        .opacity(fullPlayerScrimOpacity)
                        .ignoresSafeArea()
                        .zIndex(9)
                        .allowsHitTesting(false)

                    NowPlayingView(
                        onDismiss: { closeFullPlayer() },
                        namespace: playerTransition,
                        usesSharedTransition: usesSharedPlayerTransition,
                        isCoverTransitionSource: showFullPlayer,
                        coverRevealProgress: renderedPlayerOpenProgress,
                        contentRevealProgress: renderedPlayerOpenProgress,
                        safeAreaTop: proxy.safeAreaInsets.top
                    )
                        .offset(y: fullPlayerOffset(height: proxy.size.height, safeAreaInsets: proxy.safeAreaInsets))
                        .scaleEffect(
                            x: fullPlayerScaleX,
                            y: fullPlayerScaleY,
                            anchor: .bottom
                        )
                        .ignoresSafeArea()
                        .zIndex(10)
                        .allowsHitTesting(showFullPlayer)
                }

            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: selectedTab) { _, _ in
            engine.isMiniPlayerHidden = false
        }
        .onChange(of: engine.current?.id) { _, trackID in
            if trackID == nil {
                resetFullPlayerState()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                Task {
                    await AppResourceCleanup.handleBackgrounding(engine: engine)
                }
            case .inactive:
                Task {
                    await engine.handleScenePhase(isBackground: true)
                }
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
            await CacheStore.shared.loadIfNeeded()
            await PlaybackHistoryStore.shared.loadIfNeeded()
#if DEBUG
            if UITestFixtures.enabled {
                engine.installUITestFixture(tracks: UITestFixtures.homeTracks, startAt: 0)
                if ProcessInfo.processInfo.environment["BILIMUSIC_UITEST_OPEN_FULL_PLAYER"] != nil {
                    DispatchQueue.main.async {
                        openFullPlayer(startProgress: 1)
                    }
                }
            }
#endif
            // 调试用:simctl launch 注入 AUTOPLAY_BV 即可无交互验证播放链路。
            if let bv = ProcessInfo.processInfo.environment["AUTOPLAY_BV"] {
#if DEBUG
                PlaybackDiagnostics.DebugRecentEventStore.shared.clear()
#endif
                await engine.play(bvid: bv)
                if ProcessInfo.processInfo.environment["AUTOPLAY_OPEN_FULL_PLAYER"] != nil {
                    openFullPlayer(startProgress: 1)
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

    @ViewBuilder
    private var systemTabs: some View {
        baseTabs
            .tabViewBottomAccessory {
                if engine.current != nil {
                    SystemMiniPlayer(
                        miniOpenDragTranslation: $miniOpenDragTranslation,
                        isFullPlayerPresented: showFullPlayer,
                        namespace: playerTransition,
                        usesSharedTransition: usesSharedPlayerTransition,
                        openProgress: renderedPlayerOpenProgress,
                        openFullPlayer: { openFullPlayer() },
                        onOpenDragChanged: { handleMiniOpenDragChanged($0) },
                        onOpenDragEnded: { handleMiniOpenDragEnded($0) }
                    )
                }
            }
    }

    private var openAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : Motion.open
    }

    private var closeAnimation: Animation {
        reduceMotion ? .easeIn(duration: 0.12) : Motion.close
    }

    private var cancelAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.10) : Motion.cancel
    }

    private var closeRemovalDelay: TimeInterval {
        reduceMotion ? 0.14 : Motion.closeRemovalDelay
    }

    private var baseTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("推荐", systemImage: "music.note.house", value: 0) {
                HomeView(showSettings: $showSettings)
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
        .tabBarMinimizeBehavior(shouldPreventTabBarMinimize ? .never : .onScrollDown)
    }

    private var shouldPreventTabBarMinimize: Bool {
        isMiniOpening || showFullPlayer || fullPlayerOpenProgress > 0
    }

    private func fullPlayerOffset(height: CGFloat, safeAreaInsets: EdgeInsets) -> CGFloat {
        guard showFullPlayer || isMiniOpening || fullPlayerOpenProgress > 0 else {
            return height
        }
        let offscreenOffset = height + safeAreaInsets.bottom + 24
        return offscreenOffset * (1 - renderedPlayerOpenProgress)
    }

    private var isMiniOpening: Bool {
        miniOpenDragTranslation != nil
    }

    private var playerOpenProgress: CGFloat {
        if let miniOpenDragTranslation {
            return PlayerGesturePolicy.miniOpenProgress(for: miniOpenDragTranslation)
        }
        return min(1, max(0, fullPlayerOpenProgress))
    }

    private var renderedPlayerOpenProgress: CGFloat {
        PlayerGesturePolicy.renderedMiniOpenProgress(
            rawProgress: playerOpenProgress,
            isMiniOpening: isMiniOpening,
            isFullPlayerPresented: showFullPlayer)
    }

    private var usesSharedPlayerTransition: Bool {
        sharedPlayerTransitionActive || isMiniOpening
    }

    private var fullPlayerScrimOpacity: Double {
        Double(min(0.58, max(0, renderedPlayerOpenProgress * 0.58)))
    }

    private var fullPlayerScaleX: CGFloat {
        guard !reduceMotion else { return 1 }
        return 0.985 + renderedPlayerOpenProgress * 0.015
    }

    private var fullPlayerScaleY: CGFloat {
        guard !reduceMotion else { return 1 }
        return 0.992 + renderedPlayerOpenProgress * 0.008
    }

    private func openFullPlayer(startProgress explicitStartProgress: CGFloat? = nil) {
        let startProgress = max(explicitStartProgress ?? playerOpenProgress, 0.04)
        #if DEBUG
        NSLog("mini->full open startProgress=%.3f", Double(startProgress))
        #endif
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            sharedPlayerTransitionActive = true
            showFullPlayer = true
            miniOpenDragTranslation = nil
            isTrackingMiniOpenDrag = false
            fullPlayerOpenProgress = min(1, startProgress)
        }

        withAnimation(openAnimation) {
            fullPlayerOpenProgress = 1
        }
        finishSharedPlayerTransitionAfterOpen()
    }

    private func cancelFullPlayerDrag() {
        withAnimation(cancelAnimation) {
            miniOpenDragTranslation = nil
            isTrackingMiniOpenDrag = false
            showFullPlayer = false
            fullPlayerOpenProgress = 0
            sharedPlayerTransitionActive = false
        }
    }

    private func closeFullPlayer() {
        sharedPlayerTransitionActive = true
        withAnimation(closeAnimation) {
            miniOpenDragTranslation = nil
            isTrackingMiniOpenDrag = false
            fullPlayerOpenProgress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + closeRemovalDelay) {
            guard fullPlayerOpenProgress <= 0.01 else { return }
            showFullPlayer = false
            sharedPlayerTransitionActive = false
        }
    }

    private func resetFullPlayerState() {
        showFullPlayer = false
        miniOpenDragTranslation = nil
        isTrackingMiniOpenDrag = false
        fullPlayerOpenProgress = 0
        sharedPlayerTransitionActive = false
    }

    private func finishSharedPlayerTransitionAfterOpen() {
        let delay: TimeInterval = reduceMotion ? 0.16 : 0.56
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard showFullPlayer, fullPlayerOpenProgress >= 0.99, !isMiniOpening else { return }
            sharedPlayerTransitionActive = false
        }
    }

    private func finishMiniOpenDrag(_ sample: MiniOpenDragSample) {
        defer { miniOpenDragTranslation = nil }
        guard engine.current != nil, !showFullPlayer else { return }
        guard PlayerGesturePolicy.shouldFinishMiniOpenDrag(
            translationY: sample.translation.height,
            velocityY: sample.velocity.height
        ) else {
            cancelFullPlayerDrag()
            return
        }

        openFullPlayer(startProgress: PlayerGesturePolicy.initialMiniOpenProgress(
            for: sample.translation.height))
    }

    private func handleMiniOpenDragChanged(_ sample: MiniOpenDragSample) {
        guard engine.current != nil, !showFullPlayer else {
            isTrackingMiniOpenDrag = false
            return
        }

        if !isTrackingMiniOpenDrag {
            guard shouldBeginMiniOpenDrag(sample) else { return }
            isTrackingMiniOpenDrag = true
        }

        miniOpenDragTranslation = sample.translation.height
        if PlayerGesturePolicy.shouldOpenMiniPlayerLive(
            translationY: sample.translation.height,
            velocityY: sample.velocity.height
        ) {
            isTrackingMiniOpenDrag = false
            miniOpenDragTranslation = nil
            openFullPlayer(startProgress: PlayerGesturePolicy.initialMiniOpenProgress(for: sample.translation.height))
            return
        }
    }

    private func handleMiniOpenDragEnded(_ sample: MiniOpenDragSample) {
        guard isTrackingMiniOpenDrag else { return }
        isTrackingMiniOpenDrag = false
        #if DEBUG
        NSLog("mini drag ended translationY=%.1f velocityY=%.1f", Double(sample.translation.height), Double(sample.velocity.height))
        #endif
        finishMiniOpenDrag(sample)
    }

    private func shouldBeginMiniOpenDrag(_ sample: MiniOpenDragSample) -> Bool {
        PlayerGesturePolicy.shouldBeginMiniOpenDrag(translation: sample.translation)
    }

    private func miniOpenProgress(for translationY: CGFloat) -> CGFloat {
        PlayerGesturePolicy.miniOpenProgress(for: translationY)
    }
}

@MainActor
enum AppResourceCleanup {
    static func handleBackgrounding(engine: PlayerEngine) async {
        engine.restoreCurrentArtworkFromImageCache()
        ImageMemoryCache.shared.releaseReloadableImages()
        await CacheStore.shared.flush()
        await PlaybackHistoryStore.shared.flush()
        await engine.handleScenePhase(isBackground: true)
    }

    static func handleMemoryWarning(_ notification: Notification, engine: PlayerEngine? = nil) {
        guard notification.name == UIApplication.didReceiveMemoryWarningNotification else { return }
        engine?.restoreCurrentArtworkFromImageCache()
        ImageMemoryCache.shared.releaseReloadableImages()
    }
}

/// 系统底部 accessory 中的 mini 播放器。封面保持 16:9。
private struct SystemMiniPlayer: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(TrackTitleFormatter.cleanListTitlesDefaultsKey) private var cleanListTitles = false
    @Binding var miniOpenDragTranslation: CGFloat?
    let isFullPlayerPresented: Bool
    var namespace: Namespace.ID
    let usesSharedTransition: Bool
    let openProgress: CGFloat
    let openFullPlayer: () -> Void
    let onOpenDragChanged: (MiniOpenDragSample) -> Void
    let onOpenDragEnded: (MiniOpenDragSample) -> Void
    @State private var playPauseTrigger = 0
    @State private var nextTrigger = 0

    private var isInline: Bool {
        placement == .inline
    }

    var body: some View {
        let layoutProgress = miniLayoutProgress
        let accessoryProgress = isFullPlayerPresented || miniOpenDragTranslation != nil
            ? transitionProgress(openProgress)
            : 0
        let display = engine.current.map { TrackTitleFormatter.displayMetadata(for: $0, clean: cleanListTitles) }

        HStack(spacing: lerp(7, 9, layoutProgress)) {
            HStack(spacing: lerp(7, 9, layoutProgress)) {
                artwork(layoutProgress: layoutProgress)

                VStack(alignment: .leading, spacing: 1) {
                    Text(display?.title ?? "")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .accessibilityIdentifier("miniPlayerTitle")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(display?.artist ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(height: 13, alignment: .top)
                        .clipped()
                }
                .frame(height: 30, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: openFullPlayer)

            miniControlButton(
                systemName: engine.state == .playing ? "pause.fill" : "play.fill",
                accessibilityLabel: engine.state == .playing ? "暂停" : "播放",
                layoutProgress: layoutProgress,
                trigger: $playPauseTrigger
            ) {
                engine.togglePlayPause()
            }

            miniControlButton(
                systemName: "forward.fill",
                accessibilityLabel: "下一首",
                layoutProgress: layoutProgress,
                trigger: $nextTrigger
            ) {
                Task { await engine.playNext() }
            }
            .disabled(!engine.hasNext)
            .opacity(engine.hasNext ? 1.0 : 0.32)
        }
        .padding(.horizontal, lerp(10, 12, layoutProgress))
        .frame(maxWidth: .infinity)
        .frame(height: lerp(40, 48, layoutProgress))
        .contentShape(Rectangle())
        .highPriorityGesture(miniOpenDragGesture, including: .all)
        .opacity(miniPlayerOpacity(accessoryProgress: accessoryProgress))
        .scaleEffect(1 - accessoryProgress * 0.03, anchor: .bottom)
        .accessibilityElement(children: .contain)
	        .accessibilityLabel(display?.title ?? "正在播放")
        .accessibilityIdentifier("miniPlayer")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, openFullPlayer)
        .onDisappear { miniOpenDragTranslation = nil }
    }

    private var miniLayoutProgress: CGFloat {
        guard isInline else { return 1 }
        if let miniOpenDragTranslation {
            return min(1, max(0, -miniOpenDragTranslation / 34))
        }
        guard isFullPlayerPresented || openProgress > 0 else { return 0 }
        return min(1, max(0, openProgress / 0.12))
    }

    private func artwork(layoutProgress: CGFloat) -> some View {
        let currentTrack = engine.current
        return Group {
            if let url = thumbnailURL(currentTrack?.coverURL, width: 150, height: 85) {
                CachedAsyncImage(
                    url: url,
                    targetSize: CGSize(width: 44, height: 25),
                    fallbackImage: engine.currentCoverImage,
                    onImageLoaded: { image in
                        engine.rememberCurrentCover(image, for: currentTrack)
                    }
                ) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    artworkPlaceholder
                }
            } else if let currentCoverImage = engine.currentCoverImage {
                Image(uiImage: currentCoverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                artworkPlaceholder
            }
        }
        .miniPlayerSharedGeometry(id: "playerArtwork", in: namespace, active: usesSharedTransition)
        .frame(width: lerp(34, 44, layoutProgress), height: lerp(19, 25, layoutProgress))
        .clipShape(RoundedRectangle(cornerRadius: lerp(4, 5, layoutProgress), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: lerp(4, 5, layoutProgress), style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.10), radius: 2.5, x: 0, y: 1)
        .accessibilityIdentifier("miniPlayerArtwork")
    }

    private var artworkPlaceholder: some View {
        ZStack {
            Color.primary.opacity(0.055)
            LinearGradient(
                colors: [
                    Color.primary.opacity(0.12),
                    Color.primary.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.42))
        }
    }

    private func miniControlButton(
        systemName: String,
        accessibilityLabel: String,
        layoutProgress: CGFloat,
        trigger: Binding<Int>,
        action: @escaping () -> Void
    ) -> some View {
        let size = lerp(28, 32, layoutProgress)
        return Button {
            trigger.wrappedValue += 1
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(MiniPlayerControlButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .sensoryFeedback(.impact(weight: .medium), trigger: trigger.wrappedValue)
    }

    private func miniPlayerOpacity(accessoryProgress: CGFloat) -> Double {
        if isFullPlayerPresented {
            return 0
        }
        return Double(max(0, 1 - max(0, (accessoryProgress - 0.14) / 0.86)))
    }

    private var miniOpenDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                onOpenDragChanged(miniOpenDragSample(from: value))
            }
            .onEnded { value in
                onOpenDragEnded(miniOpenDragSample(from: value))
            }
    }

    private func miniOpenDragSample(from value: DragGesture.Value) -> MiniOpenDragSample {
        let predictedVelocity = CGSize(
            width: (value.predictedEndTranslation.width - value.translation.width) / PlayerGesturePolicy.velocityProjectionTime,
            height: (value.predictedEndTranslation.height - value.translation.height) / PlayerGesturePolicy.velocityProjectionTime
        )
        return MiniOpenDragSample(
            startLocation: value.startLocation,
            location: value.location,
            translation: value.translation,
            velocity: predictedVelocity
        )
    }

    private func thumbnailURL(_ url: URL?, width: Int, height: Int) -> URL? {
        guard let url else { return nil }
        let raw = url.absoluteString
        guard !raw.localizedCaseInsensitiveContains("transparent.png") else { return nil }
        guard raw.contains("hdslb.com"), !raw.contains("@") else { return url }
        return URL(string: raw + "@\(width)w_\(height)h_1c.webp")
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * min(1, max(0, progress))
    }
}

private struct MiniOpenDragSample {
    let startLocation: CGPoint
    let location: CGPoint
    let translation: CGSize
    let velocity: CGSize
}

private func transitionProgress(_ progress: CGFloat) -> CGFloat {
    let clamped = min(1, max(0, progress))
    let smoother = clamped * clamped * clamped * (clamped * (clamped * 6 - 15) + 10)
    return smoother
}

private extension View {
    @ViewBuilder
    func miniPlayerSharedGeometry(id: String, in namespace: Namespace.ID, active: Bool) -> some View {
        if active {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
