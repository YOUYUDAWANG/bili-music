import AVKit
import SwiftUI

/// PreferenceKey 用于检测 ScrollView 的滚动偏移。
private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct RecommendationPanelRefreshPolicy: Equatable {
    var shouldLoadImmediately: Bool
    var shouldMarkStale: Bool

    static func currentTrackChanged(
        suppressImmediateRefresh: Bool,
        recommendationPanelVisible: Bool
    ) -> RecommendationPanelRefreshPolicy {
        if suppressImmediateRefresh {
            return RecommendationPanelRefreshPolicy(shouldLoadImmediately: false, shouldMarkStale: true)
        }
        if recommendationPanelVisible {
            return RecommendationPanelRefreshPolicy(shouldLoadImmediately: true, shouldMarkStale: false)
        }
        return RecommendationPanelRefreshPolicy(shouldLoadImmediately: false, shouldMarkStale: true)
    }
}

/// 全屏正在播放页(从 mini bar 上拉打开)。
struct NowPlayingView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onDismiss: (() -> Void)? = nil
    var namespace: Namespace.ID
    var safeAreaTop: CGFloat = 0
    private enum PlayerPage: Int {
        case queue = 0
        case nowPlaying = 1
        case recommendations = 2
    }

    @State private var selectedPage = PlayerPage.nowPlaying.rawValue
    @State private var recommendedTracks: [Track] = []
    @State private var recommendationsLoading = false
    @State private var recommendationsError: String?
    @State private var currentPlaylist: BiliClient.UPPlaylist?
    @State private var currentPlaylistTracks: [Track] = []
    @State private var currentPlaylistLoading = false
    @State private var currentPlaylistError: String?
    @State private var suppressNextRecommendationRefresh = false
    @State private var recommendationsStale = false
    @State private var shownRecommendationKeys: Set<TrackKey> = []
    @State private var recommendationTask: Task<Void, Never>?
    @State private var playlistLookupTask: Task<Void, Never>?
    @State private var playlistLookupCache: [String: PlaylistLookupResult] = [:]
    @State private var showLyrics = false
    @State private var showMVFullscreen = false
    @State private var showMVControls = false
    @State private var showUPPlaylists = false
    @State private var showFavoriteFolders = false
    @State private var switchingMode = false
    @State private var selectedMode: PlayerEngine.PlaybackMode = .music
    @GestureState private var dismissDragOffset: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var playHapticTrigger = 0
    @State private var prevHapticTrigger = 0
    @State private var nextHapticTrigger = 0
    @State private var favoriteHapticTrigger = 0
    @State private var favoriteWasAdded = false
    @State private var downloadTrigger = 0
    @State private var isProgressScrubbing = false
    @State private var suppressPageSwipeForScrub = false
    @State private var progressScrubGeneration = 0
    @Environment(\.dismiss) private var dismiss
    private var favorites: FavoriteManager { .shared }

    private enum Layout {
        static let topSwitcherInset: CGFloat = 16
        static let topSwitcherHeight: CGFloat = 32
        static let contentTopInset: CGFloat = 16
        static let contextPreviewLimit = 8
        static let compactRowHeight: CGFloat = 34
        static let dismissGrabZoneHeight: CGFloat = PlayerGesturePolicy.dismissGrabZoneHeight
    }

    private struct PlaylistLookupResult {
        let playlist: BiliClient.UPPlaylist?
        let tracks: [Track]
        let error: String?
    }

    var body: some View {
        GeometryReader { proxy in
            let coverSize = min(proxy.size.width - 28, max(260, proxy.size.height * 0.46), 420)
            let effectiveSafeAreaTop = max(proxy.safeAreaInsets.top, safeAreaTop)
            ZStack {
                playerBackground
                    .ignoresSafeArea()

                if isLandscapeMV(size: proxy.size), let player = engine.avPlayer {
                    landscapeMVPlayer(
                        player: player,
                        width: proxy.size.width,
                        safeAreaTop: effectiveSafeAreaTop
                    )
                } else {
                    playerPages(
                        coverSize: coverSize,
                        width: proxy.size.width,
                        safeAreaTop: effectiveSafeAreaTop
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(playerBackground.ignoresSafeArea())
            .offset(y: dismissDragOffset)
            .accessibilityIdentifier("nowPlayingView")
            .simultaneousGesture(dismissDrag, including: .gesture)
            .animation(dismissDragAnimation, value: dismissDragOffset)
        }
        .sheet(isPresented: $showUPPlaylists) {
            UPPlaylistsView()
        }
        .sheet(isPresented: $showFavoriteFolders) {
            FavoriteFolderPickerView()
        }
        .sheet(isPresented: $showLyrics) {
            LyricsSheetView()
        }
        .fullScreenCover(isPresented: $showMVFullscreen) {
            MVFullscreenView()
        }
        .onAppear {
            selectedMode = engine.playbackMode
            scheduleCurrentPlaylistLookup(force: false, delay: .milliseconds(1600))
        }
        .onChange(of: engine.playbackMode) { _, mode in
            selectedMode = mode
        }
        .onChange(of: engine.current?.bvid) {
            recommendationTask?.cancel()
            playlistLookupTask?.cancel()
            scheduleCurrentPlaylistLookup(force: false, delay: .milliseconds(1800))
            shownRecommendationKeys = []
            let refreshPolicy = RecommendationPanelRefreshPolicy.currentTrackChanged(
                suppressImmediateRefresh: suppressNextRecommendationRefresh,
                recommendationPanelVisible: selectedPage == PlayerPage.recommendations.rawValue)
            suppressNextRecommendationRefresh = false
            recommendationsStale = refreshPolicy.shouldMarkStale
            if refreshPolicy.shouldLoadImmediately {
                scheduleRecommendationLoad(clear: true)
                recommendationsStale = false
            }
        }
        .onChange(of: selectedPage) { _, page in
            guard page == PlayerPage.recommendations.rawValue else { return }
            guard recommendationsStale || recommendedTracks.isEmpty else { return }
            recommendationsStale = false
            scheduleRecommendationLoad(clear: true)
        }
        .onDisappear {
            recommendationTask?.cancel()
            playlistLookupTask?.cancel()
        }
    }

    /// 中性渐变背景:可靠、内容对比清晰。之前整屏专辑虚化会把封面和文字洗成灰白一片。
    private var playerBackground: some View {
        AppTheme.playerGradient
    }

    private func isLandscapeMV(size: CGSize) -> Bool {
        engine.playbackMode == .mv && size.width > size.height
    }

    private func nowPlayingPage(coverSize: CGFloat) -> some View {
        VStack(spacing: 15) {
            mediaView(coverSize: coverSize)
                .padding(.top, 6)

            VStack(spacing: 5) {
                Text(engine.current?.title ?? "")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(engine.current?.artist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if case .failed(let message) = engine.state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppTheme.error)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)

            progressView
            transportControls
            actionRow

            if let favoriteError = favorites.lastError {
                Text(favoriteError)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.error)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            bottomContextPanel

            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
    }

    private func playerPages(coverSize: CGFloat, width: CGFloat, safeAreaTop: CGFloat) -> some View {
        TabView(selection: $selectedPage) {
            horizontalListPage {
                queueList
            }
            .tag(PlayerPage.queue.rawValue)

            ScrollView(showsIndicators: false) {
                nowPlayingPage(coverSize: coverSize)
                    .padding(.top, Layout.contentTopInset)
                    .background(GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: geo.frame(in: .named("playerScroll")).minY
                        )
                    })
            }
            .coordinateSpace(name: "playerScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                scrollOffset = offset
            }
            .tag(PlayerPage.nowPlaying.rawValue)

            horizontalListPage {
                recommendationsList
            }
            .tag(PlayerPage.recommendations.rawValue)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
        .scrollDisabled(suppressPageSwipeForScrub)
        .contentShape(Rectangle())
        .simultaneousGesture(pageSwipeGesture(width: width), including: .gesture)
        .safeAreaInset(edge: .top, spacing: 0) {
            playerTopModeSwitcher(safeAreaTop: safeAreaTop)
        }
    }

    private func landscapeMVPlayer(player: AVPlayer, width: CGFloat, safeAreaTop: CGFloat) -> some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .simultaneousGesture(pageSwipeGesture(width: width), including: .all)
            .safeAreaInset(edge: .top, spacing: 0) {
                playerTopModeSwitcher(safeAreaTop: safeAreaTop)
            }
    }

    @ViewBuilder
    private func mediaView(coverSize: CGFloat) -> some View {
        if engine.playbackMode == .mv, let player = engine.avPlayer {
            ZStack(alignment: .topTrailing) {
                artworkPlaceholder(cornerRadius: AppTheme.playerCoverRadius)
                VideoPlayer(player: player)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showMVControls.toggle()
                        }
                    }
                if showMVControls {
                    Button {
                        showMVFullscreen = true
                        showMVControls = false
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(10)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .transition(.opacity)
                }
            }
            .frame(width: min(coverSize, 430), height: min(coverSize, 430) * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.playerCoverRadius))
            .shadow(color: .black.opacity(0.42), radius: 28, y: 18)
            .onChange(of: showMVControls) { _, visible in
                guard visible else { return }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showMVControls = false
                        }
                    }
                }
            }
        } else {
            let coverURL = thumbnailURL(engine.current?.coverURL, width: 960, height: 540)
            Group {
                if let coverURL {
                    CachedAsyncImage(
                        url: coverURL,
                        targetSize: CGSize(width: coverSize, height: coverSize * 9 / 16)
                    ) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        artworkPlaceholder(cornerRadius: AppTheme.playerCoverRadius)
                    }
                } else {
                    artworkPlaceholder(cornerRadius: AppTheme.playerCoverRadius)
                }
            }
            .matchedGeometryEffect(id: "playerCover", in: namespace)
            .frame(width: coverSize, height: coverSize * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.playerCoverRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.playerCoverRadius)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.42), radius: 28, y: 18)
        }
    }

    private func artworkPlaceholder(cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.055))
            LinearGradient(
                colors: [
                    Color.primary.opacity(0.12),
                    Color.primary.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.42))
        }
    }

    private var progressView: some View {
        // 独立子视图:只有它订阅 engine.currentTime(每 0.5s 变),
        // 避免整个播放器 body(封面、操作栏、TabView)跟着每半秒重渲染。
        PlayerProgressBar { scrubbing in
            setProgressScrubbing(scrubbing)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 34) {
            PlayerIconButton(systemName: "backward.fill", size: 28, accessibilityLabel: "上一曲") {
                prevHapticTrigger += 1
                Task { await engine.playPrevious() }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: prevHapticTrigger)
            Button {
                playHapticTrigger += 1
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 36, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 76, height: 76)
                    .foregroundStyle(AppTheme.background)
                    .background(AppTheme.label, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
            }
            .overlay { if engine.state == .loading { ProgressView().tint(AppTheme.background) } }
            .sensoryFeedback(.impact(weight: .medium), trigger: playHapticTrigger)
            PlayerIconButton(systemName: "forward.fill", size: 28, accessibilityLabel: "下一曲") {
                nextHapticTrigger += 1
                Task { await engine.playNext() }
            }
            .disabled(!engine.hasNext)
            .sensoryFeedback(.impact(weight: .medium), trigger: nextHapticTrigger)
        }
        .foregroundStyle(AppTheme.label)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            favoriteButton
            downloadIconButton
            if !engine.lyrics.isEmpty {
                lyricsButton
            }
            queueModeMenu
            moreMenu
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var favoriteButton: some View {
        if let track = engine.current {
            ActionSymbolButton(
                title: favorites.isFavorite(track) ? "已收藏" : "收藏",
                systemName: favorites.isFavorite(track) ? "heart.fill" : "heart"
            ) {
                guard !favorites.busyBVIDs.contains(track.bvid) else { return }
                let wasFavorite = favorites.isFavorite(track)
                Task {
                    await favorites.toggle(track: track)
                    favoriteWasAdded = !wasFavorite
                    favoriteHapticTrigger += 1
                }
            }
            .symbolEffect(.bounce, value: favorites.isFavorite(track))
            .opacity(favorites.busyBVIDs.contains(track.bvid) ? 0.55 : 1)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("收藏到默认收藏夹")
            .sensoryFeedback(.intent(favoriteWasAdded ? .success : .selection), trigger: favoriteHapticTrigger)
        }
    }

    @ViewBuilder
    private var lyricsButton: some View {
        ActionSymbolButton(title: "歌词", systemName: "quote.bubble") {
            showLyrics = true
        }
    }

    @ViewBuilder
    private var downloadIconButton: some View {
        let downloads = DownloadManager.shared
        if let track = engine.current {
            if CacheStore.shared.entry(for: track) != nil {
                ActionSymbolButton(title: "已缓存", systemName: "arrow.down.circle.fill") {}
                    .foregroundStyle(AppTheme.success)
            } else if downloads.progress(for: track) != nil {
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.thinMaterial)
                            .frame(width: 54, height: 42)
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                ActionSymbolButton(title: "缓存", systemName: "arrow.down.circle") {
                    downloadTrigger += 1
                    Task { await downloads.download(track: track) }
                }
                .sensoryFeedback(.intent(.start), trigger: downloadTrigger)
            }
        }
    }

    private var queueModeMenu: some View {
        Menu {
            ForEach(PlayerEngine.QueueMode.allCases) { mode in
                Button {
                    engine.queueMode = mode
                } label: {
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
        } label: {
            ActionSymbolLabel(title: "播放模式", systemName: engine.queueMode.icon)
        }
        .buttonStyle(.plain)
    }

    private var moreMenu: some View {
        Menu {
            Section("音质") {
                ForEach(BiliClient.qualityOptions, id: \.id) { option in
                    Button {
                        Task { await engine.setPlaybackQuality(option.id) }
                    } label: {
                        Label(option.title, systemImage: PlayerEngine.playbackQuality == option.id ? "checkmark" : "circle")
                    }
                }
                if let quality = engine.currentAudioQuality {
                    Divider()
                    Label("当前: \(BiliClient.qualityName(quality))", systemImage: "waveform")
                    if let bandwidth = engine.currentAudioBandwidth {
                        Label("码率: \(formatBitrate(bandwidth))", systemImage: "speedometer")
                    }
                } else if engine.playbackMode == .mv {
                    Divider()
                    Label("当前为 MV 视频流", systemImage: "play.rectangle")
                }
            }
            if engine.current?.ownerMid != nil {
                Button {
                    showUPPlaylists = true
                } label: {
                    Label("合集", systemImage: "rectangle.stack")
                }
            }
        } label: {
            ActionSymbolLabel(title: "更多", systemName: "ellipsis.circle")
        }
        .buttonStyle(.plain)
    }

    private var playbackModeSwitcher: some View {
        Picker("播放模式", selection: $selectedMode) {
            ForEach(PlayerEngine.PlaybackMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(maxWidth: 214)
        .frame(height: 32)
        .tint(AppTheme.accent)
        .accessibilityIdentifier("playerModeSwitcher")
        .disabled(switchingMode || (!engine.videoAvailable && engine.playbackMode == .music))
        .onChange(of: selectedMode) { _, mode in
            guard mode != engine.playbackMode else { return }
            setPlaybackMode(mode)
        }
    }

    private func playerTopModeSwitcher(safeAreaTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: max(safeAreaTop, 44) + Layout.topSwitcherInset)
                .accessibilityHidden(true)

            HStack {
                Spacer()
                playbackModeSwitcher
                    .padding(3)
                    .background(.thinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
                    }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: max(safeAreaTop, 44) + Layout.topSwitcherInset + Layout.topSwitcherHeight + 6)
        .contentShape(Rectangle())
        .highPriorityGesture(topChromeDismissDrag, including: .all)
    }

    private func setPlaybackMode(_ mode: PlayerEngine.PlaybackMode) {
        guard mode != engine.playbackMode, !switchingMode else { return }
        guard mode == .music || engine.videoAvailable else { return }
        Task {
            switchingMode = true
            await engine.setPlaybackMode(mode)
            switchingMode = false
        }
    }

    private func horizontalListPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                content()
                    .padding(.horizontal, 20)
                Spacer(minLength: 32)
            }
            .padding(.top, Layout.contentTopInset)
            .padding(.bottom, 28)
        }
    }

    @ViewBuilder
    private var queueList: some View {
        if engine.queue.isEmpty {
            ContentUnavailableView("播放列表为空", systemImage: "list.bullet")
                .frame(minHeight: 160)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(engine.queue.enumerated()), id: \.element.id) { index, track in
                    Button {
                        Task { await engine.jump(to: index) }
                    } label: {
                        TrackRow(track: track, isPlaying: index == engine.queueIndex)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if engine.queue.count > 1 {
                            Button(role: .destructive) {
                                engine.removeFromQueue(at: index)
                            } label: {
                                Label("从播放列表移除", systemImage: "minus.circle")
                            }
                        }
                    }
                    if index != engine.queue.count - 1 {
                        Divider().padding(.leading, 70)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recommendationsList: some View {
        if recommendationsLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 160)
        } else if let recommendationsError {
            ContentUnavailableView("推荐加载失败", systemImage: "exclamationmark.triangle",
                                   description: Text(recommendationsError))
            .frame(minHeight: 160)
        } else if recommendedTracks.isEmpty {
            ContentUnavailableView("没有推荐歌曲", systemImage: "music.note.list")
                .frame(minHeight: 160)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(recommendedTracks.prefix(12).enumerated()), id: \.element.id) { index, track in
                    Button {
                        suppressNextRecommendationRefresh = true
                        Task { await engine.play(tracks: recommendedTracks, startAt: index, queueMode: .radio) }
                    } label: {
                        TrackRow(track: track, isPlaying: engine.current.map { track.key.matches($0) } ?? false)
                    }
                    .buttonStyle(.plain)
                    if index != min(recommendedTracks.count, 12) - 1 {
                        Divider().padding(.leading, 70)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bottomContextPanel: some View {
        if currentPlaylistLoading && currentPlaylistTracks.isEmpty {
            currentPlaylistPanel
        } else if currentPlaylist != nil && !currentPlaylistTracks.isEmpty {
            currentPlaylistPanel
        } else {
            queuePreviewPanel
        }
    }

    @ViewBuilder
    private var currentPlaylistPanel: some View {
        if currentPlaylistLoading && currentPlaylistTracks.isEmpty {
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.75)
                Text("正在检测所属合集")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
        } else if let currentPlaylist, !currentPlaylistTracks.isEmpty {
            let visibleRows = min(currentPlaylistTracks.count, Layout.contextPreviewLimit)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("所在合集")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(currentPlaylist.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(currentPlaylistPositionText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(currentPlaylistTracks.enumerated()), id: \.element.id) { index, track in
                                Button {
                                    Task { await playCurrentPlaylistTrack(at: index) }
                                } label: {
                                    compactPlaylistRow(track: track, index: index)
                                        .id(track.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: CGFloat(visibleRows) * Layout.compactRowHeight)
                    .onAppear { scrollCurrentPlaylist(proxy) }
                    .onChange(of: engine.current?.id) { _, _ in
                        scrollCurrentPlaylist(proxy)
                    }
                }
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 24)
        } else if let currentPlaylistError {
            Text(currentPlaylistError)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 28)
        }
    }

    @ViewBuilder
    private var queuePreviewPanel: some View {
        if !engine.queue.isEmpty {
            let previewItems = queuePreviewItems
            let visibleRows = min(previewItems.count, Layout.contextPreviewLimit)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("接下来播放")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(engine.queueIndex + 1)/\(engine.queue.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: previewItems.count > visibleRows) {
                        LazyVStack(spacing: 0) {
                            ForEach(previewItems, id: \.track.id) { item in
                                Button {
                                    Task { await engine.jump(to: item.index) }
                                } label: {
                                    compactPlaylistRow(track: item.track, index: item.index)
                                        .id(item.track.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: CGFloat(visibleRows) * Layout.compactRowHeight)
                    .onAppear { scrollCurrentQueue(proxy) }
                    .onChange(of: engine.queueIndex) { _, _ in
                        scrollCurrentQueue(proxy)
                    }
                    .onChange(of: engine.current?.id) { _, _ in
                        scrollCurrentQueue(proxy)
                    }
                }
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 24)
        }
    }

    private func compactPlaylistRow(track: Track, index: Int) -> some View {
        let isCurrent = engine.current.map { track.key.matches($0) } ?? false
        return HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? AppTheme.accent : .secondary)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.caption.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? AppTheme.label : .primary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            } else {
                Text(format(Double(track.duration)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private var queuePreviewItems: [(index: Int, track: Track)] {
        Array(engine.queue.enumerated()).map { index, track in
            (index, track)
        }
    }

    private func scheduleRecommendationLoad(clear: Bool) {
        recommendationTask?.cancel()
        recommendationsError = nil
        if clear {
            recommendedTracks = []
        }
        guard selectedPage == PlayerPage.recommendations.rawValue,
              engine.current?.bvid != nil else {
            recommendationsLoading = false
            return
        }
        if recommendedTracks.isEmpty {
            recommendationsLoading = true
        }
        recommendationTask = Task {
            try? await Task.sleep(for: .milliseconds(clear ? 260 : 0))
            guard !Task.isCancelled else { return }
            await loadRecommendations()
        }
    }

    private func scheduleCurrentPlaylistLookup(force: Bool, delay: Duration) {
        playlistLookupTask?.cancel()
        guard let current = engine.current else {
            currentPlaylist = nil
            currentPlaylistTracks = []
            currentPlaylistError = nil
            currentPlaylistLoading = false
            return
        }

        let bvid = current.bvid
        if !force, let cached = playlistLookupCache[bvid] {
            applyPlaylistLookup(cached, for: bvid)
            return
        }

        currentPlaylist = nil
        currentPlaylistTracks = []
        currentPlaylistError = nil
        currentPlaylistLoading = false
        playlistLookupTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled,
                  engine.current?.bvid == bvid else { return }
            await loadCurrentPlaylistIfNeeded(force: force)
        }
    }

    private func applyPlaylistLookup(_ result: PlaylistLookupResult, for bvid: String) {
        guard engine.current?.bvid == bvid else { return }
        currentPlaylist = result.playlist
        currentPlaylistTracks = result.tracks
        currentPlaylistError = result.error
        currentPlaylistLoading = false
    }

    private func loadRecommendations() async {
        guard let bvid = engine.current?.bvid else { return }
        recommendationsLoading = recommendedTracks.isEmpty
        defer { recommendationsLoading = false }
        let currentKey = engine.current?.key ?? TrackKey(bvid: bvid, cid: nil)
        let excluded = shownRecommendationKeys.union([currentKey])
        let tracks = await RecommendationEngine().recommendations(
            mode: .relatedPanel,
            context: .init(
                current: engine.current,
                queue: engine.queue,
                playlistTracks: currentPlaylistTracks,
                excludedKeys: excluded),
            limit: 24)
        guard engine.current?.bvid == bvid else { return }
        shownRecommendationKeys.formUnion(tracks.map(\.key))
        recommendedTracks = tracks
        recommendationsError = tracks.isEmpty ? "没有找到合适的推荐歌曲" : nil
        engine.preload(tracks: recommendedTracks, limit: 2, delay: .milliseconds(500))
    }

    private func loadCurrentPlaylistIfNeeded(force: Bool) async {
        guard let current = engine.current else {
            currentPlaylist = nil
            currentPlaylistTracks = []
            currentPlaylistError = nil
            return
        }
        if !force, currentPlaylistTracks.contains(where: { $0.bvid == current.bvid }) {
            return
        }

        let bvid = current.bvid
        if !force, let cached = playlistLookupCache[bvid] {
            applyPlaylistLookup(cached, for: bvid)
            return
        }

        currentPlaylistLoading = true
        currentPlaylistError = nil
        defer { currentPlaylistLoading = false }
        do {
            let client = BiliClient()
            var resolvedOwnerMid = current.ownerMid
            var playlist = try await client.currentVideoPlaylist(bvid: bvid)
            if playlist == nil {
                if resolvedOwnerMid == nil {
                    resolvedOwnerMid = try? await client.videoInfo(bvid: bvid).owner.mid
                }
                if let ownerMid = resolvedOwnerMid {
                    playlist = try? await client.upPlaylistContaining(bvid: bvid, mid: ownerMid)
                }
            }
            guard let playlist else {
                guard engine.current?.bvid == bvid else { return }
                let result = PlaylistLookupResult(playlist: nil, tracks: [], error: nil)
                playlistLookupCache[bvid] = result
                applyPlaylistLookup(result, for: bvid)
                return
            }
            let artist = current.artist
            let ownerMid = resolvedOwnerMid
            let tracks = playlist.items?.map { item in
                Track(
                    aid: item.aid,
                    ownerMid: ownerMid,
                    bvid: item.bvid,
                    cid: item.cid,
                    title: item.title,
                    artist: artist,
                    coverURL: normalizedCoverURL(item.pic),
                    duration: item.duration ?? 0)
            } ?? []
            guard engine.current?.bvid == bvid else { return }
            let result = PlaylistLookupResult(playlist: playlist, tracks: tracks, error: nil)
            playlistLookupCache[bvid] = result
            applyPlaylistLookup(result, for: bvid)
            engine.preload(tracks: tracks, limit: 2, delay: .milliseconds(700))
        } catch {
            guard engine.current?.bvid == bvid else { return }
            let result = PlaylistLookupResult(
                playlist: nil,
                tracks: [],
                error: "合集检测失败: \(error.localizedDescription)")
            playlistLookupCache[bvid] = result
            applyPlaylistLookup(result, for: bvid)
        }
    }

    private var currentPlaylistPositionText: String {
        guard let bvid = engine.current?.bvid,
              let index = currentPlaylistTracks.firstIndex(where: { $0.bvid == bvid }) else {
            return "\(currentPlaylistTracks.count) 首"
        }
        return "\(index + 1)/\(currentPlaylistTracks.count)"
    }

    private func playCurrentPlaylistTrack(at index: Int) async {
        guard currentPlaylistTracks.indices.contains(index) else { return }
        await engine.play(tracks: currentPlaylistTracks, startAt: index, queueMode: .sequential)
    }

    private func scrollCurrentPlaylist(_ proxy: ScrollViewProxy) {
        guard let currentId = engine.current?.id,
              currentPlaylistTracks.contains(where: { $0.id == currentId }) else { return }
        DispatchQueue.main.async {
            animate(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(currentId, anchor: .center)
            }
        }
    }

    private func scrollCurrentQueue(_ proxy: ScrollViewProxy) {
        guard engine.queue.indices.contains(engine.queueIndex) else { return }
        let currentId = engine.queue[engine.queueIndex].id
        DispatchQueue.main.async {
            animate(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(currentId, anchor: .center)
            }
        }
    }

    private func normalizedCoverURL(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        return URL(string: raw.hasPrefix("//") ? "https:" + raw : raw)
    }

    private func dedupe(_ tracks: [Track]) -> [Track] {
        var seen = Set<String>()
        return tracks.filter { track in
            guard !seen.contains(track.bvid) else { return false }
            seen.insert(track.bvid)
            return true
        }
    }

    /// 垂直下拉关闭播放页;拖动时整页跟手,超过阈值松手即收起。
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .global)
            .updating($dismissDragOffset) { value, state, _ in
                guard let offset = PlayerGesturePolicy.dismissDragOffset(
                    translation: value.translation,
                    startY: value.startLocation.y,
                    dismissGrabZoneHeight: Layout.dismissGrabZoneHeight
                ) else { return }
                state = offset
            }
            .onEnded { value in
                if PlayerGesturePolicy.shouldDismissFullPlayer(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation,
                    startY: value.startLocation.y,
                    dismissGrabZoneHeight: Layout.dismissGrabZoneHeight
                ) {
                    closePlayer()
                }
            }
    }

    private func format(_ seconds: Double) -> String {
        let s = Int(seconds.isFinite ? max(seconds, 0) : 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func formatBitrate(_ bandwidth: Int) -> String {
        if bandwidth >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bandwidth) / 1_000_000)
        }
        return "\(max(1, bandwidth / 1000)) kbps"
    }

    private func closePlayer() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private func pageSwipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onEnded { value in
                guard !suppressPageSwipeForScrub else { return }
                let horizontalIntent = abs(value.predictedEndTranslation.width) > abs(value.translation.width)
                    ? value.predictedEndTranslation.width
                    : value.translation.width
                let verticalIntent = abs(value.predictedEndTranslation.height) > abs(value.translation.height)
                    ? value.predictedEndTranslation.height
                    : value.translation.height
                let horizontalThreshold = max(28, width * 0.07)
                guard abs(horizontalIntent) > horizontalThreshold,
                      abs(horizontalIntent) > abs(verticalIntent) * 0.82 else { return }

                animate(.snappy(duration: 0.28, extraBounce: 0.02)) {
                    if horizontalIntent < 0 {
                        selectedPage = min(PlayerPage.recommendations.rawValue, selectedPage + 1)
                    } else {
                        selectedPage = max(PlayerPage.queue.rawValue, selectedPage - 1)
                    }
                }
            }
    }

    private func setProgressScrubbing(_ scrubbing: Bool) {
        progressScrubGeneration += 1
        let generation = progressScrubGeneration
        isProgressScrubbing = scrubbing
        suppressPageSwipeForScrub = true

        guard !scrubbing else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard progressScrubGeneration == generation else { return }
            suppressPageSwipeForScrub = false
        }
    }

    private var topChromeDismissDrag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($dismissDragOffset) { value, state, _ in
                guard let offset = PlayerGesturePolicy.topChromeDismissDragOffset(
                    translation: value.translation
                ) else { return }
                state = offset
            }
            .onEnded { value in
                if PlayerGesturePolicy.shouldDismissFromTopChrome(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation
                ) {
                    closePlayer()
                }
            }
    }

    private var dismissDragAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .interactiveSpring(response: 0.26, dampingFraction: 0.9)
    }

    private func animate(_ animation: Animation, _ updates: @escaping () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }
}

/// 为 hdslb.com 的封面 URL 追加 WebP 缩略图参数。
private func thumbnailURL(_ url: URL?, width: Int, height: Int) -> URL? {
    guard let url else { return nil }
    let raw = url.absoluteString
    guard !raw.localizedCaseInsensitiveContains("transparent.png") else { return nil }
    guard raw.contains("hdslb.com"), !raw.contains("@") else { return url }
    return URL(string: raw + "@\(width)w_\(height)h_1c.webp")
}

// MARK: - Control views and sheet views are in separate files:
// PlayerControlViews.swift (PlayerIconButton, ActionSymbolButton, PlayerProgressBar, etc.)
// PlayerSheetViews.swift (LyricsSheetView, MVFullscreenView, FavoriteFolderPickerView, UPPlaylistsView, etc.)
