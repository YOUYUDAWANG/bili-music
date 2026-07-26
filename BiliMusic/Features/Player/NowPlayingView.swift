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
        recommendationContextVisible: Bool,
        recommendationsStale: Bool,
        recommendationsEmpty: Bool,
        recommendationsMismatched: Bool
    ) -> RecommendationVisibleLoadPolicy {
        visibleLoad(
            recommendationContextVisible: recommendationContextVisible,
            recommendationsStale: recommendationsStale,
            recommendationsEmpty: recommendationsEmpty,
            recommendationsMismatched: recommendationsMismatched)
    }

    static func visibleContextChanged(
        recommendationContextVisible: Bool,
        recommendationsStale: Bool,
        recommendationsEmpty: Bool,
        recommendationsMismatched: Bool
    ) -> RecommendationVisibleLoadPolicy {
        visibleLoad(
            recommendationContextVisible: recommendationContextVisible,
            recommendationsStale: recommendationsStale,
            recommendationsEmpty: recommendationsEmpty,
            recommendationsMismatched: recommendationsMismatched)
    }

    private static func visibleLoad(
        recommendationContextVisible: Bool,
        recommendationsStale: Bool,
        recommendationsEmpty: Bool,
        recommendationsMismatched: Bool
    ) -> RecommendationVisibleLoadPolicy {
        RecommendationVisibleLoadPolicy(
            shouldLoad: recommendationContextVisible &&
                (recommendationsStale || recommendationsEmpty || recommendationsMismatched))
    }
}

private struct PlaylistLookupResult {
    let playlist: BiliClient.UPPlaylist?
    let tracks: [Track]
    let error: String?
}

@MainActor
private final class PlayerPlaylistLookupCache {
    static let shared = PlayerPlaylistLookupCache()

    private struct Entry {
        let result: PlaylistLookupResult
        let storedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let capacity = 32

    func result(for bvid: String, now: Date = Date()) -> PlaylistLookupResult? {
        guard let entry = entries[bvid] else { return nil }
        let ttl: TimeInterval
        if entry.result.error != nil {
            ttl = 60
        } else if entry.result.playlist == nil {
            ttl = 30 * 60
        } else {
            ttl = 2 * 60 * 60
        }
        guard now.timeIntervalSince(entry.storedAt) < ttl else {
            entries[bvid] = nil
            return nil
        }
        return entry.result
    }

    func store(_ result: PlaylistLookupResult, for bvid: String, now: Date = Date()) {
        entries[bvid] = Entry(result: result, storedAt: now)
        guard entries.count > capacity else { return }
        let overflow = entries.count - capacity
        for key in entries
            .sorted(by: { $0.value.storedAt < $1.value.storedAt })
            .prefix(overflow)
            .map(\.key) {
            entries[key] = nil
        }
    }
}

/// 全屏正在播放页(从 mini bar 上拉打开)。
struct NowPlayingView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onDismiss: (() -> Void)? = nil
    var namespace: Namespace.ID
    var usesSharedTransition = false
    var isCoverTransitionSource = true
    var coverRevealProgress: CGFloat = 1
    var contentRevealProgress: CGFloat = 1
    var safeAreaTop: CGFloat = 0
    private enum QueuePresentationState: Int, Comparable {
        case collapsed = 0
        case split = 1
        case fullQueue = 2

        static func < (lhs: QueuePresentationState, rhs: QueuePresentationState) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var isExpanded: Bool { self != .collapsed }

        mutating func promote() {
            switch self {
            case .collapsed:
                self = .split
            case .split:
                self = .fullQueue
            case .fullQueue:
                break
            }
        }

        mutating func demote() {
            switch self {
            case .collapsed:
                break
            case .split:
                self = .collapsed
            case .fullQueue:
                self = .split
            }
        }
    }

    private enum BottomContextTab: String, CaseIterable, Identifiable {
        case queue
        case playlist
        case recommendations

        var id: String { rawValue }

        var title: String {
            switch self {
            case .queue:
                return "当前列表"
            case .playlist:
                return "合集"
            case .recommendations:
                return "推荐"
            }
        }

        var icon: String {
            switch self {
            case .queue:
                return "text.line.first.and.arrowtriangle.forward"
            case .playlist:
                return "rectangle.stack"
            case .recommendations:
                return "sparkles"
            }
        }

        var accessibilityIdentifier: String {
            "playerBottomTab-\(rawValue)"
        }
    }

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
    @State private var recommendationLoadID = UUID()
    @State private var playlistLookupTask: Task<Void, Never>?
    @State private var scheduledPlaylistBVID: String?
    @State private var showLyrics = false
    @State private var showMVFullscreen = false
    @State private var showUPPlaylists = false
    @State private var showFavoriteFolders = false
    @State private var switchingMode = false
    @GestureState private var dismissDragOffset: CGFloat = 0
    @GestureState private var bottomContextDragOffset: CGFloat = 0
    @State private var queuePresentationState: QueuePresentationState = .collapsed
    @State private var bottomContextTab: BottomContextTab = .queue
    @State private var playHapticTrigger = 0
    @State private var prevHapticTrigger = 0
    @State private var nextHapticTrigger = 0
    @State private var favoriteHapticTrigger = 0
    @State private var favoriteWasAdded = false
    @State private var downloadTrigger = 0
    @State private var isProgressScrubbing = false
    // 抽屉 frame 只被手势判定读取，不参与布局；存进引用盒避免
    // onPreferenceChange 在拖拽/动画期间每帧触发整个 body 重算。
    @State private var bottomContextFrameBox = BottomContextFrameBox()
    // 确认下滑关闭后冻结的偏移量：@GestureState 松手自动归零会导致内容
    // 先回弹再淡出，这里把最终偏移接住让关闭沿手势方向继续。
    @State private var dismissCommitOffset: CGFloat = 0
    @State private var landscapeMVFullscreenKey: TrackKey?
    @State private var showInlineMVChrome = false
    @State private var inlineMVChromeHideTask: Task<Void, Never>?
    @AppStorage(TrackTitleFormatter.cleanListTitlesDefaultsKey) private var cleanListTitles = false
    @Environment(\.dismiss) private var dismiss
    private var favorites: FavoriteManager { .shared }

    private enum Layout {
        static let topChromeBottomPadding: CGFloat = 0
        static let topChromeControlSize: CGFloat = 44
        static let contentTopInset: CGFloat = 0
        static let centerHorizontalPadding: CGFloat = 26
        static let bottomSheetRowHeight: CGFloat = 52
        static let collapsedDrawerTopPadding: CGFloat = 36
        static let compactCollapsedDrawerTopPadding: CGFloat = 28
        static let fullQueueMiniHeaderHeight: CGFloat = 66
        static let dismissGrabZoneHeight: CGFloat = PlayerGesturePolicy.dismissGrabZoneHeight
    }

    private enum PlayerSurface {
        static let primaryText = Color.white.opacity(0.94)
        static let secondaryText = Color.white.opacity(0.66)
        static let tertiaryText = Color.white.opacity(0.46)
        static let divider = Color.white.opacity(0.11)
        static let panelFill = Color.white.opacity(0.14)
        static let panelStroke = Color.white.opacity(0.17)
        static let accentFill = AppTheme.accent.opacity(0.18)
        static let accentStroke = AppTheme.accent.opacity(0.30)
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
            .offset(y: dismissDragOffset + dismissCommitOffset)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nowPlayingView")
            // 对两者之和做动画：确认关闭时 GestureState 归零、commit 同帧接住，
            // 和值不变所以不产生回弹动画。
            .animation(dismissDragAnimation, value: dismissDragOffset + dismissCommitOffset)
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
            if engine.state == .playing {
                scheduleCurrentPlaylistLookup(force: false, delay: .milliseconds(350))
            }
        }
        .onChange(of: engine.playbackMode) { _, mode in
            inlineMVChromeHideTask?.cancel()
            showInlineMVChrome = false
            if mode != .mv {
                landscapeMVFullscreenKey = nil
            }
        }
        .onChange(of: isCoverTransitionSource) { _, ownsArtwork in
            // 关闭动画中途重新打开:清掉已冻结的下滑偏移,让内容滑回原位。
            if ownsArtwork, dismissCommitOffset != 0 {
                dismissCommitOffset = 0
            }
        }
        .onChange(of: engine.current?.key) { oldKey, newKey in
            if let oldKey, let newKey, oldKey.isCIDEnrichment(to: newKey) {
                return
            }
            recommendationTask?.cancel()
            recommendationLoadID = UUID()
            playlistLookupTask?.cancel()
            scheduledPlaylistBVID = nil
            currentPlaylist = nil
            currentPlaylistTracks = []
            currentPlaylistError = nil
            currentPlaylistLoading = false
            recommendationSeedKey = nil
            recommendedTracks = []
            recommendationsError = nil
            shownRecommendationKeys = []
            let refreshPolicy = RecommendationPanelRefreshPolicy.currentTrackChanged(
                suppressImmediateRefresh: suppressNextRecommendationRefresh,
                recommendationPanelVisible: isRecommendationContextVisible)
            suppressNextRecommendationRefresh = false
            recommendationsStale = refreshPolicy.shouldMarkStale
            if refreshPolicy.shouldLoadImmediately {
                scheduleRecommendationLoad(clear: true)
                recommendationsStale = false
            }
        }
        .onChange(of: engine.state) { _, state in
            guard state == .playing else { return }
            scheduleCurrentPlaylistLookup(force: false, delay: .milliseconds(350))
            let loadPolicy = RecommendationVisibleLoadPolicy.playbackStarted(
                recommendationContextVisible: isRecommendationContextVisible,
                recommendationsStale: recommendationsStale,
                recommendationsEmpty: recommendedTracks.isEmpty,
                recommendationsMismatched: !recommendationsMatchCurrentTrack)
            guard loadPolicy.shouldLoad else { return }
            recommendationsStale = false
            scheduleRecommendationLoad(clear: !recommendedTracks.isEmpty)
        }
        .onChange(of: bottomContextTab) { _, _ in
            let loadPolicy = RecommendationVisibleLoadPolicy.visibleContextChanged(
                recommendationContextVisible: isRecommendationContextVisible,
                recommendationsStale: recommendationsStale,
                recommendationsEmpty: recommendedTracks.isEmpty,
                recommendationsMismatched: !recommendationsMatchCurrentTrack)
            guard loadPolicy.shouldLoad else { return }
            recommendationsStale = false
            scheduleRecommendationLoad(clear: !recommendedTracks.isEmpty)
        }
        .onChange(of: queuePresentationState) { _, _ in
            let loadPolicy = RecommendationVisibleLoadPolicy.visibleContextChanged(
                recommendationContextVisible: isRecommendationContextVisible,
                recommendationsStale: recommendationsStale,
                recommendationsEmpty: recommendedTracks.isEmpty,
                recommendationsMismatched: !recommendationsMatchCurrentTrack)
            guard loadPolicy.shouldLoad else { return }
            recommendationsStale = false
            scheduleRecommendationLoad(clear: !recommendedTracks.isEmpty)
        }
        .onDisappear {
            recommendationTask?.cancel()
            recommendationLoadID = UUID()
            playlistLookupTask?.cancel()
            scheduledPlaylistBVID = nil
            inlineMVChromeHideTask?.cancel()
        }
    }

    private func playerCoverSize(for size: CGSize, safeAreaTop: CGFloat) -> CGFloat {
        let availableHeight = max(1, size.height - safeAreaTop)
        let isLandscape = size.width > size.height

        if isLandscape {
            return min(max(168, size.width * 0.24), max(168, availableHeight * 0.48), 250)
        }

        return min(max(300, size.width - 44), max(306, availableHeight * 0.46), 398)
    }

    @ViewBuilder
    private var playerBackground: some View {
        let palette = engine.currentArtworkPalette
        ZStack {
            Color(uiColor: palette.middle)

            palette.gradient
                .opacity(0.96)

            palette.glow
                .blendMode(.screen)
                .opacity(0.56)

            RadialGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 32,
                endRadius: 520
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.04),
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.34)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .animation(.easeInOut(duration: 0.32), value: palette)
    }

    @ViewBuilder
    private func nowPlayingPage(coverSize: CGFloat, pageWidth: CGFloat, isLandscape: Bool) -> some View {
        if isLandscape {
            landscapeNowPlayingPage(coverSize: coverSize, pageWidth: pageWidth)
        } else {
            portraitNowPlayingPage(coverSize: coverSize, pageWidth: pageWidth)
        }
    }

    private func landscapeNowPlayingPage(coverSize: CGFloat, pageWidth: CGFloat) -> some View {
            HStack(spacing: 22) {
                mediaView(coverSize: coverSize)

            VStack(spacing: 8) {
                playerMetadata(compact: true)

                playerControlStack(compact: true)
            }
            .playerContentReveal(opacity: playerContentOpacity)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func portraitNowPlayingPage(coverSize: CGFloat, pageWidth: CGFloat) -> some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 760
            let activeCoverSize = portraitCoverSize(base: coverSize, isCompact: isCompact)
            let topPadding = portraitTopPadding(height: proxy.size.height, isCompact: isCompact)
            let coverBottomSpacing = portraitCoverBottomSpacing(isCompact: isCompact)
            let metadataBottomSpacing = portraitMetadataBottomSpacing(isCompact: isCompact)
            let bottomFloor: CGFloat = queuePresentationState == .fullQueue ? 0 : (isCompact ? 16 : 26)
            let maxRows = bottomContextMaxRows(for: proxy.size, isCompact: isCompact)
            let drawerTopOffset = fullQueueDrawerTopOffset(for: proxy.size.height)
            let drawerHeight = max(420, proxy.size.height - drawerTopOffset)
            let drawerFrameHeight: CGFloat? = queuePresentationState == .fullQueue ? drawerHeight : nil
            let drawerAlignment: Alignment = queuePresentationState == .fullQueue ? .top : .bottom
            let drawerOffsetY: CGFloat = queuePresentationState == .fullQueue ? drawerTopOffset : 0
            let drawerBottomPadding: CGFloat = queuePresentationState == .collapsed
                ? (isCompact ? 24 : 30)
                : 0

            ZStack(alignment: .top) {
                if queuePresentationState == .fullQueue {
                    fullQueueMiniPlayerHeader
                        .padding(.horizontal, 24)
                        .frame(height: Layout.fullQueueMiniHeaderHeight, alignment: .center)
                        .playerContentReveal(opacity: playerContentOpacity)
                } else {
                    VStack(spacing: 0) {
                        mediaView(coverSize: activeCoverSize)
                            .padding(.top, topPadding)
                            .padding(.bottom, coverBottomSpacing)

                        VStack(spacing: 0) {
                            playerMetadata(
                                compact: isCompact || queuePresentationState.isExpanded,
                                centered: false)
                                .padding(.horizontal, 34)
                                .padding(.bottom, metadataBottomSpacing + (queuePresentationState == .collapsed ? 16 : 0))
                                .playerContentReveal(opacity: playerContentOpacity)

                            portraitPlayerControls(
                                isCompact: isCompact,
                                maxRows: maxRows,
                                includeBottomContext: false)
                                .playerContentReveal(opacity: playerContentOpacity)

                            if let favoriteError = favorites.lastError {
                                Text(favoriteError)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.error)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 8)
                                    .padding(.horizontal, 28)
                                    .playerContentReveal(opacity: playerContentOpacity)
                            }
                        }
                        .offset(y: queuePresentationState == .collapsed ? 64 : 0)

                        Spacer(minLength: bottomFloor)
                    }
                }

                bottomContextDrawer(maxRows: maxRows)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: drawerAlignment)
                    .frame(height: drawerFrameHeight, alignment: .top)
                    .offset(y: drawerOffsetY)
                    .padding(.bottom, drawerBottomPadding)
                    .layoutPriority(queuePresentationState == .fullQueue ? 1 : 0)
                    .playerContentReveal(opacity: playerContentOpacity)
            }
        }
        .animation(contextTransitionAnimation, value: queuePresentationState)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func fullQueueDrawerTopOffset(for pageHeight: CGFloat) -> CGFloat {
        pageHeight < 760 ? 76 : 84
    }

    private var fullQueueMiniPlayerHeader: some View {
        HStack(spacing: 14) {
            fullQueueHeaderArtwork

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PlayerSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(displayArtist)
                    .font(.system(size: 15))
                    .foregroundStyle(PlayerSurface.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                playHapticTrigger += 1
                engine.togglePlayPause()
            } label: {
                ZStack {
                    Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .contentTransition(.symbolEffect(.replace))

                    if engine.state == .loading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.white.opacity(0.82))
                    }
                }
                .frame(width: 46, height: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(engine.state == .playing ? "暂停" : "播放")
            .accessibilityIdentifier("playerTransportControls")
            .sensoryFeedback(.impact(weight: .medium), trigger: playHapticTrigger)
        }
        .frame(height: 58)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playerFullQueueMiniHeader")
    }

    @ViewBuilder
    private var fullQueueHeaderArtwork: some View {
        let currentTrack = engine.current
        let coverURL = BiliArtworkURL.thumbnail(currentTrack?.coverURL, width: 320, height: 180)
        if let coverURL {
            CachedAsyncImage(
                url: coverURL,
                targetSize: CGSize(width: 72, height: 42),
                fallbackImage: engine.currentCoverImage,
                onImageLoaded: { image in
                    engine.rememberCurrentCover(image, for: currentTrack)
                }
            ) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                artworkPlaceholder(cornerRadius: 6)
            }
            .frame(width: 72, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if let currentCoverImage = engine.currentCoverImage {
            Image(uiImage: currentCoverImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 72, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            artworkPlaceholder(cornerRadius: 6)
                .frame(width: 72, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func portraitCoverSize(base: CGFloat, isCompact: Bool) -> CGFloat {
        switch queuePresentationState {
        case .collapsed:
            return isCompact ? min(base * 0.98, base - 4) : min(base * 0.98, base - 6)
        case .split:
            return max(isCompact ? 188 : 226, min(base * 0.74, base - 58))
        case .fullQueue:
            return max(isCompact ? 128 : 150, min(base * 0.48, 178))
        }
    }

    private func portraitTopPadding(height: CGFloat, isCompact: Bool) -> CGFloat {
        switch queuePresentationState {
        case .collapsed:
            return isCompact ? 22 : min(58, max(40, height * 0.052))
        case .split:
            return isCompact ? 4 : 8
        case .fullQueue:
            return isCompact ? 0 : 4
        }
    }

    private func portraitCoverBottomSpacing(isCompact: Bool) -> CGFloat {
        switch queuePresentationState {
        case .collapsed:
            return isCompact ? 18 : 26
        case .split:
            return isCompact ? 8 : 10
        case .fullQueue:
            return isCompact ? 8 : 10
        }
    }

    private func portraitMetadataBottomSpacing(isCompact: Bool) -> CGFloat {
        switch queuePresentationState {
        case .collapsed:
            return isCompact ? 10 : 14
        case .split:
            return isCompact ? 8 : 10
        case .fullQueue:
            return isCompact ? 8 : 10
        }
    }

    private func bottomContextMaxRows(for size: CGSize, isCompact: Bool) -> Int {
        switch queuePresentationState {
        case .collapsed:
            return 0
        case .split:
            return isCompact ? 4 : 5
        case .fullQueue:
            return Int.max
        }
    }

    private func playerMetadata(compact: Bool, centered: Bool = true) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: compact ? 3 : 6) {
            Text(displayTitle)
                .font(.system(size: compact ? 19 : 22, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(centered ? .center : .leading)
                .lineLimit(compact ? 1 : 2)
                .lineSpacing(2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .accessibilityIdentifier("nowPlayingTitle")

            Text(displayArtist)
                .font(.system(size: compact ? 13 : 16, weight: .regular))
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
        .accessibilityIdentifier("nowPlayingMetadata")
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

    private func portraitPlayerControls(
        isCompact: Bool,
        maxRows: Int,
        includeBottomContext: Bool = true
    ) -> some View {
        VStack(spacing: 0) {
            progressView

            transportControls
                .padding(.top, portraitTransportTopPadding(isCompact: isCompact))

            VStack(spacing: 0) {
                if queuePresentationState != .fullQueue {
                    playerToolbarButtons
                        .padding(.top, portraitToolbarTopPadding(isCompact: isCompact))
                        .transition(
                            .opacity
                                .combined(with: .scale(scale: 0.98, anchor: .top))
                                .combined(with: .move(edge: .top))
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("playerToolbar")
                }

                if includeBottomContext {
                    bottomContextDrawer(maxRows: maxRows)
                        .padding(.top, portraitBottomContextTopPadding(isCompact: isCompact))
                }
            }
        }
    }

    private func portraitTransportTopPadding(isCompact: Bool) -> CGFloat {
        switch queuePresentationState {
        case .collapsed:
            return isCompact ? 18 : 24
        case .split:
            return isCompact ? 10 : 12
        case .fullQueue:
            return isCompact ? 8 : 10
        }
    }

    private func portraitToolbarTopPadding(isCompact: Bool) -> CGFloat {
        switch queuePresentationState {
        case .collapsed:
            return isCompact ? 14 : 18
        case .split:
            return isCompact ? 8 : 10
        case .fullQueue:
            return isCompact ? 8 : 10
        }
    }

    private func portraitBottomContextTopPadding(isCompact: Bool) -> CGFloat {
        switch queuePresentationState {
        case .collapsed:
            return isCompact ? Layout.compactCollapsedDrawerTopPadding : Layout.collapsedDrawerTopPadding
        case .split:
            return isCompact ? 8 : 10
        case .fullQueue:
            return isCompact ? 6 : 8
        }
    }

    private func playerControlStack(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 12) {
            progressView

            transportControls
                .padding(.top, compact ? -6 : -2)

            playerToolbarButtons
                .padding(.top, compact ? -2 : 2)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("playerToolbar")
        }
        .padding(.bottom, 2)
    }

    private func playerPages(coverSize: CGFloat, width: CGFloat, safeAreaTop: CGFloat, isLandscape: Bool) -> some View {
        nowPlayingPage(coverSize: coverSize, pageWidth: width, isLandscape: isLandscape)
            .padding(.top, playerContentTopInset(safeAreaTop: safeAreaTop, isLandscape: isLandscape))
            .contentShape(Rectangle())
            .simultaneousGesture(centerBodyDismissDrag, including: .all)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            playerTopChrome(safeAreaTop: safeAreaTop)
                .playerContentReveal(opacity: playerContentOpacity)
        }
        .onPreferenceChange(PlayerBottomContextFrameKey.self) { [box = bottomContextFrameBox] frame in
            box.rect = frame
        }
    }

    private func playerContentTopInset(safeAreaTop: CGFloat, isLandscape: Bool) -> CGFloat {
        guard !isLandscape else { return Layout.contentTopInset }
        switch queuePresentationState {
        case .collapsed:
            return max(124, safeAreaTop + 78)
        case .split:
            return max(58, safeAreaTop + 18)
        case .fullQueue:
            return max(92, safeAreaTop + 42)
        }
    }

    @ViewBuilder
    private func mediaView(coverSize: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            let currentTrack = engine.current
            let coverURL = BiliArtworkURL.thumbnail(currentTrack?.coverURL, width: 960, height: 540)
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
            .frame(width: coverSize, height: coverSize * 9 / 16)
            .nowPlayingSharedGeometry(
                id: "playerArtwork",
                in: namespace,
                active: usesSharedTransition,
                isSource: isCoverTransitionSource)
            .opacity(coverRevealOpacity)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.playerCoverRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.playerCoverRadius)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.42), radius: 28, y: 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("播放封面")
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
        Double(PlayerGesturePolicy.artworkRevealOpacity(
            openProgress: coverRevealProgress,
            isTransitionSource: isCoverTransitionSource,
            isSharedTransitionActive: usesSharedTransition))
    }

    private var playerContentOpacity: Double {
        let progress = min(1, max(0, (contentRevealProgress - 0.24) / 0.22))
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
        HStack(spacing: 48) {
            PlayerIconButton(systemName: "backward.fill", size: 30, accessibilityLabel: "上一曲") {
                prevHapticTrigger += 1
                Task { await engine.playPrevious() }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: prevHapticTrigger)
            Button {
                playHapticTrigger += 1
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 72, height: 72)
                    .foregroundStyle(Color.black.opacity(0.92))
                    .background(Color.white, in: Circle())
                    .shadow(color: .black.opacity(0.16), radius: 14, y: 7)
            }
            .overlay { if engine.state == .loading { ProgressView().tint(Color.black.opacity(0.80)) } }
            .accessibilityIdentifier("playerTransportControls")
            .sensoryFeedback(.impact(weight: .medium), trigger: playHapticTrigger)
            PlayerIconButton(systemName: "forward.fill", size: 30, accessibilityLabel: "下一曲") {
                nextHapticTrigger += 1
                Task { await engine.playNext() }
            }
            .disabled(!engine.hasNext)
            .sensoryFeedback(.impact(weight: .medium), trigger: nextHapticTrigger)
        }
        .foregroundStyle(Color.white.opacity(0.94))
    }

    private var playerToolbarButtons: some View {
        HStack(spacing: 20) {
            favoriteButton
            downloadButton
            mvSwitchButton
            moreMenu
        }
        .frame(maxWidth: 246)
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
        .contextMenu {
            if CookieStore.isLoggedIn, !favorites.folders.isEmpty {
                ForEach(favorites.folders) { folder in
                    Button {
                        guard let current = engine.current else { return }
                        Task {
                            await favorites.toggle(track: current, folder: folder)
                        }
                    } label: {
                        Label(folder.title, systemImage: "folder")
                    }
                }
            } else {
                Button {
                    showFavoriteFolders = true
                } label: {
                    Label(
                        CookieStore.isLoggedIn ? "选择收藏夹" : "请先登录 B 站",
                        systemImage: "folder.badge.plus")
                }
                .disabled(!CookieStore.isLoggedIn)
            }
        }
        .task {
            guard CookieStore.isLoggedIn, favorites.folders.isEmpty else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await favorites.loadFolders()
        }
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
                    engine.setQueueMode(mode)
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
                        engine.setQueueMode(mode)
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
        VStack(spacing: 0) {
            Color.clear
                .frame(height: max(safeAreaTop, 12))
                .accessibilityHidden(true)

            HStack {
                Button {
                    closePlayer()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 21, weight: .semibold))
                        .frame(width: Layout.topChromeControlSize, height: Layout.topChromeControlSize)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .accessibilityLabel("收起播放器")

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, Layout.topChromeBottomPadding)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(topChromeDismissDrag, including: .all)
        .accessibilityIdentifier("playerTopChrome")
    }

    private func setPlaybackMode(_ mode: PlayerEngine.PlaybackMode) {
        guard mode != engine.playbackMode, !switchingMode else { return }
        guard mode == .music || engine.videoAvailable else { return }
        // 同步置位：Task 内置位会让快速双击都通过 guard，模式被切换两次。
        switchingMode = true
        Task {
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
        // sheet 与 fullScreenCover 不能同时呈现；有 sheet 时不消费 key，
        // 留待 sheet 关闭后再次旋转仍可触发。
        guard !showLyrics, !showFavoriteFolders, !showUPPlaylists else { return }
        guard landscapeMVFullscreenKey?.matches(current) != true else { return }
        landscapeMVFullscreenKey = current.key
        showMVFullscreen = true
    }

    private var playerDivider: some View {
        PlayerSurface.divider.frame(height: 0.5)
    }

    private func guardedPlayerRowButton<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
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
    private func bottomContextDrawer(maxRows: Int) -> some View {
        if hasBottomContextContent {
            VStack(spacing: 0) {
                bottomContextHeader

                if queuePresentationState.isExpanded {
                    VStack(spacing: 0) {
                        bottomContextTabPicker
                            .padding(.horizontal, 28)
                            .padding(.bottom, 8)

                        PlayerSurface.divider
                            .frame(height: 0.5)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 6)

                        bottomContextListPanel(maxRows: maxRows)
                            .id(bottomContextTab)
                            .transition(bottomContextPanelTransition)
                    }
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                        )
                    )
                }
            }
            .padding(.bottom, queuePresentationState.isExpanded ? 0 : 2)
            .offset(y: bottomContextInteractiveOffset)
            .frame(maxWidth: .infinity, maxHeight: queuePresentationState == .fullQueue ? .infinity : nil, alignment: .top)
            .background(alignment: .top) {
                RoundedRectangle(cornerRadius: bottomContextCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(bottomContextBackgroundOpacity))
                    .overlay {
                        RoundedRectangle(cornerRadius: bottomContextCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(bottomContextStrokeOpacity), lineWidth: 1)
                    }
                    .padding(.horizontal, bottomContextBackgroundHorizontalInset)
                    .opacity(queuePresentationState == .collapsed ? 0 : 1)
                    .scaleEffect(x: 1, y: queuePresentationState == .collapsed ? 0.82 : 1, anchor: .top)
            }
            .clipShape(RoundedRectangle(cornerRadius: bottomContextCornerRadius, style: .continuous))
            .background(bottomContextFrameReader)
            .animation(contextTransitionAnimation, value: queuePresentationState)
            .animation(contextTransitionAnimation, value: bottomContextTab)
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: bottomContextDragOffset)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("playerBottomContextDrawer")
        }
    }

    private var bottomContextHeader: some View {
        Group {
            if queuePresentationState == .fullQueue {
                VStack(spacing: 0) {
                    bottomContextHandle
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity)

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(bottomContextEyebrow)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(PlayerSurface.secondaryText)
                                .lineLimit(1)
                            Text(bottomContextFullTitle)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(PlayerSurface.primaryText)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            animate(contextTransitionAnimation) {
                                queuePresentationState = .split
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.80))
                                .frame(width: 42, height: 38)
                                .background(Color.white.opacity(0.10), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(bottomContextFullListLabel)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityIdentifier("playerQueueFullHeader")
            } else if queuePresentationState.isExpanded {
                HStack(spacing: 12) {
                    bottomContextHandle

                    VStack(alignment: .leading, spacing: 1) {
                        Text(bottomContextEyebrow)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(PlayerSurface.secondaryText)
                            .lineLimit(1)
                        Text(bottomContextTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PlayerSurface.primaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        animate(contextTransitionAnimation) {
                            queuePresentationState = queuePresentationState == .fullQueue ? .split : .fullQueue
                        }
                    } label: {
                        Image(systemName: queuePresentationState == .fullQueue ? "chevron.down" : "chevron.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.74))
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(bottomContextFullListLabel)
                }
                .padding(.horizontal, 28)
                .frame(height: 54)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityIdentifier(queuePresentationState == .fullQueue ? "playerQueueFullHeader" : "playerQueueSplitHeader")
            } else {
                VStack(spacing: 0) {
                    bottomContextHandle
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityIdentifier("playerBottomContextCollapsed")
            }
        }
        .contentShape(Rectangle())
        .gesture(bottomContextHeaderDrag)
        .onTapGesture {
            animate(contextTransitionAnimation) {
                if queuePresentationState == .fullQueue {
                    queuePresentationState = .split
                } else {
                    queuePresentationState.promote()
                }
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(bottomContextAccessibilityLabel)
    }

    private var bottomContextCornerRadius: CGFloat {
        switch queuePresentationState {
        case .collapsed:
            return 12
        case .split:
            return 18
        case .fullQueue:
            return 22
        }
    }

    private var bottomContextBackgroundHorizontalInset: CGFloat {
        switch queuePresentationState {
        case .collapsed:
            return 86
        case .split:
            return 18
        case .fullQueue:
            return 0
        }
    }

    private var bottomContextBackgroundOpacity: Double {
        switch queuePresentationState {
        case .collapsed:
            return 0.055
        case .split:
            return 0.078
        case .fullQueue:
            return 0.108
        }
    }

    private var bottomContextStrokeOpacity: Double {
        queuePresentationState == .collapsed ? 0.055 : 0.075
    }

    private var bottomContextPanelTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .move(edge: .bottom))
                .combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .opacity
                .combined(with: .scale(scale: 0.985, anchor: .top))
        )
    }

    private var bottomContextHandle: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color.white.opacity(queuePresentationState.isExpanded ? 0.30 : 0.24))
            .frame(width: 34, height: 3)
    }

    private var bottomContextTabPicker: some View {
        HStack(spacing: 6) {
            ForEach(BottomContextTab.allCases) { tab in
                Button {
                    animate(contextTransitionAnimation) {
                        bottomContextTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.title)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(bottomContextTab == tab ? Color.white : PlayerSurface.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(bottomContextTab == tab ? Color.white.opacity(0.14) : Color.white.opacity(0.045))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.accessibilityIdentifier)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(bottomContextTab == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    @ViewBuilder
    private func bottomContextListPanel(maxRows: Int) -> some View {
        switch bottomContextTab {
        case .queue:
            queueBottomPanel(maxRows: maxRows)
        case .playlist:
            currentPlaylistBottomPanel(maxRows: maxRows)
        case .recommendations:
            recommendationsBottomPanel(maxRows: maxRows)
        }
    }

    @ViewBuilder
    private func currentPlaylistBottomPanel(maxRows: Int) -> some View {
        if currentPlaylistLoading && currentPlaylistTracks.isEmpty {
            playerPageState(
                title: "正在检测合集",
                message: "如果当前歌曲来自 UP 主合集，会在这里显示完整列表。",
                systemName: "rectangle.stack",
                isLoading: true
            )
            .padding(.horizontal, 28)
            .accessibilityIdentifier("playerBottomPlaylistLoading")
        } else if currentPlaylist != nil && !currentPlaylistTracks.isEmpty {
            let visibleItems = queuePresentationState == .fullQueue
                ? Array(currentPlaylistTracks.enumerated()).map { PlayerListWindow.Item(index: $0.offset, track: $0.element) }
                : PlayerListWindow.items(
                    tracks: currentPlaylistTracks,
                    current: engine.current,
                    maxRows: maxRows)
            let visibleRows = queuePresentationState == .fullQueue
                ? max(1, visibleItems.count)
                : min(visibleItems.count, max(1, maxRows))
            VStack(alignment: .leading, spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: queuePresentationState == .fullQueue || visibleItems.count > visibleRows) {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleItems) { item in
                                guardedPlayerRowButton {
                                    Task { await playCurrentPlaylistTrack(at: item.index) }
                                } label: {
                                    bottomSheetTrackRow(track: item.track, index: item.index)
                                        .id(item.track.id)
                                }

                                if item.index != visibleItems.last?.index {
                                    playerDivider.padding(.leading, 72)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: queuePresentationState == .fullQueue ? .infinity : CGFloat(visibleRows) * Layout.bottomSheetRowHeight)
                    .onAppear { scrollCurrentPlaylist(proxy) }
                    .onChange(of: engine.current?.key) { oldKey, newKey in
                        if let oldKey, let newKey, oldKey.isCIDEnrichment(to: newKey) {
                            return
                        }
                        scrollCurrentPlaylist(proxy)
                    }
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: queuePresentationState == .fullQueue ? .infinity : nil, alignment: .top)
            .accessibilityIdentifier("playerBottomPlaylistPanel")
        } else {
            playerPageState(
                title: "没有检测到合集",
                message: currentPlaylistError ?? "这首歌不在可识别的 UP 主合集里。",
                systemName: "rectangle.stack"
            )
            .padding(.horizontal, 28)
            .accessibilityIdentifier("playerBottomPlaylistEmpty")
        }
    }

    @ViewBuilder
    private func queueBottomPanel(maxRows: Int) -> some View {
        if !engine.queue.isEmpty {
            let visibleRows = queuePresentationState == .fullQueue
                ? max(1, engine.queue.count)
                : min(engine.queue.count, maxRows)
            VStack(alignment: .leading, spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: queuePresentationState == .fullQueue || engine.queue.count > visibleRows) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(engine.queue.enumerated()), id: \.element.id) { index, track in
                                guardedPlayerRowButton {
                                    Task { await engine.jump(to: index) }
                                } label: {
                                    bottomSheetTrackRow(track: track, index: index)
                                        .id(track.id)
                                }

                                if index != engine.queue.count - 1 {
                                    playerDivider.padding(.leading, 72)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: queuePresentationState == .fullQueue ? .infinity : CGFloat(visibleRows) * Layout.bottomSheetRowHeight)
                    .onAppear { scrollCurrentQueue(proxy) }
                    .onChange(of: engine.queueIndex) { _, _ in
                        scrollCurrentQueue(proxy)
                    }
                    .onChange(of: engine.current?.key) { oldKey, newKey in
                        if let oldKey, let newKey, oldKey.isCIDEnrichment(to: newKey) {
                            return
                        }
                        scrollCurrentQueue(proxy)
                    }
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: queuePresentationState == .fullQueue ? .infinity : nil, alignment: .top)
            .accessibilityIdentifier("playerBottomQueuePanel")
        } else {
            playerPageState(
                title: "当前列表为空",
                message: "从搜索、推荐或收藏夹播放歌曲后，这里会显示当前列表。",
                systemName: "list.bullet"
            )
            .padding(.horizontal, 28)
            .accessibilityIdentifier("playerBottomQueueEmpty")
        }
    }

    @ViewBuilder
    private func recommendationsBottomPanel(maxRows: Int) -> some View {
        Group {
            if recommendationsLoading {
                playerPageState(
                    title: "正在加载推荐",
                    message: "推荐会根据当前歌曲生成，播放不会因此中断。",
                    systemName: "music.note.list",
                    isLoading: true
                )
                .accessibilityIdentifier("playerBottomRecommendationsLoading")
            } else if recommendationsError != nil {
                playerPageState(
                    title: "推荐加载失败",
                    message: recommendationsError ?? "请稍后重试。",
                    systemName: "exclamationmark.triangle"
                )
                .accessibilityIdentifier("playerBottomRecommendationsError")
            } else if !recommendationsMatchCurrentTrack {
                playerPageState(
                    title: "准备当前歌曲推荐",
                    message: "打开推荐后会加载和当前歌曲相关的音乐。",
                    systemName: "sparkles",
                    isLoading: true
                )
                .accessibilityIdentifier("playerBottomRecommendationsLoading")
            } else if recommendedTracks.isEmpty {
                playerPageState(
                    title: "暂无推荐",
                    message: "当前歌曲暂时没有找到合适的相关音乐。",
                    systemName: "music.note.list"
                )
                .accessibilityIdentifier("playerBottomRecommendationsEmpty")
            } else {
                let visibleItems = queuePresentationState == .fullQueue
                    ? Array(recommendedTracks.enumerated())
                    : Array(recommendedTracks.prefix(maxRows).enumerated())
                let visibleRows = queuePresentationState == .fullQueue
                    ? max(1, visibleItems.count)
                    : min(visibleItems.count, max(1, maxRows))

                VStack(alignment: .leading, spacing: 0) {
                    ScrollView(.vertical, showsIndicators: queuePresentationState == .fullQueue || recommendedTracks.count > visibleRows) {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleItems, id: \.element.id) { index, track in
                                guardedPlayerRowButton {
                                    suppressNextRecommendationRefresh = true
                                    Task { await engine.play(tracks: recommendedTracks, startAt: index, queueMode: .radio) }
                                } label: {
                                    bottomSheetTrackRow(track: track, index: index)
                                }

                                if index != visibleItems.last?.offset {
                                    playerDivider.padding(.leading, 72)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: queuePresentationState == .fullQueue ? .infinity : CGFloat(visibleRows) * Layout.bottomSheetRowHeight)
                }
                .accessibilityIdentifier("playerBottomRecommendationsPanel")
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: queuePresentationState == .fullQueue ? .infinity : nil, alignment: .top)
        .onAppear {
            ensureRecommendationsLoadedIfVisible()
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

    private var hasBottomContextContent: Bool {
        engine.current != nil ||
            currentPlaylistLoading ||
            currentPlaylist != nil ||
            !currentPlaylistTracks.isEmpty ||
            !engine.queue.isEmpty
    }

    private var bottomContextEyebrow: String {
        if queuePresentationState == .fullQueue && bottomContextTab == .queue {
            return "Playing from"
        }
        if bottomContextTab == .playlist && currentPlaylistLoading && currentPlaylistTracks.isEmpty {
            return "正在检测"
        }
        if bottomContextTab == .playlist && currentPlaylist != nil && !currentPlaylistTracks.isEmpty {
            return "Playing from"
        }
        if bottomContextTab == .recommendations {
            return "Related"
        }
        return "Up Next"
    }

    private var bottomContextTitle: String {
        switch bottomContextTab {
        case .queue:
            guard !engine.queue.isEmpty else { return "当前列表" }
            return "\(engine.queueIndex + 1)/\(engine.queue.count)"
        case .playlist:
            if currentPlaylistLoading && currentPlaylistTracks.isEmpty {
                return "当前歌曲所属合集"
            }
            if let currentPlaylist, !currentPlaylistTracks.isEmpty {
                return currentPlaylist.title
            }
            return "当前歌曲所属合集"
        case .recommendations:
            return recommendationsMatchCurrentTrack && !recommendedTracks.isEmpty
                ? "\(recommendedTracks.count) 首相关歌曲"
                : "当前歌曲推荐"
        }
    }

    private var bottomContextFullTitle: String {
        switch bottomContextTab {
        case .queue:
            return "当前列表"
        case .playlist:
            if let currentPlaylist, !currentPlaylistTracks.isEmpty {
                return currentPlaylist.title
            }
            return "当前歌曲所属合集"
        case .recommendations:
            return "当前歌曲推荐"
        }
    }

    private var bottomContextFullListLabel: String {
        queuePresentationState == .fullQueue ? "收起列表" : "展开完整列表"
    }

    private var bottomContextAccessibilityLabel: String {
        switch queuePresentationState {
        case .collapsed:
            return "展开接下来播放"
        case .split:
            return "展开完整播放列表"
        case .fullQueue:
            return "收起到接下来播放"
        }
    }

    private var bottomContextInteractiveOffset: CGFloat {
        if queuePresentationState.isExpanded {
            return max(0, min(28, bottomContextDragOffset * 0.35))
        }
        return min(0, max(-24, bottomContextDragOffset * 0.35))
    }

    private var bottomContextHeaderDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($bottomContextDragOffset) { value, state, _ in
                guard abs(value.translation.height) > abs(value.translation.width) * 1.1 else {
                    // 方向意图消失时归零,避免视差偏移冻结。
                    state = 0
                    return
                }
                state = value.translation.height
            }
            .onEnded { value in
                guard abs(value.translation.height) > abs(value.translation.width) * 1.1 else { return }
                let projected = value.predictedEndTranslation.height
                if value.translation.height < -22 || projected < -46 {
                    animate(contextTransitionAnimation) {
                        queuePresentationState.promote()
                    }
                } else if value.translation.height > 28 || projected > 58 {
                    animate(contextTransitionAnimation) {
                        queuePresentationState.demote()
                    }
                }
            }
    }

    private func bottomSheetTrackRow(track: Track, index: Int) -> some View {
        let isCurrent = engine.current.map { track.key.matches($0) } ?? false
        let display = TrackTitleFormatter.displayMetadata(for: track, clean: cleanListTitles)
        return HStack(spacing: 12) {
            if let coverURL = BiliArtworkURL.thumbnail(track.coverURL, width: 96, height: 54) {
                CachedAsyncImage(
                    url: coverURL,
                    targetSize: CGSize(width: 42, height: 24),
                    fallbackImage: isCurrent ? engine.currentCoverImage : nil
                ) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    artworkPlaceholder(cornerRadius: 4)
                }
                .frame(width: 42, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                artworkPlaceholder(cornerRadius: 4)
                    .frame(width: 42, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(display.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.white : PlayerSurface.primaryText)
                    .lineLimit(1)
                Text("\(display.artist) · \(MusicFormatters.playbackTime(Double(track.duration)))")
                    .font(.caption)
                    .foregroundStyle(PlayerSurface.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: isCurrent ? "waveform" : "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isCurrent ? AppTheme.accent : PlayerSurface.secondaryText)
                .frame(width: 24, height: 32)
        }
        .frame(height: Layout.bottomSheetRowHeight)
        .contentShape(Rectangle())
        .accessibilityLabel("\(index + 1). \(display.title)")
    }

    private var recommendationsMatchCurrentTrack: Bool {
        guard let current = engine.current else {
            return recommendedTracks.isEmpty && recommendationSeedKey == nil
        }
        guard let recommendationSeedKey else { return false }
        return recommendationSeedKey.matches(current)
    }

    private var isRecommendationContextVisible: Bool {
        queuePresentationState.isExpanded && bottomContextTab == .recommendations
    }

    private func ensureRecommendationsLoadedIfVisible() {
        let loadPolicy = RecommendationVisibleLoadPolicy.visibleContextChanged(
            recommendationContextVisible: isRecommendationContextVisible,
            recommendationsStale: recommendationsStale,
            recommendationsEmpty: recommendedTracks.isEmpty,
            recommendationsMismatched: !recommendationsMatchCurrentTrack)
        guard loadPolicy.shouldLoad else { return }
        recommendationsStale = false
        scheduleRecommendationLoad(clear: !recommendedTracks.isEmpty)
    }

    private func scheduleRecommendationLoad(clear: Bool) {
        recommendationTask?.cancel()
        recommendationLoadID = UUID()
        recommendationsError = nil
        if clear {
            recommendedTracks = []
            recommendationSeedKey = nil
        }
        guard let current = engine.current else {
            recommendationsLoading = false
            return
        }
        guard isRecommendationContextVisible else {
            recommendationsLoading = false
            return
        }
        if !clear, recommendationSeedKey?.matches(current) == true, !recommendedTracks.isEmpty {
            recommendationsLoading = false
            return
        }
        let isVisible = isRecommendationContextVisible
        if isVisible && recommendedTracks.isEmpty {
            recommendationsLoading = true
        }
        let loadID = UUID()
        recommendationLoadID = loadID
        recommendationTask = Task(priority: isVisible ? .userInitiated : .utility) {
            try? await Task.sleep(for: .milliseconds(clear && isVisible ? 260 : 0))
            guard !Task.isCancelled, recommendationLoadID == loadID else { return }
            await loadRecommendations(loadID: loadID)
        }
    }

    private func scheduleCurrentPlaylistLookup(force: Bool, delay: Duration) {
        guard let current = engine.current else {
            playlistLookupTask?.cancel()
            scheduledPlaylistBVID = nil
            currentPlaylist = nil
            currentPlaylistTracks = []
            currentPlaylistError = nil
            currentPlaylistLoading = false
            return
        }

        let bvid = current.bvid
        if !force, let cached = PlayerPlaylistLookupCache.shared.result(for: bvid) {
            playlistLookupTask?.cancel()
            scheduledPlaylistBVID = nil
            applyPlaylistLookup(cached, for: bvid)
            return
        }
        guard force || scheduledPlaylistBVID != bvid else { return }

        playlistLookupTask?.cancel()
        scheduledPlaylistBVID = bvid
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

    private func loadRecommendations(loadID: UUID) async {
        guard let current = engine.current else { return }
        let currentKey = current.key
        recommendationsLoading = isRecommendationContextVisible && recommendedTracks.isEmpty
        defer {
            if recommendationLoadID == loadID {
                recommendationsLoading = false
            }
        }
        let excluded = shownRecommendationKeys.union([currentKey])
        let tracks = await RecommendationEngine().recommendations(
            mode: .relatedPanel,
            context: .init(
                current: current,
                queue: engine.queue,
                playlistTracks: currentPlaylistTracks,
                excludedKeys: excluded),
            limit: 24)
        guard !Task.isCancelled,
              recommendationLoadID == loadID,
              engine.current.map({ currentKey.matches($0) }) ?? false else { return }
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
        if !force, let cached = PlayerPlaylistLookupCache.shared.result(for: bvid) {
            applyPlaylistLookup(cached, for: bvid)
            return
        }

        currentPlaylistLoading = true
        currentPlaylistError = nil
        defer {
            if scheduledPlaylistBVID == bvid {
                currentPlaylistLoading = false
                scheduledPlaylistBVID = nil
            }
        }
        do {
            let client = BiliClient()
            var resolvedOwnerMid = current.ownerMid
            var playlist = try await client.currentVideoPlaylist(bvid: bvid)
            if playlist == nil {
                if resolvedOwnerMid == nil {
                    resolvedOwnerMid = try? await client.videoInfo(bvid: bvid).owner.mid
                    guard !Task.isCancelled else { return }
                }
                if let ownerMid = resolvedOwnerMid {
                    playlist = try? await client.upPlaylistContaining(
                        bvid: bvid,
                        mid: ownerMid,
                        maxPlaylists: 4,
                        maxPages: 2)
                    guard !Task.isCancelled else { return }
                }
            }
            guard let playlist else {
                guard engine.current?.bvid == bvid else { return }
                let result = PlaylistLookupResult(playlist: nil, tracks: [], error: nil)
                storePlaylistLookup(result, for: bvid)
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
            storePlaylistLookup(result, for: bvid)
            applyPlaylistLookup(result, for: bvid)
            engine.preload(tracks: tracks, limit: 2, delay: .milliseconds(700))
        } catch {
            guard !Task.isCancelled, engine.current?.bvid == bvid else { return }
            let result = PlaylistLookupResult(
                playlist: nil,
                tracks: [],
                error: "合集检测失败: \(error.localizedDescription)")
            storePlaylistLookup(result, for: bvid)
            applyPlaylistLookup(result, for: bvid)
        }
    }

    private func storePlaylistLookup(_ result: PlaylistLookupResult, for bvid: String) {
        PlayerPlaylistLookupCache.shared.store(result, for: bvid)
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

    private func scrollCurrentPlaylist(_ proxy: ScrollViewProxy) {
        guard let current = engine.current,
              let currentTrack = currentPlaylistTracks.first(where: { $0.key.matches(current) })
        else { return }
        DispatchQueue.main.async {
            animate(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(currentTrack.id, anchor: .center)
            }
        }
    }

    private func normalizedCoverURL(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        return URL(string: raw.hasPrefix("//") ? "https:" + raw : raw)
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
        let frame = bottomContextFrameBox.rect
        guard !frame.isNull, !frame.isEmpty else { return false }
        if queuePresentationState == .fullQueue {
            return location.y >= frame.minY - 12
        }
        return frame
            .insetBy(dx: -10, dy: -8)
            .contains(location)
    }

    private func setProgressScrubbing(_ scrubbing: Bool) {
        isProgressScrubbing = scrubbing
    }

    private var centerBodyDismissDrag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($dismissDragOffset) { value, state, _ in
                guard !queuePresentationState.isExpanded else { return }
                guard !isBottomContextGestureStart(value.startLocation) else { return }
                guard let offset = PlayerGesturePolicy.dismissDragOffset(
                    translation: value.translation,
                    startY: value.startLocation.y,
                    dismissGrabZoneHeight: Layout.dismissGrabZoneHeight,
                    region: .centerBody,
                    isProgressScrubbing: isProgressScrubbing
                ) else {
                    // 方向意图消失时归零而不是保持旧值,避免偏移冻结在中途。
                    state = 0
                    return
                }
                state = offset
            }
            .onEnded { value in
                guard !queuePresentationState.isExpanded else { return }
                guard !isBottomContextGestureStart(value.startLocation) else { return }
                if PlayerGesturePolicy.shouldDismissFullPlayer(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation,
                    startY: value.startLocation.y,
                    dismissGrabZoneHeight: Layout.dismissGrabZoneHeight,
                    region: .centerBody,
                    isProgressScrubbing: isProgressScrubbing
                ) {
                    commitDismissOffset(for: value, region: .centerBody)
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
                ) else {
                    state = 0
                    return
                }
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
                    commitDismissOffset(for: value, region: .topChrome)
                    closePlayer()
                }
            }
    }

    /// 确认关闭时把手势最终偏移接进 `dismissCommitOffset`,
    /// 抵消 @GestureState 自动归零造成的向上回弹。
    private func commitDismissOffset(for value: DragGesture.Value, region: PlayerGesturePolicy.DismissRegion) {
        dismissCommitOffset = PlayerGesturePolicy.dismissDragOffset(
            translation: value.translation,
            startY: value.startLocation.y,
            dismissGrabZoneHeight: Layout.dismissGrabZoneHeight,
            region: region,
            isProgressScrubbing: isProgressScrubbing
        ) ?? 0
    }

    private var dismissDragAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .interactiveSpring(response: 0.26, dampingFraction: 0.9)
    }

    private var contextTransitionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .interactiveSpring(response: 0.42, dampingFraction: 0.90, blendDuration: 0.08)
    }

    private func animate(_ animation: Animation, _ updates: @escaping () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }
}

/// 承载抽屉全局 frame 的引用盒:写入不触发 SwiftUI 视图失效。
/// 仅在主线程读写(手势回调与 preference 回调均在主线程)。
private final class BottomContextFrameBox: @unchecked Sendable {
    var rect: CGRect = .null
}

private extension View {
    @ViewBuilder
    func playerContentReveal(opacity: Double) -> some View {
        self
            .opacity(opacity)
            .animation(.easeOut(duration: 0.12), value: opacity)
    }

    @ViewBuilder
    func nowPlayingSharedGeometry(
        id: String,
        in namespace: Namespace.ID,
        active: Bool,
        isSource: Bool
    ) -> some View {
        if active {
            matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .frame,
                anchor: .center,
                isSource: isSource)
        } else {
            self
        }
    }

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

// MARK: - Control views and sheet views are in separate files:
// PlayerControlViews.swift (PlayerIconButton, PlayerProgressBar, etc.)
// PlayerSheetViews.swift (LyricsSheetView, MVFullscreenView, FavoriteFolderPickerView, UPPlaylistsView, etc.)
