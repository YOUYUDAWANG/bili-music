import SwiftUI

/// 根视图：底部 tab + 自定义全屏播放器浮层（从 mini bar 上滑出现）。
struct RootView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase
    @State private var showFullPlayer = false
    @State private var isDraggingFullPlayer = false
    @State private var openPlayerTranslation: CGFloat = 0
    @State private var showSettings = false
    @State private var selectedTab = 0
    @Namespace private var playerTransition
    @State private var pageOffsets: [Int: CGFloat] = [:]
    @State private var tabDragOffset: CGFloat? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                // Tab Content Switcher (Page style TabView to support swipe transitions)
                TabView(selection: $selectedTab) {
                    miniBarSpacer(HomeView(showSettings: $showSettings), safeAreaInsets: proxy.safeAreaInsets)
                        .background(PageOffsetTracker(index: 0))
                        .tag(0)
                    miniBarSpacer(FavoritesView(), safeAreaInsets: proxy.safeAreaInsets)
                        .background(PageOffsetTracker(index: 1))
                        .tag(1)
                    miniBarSpacer(LibraryView(), safeAreaInsets: proxy.safeAreaInsets)
                        .background(PageOffsetTracker(index: 2))
                        .tag(2)
                    miniBarSpacer(SearchView(), safeAreaInsets: proxy.safeAreaInsets)
                        .background(PageOffsetTracker(index: 3))
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .coordinateSpace(name: "pager")
                .onPreferenceChange(PageOffsetPreferenceKey.self) { offsets in
                    pageOffsets = offsets
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom Floating Controls (Player + Custom TabBar)
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        // 1. Mini Player Bar (Normal state, floats above tab bar)
                        if engine.current != nil && !showFullPlayer {
                            if !engine.isMiniPlayerHidden {
                                MiniPlayerBar(
                                    showFullPlayer: $showFullPlayer,
                                    isDraggingFullPlayer: $isDraggingFullPlayer,
                                    openPlayerTranslation: $openPlayerTranslation,
                                    namespace: playerTransition
                                )
                                .padding(.horizontal, 20)
                                .frame(width: 330)
                                .opacity(isDraggingFullPlayer ? Double(max(0.0, 1.0 + openPlayerTranslation / 150.0)) : 1.0)
                                .glassEffect(in: RoundedRectangle(cornerRadius: 26))
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .bottom).combined(with: .opacity)
                                ))
                            }
                        }

                        // 2. Custom Floating Bottom Bar
                        HStack(spacing: 0) {
                            if engine.isMiniPlayerHidden && engine.current != nil {
                                // --- MERGED STATE (SPLIT LAYOUT) ---
                                // Left Circle: Active Tab Button
                                activeTabCircle
                                    .glassEffect(in: Circle())
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .leading).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)
                                    ))
                                
                                Spacer(minLength: 0)
                                
                                // Center: Shrunk Mini Player
                                shrunkPlayerBar
                                    .opacity(isDraggingFullPlayer ? Double(max(0.0, 1.0 + openPlayerTranslation / 150.0)) : 1.0)
                                    .glassEffect(in: RoundedRectangle(cornerRadius: 26))
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .bottom).combined(with: .opacity)
                                    ))
                                
                                Spacer(minLength: 0)
                                
                                // Right Circle: Search
                                searchCircle
                                    .glassEffect(in: Circle())
                            } else {
                                // --- NORMAL STATE ---
                                // Left: Home + Library Capsule Tab Bar
                                normalTabsCapsule(screenWidth: proxy.size.width)
                                    .glassEffect(in: RoundedRectangle(cornerRadius: 26))
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .leading).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)
                                    ))
                                
                                Spacer()
                                
                                // Right: Search Circle
                                searchCircle
                                    .glassEffect(in: Circle())
                            }
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 52)
                        .opacity(isDraggingFullPlayer ? Double(max(0.0, 1.0 + openPlayerTranslation / 150.0)) : 1.0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: engine.isMiniPlayerHidden)
                        .padding(.bottom, proxy.safeAreaInsets.bottom > 0 ? proxy.safeAreaInsets.bottom : 12)
                    }
                }
                .offset(y: bottomControlsOffset)
                .opacity(bottomControlsOpacity)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .zIndex(5)

                if engine.current != nil {
                    NowPlayingView(onDismiss: { closeFullPlayer() }, namespace: playerTransition)
                        .offset(y: fullPlayerOffset(height: proxy.size.height))
                        .ignoresSafeArea()
                        .zIndex(10)
                        .allowsHitTesting(showFullPlayer || isDraggingFullPlayer)
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: selectedTab) { _, _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                engine.isMiniPlayerHidden = false
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

    /// 为每个 tab 预留 MiniPlayer 的底部空间，避免内容被浮动卡片遮挡。
    private func miniBarSpacer(_ content: some View, safeAreaInsets: EdgeInsets) -> some View {
        content.safeAreaInset(edge: .bottom) {
            let baseSpacer: CGFloat = (engine.current != nil && !engine.isMiniPlayerHidden) ? 120.0 : 64.0
            Color.clear.frame(height: baseSpacer + safeAreaInsets.bottom)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: engine.isMiniPlayerHidden)
        }
    }

    /// 全屏播放器的纵向偏移：展开为 0，否则停在屏幕下方并随拖动跟手。
    private func fullPlayerOffset(height: CGFloat) -> CGFloat {
        if showFullPlayer {
            return 0
        }
        return max(0, height + openPlayerTranslation)
    }

    private var bottomControlsOffset: CGFloat {
        if showFullPlayer {
            return 150.0
        }
        if isDraggingFullPlayer {
            let progress = min(max(-openPlayerTranslation / 300.0, 0.0), 1.0)
            return progress * 150.0
        }
        return 0.0
    }

    private var bottomControlsOpacity: Double {
        if showFullPlayer {
            return 0.0
        }
        if isDraggingFullPlayer {
            let progress = min(max(-openPlayerTranslation / 200.0, 0.0), 1.0)
            return 1.0 - Double(progress)
        }
        return 1.0
    }

    /// 收起全屏播放器，回到 mini 模式。
    private func closeFullPlayer() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            showFullPlayer = false
            isDraggingFullPlayer = false
            openPlayerTranslation = 0
        }
    }

    // MARK: - 自定义 Tab 栏辅助组件

    @ViewBuilder
    private var searchCircle: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedTab = 3
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(selectedTab == 3 ? AppTheme.accent : .secondary)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .stroke(strokeGradient, lineWidth: 0.3)
                )
        }
        .buttonStyle(.plain)
    }

    private var activeTabIconName: String {
        switch selectedTab {
        case 0: return "music.note.house.fill"
        case 1: return "rectangle.stack.fill"
        case 2: return "arrow.down.circle.fill"
        default: return "music.note.house.fill"
        }
    }

    @ViewBuilder
    private var activeTabCircle: some View {
        Button {
            // 点击活动 Tab 图标可平滑复原迷你播放器悬浮状态，如果在搜索页，点击可返回首页
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                if selectedTab == 3 {
                    selectedTab = 0
                }
                engine.isMiniPlayerHidden = false
            }
        } label: {
            Image(systemName: activeTabIconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selectedTab == 3 ? .secondary : AppTheme.accent)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .stroke(strokeGradient, lineWidth: 0.3)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var shrunkPlayerBar: some View {
        HStack(spacing: 8) {
            CachedAsyncImage(url: thumbnailURL(engine.current?.coverURL, width: 150, height: 85)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                AppTheme.secondaryBackground
            }
            .matchedGeometryEffect(id: "playerCover", in: playerTransition)
            .frame(width: 52, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            
            VStack(alignment: .leading, spacing: 1) {
                Text(engine.current?.title ?? "")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(engine.current?.artist ?? "")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 4)
            
            Button {
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(MiniPlayerControlButtonStyle())
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .stroke(strokeGradient, lineWidth: 0.3)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                engine.isMiniPlayerHidden = false
            }
        }
        .gesture(
            DragGesture(minimumDistance: 15)
                .onChanged { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    if value.translation.height < 0 {
                        isDraggingFullPlayer = true
                        openPlayerTranslation = value.translation.height
                    } else {
                        isDraggingFullPlayer = false
                        openPlayerTranslation = 0
                    }
                }
                .onEnded { value in
                    if isDraggingFullPlayer {
                        if value.translation.height < -100 || value.predictedEndTranslation.height < -200 {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
                                showFullPlayer = true
                                isDraggingFullPlayer = false
                                openPlayerTranslation = 0
                            }
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showFullPlayer = false
                                isDraggingFullPlayer = false
                                openPlayerTranslation = 0
                            }
                        }
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            engine.isMiniPlayerHidden = false
                        }
                    }
                }
        )
    }

    @ViewBuilder
    private func normalTabsCapsule(screenWidth: CGFloat) -> some View {
        ZStack(alignment: .center) {
            // 滑动选框 (Sliding Selection Frame)
            let boxOffset = selectionBoxOffset(screenWidth: screenWidth)
            let boxOpacity = selectionBoxOpacity(screenWidth: screenWidth)
            
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.white.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                )
                .glassEffect(in: RoundedRectangle(cornerRadius: 22))
                .frame(width: 82, height: 40)
                .offset(x: boxOffset)
                .opacity(boxOpacity)
                .animation(.spring(response: 0.28, dampingFraction: 0.8), value: boxOffset)
            
            HStack(spacing: 0) {
                tabButton(index: 0, title: "推荐", icon: "music.note.house.fill")
                tabButton(index: 1, title: "资料库", icon: "rectangle.stack.fill")
                tabButton(index: 2, title: "缓存", icon: "arrow.down.circle.fill")
            }
        }
        .frame(height: 52)
        .frame(width: 270)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .stroke(strokeGradient, lineWidth: 0.3)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    let initialOffset = CGFloat(selectedTab - 1) * 90.0
                    tabDragOffset = initialOffset + value.translation.width
                }
                .onEnded { value in
                    let finalOffset = CGFloat(selectedTab - 1) * 90.0 + value.translation.width
                    let rawIndex = finalOffset / 90.0 + 1.0
                    let newIndex = min(max(Int(round(rawIndex)), 0), 2)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = newIndex
                        tabDragOffset = nil
                    }
                }
        )
    }

    private func getContinuousIndex(screenWidth: CGFloat) -> CGFloat {
        guard screenWidth > 0 else { return CGFloat(selectedTab) }
        // Find the page index currently closest to the screen center to compute a mathematically continuous index
        if let closest = pageOffsets.min(by: { abs($0.value) < abs($1.value) }) {
            let i = closest.key
            let offset = closest.value
            return CGFloat(i) - (offset / screenWidth)
        }
        return CGFloat(selectedTab)
    }

    private func selectionBoxOffset(screenWidth: CGFloat) -> CGFloat {
        if let drag = tabDragOffset {
            return min(max(drag, -90.0), 90.0)
        }
        let continuous = getContinuousIndex(screenWidth: screenWidth)
        let clamped = min(max(continuous, 0.0), 2.0)
        return (clamped - 1.0) * 90.0
    }

    private func selectionBoxOpacity(screenWidth: CGFloat) -> Double {
        let offset = selectionBoxOffset(screenWidth: screenWidth)
        if offset > 90.0 {
            return Double(max(0.0, 1.0 - (offset - 90.0) / 90.0))
        }
        return 1.0
    }

    @ViewBuilder
    private func tabButton(index: Int, title: String, icon: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedTab = index
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(selectedTab == index ? AppTheme.accent : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func thumbnailURL(_ url: URL?, width: Int, height: Int) -> URL? {
        guard let url else { return nil }
        let raw = url.absoluteString
        guard raw.contains("hdslb.com"), !raw.contains("@") else { return url }
        return URL(string: raw + "@\(width)w_\(height)h_1c.webp")
    }

    private var strokeGradient: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(0.18),
                .white.opacity(0.04),
                .clear,
                .black.opacity(0.02),
                .white.opacity(0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Page Offset tracking elements for sliding tab frame
struct PageOffsetTracker: View {
    let index: Int
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: PageOffsetPreferenceKey.self,
                    value: [index: proxy.frame(in: .named("pager")).minX]
                )
        }
    }
}

struct PageOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
