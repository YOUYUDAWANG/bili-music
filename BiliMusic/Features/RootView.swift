import SwiftUI

/// 根视图：使用系统 TabView + iOS 26 bottom accessory 承载 mini 播放器。
struct RootView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showFullPlayer = false
    @State private var fullPlayerOpenProgress: CGFloat = 0
    @State private var miniOpenDragTranslation: CGFloat?
    @State private var isTrackingMiniOpenDrag = false
    @State private var showSettings = false
    @State private var selectedTab = 0
    @Namespace private var playerTransition

    private enum Metrics {
        static let openingDragRange: CGFloat = 190
        static let openingActivationProgress: CGFloat = 0.10
        static let liveOpeningActivationProgress: CGFloat = 0.07
        static let predictedOpeningMinimumProgress: CGFloat = 0.10
        static let openingPredictedActivationProgress: CGFloat = 0.38
    }

    private enum Motion {
        static let open = Animation.interpolatingSpring(mass: 0.86, stiffness: 170, damping: 21, initialVelocity: 0)
        static let close = Animation.interpolatingSpring(mass: 0.92, stiffness: 210, damping: 28, initialVelocity: 0)
        static let cancel = Animation.interpolatingSpring(mass: 0.85, stiffness: 235, damping: 30, initialVelocity: 0)
        static let closeRemovalDelay: TimeInterval = 0.38
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                systemTabs
                    .accessibilityHidden(showFullPlayer)

                if engine.current != nil && (showFullPlayer || isMiniOpening || fullPlayerOpenProgress > 0) {
                    NowPlayingView(
                        onDismiss: { closeFullPlayer() },
                        namespace: playerTransition,
                        safeAreaTop: proxy.safeAreaInsets.top
                    )
                        .offset(y: fullPlayerOffset(height: proxy.size.height, safeAreaInsets: proxy.safeAreaInsets))
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
#if DEBUG
            if UITestFixtures.enabled {
                engine.installUITestFixture(tracks: UITestFixtures.homeTracks, startAt: 0)
            }
#endif
            // 调试用:simctl launch 注入 AUTOPLAY_BV 即可无交互验证播放链路。
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

    @ViewBuilder
    private var systemTabs: some View {
        if engine.current != nil {
            baseTabs
                .tabViewBottomAccessory {
                    SystemMiniPlayer(
                        miniOpenDragTranslation: $miniOpenDragTranslation,
                        isFullPlayerPresented: showFullPlayer,
                        namespace: playerTransition,
                        openProgress: renderedPlayerOpenProgress,
                        openFullPlayer: { openFullPlayer() },
                        onOpenDragChanged: { handleMiniOpenDragChanged($0) },
                        onOpenDragEnded: { handleMiniOpenDragEnded($0) }
                    )
                }
        } else {
            baseTabs
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
            return min(1, max(0, -miniOpenDragTranslation / Metrics.openingDragRange))
        }
        return min(1, max(0, fullPlayerOpenProgress))
    }

    private var renderedPlayerOpenProgress: CGFloat {
        let clamped = min(1, max(0, playerOpenProgress))
        if isMiniOpening && !showFullPlayer {
            return 1 - CGFloat(pow(Double(1 - clamped), 1.22))
        }
        return transitionProgress(clamped)
    }

    private func openFullPlayer(startProgress explicitStartProgress: CGFloat? = nil) {
        let startProgress = max(explicitStartProgress ?? playerOpenProgress, 0.04)
        #if DEBUG
        NSLog("mini->full open startProgress=%.3f", Double(startProgress))
        #endif
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            showFullPlayer = true
            miniOpenDragTranslation = nil
            isTrackingMiniOpenDrag = false
            fullPlayerOpenProgress = min(1, startProgress)
        }

        withAnimation(openAnimation) {
            fullPlayerOpenProgress = 1
        }
    }

    private func cancelFullPlayerDrag() {
        withAnimation(cancelAnimation) {
            miniOpenDragTranslation = nil
            isTrackingMiniOpenDrag = false
            showFullPlayer = false
            fullPlayerOpenProgress = 0
        }
    }

    private func closeFullPlayer() {
        withAnimation(closeAnimation) {
            miniOpenDragTranslation = nil
            isTrackingMiniOpenDrag = false
            fullPlayerOpenProgress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + closeRemovalDelay) {
            guard fullPlayerOpenProgress <= 0.01 else { return }
            showFullPlayer = false
        }
    }

    private func resetFullPlayerState() {
        showFullPlayer = false
        miniOpenDragTranslation = nil
        isTrackingMiniOpenDrag = false
        fullPlayerOpenProgress = 0
    }

    private func finishMiniOpenDrag(_ sample: MiniOpenDragSample) {
        defer { miniOpenDragTranslation = nil }
        guard engine.current != nil, !showFullPlayer else { return }
        let predictedTranslationY = sample.translation.height + sample.velocity.height * 0.22
        let progress = miniOpenProgress(for: sample.translation.height)
        let predictedProgress = miniOpenProgress(for: predictedTranslationY)
        guard progress > Metrics.openingActivationProgress ||
            (progress > Metrics.predictedOpeningMinimumProgress &&
             predictedProgress > Metrics.openingPredictedActivationProgress) else {
            cancelFullPlayerDrag()
            return
        }

        openFullPlayer(startProgress: max(progress, Metrics.openingActivationProgress))
    }

    private func handleMiniOpenDragChanged(_ sample: MiniOpenDragSample) {
        guard engine.current != nil, !showFullPlayer else {
            isTrackingMiniOpenDrag = false
            return
        }

        if !isTrackingMiniOpenDrag {
            guard shouldBeginMiniOpenDrag(sample) else { return }
            isTrackingMiniOpenDrag = true
            #if DEBUG
            NSLog("mini drag began start=(%.1f, %.1f)", Double(sample.startLocation.x), Double(sample.startLocation.y))
            #endif
        }

        miniOpenDragTranslation = sample.translation.height
        let predictedTranslationY = sample.translation.height + sample.velocity.height * 0.22
        let progress = miniOpenProgress(for: sample.translation.height)
        let predictedProgress = miniOpenProgress(for: predictedTranslationY)
        if progress >= Metrics.liveOpeningActivationProgress ||
            (progress >= Metrics.predictedOpeningMinimumProgress &&
             predictedProgress >= Metrics.openingPredictedActivationProgress) {
            isTrackingMiniOpenDrag = false
            miniOpenDragTranslation = nil
            openFullPlayer(startProgress: max(progress, Metrics.openingActivationProgress))
            return
        }

        #if DEBUG
        NSLog("mini drag change translationY=%.1f", Double(sample.translation.height))
        #endif
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
        let translation = sample.translation
        let isVertical = abs(translation.height) > abs(translation.width) * 1.2
        return translation.height < -18 && isVertical
    }

    private func miniOpenProgress(for translationY: CGFloat) -> CGFloat {
        min(1, max(0, -translationY / Metrics.openingDragRange))
    }
}

/// 系统底部 accessory 中的 mini 播放器。封面保持 16:9。
private struct SystemMiniPlayer: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var miniOpenDragTranslation: CGFloat?
    let isFullPlayerPresented: Bool
    var namespace: Namespace.ID
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

        HStack(spacing: lerp(7, 9, layoutProgress)) {
            HStack(spacing: lerp(7, 9, layoutProgress)) {
                artwork(layoutProgress: layoutProgress)

                VStack(alignment: .leading, spacing: layoutProgress) {
                    Text(engine.current?.title ?? "")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(engine.current?.artist ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .opacity(layoutProgress)
                        .frame(height: 13 * layoutProgress, alignment: .top)
                        .clipped()
                }
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
        .opacity(Double(max(0, 1 - max(0, (accessoryProgress - 0.14) / 0.86))))
        .scaleEffect(1 - accessoryProgress * 0.03, anchor: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(engine.current?.title ?? "正在播放")
        .accessibilityIdentifier("miniPlayer")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, openFullPlayer)
        .onDisappear { miniOpenDragTranslation = nil }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0.02), value: layoutProgress)
        .task(id: engine.current?.coverURL) {
            guard let url = engine.current?.coverURL,
                  let fullURL = thumbnailURL(url, width: 960, height: 540),
                  ImageMemoryCache.shared.image(for: fullURL) == nil else { return }
            _ = await ImageLoadCoordinator.shared.image(for: fullURL)
        }
    }

    private var miniLayoutProgress: CGFloat {
        guard isInline else { return 1 }
        guard let miniOpenDragTranslation else { return 0 }
        return min(1, max(0, -miniOpenDragTranslation / 34))
    }

    private func artwork(layoutProgress: CGFloat) -> some View {
        Group {
            if let url = thumbnailURL(engine.current?.coverURL, width: 150, height: 85) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    artworkPlaceholder
                }
            } else {
                artworkPlaceholder
            }
        }
        .matchedGeometryEffect(id: "playerCover", in: namespace)
        .frame(width: lerp(34, 44, layoutProgress), height: lerp(19, 25, layoutProgress))
        .clipShape(RoundedRectangle(cornerRadius: lerp(4, 5, layoutProgress), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: lerp(4, 5, layoutProgress), style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.10), radius: 2.5, x: 0, y: 1)
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
                .font(.system(size: isInline ? 10 : 14, weight: .semibold))
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

    private var miniOpenDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                onOpenDragChanged(miniOpenDragSample(from: value))
            }
            .onEnded { value in
                onOpenDragEnded(miniOpenDragSample(from: value))
            }
    }

    private func miniOpenDragSample(from value: DragGesture.Value) -> MiniOpenDragSample {
        let predictedVelocity = CGSize(
            width: (value.predictedEndTranslation.width - value.translation.width) / 0.22,
            height: (value.predictedEndTranslation.height - value.translation.height) / 0.22
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
