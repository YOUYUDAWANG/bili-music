import AVFoundation
import SwiftUI
import UIKit

private final class InlinePlayerLayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private struct InlineMVPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> InlinePlayerLayerContainerView {
        let view = InlinePlayerLayerContainerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: InlinePlayerLayerContainerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
        view.playerLayer.videoGravity = .resizeAspectFill
    }

    static func dismantleUIView(_ view: InlinePlayerLayerContainerView, coordinator: ()) {
        view.playerLayer.player = nil
    }
}

private struct PlayerProgressFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct PlayerBottomContextFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
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

struct RecommendationVisibleLoadPolicy: Equatable {
    var shouldLoad: Bool

    static func playbackStarted(
        recommendationsPageSelected: Bool,
        recommendationsStale: Bool,
        recommendationsEmpty: Bool,
        recommendationsMismatched: Bool
    ) -> RecommendationVisibleLoadPolicy {
        visibleLoad(
            recommendationsPageSelected: recommendationsPageSelected,
            recommendationsStale: recommendationsStale,
            recommendationsEmpty: recommendationsEmpty,
            recommendationsMismatched: recommendationsMismatched)
    }

    static func selectedPageChanged(
        recommendationsPageSelected: Bool,
        recommendationsStale: Bool,
        recommendationsEmpty: Bool,
        recommendationsMismatched: Bool
    ) -> RecommendationVisibleLoadPolicy {
        visibleLoad(
            recommendationsPageSelected: recommendationsPageSelected,
            recommendationsStale: recommendationsStale,
            recommendationsEmpty: recommendationsEmpty,
            recommendationsMismatched: recommendationsMismatched)
    }

    private static func visibleLoad(
        recommendationsPageSelected: Bool,
        recommendationsStale: Bool,
        recommendationsEmpty: Bool,
        recommendationsMismatched: Bool
    ) -> RecommendationVisibleLoadPolicy {
        RecommendationVisibleLoadPolicy(
            shouldLoad: recommendationsPageSelected &&
                (recommendationsStale || recommendationsEmpty || recommendationsMismatched))
    }
}

/// 全屏正在播放页(从 mini bar 上拉打开)。
struct NowPlayingView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onDismiss: (() -> Void)? = nil
    var namespace: Namespace.ID
    var isCoverTransitionSource = true
    var coverRevealProgress: CGFloat = 1
    var safeAreaTop: CGFloat = 0
    private enum PlayerPage: Int, CaseIterable {
        case queue = 0
        case nowPlaying = 1
        case recommendations = 2

        var title: String {
            switch self {
            case .queue:
                return "队列"
            case .nowPlaying:
                return "正在播放"
            case .recommendations:
                return "推荐"
            }
        }
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
    @State private var recommendationSeedKey: TrackKey?
    @State private var shownRecommendationKeys: Set<TrackKey> = []
    @State private var recommendationTask: Task<Void, Never>?
    @State private var playlistLookupTask: Task<Void, Never>?
    @State private var playlistLookupCache: [String: PlaylistLookupResult] = [:]
    @State private var showLyrics = false
    @State private var showMVFullscreen = false
    @State private var showUPPlaylists = false
    @State private var showFavoriteFolders = false
    @State private var switchingMode = false
    @GestureState private var dismissDragOffset: CGFloat = 0
    @State private var playHapticTrigger = 0
    @State private var prevHapticTrigger = 0
    @State private var nextHapticTrigger = 0
    @State private var favoriteHapticTrigger = 0
    @State private var favoriteWasAdded = false
    @State private var downloadTrigger = 0
    @State private var isProgressScrubbing = false
    @State private var progressFrameInGlobal: CGRect = .null
    @State private var bottomContextFrameInGlobal: CGRect = .null
    @State private var listRowActionSuppressedUntil: Date?
    @State private var landscapeMVFullscreenKey: TrackKey?
    @State private var showInlineMVChrome = false
    @State private var inlineMVChromeHideTask: Task<Void, Never>?
    @AppStorage(TrackTitleFormatter.cleanListTitlesDefaultsKey) private var cleanListTitles = false
    @Environment(\.dismiss) private var dismiss
    private var favorites: FavoriteManager { .shared }

    private enum Layout {
        static let topChromeBottomPadding: CGFloat = 2
        static let topChromeControlSize: CGFloat = 44
        static let contentTopInset: CGFloat = 12
        static let centerHorizontalPadding: CGFloat = 26
        static let contextPreviewLimit = 8
        static let sidePanelPreviewLimit = 5
        static let compactRowHeight: CGFloat = 34
        static let dismissGrabZoneHeight: CGFloat = PlayerGesturePolicy.dismissGrabZoneHeight
    }

    private enum PlayerSurface {
        static let primaryText = Color.white.opacity(0.90)
        static let secondaryText = Color.white.opacity(0.52)
        static let tertiaryText = Color.white.opacity(0.34)
        static let divider = Color.white.opacity(0.08)
        static let panelFill = Color.white.opacity(0.11)
        static let panelStroke = Color.white.opacity(0.13)
        static let accentFill = AppTheme.accent.opacity(0.18)
        static let accentStroke = AppTheme.accent.opacity(0.30)
    }

    private struct PlaylistLookupResult {
        let playlist: BiliClient.UPPlaylist?
        let tracks: [Track]
        let error: String?
    }

    var body: some View {
        GeometryReader { proxy in
            let effectiveSafeAreaTop = max(proxy.safeAreaInsets.top, safeAreaTop)
            let coverSize = playerCoverSize(for: proxy.size, safeAreaTop: effectiveSafeAreaTop)
            let isLandscape = proxy.size.width > proxy.size.height
            ZStack {
                playerBackground
                    .ignoresSafeArea()

                playerPages(
                    coverSize: coverSize,
                    width: proxy.size.width,
                    safeAreaTop: effectiveSafeAreaTop,
                    isLandscape: isLandscape
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .offset(y: dismissDragOffset)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nowPlayingView")
            .animation(dismissDragAnimation, value: dismissDragOffset)
            .onAppear {
                handleLandscapeMVFullscreen(isLandscape: isLandscape)
            }
            .onChange(of: isLandscape) { _, landscape in
                handleLandscapeMVFullscreen(isLandscape: landscape)
            }
            .onChange(of: engine.playbackMode) { _, _ in
                handleLandscapeMVFullscreen(isLandscape: isLandscape)
            }
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
            scheduleCurrentPlaylistLookup(force: false, delay: .milliseconds(1600))
        }
        .onChange(of: engine.playbackMode) { _, mode in
            if mode == .mv {
                inlineMVChromeHideTask?.cancel()
                showInlineMVChrome = false
            } else {
                inlineMVChromeHideTask?.cancel()
                showInlineMVChrome = false
            }
            if mode != .mv {
                landscapeMVFullscreenKey = nil
            }
        }
        .onChange(of: engine.current?.bvid) {
            recommendationTask?.cancel()
            playlistLookupTask?.cancel()
            scheduleCurrentPlaylistLookup(force: false, delay: .milliseconds(1800))
            recommendationSeedKey = nil
            recommendedTracks = []
            recommendationsError = nil
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
        .onChange(of: engine.state) { _, state in
            guard state == .playing else { return }
            let loadPolicy = RecommendationVisibleLoadPolicy.playbackStarted(
                recommendationsPageSelected: selectedPage == PlayerPage.recommendations.rawValue,
                recommendationsStale: recommendationsStale,
                recommendationsEmpty: recommendedTracks.isEmpty,
                recommendationsMismatched: !recommendationsMatchCurrentTrack)
            guard loadPolicy.shouldLoad else { return }
            recommendationsStale = false
            scheduleRecommendationLoad(clear: !recommendedTracks.isEmpty)
        }
        .onChange(of: selectedPage) { _, page in
            let loadPolicy = RecommendationVisibleLoadPolicy.selectedPageChanged(
                recommendationsPageSelected: page == PlayerPage.recommendations.rawValue,
                recommendationsStale: recommendationsStale,
                recommendationsEmpty: recommendedTracks.isEmpty,
                recommendationsMismatched: !recommendationsMatchCurrentTrack)
            guard loadPolicy.shouldLoad else { return }
            recommendationsStale = false
            scheduleRecommendationLoad(clear: !recommendedTracks.isEmpty)
        }
        .onDisappear {
            recommendationTask?.cancel()
            playlistLookupTask?.cancel()
            inlineMVChromeHideTask?.cancel()
        }
    }

    private func playerCoverSize(for size: CGSize, safeAreaTop: CGFloat) -> CGFloat {
        let availableHeight = max(1, size.height - safeAreaTop)
        let isLandscape = size.width > size.height

        if isLandscape {
            return min(max(168, size.width * 0.24), max(168, availableHeight * 0.48), 250)
        }

        return min(max(270, size.width - 20), max(286, availableHeight * 0.49), 430)
    }

    private var playerBackground: some View {
        ZStack {
            Color.black

            engine.currentArtworkPalette.gradient
                .opacity(0.92)

            RadialGradient(
                colors: [
                    Color.white.opacity(0.07),
                    Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 430
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.06),
                    Color.black.opacity(0.28),
                    Color.black.opacity(0.76)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private func nowPlayingPage(coverSize: CGFloat, isLandscape: Bool) -> some View {
        if isLandscape {
            landscapeNowPlayingPage(coverSize: coverSize)
        } else {
            portraitNowPlayingPage(coverSize: coverSize)
        }
    }

    private func landscapeNowPlayingPage(coverSize: CGFloat) -> some View {
        HStack(spacing: 22) {
            mediaView(coverSize: coverSize)

            VStack(spacing: 8) {
                playerMetadata(compact: true)

                playerControlStack(compact: true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func portraitNowPlayingPage(coverSize: CGFloat) -> some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 760
            let topPadding = isCompact ? 24 : min(72, max(48, proxy.size.height * 0.072))
            let coverBottomSpacing: CGFloat = isCompact ? 22 : 30
            let metadataBottomSpacing: CGFloat = isCompact ? 22 : 30
            let bottomFloor: CGFloat = isCompact ? 16 : 26

            VStack(spacing: 0) {
                mediaView(coverSize: coverSize)
                    .padding(.top, topPadding)
                    .padding(.bottom, coverBottomSpacing)

                playerMetadata(compact: false, centered: false)
                    .padding(.horizontal, 34)
                    .padding(.bottom, metadataBottomSpacing)

                portraitPlayerControls(isCompact: isCompact)

                if let favoriteError = favorites.lastError {
                    Text(favoriteError)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.error)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.horizontal, 28)
                }

                Spacer(minLength: bottomFloor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func playerMetadata(compact: Bool, centered: Bool = true) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: compact ? 3 : 8) {
            Text(displayTitle)
                .font(.system(size: compact ? 20 : 23, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(centered ? .center : .leading)
                .lineLimit(compact ? 1 : 2)
                .lineSpacing(2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
                .matchedGeometryEffect(id: "playerTitle", in: namespace)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .accessibilityIdentifier("nowPlayingMetadata")
            Text(displayArtist)
                .font(.system(size: compact ? 13 : 17, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            if case .failed(let message) = engine.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.error)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    private var displayTitle: String {
        guard let current = engine.current else { return "" }
        return TrackTitleFormatter.displayMetadata(for: current, clean: cleanListTitles).title
    }

    private var displayArtist: String {
        guard let current = engine.current else { return "" }
        return TrackTitleFormatter.displayMetadata(for: current, clean: cleanListTitles).artist
    }

    private func portraitPlayerControls(isCompact: Bool) -> some View {
        VStack(spacing: 0) {
            trackedProgressView

            transportControls
                .padding(.top, isCompact ? 24 : 28)

            VStack(spacing: 0) {
                playerToolbarButtons
                    .padding(.top, isCompact ? 20 : 24)

                bottomContextListPanel(maxRows: isCompact ? 3 : 5)
                    .padding(.top, isCompact ? 12 : 16)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("playerToolbar")
        }
    }

    private func playerControlStack(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 12) {
            trackedProgressView

            transportControls
                .padding(.top, compact ? -6 : -2)

            playerToolbarButtons
                .padding(.top, compact ? -2 : 2)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("playerToolbar")
        }
        .padding(.bottom, 2)
    }

    private var trackedProgressView: some View {
        progressView
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: PlayerProgressFrameKey.self,
                        value: geo.frame(in: .global)
                    )
                }
            )
    }

    private func playerPages(coverSize: CGFloat, width: CGFloat, safeAreaTop: CGFloat, isLandscape: Bool) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                horizontalListPage(accessibilityIdentifier: "playerQueuePage") {
                    queueList
                }
                .frame(width: width)
                .id(PlayerPage.queue.rawValue)

                nowPlayingPage(coverSize: coverSize, isLandscape: isLandscape)
                    .padding(.top, Layout.contentTopInset)
                    .contentShape(Rectangle())
                    .simultaneousGesture(centerBodyDismissDrag, including: .gesture)
                    .frame(width: width)
                    .id(PlayerPage.nowPlaying.rawValue)

                horizontalListPage(accessibilityIdentifier: "playerRecommendationsPage") {
                    recommendationsList
                }
                .frame(width: width)
                .id(PlayerPage.recommendations.rawValue)
            }
            .frame(width: width * CGFloat(PlayerPage.allCases.count), alignment: .leading)
            .scrollTargetLayout()
        }
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: Binding<Int?>(
            get: { selectedPage },
            set: { selectedPage = $0 ?? PlayerPage.nowPlaying.rawValue }
        ))
        .accessibilityIdentifier("playerHorizontalPager")
        .animation(pageTransitionAnimation, value: selectedPage)
        .safeAreaInset(edge: .top, spacing: 0) {
            playerTopChrome(safeAreaTop: safeAreaTop)
        }
        .onPreferenceChange(PlayerProgressFrameKey.self) { frame in
            progressFrameInGlobal = frame
        }
        .onPreferenceChange(PlayerBottomContextFrameKey.self) { frame in
            bottomContextFrameInGlobal = frame
        }
    }

    @ViewBuilder
    private func mediaView(coverSize: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            let currentTrack = engine.current
            let coverURL = thumbnailURL(currentTrack?.coverURL, width: 960, height: 540)
            ZStack {
                if engine.playbackMode == .mv, let player = engine.avPlayer {
                    InlineMVPlayerView(player: player)
                        .background(Color.black)
                        .accessibilityLabel("MV 画面")
                } else if let coverURL {
                    CachedAsyncImage(
                        url: coverURL,
                        targetSize: CGSize(width: coverSize, height: coverSize * 9 / 16),
                        fallbackImage: engine.currentCoverImage,
                        onImageLoaded: { image in
                            engine.rememberCurrentCover(image, for: currentTrack)
                        }
                    ) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        artworkPlaceholder(cornerRadius: AppTheme.playerCoverRadius)
                    }
                } else if let currentCoverImage = engine.currentCoverImage {
                    Image(uiImage: currentCoverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    artworkPlaceholder(cornerRadius: AppTheme.playerCoverRadius)
                }
            }

            if engine.playbackMode == .mv {
                Button {
                    revealInlineMVChrome()
                    showMVFullscreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(10)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .opacity(showInlineMVChrome ? 1 : 0)
                .allowsHitTesting(showInlineMVChrome)
                .animation(.easeInOut(duration: 0.2), value: showInlineMVChrome)
                .padding(8)
                .accessibilityLabel("全屏播放 MV")
            }
        }
            .matchedGeometryEffect(id: "playerArtwork", in: namespace)
            .frame(width: coverSize, height: coverSize * 9 / 16)
            .opacity(coverRevealOpacity)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.playerCoverRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.playerCoverRadius)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.42), radius: 28, y: 18)
            .accessibilityIdentifier("nowPlayingArtwork")
            .simultaneousGesture(TapGesture().onEnded {
                guard engine.playbackMode == .mv else { return }
                revealInlineMVChrome()
            })
    }

    private func revealInlineMVChrome() {
        inlineMVChromeHideTask?.cancel()
        showInlineMVChrome = true
        inlineMVChromeHideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            showInlineMVChrome = false
        }
    }

    private var coverRevealOpacity: Double {
        guard isCoverTransitionSource else { return 0 }
        let progress = min(1, max(0, (coverRevealProgress - 0.55) / 0.28))
        let smoothed = progress * progress * (3 - 2 * progress)
        return Double(smoothed)
    }

    private func artworkPlaceholder(cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.08))
            LinearGradient(
                colors: [
                    Color.white.opacity(0.16),
                    Color.white.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.42))
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
        HStack(spacing: 46) {
            PlayerIconButton(systemName: "backward.fill", size: 31, accessibilityLabel: "上一曲") {
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
                    .frame(width: 78, height: 78)
                    .foregroundStyle(Color.black.opacity(0.92))
                    .background(Color.white, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
            }
            .overlay { if engine.state == .loading { ProgressView().tint(Color.black.opacity(0.80)) } }
            .accessibilityIdentifier("playerTransportControls")
            .sensoryFeedback(.impact(weight: .medium), trigger: playHapticTrigger)
            PlayerIconButton(systemName: "forward.fill", size: 31, accessibilityLabel: "下一曲") {
                nextHapticTrigger += 1
                Task { await engine.playNext() }
            }
            .disabled(!engine.hasNext)
            .sensoryFeedback(.impact(weight: .medium), trigger: nextHapticTrigger)
        }
        .foregroundStyle(Color.white.opacity(0.94))
    }

    private var playerToolbarButtons: some View {
        HStack(spacing: 22) {
            favoriteButton
            downloadButton
            mvSwitchButton
            moreMenu
        }
        .frame(maxWidth: 262)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
    }

    private var favoriteButton: some View {
        let track = engine.current
        let isFavorite = track.map { favorites.isFavorite($0) } ?? false
        let isBusy = track.map { favorites.busyBVIDs.contains($0.bvid) } ?? false

        return PlayerToolbarActionButton(
            title: isFavorite ? "已收藏" : "收藏",
            systemName: isFavorite ? "heart.fill" : "heart",
            isActive: isFavorite,
            isEnabled: track != nil,
            isBusy: isBusy,
            accessibilityLabel: isFavorite ? "已收藏" : "收藏",
            accessibilityValue: isBusy ? "正在更新" : (isFavorite ? "已收藏" : "未收藏")
        ) {
            guard let track, !favorites.busyBVIDs.contains(track.bvid) else { return }
            let wasFavorite = favorites.isFavorite(track)
            Task {
                await favorites.toggle(track: track)
                favoriteWasAdded = !wasFavorite
                favoriteHapticTrigger += 1
            }
        }
        .symbolEffect(.bounce, value: isFavorite)
        .accessibilityHint("收藏到默认收藏夹")
        .sensoryFeedback(.intent(favoriteWasAdded ? .success : .selection), trigger: favoriteHapticTrigger)
    }

    private var downloadButton: some View {
        let downloads = DownloadManager.shared
        let track = engine.current
        let progress = track.flatMap { downloads.progress(for: $0) }
        let isCached = track.map { CacheStore.shared.entry(for: $0) != nil } ?? false
        let title = isCached ? "已缓存" : (progress != nil ? "缓存中" : "缓存")
        let icon = isCached ? "checkmark.circle.fill" : "arrow.down.circle"

        return PlayerToolbarActionButton(
            title: title,
            systemName: icon,
            isActive: isCached,
            isEnabled: track != nil && !isCached,
            isBusy: progress != nil,
            accessibilityLabel: title,
            accessibilityValue: progress != nil ? "正在下载" : (isCached ? "已缓存" : "未缓存")
        ) {
            guard let track else { return }
            downloadTrigger += 1
            Task { await downloads.download(track: track) }
        }
        .sensoryFeedback(.intent(.start), trigger: downloadTrigger)
    }

    private var lyricsButton: some View {
        let hasLyrics = !engine.lyrics.isEmpty
        return PlayerToolbarActionButton(
            title: hasLyrics ? "歌词" : "暂无歌词",
            systemName: hasLyrics ? "quote.bubble.fill" : "quote.bubble",
            isActive: showLyrics && hasLyrics,
            isEnabled: hasLyrics,
            accessibilityLabel: hasLyrics ? "歌词" : "暂无歌词",
            accessibilityValue: hasLyrics ? "可打开" : "不可用"
        ) {
            guard hasLyrics else { return }
            showLyrics = true
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
            PlayerToolbarActionLabel(
                title: "播放模式",
                systemName: engine.queueMode.icon,
                isActive: engine.queueMode != .sequential,
                accessibilityLabel: "播放模式",
                accessibilityValue: engine.queueMode.rawValue
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("播放模式")
        .accessibilityValue(engine.queueMode.rawValue)
        .accessibilityIdentifier("playerQueueModeMenu")
    }

    private var audioQualityMenu: some View {
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
                    if let quality = engine.currentVideoQuality {
                        Label("当前 MV: \(BiliClient.videoQualityName(quality))", systemImage: "play.rectangle")
                    } else {
                        Label("当前为 MV 视频流", systemImage: "play.rectangle")
                    }
                }
            }
        } label: {
            PlayerToolbarActionLabel(
                title: "音质",
                systemName: "waveform",
                isActive: engine.currentAudioQuality != nil || engine.playbackMode == .mv,
                accessibilityLabel: "音质",
                accessibilityValue: audioQualityAccessibilityValue
            )
        }
        .buttonStyle(.plain)
    }

    private var audioQualityAccessibilityValue: String {
        if let quality = engine.currentAudioQuality {
            return BiliClient.qualityName(quality)
        }
        if engine.playbackMode == .mv {
            if let quality = engine.currentVideoQuality {
                return "MV \(BiliClient.videoQualityName(quality))"
            }
            return "MV 视频流"
        }
        return "未选择"
    }

    private var mvSwitchButton: some View {
        let isMV = engine.playbackMode == .mv
        let canSwitch = isMV || engine.videoAvailable
        let targetMode: PlayerEngine.PlaybackMode = isMV ? .music : .mv

        return Button {
            guard canSwitch, !switchingMode else { return }
            setPlaybackMode(targetMode)
        } label: {
            ZStack {
                if switchingMode {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.white.opacity(0.82))
                } else {
                    Image(systemName: isMV ? "play.rectangle.fill" : "headphones")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(canSwitch ? (isMV ? AppTheme.accent : Color.white.opacity(0.76)) : Color.white.opacity(0.34))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 46, height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSwitch || switchingMode)
        .accessibilityLabel(canSwitch ? (isMV ? "切回音乐" : "切换 MV") : "暂无 MV")
        .accessibilityValue(mvSwitchAccessibilityValue(canSwitch: canSwitch, isMV: isMV))
        .accessibilityIdentifier("playerModeSwitchButton")
    }

    private func mvSwitchAccessibilityValue(canSwitch: Bool, isMV: Bool) -> String {
        guard canSwitch else { return "不可用" }
        return isMV ? "MV 播放中" : "音乐播放中"
    }

    private var moreMenu: some View {
        let hasLyrics = !engine.lyrics.isEmpty

        return Menu {
            Section("歌词") {
                Button {
                    showLyrics = true
                } label: {
                    Label(hasLyrics ? "打开歌词" : "暂无歌词", systemImage: hasLyrics ? "quote.bubble.fill" : "quote.bubble")
                }
                .disabled(!hasLyrics)
            }

            Section("播放模式") {
                ForEach(PlayerEngine.QueueMode.allCases) { mode in
                    Button {
                        engine.queueMode = mode
                    } label: {
                        Label(mode.rawValue, systemImage: engine.queueMode == mode ? "checkmark" : mode.icon)
                    }
                }
            }

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
                    if let quality = engine.currentVideoQuality {
                        Label("当前 MV: \(BiliClient.videoQualityName(quality))", systemImage: "play.rectangle")
                    } else {
                        Label("当前为 MV 视频流", systemImage: "play.rectangle")
                    }
                }
            }

            if engine.current?.ownerMid != nil {
                Section("合集") {
                    Button {
                        showUPPlaylists = true
                    } label: {
                        Label("查看 UP 合集", systemImage: "rectangle.stack")
                    }
                }
            }
        } label: {
            PlayerToolbarActionLabel(
                title: "更多",
                systemName: "ellipsis",
                accessibilityLabel: "更多"
            )
        }
        .buttonStyle(.plain)
    }

    private func playerTopChrome(safeAreaTop: CGFloat) -> some View {
        VStack(spacing: 8) {
            Color.clear
                .frame(height: max(safeAreaTop, 12))
                .accessibilityHidden(true)

            ZStack {
                playerPageHint

                HStack {
                    Button {
                        closePlayer()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: Layout.topChromeControlSize, height: Layout.topChromeControlSize)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white)
                    .accessibilityLabel("收起播放器")

                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, Layout.topChromeBottomPadding)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(topChromeDismissDrag, including: .all)
    }

    private var playerPageHint: some View {
        VStack(spacing: 5) {
            Text(PlayerPage(rawValue: selectedPage)?.title ?? PlayerPage.nowPlaying.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(1)

            HStack(spacing: 4) {
                ForEach(PlayerPage.allCases, id: \.rawValue) { page in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(page.rawValue == selectedPage ? AppTheme.accent : Color.white.opacity(0.26))
                        .frame(
                            width: page.rawValue == selectedPage ? 14 : 5,
                            height: 2
                        )
                        .animation(pageTransitionAnimation, value: selectedPage)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: Layout.topChromeControlSize)
        .accessibilityIdentifier("playerPageHint")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放器页面")
        .accessibilityValue(PlayerPage(rawValue: selectedPage)?.title ?? PlayerPage.nowPlaying.title)
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

    private func handleLandscapeMVFullscreen(isLandscape: Bool) {
        guard isLandscape,
              engine.playbackMode == .mv,
              let current = engine.current else {
            if !isLandscape || engine.playbackMode != .mv {
                landscapeMVFullscreenKey = nil
            }
            return
        }
        guard landscapeMVFullscreenKey?.matches(current) != true else { return }
        landscapeMVFullscreenKey = current.key
        showMVFullscreen = true
    }

    private func horizontalListPage<Content: View>(
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                content()
                    .padding(.horizontal, 20)
                Spacer(minLength: 32)
            }
            .padding(.top, Layout.contentTopInset)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var playerDivider: some View {
        PlayerSurface.divider.frame(height: 0.5)
    }

    private func guardedPlayerRowButton<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                guard !isListRowActionSuppressed else { return }
                action()
            }
        } label: {
            label()
        }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isButton)
    }

    private var isListRowActionSuppressed: Bool {
        guard let listRowActionSuppressedUntil else { return false }
        return Date() < listRowActionSuppressedUntil
    }

    private func suppressListRowActionsBriefly() {
        listRowActionSuppressedUntil = Date().addingTimeInterval(0.45)
    }

    @ViewBuilder
    private var queueList: some View {
        if engine.queue.isEmpty && !hasPlaylistContext {
            playerPageState(
                title: "队列为空",
                message: "从搜索、推荐或收藏夹播放歌曲后，这里会显示当前队列。",
                systemName: "list.bullet"
            )
            .accessibilityIdentifier("playerQueueEmptyState")
        } else {
            let shouldShowQueueList = !queueMatchesCurrentPlaylist
            VStack(alignment: .leading, spacing: 16) {
                if hasPlaylistContext {
                    currentPlaylistPanel
                }

                if !engine.queue.isEmpty && shouldShowQueueList {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(engine.queue.enumerated()), id: \.element.id) { index, track in
                            guardedPlayerRowButton {
                                Task { await engine.jump(to: index) }
                            } label: {
                                TrackRow(
                                    track: track,
                                    isPlaying: index == engine.queueIndex,
                                    appearance: .player)
                            }
                            .accessibilityIdentifier(index == engine.queueIndex ? "playerQueueCurrentRow" : "playerQueueRow-\(index)")
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
                                playerDivider.padding(.leading, 70)
                            }
                        }
                    }
                    .accessibilityIdentifier("playerQueueListContainer")
                }
            }
        }
    }

    @ViewBuilder
    private var recommendationsList: some View {
        if recommendationsLoading {
            playerPageState(
                title: "正在加载推荐...",
                message: "播放不会因此中断。",
                systemName: "music.note.list",
                isLoading: true
            )
            .accessibilityIdentifier("playerRecommendationsLoadingState")
        } else if recommendationsError != nil {
            playerPageState(
                title: "推荐加载失败",
                message: "推荐加载失败，请稍后重试。",
                systemName: "exclamationmark.triangle"
            )
            .accessibilityIdentifier("playerRecommendationsErrorState")
        } else if !recommendationsMatchCurrentTrack {
            playerPageState(
                title: "正在准备当前歌曲推荐",
                message: "推荐会根据当前歌曲生成，播放不会因此中断。",
                systemName: "music.note.list",
                isLoading: true
            )
            .accessibilityIdentifier("playerRecommendationsLoadingState")
        } else if recommendedTracks.isEmpty {
            playerPageState(
                title: "暂无推荐",
                message: "播放一首歌曲后再打开推荐页。",
                systemName: "music.note.list"
            )
            .accessibilityIdentifier("playerRecommendationsEmptyState")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(recommendedTracks.prefix(12).enumerated()), id: \.element.id) { index, track in
                    guardedPlayerRowButton {
                        suppressNextRecommendationRefresh = true
                        Task { await engine.play(tracks: recommendedTracks, startAt: index, queueMode: .radio) }
                    } label: {
                        TrackRow(
                            track: track,
                            isPlaying: engine.current.map { track.key.matches($0) } ?? false,
                            appearance: .player)
                    }
                    if index != min(recommendedTracks.count, 12) - 1 {
                        playerDivider.padding(.leading, 70)
                    }
                }
            }
            .accessibilityIdentifier("playerRecommendationsList")
        }
    }

    private func playerPageState(
        title: String,
        message: String,
        systemName: String,
        isLoading: Bool = false
    ) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 58, height: 58)

                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(PlayerSurface.secondaryText)
                }
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(PlayerSurface.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(message)
                    .font(.system(size: 17))
                    .foregroundStyle(PlayerSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
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
                ProgressView()
                    .tint(PlayerSurface.primaryText)
                    .scaleEffect(0.75)
                Text("正在检测所属合集")
                    .font(.caption)
                    .foregroundStyle(PlayerSurface.secondaryText)
                Spacer()
            }
            .padding(14)
            .playerPanelBackground(cornerRadius: 16)
        } else if let currentPlaylist, !currentPlaylistTracks.isEmpty {
            let previewItems = PlayerListWindow.items(
                tracks: currentPlaylistTracks,
                current: engine.current,
                maxRows: Layout.sidePanelPreviewLimit)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("所在合集")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(PlayerSurface.secondaryText)
                        Text(currentPlaylist.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PlayerSurface.primaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(currentPlaylistPositionText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(PlayerSurface.secondaryText)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(previewItems) { item in
                            guardedPlayerRowButton {
                                Task { await playCurrentPlaylistTrack(at: item.index) }
                            } label: {
                                compactPlaylistRow(track: item.track, index: item.index)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(previewItems.count) * Layout.compactRowHeight)
            }
            .padding(14)
            .playerPanelBackground(cornerRadius: 18)
            .accessibilityIdentifier("playerCurrentPlaylistPanel")
        } else if let currentPlaylistError {
            Text(currentPlaylistError)
                .font(.caption2)
                .foregroundStyle(PlayerSurface.secondaryText)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func bottomContextListPanel(maxRows: Int) -> some View {
        if currentPlaylist != nil && !currentPlaylistTracks.isEmpty {
            currentPlaylistBottomPanel(maxRows: maxRows)
        } else {
            queueBottomPanel(maxRows: maxRows)
        }
    }

    @ViewBuilder
    private func currentPlaylistBottomPanel(maxRows: Int) -> some View {
        if let currentPlaylist, !currentPlaylistTracks.isEmpty {
            let previewItems = PlayerListWindow.items(
                tracks: currentPlaylistTracks,
                current: engine.current,
                maxRows: maxRows)
            VStack(alignment: .leading, spacing: 8) {
                playerDivider

                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(currentPlaylist.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PlayerSurface.primaryText)
                            .lineLimit(1)
                        Text("所在合集 · \(currentPlaylistPositionText)")
                            .font(.caption2)
                            .foregroundStyle(PlayerSurface.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        animate(pageTransitionAnimation) {
                            selectedPage = PlayerPage.queue.rawValue
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PlayerSurface.secondaryText)
                            .frame(width: 34, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看完整合集")
                }

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(previewItems) { item in
                            guardedPlayerRowButton {
                                Task { await playCurrentPlaylistTrack(at: item.index) }
                            } label: {
                                compactPlaylistRow(track: item.track, index: item.index)
                            }

                            if item.index != previewItems.last?.index {
                                playerDivider.padding(.leading, 34)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(previewItems.count) * Layout.compactRowHeight)
            }
            .padding(.horizontal, 28)
            .background(bottomContextFrameReader)
            .accessibilityIdentifier("playerBottomPlaylistPanel")
        }
    }

    @ViewBuilder
    private func queueBottomPanel(maxRows: Int) -> some View {
        if !engine.queue.isEmpty {
            let visibleRows = min(engine.queue.count, maxRows)
            VStack(alignment: .leading, spacing: 8) {
                playerDivider

                HStack(spacing: 8) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("播放列表")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PlayerSurface.primaryText)
                            .lineLimit(1)
                        Text("\(engine.queueIndex + 1)/\(engine.queue.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(PlayerSurface.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        animate(pageTransitionAnimation) {
                            selectedPage = PlayerPage.queue.rawValue
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PlayerSurface.secondaryText)
                            .frame(width: 34, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看完整播放列表")
                }

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: engine.queue.count > visibleRows) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(engine.queue.enumerated()), id: \.element.id) { index, track in
                                guardedPlayerRowButton {
                                    Task { await engine.jump(to: index) }
                                } label: {
                                    compactPlaylistRow(track: track, index: index)
                                        .id(track.id)
                                }

                                if index != engine.queue.count - 1 {
                                    playerDivider.padding(.leading, 34)
                                }
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
            .padding(.horizontal, 28)
            .background(bottomContextFrameReader)
            .accessibilityIdentifier("playerBottomQueuePanel")
        }
    }

    private var bottomContextFrameReader: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: PlayerBottomContextFrameKey.self,
                value: geo.frame(in: .global)
            )
        }
    }

    @ViewBuilder
    private var queuePreviewPanel: some View {
        if !engine.queue.isEmpty {
            let previewItems = queuePreviewItems
            let visibleRows = min(previewItems.count, Layout.sidePanelPreviewLimit)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("接下来播放")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PlayerSurface.primaryText)
                    Spacer()
                    Text("\(engine.queueIndex + 1)/\(engine.queue.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(PlayerSurface.secondaryText)
                }

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: previewItems.count > visibleRows) {
                        LazyVStack(spacing: 0) {
                            ForEach(previewItems, id: \.track.id) { item in
                                guardedPlayerRowButton {
                                    Task { await engine.jump(to: item.index) }
                                } label: {
                                    compactPlaylistRow(track: item.track, index: item.index)
                                        .id(item.track.id)
                                }
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
            .playerPanelBackground(cornerRadius: 18)
            .padding(.horizontal, 24)
        }
    }

    private func compactPlaylistRow(track: Track, index: Int) -> some View {
        let isCurrent = engine.current.map { track.key.matches($0) } ?? false
        let display = TrackTitleFormatter.displayMetadata(for: track, clean: cleanListTitles)
        return HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? AppTheme.accent : PlayerSurface.tertiaryText)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(display.title)
                    .font(.caption.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? AppTheme.accent : PlayerSurface.primaryText)
                    .lineLimit(1)
                Text(display.artist)
                    .font(.caption2)
                    .foregroundStyle(PlayerSurface.secondaryText)
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
                    .foregroundStyle(PlayerSurface.tertiaryText)
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

    private var recommendationsMatchCurrentTrack: Bool {
        guard let current = engine.current else {
            return recommendedTracks.isEmpty && recommendationSeedKey == nil
        }
        guard let recommendationSeedKey else { return false }
        return recommendationSeedKey.matches(current)
    }

    private func scheduleRecommendationLoad(clear: Bool) {
        recommendationTask?.cancel()
        recommendationsError = nil
        if clear {
            recommendedTracks = []
            recommendationSeedKey = nil
        }
        guard let current = engine.current else {
            recommendationsLoading = false
            return
        }
        guard selectedPage == PlayerPage.recommendations.rawValue else {
            recommendationsLoading = false
            return
        }
        if !clear, recommendationSeedKey?.matches(current) == true, !recommendedTracks.isEmpty {
            recommendationsLoading = false
            return
        }
        let isVisible = selectedPage == PlayerPage.recommendations.rawValue
        if isVisible && recommendedTracks.isEmpty {
            recommendationsLoading = true
        }
        recommendationTask = Task(priority: isVisible ? .userInitiated : .utility) {
            try? await Task.sleep(for: .milliseconds(clear && isVisible ? 260 : 0))
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
        guard let current = engine.current else { return }
        let bvid = current.bvid
        let currentKey = current.key
        recommendationsLoading = selectedPage == PlayerPage.recommendations.rawValue && recommendedTracks.isEmpty
        defer { recommendationsLoading = false }
        let excluded = shownRecommendationKeys.union([currentKey])
        let tracks = await RecommendationEngine().recommendations(
            mode: .relatedPanel,
            context: .init(
                current: current,
                queue: engine.queue,
                playlistTracks: currentPlaylistTracks,
                excludedKeys: excluded),
            limit: 24)
        guard engine.current?.bvid == bvid else { return }
        shownRecommendationKeys.formUnion(tracks.map(\.key))
        recommendationSeedKey = currentKey
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
        PlayerListWindow.positionText(tracks: currentPlaylistTracks, current: engine.current)
    }

    private var hasPlaylistContext: Bool {
        currentPlaylistLoading || currentPlaylist != nil || !currentPlaylistTracks.isEmpty || currentPlaylistError != nil
    }

    private var queueMatchesCurrentPlaylist: Bool {
        !currentPlaylistTracks.isEmpty
            && engine.queue.count == currentPlaylistTracks.count
            && zip(engine.queue, currentPlaylistTracks).allSatisfy { queueTrack, playlistTrack in
                queueTrack.key == playlistTrack.key
            }
    }

    private func playCurrentPlaylistTrack(at index: Int) async {
        guard currentPlaylistTracks.indices.contains(index) else { return }
        await engine.play(tracks: currentPlaylistTracks, startAt: index, queueMode: .sequential)
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

    private func isBottomContextGestureStart(_ location: CGPoint) -> Bool {
        guard selectedPage == PlayerPage.nowPlaying.rawValue else { return false }
        guard !bottomContextFrameInGlobal.isNull, !bottomContextFrameInGlobal.isEmpty else { return false }
        return bottomContextFrameInGlobal
            .insetBy(dx: -10, dy: -8)
            .contains(location)
    }

    private func isProgressGestureStart(_ location: CGPoint) -> Bool {
        guard selectedPage == PlayerPage.nowPlaying.rawValue else { return false }
        guard !progressFrameInGlobal.isNull, !progressFrameInGlobal.isEmpty else { return false }
        return progressFrameInGlobal
            .insetBy(dx: -28, dy: -18)
            .contains(location)
    }

    private func setProgressScrubbing(_ scrubbing: Bool) {
        isProgressScrubbing = scrubbing
    }

    private var centerBodyDismissDrag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($dismissDragOffset) { value, state, _ in
                guard selectedPage == PlayerPage.nowPlaying.rawValue else { return }
                guard !isBottomContextGestureStart(value.startLocation) else { return }
                guard let offset = PlayerGesturePolicy.dismissDragOffset(
                    translation: value.translation,
                    startY: value.startLocation.y,
                    dismissGrabZoneHeight: Layout.dismissGrabZoneHeight,
                    region: .centerBody,
                    isProgressScrubbing: isProgressScrubbing
                ) else { return }
                state = offset
            }
            .onEnded { value in
                guard selectedPage == PlayerPage.nowPlaying.rawValue else { return }
                guard !isBottomContextGestureStart(value.startLocation) else { return }
                if PlayerGesturePolicy.shouldDismissFullPlayer(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation,
                    startY: value.startLocation.y,
                    dismissGrabZoneHeight: Layout.dismissGrabZoneHeight,
                    region: .centerBody,
                    isProgressScrubbing: isProgressScrubbing
                ) {
                    closePlayer()
                }
            }
    }

    private var topChromeDismissDrag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($dismissDragOffset) { value, state, _ in
                guard let offset = PlayerGesturePolicy.dismissDragOffset(
                    translation: value.translation,
                    startY: value.startLocation.y,
                    dismissGrabZoneHeight: Layout.dismissGrabZoneHeight,
                    region: .topChrome,
                    isProgressScrubbing: isProgressScrubbing
                ) else { return }
                state = offset
            }
            .onEnded { value in
                if PlayerGesturePolicy.shouldDismissFullPlayer(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation,
                    startY: value.startLocation.y,
                    dismissGrabZoneHeight: Layout.dismissGrabZoneHeight,
                    region: .topChrome,
                    isProgressScrubbing: isProgressScrubbing
                ) {
                    closePlayer()
                }
            }
    }

    private var dismissDragAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .interactiveSpring(response: 0.26, dampingFraction: 0.9)
    }

    private var pageTransitionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .interactiveSpring(response: 0.32, dampingFraction: 0.88)
    }

    private func animate(_ animation: Animation, _ updates: @escaping () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }
}

private extension View {
    func playerPanelBackground(cornerRadius: CGFloat) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.11))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AppTheme.accent.opacity(0.26),
                                    Color.white.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
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
