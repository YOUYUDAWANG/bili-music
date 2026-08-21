import AVFoundation
import LNPopupUI
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

enum PlayerSurface {
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.66)
    static let textTertiary = Color.white.opacity(0.46)
    static let controlStrong = Color.white.opacity(0.96)
    static let controlEmphasized = Color.white.opacity(0.82)
    static let controlIdle = Color.white.opacity(0.74)
    static let controlDisabled = Color.white.opacity(0.34)
    static let fill = Color.white.opacity(0.14)
    static let fillStrong = Color.white.opacity(0.74)
    static let stroke = Color.white.opacity(0.17)
    static let divider = Color.white.opacity(0.11)
    static let lyricInactive = Color.white.opacity(0.35)
    static let lyricUnsung = Color.white.opacity(0.34)
}

enum LyricStageDisplayMode: String {
    case localRules
    case v5Line
    case v51Events
    case v52Golden
    case v53Generic
    case prototype

    static var launchDefault: LyricStageDisplayMode {
        let environment = ProcessInfo.processInfo.environment
        if environment["BILIMUSIC_LYRIC_STAGE_PROTOTYPE"] == "1" { return .prototype }
        if environment["BILIMUSIC_LYRIC_STAGE_V53"] == "1" { return .v53Generic }
        if environment["BILIMUSIC_LYRIC_STAGE_V52"] == "1" { return .v52Golden }
        if environment["BILIMUSIC_LYRIC_STAGE_V51"] == "1" { return .v51Events }
        if environment["BILIMUSIC_LYRIC_STAGE_V5"] == "1" { return .v5Line }
        return .localRules
    }
}

/// 全屏正在播放页(从 mini bar 上拉打开)。
struct NowPlayingView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isPresented = true
    var safeAreaTop: CGFloat = 0
    @State private var contextStore = PlayerContextStore()
    @State private var playerPage: PlayerPage = .artwork
    @State private var showLyricsTranslation = true
    @State private var showCoverShadow = true
    @State private var showLyricsSearch = false
    @State private var showLyricsImport = false
    @State private var showLyricsOffset = false
    @State private var showTrackIdentityEditor = false
    @State private var showMVFullscreen = false
    @State private var showUPPlaylists = false
    @State private var showFavoriteFolders = false
    @State private var switchingMode = false
    @State private var playHapticTrigger = 0
    @State private var prevHapticTrigger = 0
    @State private var nextHapticTrigger = 0
    @State private var favoriteHapticTrigger = 0
    @State private var favoriteWasAdded = false
    @State private var downloadTrigger = 0
    @State private var favoriteErrorToast: String?
    @State private var favoriteErrorToastTask: Task<Void, Never>?
    @State private var landscapeMVFullscreenKey: TrackKey?
    @State private var showInlineMVChrome = false
    @State private var inlineMVChromeHideTask: Task<Void, Never>?
    @State private var lyricPerformanceScore: LyricPerformanceScore?
    @State private var stageScoreV2: LyricStageScoreV2?
    @State private var stageDirectionV3: LyricStageDirectionV3?
    @State private var stagePlanV3: LyricStagePlanV3?
    @State private var stageAudioSummaryV3: LyricStageAudioSummaryV3?
    @State private var stageAudioMapV3: AudioPerformanceMapV2?
    @State private var stageDirectionV4: LyricStageDirectionV4?
    @State private var stagePlanV4: LyricStagePlanV4?
    @State private var stageAudioScoreV4: AudioStructureScoreV4?
    @State private var lyricStageDisplayMode = LyricStageDisplayMode.launchDefault
    @State private var showLyricStageSummary = false
    @State private var showLyricStageV3Summary = false
    @State private var showLyricStageV4Summary = false
    @State private var lyricDirectorLoading = false
    @State private var lyricDirectorV2Loading = false
    @State private var lyricDirectorV2Task: Task<Void, Never>?
    @State private var lyricDirectorV3Loading = false
    @State private var lyricDirectorV3Task: Task<Void, Never>?
    @State private var lyricDirectorV3CacheTask: Task<Void, Never>?
    @State private var lyricDirectorV3GenerationID = UUID()
    @State private var lyricDirectorV4Loading = false
    @State private var lyricDirectorV4Task: Task<Void, Never>?
    @State private var lyricDirectorV4GenerationID = UUID()
    @State private var lyricDirectorToast: String?
    @State private var lyricDirectorTask: Task<Void, Never>?
    @State private var lyricDirectorToastTask: Task<Void, Never>?
    @State private var precisionHostAlignmentLoading = false
    @State private var precisionHostAlignmentStatus = ""
    @State private var precisionHostAlignmentTask: Task<Void, Never>?
    @AppStorage(TrackTitleFormatter.cleanListTitlesDefaultsKey) private var cleanListTitles = false
    private var favorites: FavoriteManager { .shared }

    private enum PlayerPage {
        case artwork
        case lyrics
        case queue
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

                if let favoriteErrorToast {
                    Text(favoriteErrorToast)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .accessibilityIdentifier("playerFavoriteErrorToast")
                        .transition(.opacity)
                }

                if let lyricDirectorToast {
                    Text(lyricDirectorToast)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 64)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .accessibilityIdentifier("lyricDirectorToast")
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(isPresented ? "nowPlayingView" : "nowPlayingViewPrewarmed")
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
        .sheet(isPresented: $showLyricsSearch) {
            LyricsSearchSheet()
        }
        .sheet(isPresented: $showLyricsImport) {
            ImportLyricsSheet()
        }
        .sheet(isPresented: $showLyricsOffset) {
            LyricsOffsetSheet()
        }
        .sheet(isPresented: $showTrackIdentityEditor) {
            TrackIdentityEditorSheet()
        }
        .fullScreenCover(isPresented: $showMVFullscreen) {
            MVFullscreenView()
        }
        .task(id: lyricPerformanceLoadID) {
            await loadCachedLyricPerformance()
            await loadCachedStageScoreV2()
            if lyricStageDisplayMode == .v53Generic,
               let track = engine.current,
               !engine.lyrics.isEmpty {
                let lines = engine.lyrics
                let emptySummary = makeEmptyAudioSummaryV3(track: track, lines: lines)
                stageAudioMapV3 = nil
                stageAudioSummaryV3 = emptySummary
                stageDirectionV3 = nil
                let localPlan = LyricStageDirectorV3.localPlan(
                    trackID: track.key.description,
                    lines: lines,
                    audioSummary: emptySummary)
                stagePlanV3 = localPlan
#if DEBUG
                if let performancePlan = UITestFixtures.makeStageV4PerformancePlan(
                    track: track,
                    lines: lines) {
                    stagePlanV3 = performancePlan.basePlan
                    stageAudioScoreV4 = performancePlan.audioScore
                    stagePlanV4 = performancePlan
                }
#endif
            }
        }
        .sheet(isPresented: $showLyricStageSummary) {
            if let summary = currentStageSummary {
                LyricStageSummarySheet(summary: summary)
            }
        }
        .sheet(isPresented: $showLyricStageV3Summary) {
            if let summary = stagePlanV3?.summary {
                LyricStageV3SummarySheet(summary: summary)
            }
        }
        .sheet(isPresented: $showLyricStageV4Summary) {
            if let stagePlanV4 {
                LyricStageV4SummarySheet(plan: stagePlanV4)
            }
        }
        .onAppear {
            if engine.state == .playing {
                contextStore.scheduleCurrentPlaylistLookup(engine: engine, force: false, delay: .milliseconds(350))
            }
        }
        .onChange(of: engine.playbackMode) { _, mode in
            inlineMVChromeHideTask?.cancel()
            showInlineMVChrome = false
            if mode != .mv {
                landscapeMVFullscreenKey = nil
            }
            if mode == .mv, playerPage == .lyrics {
                playerPage = .artwork
                showCoverShadow = true
            }
        }
        .onChange(of: engine.current?.key) { oldKey, newKey in
            if let oldKey, let newKey, oldKey.isCIDEnrichment(to: newKey) {
                return
            }
            lyricDirectorTask?.cancel()
            precisionHostAlignmentTask?.cancel()
            lyricPerformanceScore = nil
            stageScoreV2 = nil
            stageDirectionV3 = nil
            stagePlanV3 = nil
            stageAudioSummaryV3 = nil
            stageAudioMapV3 = nil
            stageDirectionV4 = nil
            stagePlanV4 = nil
            stageAudioScoreV4 = nil
            lyricDirectorLoading = false
            lyricDirectorV2Loading = false
            lyricDirectorV3Loading = false
            lyricDirectorV4Loading = false
            lyricDirectorV2Task?.cancel()
            lyricDirectorV3Task?.cancel()
            lyricDirectorV3CacheTask?.cancel()
            lyricDirectorV4Task?.cancel()
            lyricDirectorV3GenerationID = UUID()
            lyricDirectorV4Task?.cancel()
            lyricDirectorV4GenerationID = UUID()
            precisionHostAlignmentLoading = false
            precisionHostAlignmentStatus = ""
            contextStore.resetForCurrentTrackChange()
            let refreshPolicy = RecommendationPanelRefreshPolicy.currentTrackChanged(
                suppressImmediateRefresh: contextStore.suppressNextRecommendationRefresh,
                recommendationPanelVisible: playerPage == .queue)
            contextStore.suppressNextRecommendationRefresh = false
            contextStore.recommendationsStale = refreshPolicy.shouldMarkStale
            if refreshPolicy.shouldLoadImmediately {
                contextStore.scheduleRecommendationLoad(engine: engine, recommendationContextVisible: playerPage == .queue, clear: true)
                contextStore.recommendationsStale = false
            }
        }
        .onChange(of: engine.state) { _, state in
            guard state == .playing else { return }
            contextStore.scheduleCurrentPlaylistLookup(engine: engine, force: false, delay: .milliseconds(350))
            let loadPolicy = RecommendationVisibleLoadPolicy.playbackStarted(
                recommendationContextVisible: playerPage == .queue,
                recommendationsStale: contextStore.recommendationsStale,
                recommendationsEmpty: contextStore.recommendedTracks.isEmpty,
                recommendationsMismatched: !contextStore.recommendationsMatchCurrentTrack(engine: engine))
            guard loadPolicy.shouldLoad else { return }
            contextStore.recommendationsStale = false
            contextStore.scheduleRecommendationLoad(
                engine: engine,
                recommendationContextVisible: playerPage == .queue,
                clear: !contextStore.recommendedTracks.isEmpty)
        }
        .onChange(of: favorites.lastError) { _, error in
            presentFavoriteErrorToast(error)
        }
        .onDisappear {
            contextStore.cancelPendingWork()
            inlineMVChromeHideTask?.cancel()
            favoriteErrorToastTask?.cancel()
            lyricDirectorTask?.cancel()
            lyricDirectorV2Task?.cancel()
            lyricDirectorV3Task?.cancel()
            lyricDirectorV3CacheTask?.cancel()
            lyricDirectorToastTask?.cancel()
            precisionHostAlignmentTask?.cancel()
        }
    }

    private func presentFavoriteErrorToast(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        favoriteErrorToastTask?.cancel()
        withAnimation {
            favoriteErrorToast = message
        }
        favoriteErrorToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation {
                favoriteErrorToast = nil
            }
        }
    }

    private func playerCoverSize(for size: CGSize, safeAreaTop: CGFloat) -> CGFloat {
        let availableHeight = max(1, size.height - safeAreaTop)
        let isLandscape = size.width > size.height

        if isLandscape {
            return min(max(168, size.width * 0.24), max(168, availableHeight * 0.48), 250)
        }

        let horizontalInset: CGFloat = availableHeight < 760 ? 32 : 24
        return min(max(296, size.width - horizontalInset), max(320, availableHeight * 0.52), 390)
    }

    @ViewBuilder
    private var playerBackground: some View {
        let palette = engine.currentArtworkPalette
        ZStack {
            LinearGradient(
                colors: [
                    Color(uiColor: palette.top),
                    Color(uiColor: palette.bottom)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Color.black.opacity(0.10)
        }
        .animation(.easeInOut(duration: 0.32), value: palette)
    }

    @ViewBuilder
    private func nowPlayingPage(coverSize: CGFloat, pageWidth: CGFloat, isLandscape: Bool, isLyrics: Bool) -> some View {
        if isLandscape {
            landscapeNowPlayingPage(coverSize: coverSize, pageWidth: pageWidth)
        } else {
            portraitNowPlayingPage(coverSize: coverSize, pageWidth: pageWidth, isLyrics: isLyrics)
        }
    }

    private func landscapeNowPlayingPage(coverSize: CGFloat, pageWidth: CGFloat) -> some View {
            HStack(spacing: 22) {
                mediaView(coverSize: coverSize)

            VStack(spacing: 8) {
                playerMetadata(compact: true, centered: false)

                playerControlStack(compact: true)
            }
            .playerContentReveal(opacity: playerContentOpacity)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func portraitNowPlayingPage(coverSize: CGFloat, pageWidth: CGFloat, isLyrics: Bool) -> some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 760
            let availableCoverWidth = max(1, proxy.size.width - (isCompact ? 32 : 24))
            let activeCoverSize = max(1, min(coverSize, availableCoverWidth))
            let artWidth = isLyrics ? 96 : activeCoverSize
            let artHeight = artWidth * 9 / 16
            let artworkMetadataSpacing: CGFloat = isCompact ? 12 : 16
            let mainFlexibleMinimum: CGFloat = isCompact ? 8 : 12
            let progressTransportSpacing: CGFloat = isCompact ? 12 : 18
            let bottomGap: CGFloat = isCompact ? 12 : 18

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: isLyrics ? 12 : 0) {
                    portraitCover(
                        width: artWidth,
                        height: artHeight,
                        isLyrics: isLyrics,
                        loadSize: activeCoverSize
                    )

                    if isLyrics {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(displayTitle)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(PlayerSurface.textPrimary)
                                .lineLimit(1)
                            Text(displayArtist)
                                .font(.system(size: 15))
                                .foregroundStyle(PlayerSurface.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        PlayerLyricsOverflowMenu(
                            showTranslation: $showLyricsTranslation,
                            showSearch: $showLyricsSearch,
                            showImport: $showLyricsImport,
                            showIdentityEditor: $showTrackIdentityEditor,
                            showOffset: $showLyricsOffset
                        )
                    }
                }
                .padding(.horizontal, isLyrics ? 30 : 0)
                .frame(maxWidth: .infinity, alignment: isLyrics ? .leading : .center)
                .frame(height: isLyrics ? 56 : artHeight, alignment: .center)

                if isLyrics {
                    PlayerLyricsPage(
                        showTranslation: $showLyricsTranslation,
                        showSearch: $showLyricsSearch,
                        showImport: $showLyricsImport,
                        showIdentityEditor: $showTrackIdentityEditor
                    )
                } else {
                    Color.clear
                        .frame(height: artworkMetadataSpacing)

                    appleMusicMetadataRow(compact: isCompact)
                        .frame(width: activeCoverSize)

                    ZStack {
                        Color.clear

                        Group {
                            switch lyricStageDisplayMode {
                            case .prototype:
                                LyricStagePrototypeView(isActive: isPresented)
                                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            case .v5Line where !engine.lyrics.isEmpty:
                                LyricStageView(
                                    isMotionEnabled: isPresented,
                                    performanceScore: lyricPerformanceScore
                                ) {
                                    setPlayerPage(.lyrics)
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            case .v51Events where !engine.lyrics.isEmpty:
                                LyricStageCanvasView(
                                    isMotionEnabled: isPresented,
                                    score: stageScoreV2,
                                    performanceScore: lyricPerformanceScore
                                ) {
                                    setPlayerPage(.lyrics)
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            case .v52Golden where !engine.lyrics.isEmpty:
                                YouAizuGoldenSampleView(isActive: isPresented)
                                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            case .v53Generic where !engine.lyrics.isEmpty:
                                if let stagePlanV3 {
                                    LyricStageV53View(
                                        isActive: isPresented,
                                        plan: stagePlanV3,
                                        audioMap: stageAudioMapV3,
                                        v4Plan: stagePlanV4
                                    ) {
                                        setPlayerPage(.lyrics)
                                    }
                                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                                } else {
                                    NowPlayingLyricStageView(isActive: isPresented) {
                                        setPlayerPage(.lyrics)
                                    }
                                }
                            default:
                                NowPlayingLyricStageView(isActive: isPresented) {
                                    setPlayerPage(.lyrics)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(maxHeight: .infinity)
                    .frame(minHeight: mainFlexibleMinimum)

                    VStack(spacing: 0) {
                        progressView

                        Color.clear
                            .frame(height: progressTransportSpacing)

                        transportControls
                    }

                    Color.clear
                        .frame(height: bottomGap)
                }
            }
            .playerContentReveal(opacity: playerContentOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func playerMetadata(compact: Bool, centered: Bool = true) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: compact ? 4 : 7) {
            Text(displayTitle)
                .font(.system(size: compact ? 19 : 21, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(centered ? .center : .leading)
                .lineLimit(compact ? 1 : 2)
                .lineSpacing(2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .accessibilityIdentifier("nowPlayingTitle")

            Text(displayArtist)
                .font(.system(size: compact ? 15 : 17, weight: .regular))
                .foregroundStyle(PlayerSurface.textSecondary)
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

    private func appleMusicMetadataRow(compact: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: compact ? 2 : 3) {
                Text(displayTitle)
                    .font(.system(size: compact ? 20 : 23, weight: .bold))
                    .foregroundStyle(PlayerSurface.controlStrong)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .accessibilityIdentifier("nowPlayingTitle")

                Text(displayArtist)
                    .font(.system(size: compact ? 14 : 15, weight: .medium))
                    .tracking(0.35)
                    .foregroundStyle(PlayerSurface.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            favoriteButton
            moreMenu
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nowPlayingMetadata")
    }

    private var appleMusicUtilityBar: some View {
        HStack {
            Button {
                guard engine.current != nil, engine.playbackMode != .mv else { return }
                setPlayerPage(playerPage == .lyrics ? .artwork : .lyrics)
            } label: {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 52, height: 48)
                    .foregroundStyle(playerPage == .lyrics ? Color.black.opacity(0.78) : PlayerSurface.controlIdle)
                    .background(playerPage == .lyrics ? PlayerSurface.fillStrong : Color.clear, in: Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(engine.current == nil || engine.playbackMode == .mv)
            .opacity((engine.current == nil || engine.playbackMode == .mv) ? 0.34 : 1)
            .accessibilityLabel("歌词")
            .accessibilityAddTraits(playerPage == .lyrics ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("playerLyricsButton")

            Spacer()

            SystemRoutePicker()
                .frame(width: 52, height: 48)
                .accessibilityLabel("AirPlay")

            Spacer()

            Button {
                setPlayerPage(playerPage == .queue ? .artwork : .queue)
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 52, height: 48)
                    .foregroundStyle(playerPage == .queue ? Color.black.opacity(0.78) : PlayerSurface.controlIdle)
                    .background(playerPage == .queue ? PlayerSurface.fillStrong : Color.clear, in: Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("接下来播放")
            .accessibilityAddTraits(playerPage == .queue ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("playerQueueButton")
        }
        .foregroundStyle(PlayerSurface.controlIdle)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playerUtilityBar")
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
        VStack(spacing: 0) {
            Group {
                switch playerPage {
                case .queue where !isLandscape:
                    PlayerQueuePage(
                        pageWidth: width,
                        contextStore: contextStore,
                        displayTitle: displayTitle,
                        displayArtist: displayArtist,
                        headerTrailing: {
                            HStack(spacing: 0) {
                                favoriteButton
                                moreMenu
                            }
                        },
                        progressView: { progressView },
                        transportControls: { transportControls }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                default:
                    nowPlayingPage(
                        coverSize: coverSize,
                        pageWidth: width,
                        isLandscape: isLandscape,
                        isLyrics: playerPage == .lyrics && !isLandscape
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !isLandscape {
                appleMusicUtilityBar
                    .padding(.top, 8)
                    .padding(.horizontal, 56)
                    .padding(.bottom, 16)
            }
        }
            .padding(.top, playerContentTopInset(safeAreaTop: safeAreaTop, isLandscape: isLandscape))
            .contentShape(Rectangle())
            .animation(contextTransitionAnimation, value: playerPage)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            Color.clear
                .frame(height: max(54, safeAreaTop + 28))
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("下滑收起播放器")
                .accessibilityIdentifier("playerTopChrome")
        }
    }

    private func playerContentTopInset(safeAreaTop: CGFloat, isLandscape: Bool) -> CGFloat {
        guard !isLandscape else { return 0 }
        return max(12, safeAreaTop - 12)
    }

    private func setPlayerPage(_ page: PlayerPage) {
        guard page != playerPage else { return }
        if page == .lyrics {
            showCoverShadow = false
            animate(contextTransitionAnimation) {
                playerPage = page
            }
        } else if playerPage == .lyrics, page == .artwork {
            animate(contextTransitionAnimation) {
                playerPage = page
            } completion: {
                showCoverShadow = playerPage == .artwork
            }
        } else {
            showCoverShadow = page == .artwork
            animate(contextTransitionAnimation) {
                playerPage = page
            }
        }
    }

    private func portraitCover(width: CGFloat, height: CGFloat, isLyrics: Bool, loadSize: CGFloat) -> some View {
        let cornerRadius: CGFloat = isLyrics ? 6 : AppTheme.playerCoverRadius
        return ZStack {
            RoundedRectangle(cornerRadius: AppTheme.playerCoverRadius, style: .continuous)
                .fill(Color.clear)
                .shadow(color: .black.opacity(0.28), radius: 16, y: 10)
                .opacity(showCoverShadow ? 1 : 0)
                .transaction { $0.animation = nil }
                .allowsHitTesting(false)

            portraitCoverContents(loadSize: loadSize)
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                .opacity(isLyrics ? 0 : 1)
                .transaction { $0.animation = nil }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isLyrics else { return }
            setPlayerPage(.artwork)
        }
        .popupTransitionTarget()
        .accessibilityAddTraits(isLyrics ? .isButton : [])
        .accessibilityLabel(isLyrics ? "返回封面" : "播放封面")
        .accessibilityIdentifier(isLyrics ? "lyricsArtworkButton" : "nowPlayingArtwork")
    }

    @ViewBuilder
    private func portraitCoverContents(loadSize: CGFloat) -> some View {
        let currentTrack = engine.current
        let coverURL = BiliArtworkURL.thumbnail(currentTrack?.coverURL, width: 960, height: 540)
        if engine.playbackMode == .mv, let player = engine.avPlayer {
            InlineMVPlayerView(player: player)
                .background(Color.black)
                .accessibilityLabel("MV 画面")
        } else if let image = engine.currentCoverImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let coverURL {
            CachedAsyncImage(
                url: coverURL,
                targetSize: CGSize(width: loadSize, height: loadSize * 9 / 16),
                fallbackImage: engine.currentCoverImage,
                onImageLoaded: { image in
                    engine.rememberCurrentCover(image, for: currentTrack)
                }
            ) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                artworkPlaceholder(cornerRadius: AppTheme.playerCoverRadius)
            }
        } else {
            artworkPlaceholder(cornerRadius: AppTheme.playerCoverRadius)
        }
    }

    @ViewBuilder
    private func mediaView(coverSize: CGFloat) -> some View {
        let currentTrack = engine.current
        let coverURL = BiliArtworkURL.thumbnail(currentTrack?.coverURL, width: 960, height: 540)
        ZStack(alignment: .topTrailing) {
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
            .popupTransitionTarget()
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.playerCoverRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.playerCoverRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 16, y: 10)
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

    private var playerContentOpacity: Double {
        1
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
                .foregroundStyle(PlayerSurface.controlDisabled)
        }
    }

    private var progressView: some View {
        // 独立子视图:只有它订阅 engine.currentTime(每 0.5s 变),
        // 避免整个播放器 body(封面、操作栏、TabView)跟着每半秒重渲染。
        PlayerProgressBar()
    }

    private var transportControls: some View {
        HStack(spacing: 0) {
            PlayerIconButton(systemName: "backward.fill", size: 30, accessibilityLabel: "上一曲") {
                prevHapticTrigger += 1
                Task { await engine.playPrevious() }
            }
            .frame(maxWidth: .infinity)
            .sensoryFeedback(.intent(.transportImpact), trigger: prevHapticTrigger)
            Button {
                playHapticTrigger += 1
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 72, height: 72)
                    .foregroundStyle(PlayerSurface.controlStrong)
                    .contentShape(Circle())
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .overlay { if engine.state == .loading { ProgressView().tint(PlayerSurface.controlEmphasized) } }
            .accessibilityIdentifier("playerTransportControls")
            .sensoryFeedback(.intent(.transportImpact), trigger: playHapticTrigger)
            PlayerIconButton(systemName: "forward.fill", size: 30, accessibilityLabel: "下一曲") {
                nextHapticTrigger += 1
                Task { await engine.playNext() }
            }
            .frame(maxWidth: .infinity)
            .disabled(!engine.hasNext)
            .sensoryFeedback(.intent(.transportImpact), trigger: nextHapticTrigger)
        }
        .frame(maxWidth: 330)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .foregroundStyle(PlayerSurface.textPrimary)
    }

    private var playerToolbarButtons: some View {
        HStack(spacing: 24) {
            favoriteButton
            downloadButton
            mvSwitchButton
            moreMenu
        }
        .frame(maxWidth: 270)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
    }

    private var favoriteButton: some View {
        let track = engine.current
        let isFavorite = track.map { favorites.isFavorite($0) } ?? false
        let isBusy = track.map { favorites.busyBVIDs.contains($0.bvid) } ?? false

        return PlayerToolbarActionButton(
            title: isFavorite ? "已收藏" : "收藏",
            systemName: isFavorite ? "star.fill" : "star",
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
        .accessibilityHint("收藏到音乐收藏夹")
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
                        .tint(PlayerSurface.controlEmphasized)
                } else {
                    Image(systemName: isMV ? "play.rectangle.fill" : "headphones")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(canSwitch ? (isMV ? AppTheme.accent : PlayerSurface.controlIdle) : PlayerSurface.controlDisabled)
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
        let track = engine.current
        let downloads = DownloadManager.shared
        let isCached = track.map { CacheStore.shared.entry(for: $0) != nil } ?? false
        let isMV = engine.playbackMode == .mv
        let canSwitchMode = isMV || engine.videoAvailable

        return Menu {
            Section("操作") {
                Button {
                    guard let track, !isCached else { return }
                    downloadTrigger += 1
                    Task { await downloads.download(track: track) }
                } label: {
                    Label(isCached ? "已缓存" : "缓存", systemImage: isCached ? "checkmark.circle.fill" : "arrow.down.circle")
                }
                .disabled(track == nil || isCached)

                Button {
                    guard canSwitchMode, !switchingMode else { return }
                    setPlaybackMode(isMV ? .music : .mv)
                } label: {
                    Label(
                        isMV ? "切回音乐" : "切换 MV",
                        systemImage: isMV ? "headphones" : "play.rectangle")
                }
                .disabled(!canSwitchMode || switchingMode)
            }

            Section("歌词") {
                Button {
                    setPlayerPage(.lyrics)
                } label: {
                    Label(hasLyrics ? "打开歌词" : "查找歌词", systemImage: hasLyrics ? "quote.bubble.fill" : "quote.bubble")
                }
                .disabled(track == nil || engine.playbackMode == .mv)

                if engine.lyricsDocument?.hasLineSync == true {
                    Button {
                        generateWordTimingsOnPrecisionHost()
                    } label: {
                        Label(
                            precisionHostAlignmentLoading
                                ? (precisionHostAlignmentStatus.isEmpty
                                    ? "正在连接高精度主机"
                                    : precisionHostAlignmentStatus)
                                : (engine.lyricsDocument?.timingKind == .word
                                    ? "用高精度主机重新生成"
                                    : "高精度主机生成逐字歌词"),
                            systemImage: precisionHostAlignmentLoading
                                ? "hourglass"
                                : "desktopcomputer.and.macbook")
                    }
                    .disabled(
                        track == nil
                            || !engine.canGeneratePrecisionHostWordTimings
                            || precisionHostAlignmentLoading
                            || engine.playbackMode == .mv)
                    .accessibilityIdentifier("precisionHostWordAlignmentButton")
                }

#if DEBUG
                Menu("歌词舞台") {
                    Button {
                        selectLyricStageDisplayMode(.localRules)
                    } label: {
                        Label("本地规则", systemImage: lyricStageDisplayMode == .localRules ? "checkmark" : "text.alignleft")
                    }
                    .accessibilityIdentifier("lyricStageLocalRulesButton")

                    Button {
                        selectLyricStageDisplayMode(.v5Line)
                    } label: {
                        Label(
                            "当前 V5 行级舞台",
                            systemImage: lyricStageDisplayMode == .v5Line ? "checkmark" : "textformat.characters")
                    }
                    .disabled(track == nil || !hasLyrics || engine.playbackMode == .mv)
                    .accessibilityIdentifier("lyricStageV5Button")

                    Button {
                        selectLyricStageDisplayMode(.v51Events)
                    } label: {
                        Label(
                            "V5.1 Event 舞台",
                            systemImage: lyricStageDisplayMode == .v51Events ? "checkmark" : "sparkles.rectangle.stack")
                    }
                    .disabled(track == nil || !hasLyrics || engine.playbackMode == .mv)
                    .accessibilityIdentifier("lyricStageV51Button")

                    Button {
                        startYouAizuGoldenSample()
                    } label: {
                        Label(
                            "You＆合図 V5.2 全曲音频舞台",
                            systemImage: lyricStageDisplayMode == .v52Golden ? "checkmark" : "sparkles.tv")
                    }
                    .disabled(
                        engine.current?.bvid != YouAizuGoldenTimeline.targetBVID
                            || engine.lyrics.count < 14
                            || engine.playbackMode == .mv)
                    .accessibilityIdentifier("lyricStageV52GoldenButton")

                    Button {
                        startGenericV53Stage()
                    } label: {
                        Label(
                            "V5.3 通用全曲编舞",
                            systemImage: lyricStageDisplayMode == .v53Generic ? "checkmark" : "point.3.connected.trianglepath.dotted")
                    }
                    .disabled(track == nil || !hasLyrics || engine.playbackMode == .mv)
                    .accessibilityIdentifier("lyricStageV53Button")

                    Button {
                        selectLyricStageDisplayMode(.prototype)
                    } label: {
                        Label(
                            "动态文字样片",
                            systemImage: lyricStageDisplayMode == .prototype ? "checkmark" : "character.textbox")
                    }
                    .disabled(engine.playbackMode == .mv)
                    .accessibilityIdentifier("lyricStagePrototypeButton")
                }

                Menu("Luna") {
                    Button {
                        directLyricsWithGeminiV4()
                    } label: {
                        Label(
                            lyricDirectorV4Loading
                                ? "Gemini 正在结合音频结构编排 V4"
                                : (stageDirectionV4 == nil ? "生成 V4 音频结构演出（Gemini）" : "重新生成 V4 音频结构演出"),
                            systemImage: lyricDirectorV4Loading ? "hourglass" : "waveform.badge.sparkles")
                    }
                    .disabled(track == nil || !hasLyrics || lyricDirectorV4Loading || engine.playbackMode == .mv)
                    .accessibilityIdentifier("lyricDirectorV4GenerateButton")

                    Button {
                        showLyricStageV4Summary = stagePlanV4 != nil
                    } label: {
                        Label("查看 V4 音频演出摘要", systemImage: "waveform.path.ecg.rectangle")
                    }
                    .disabled(stagePlanV4 == nil)
                    .accessibilityIdentifier("lyricStageV4SummaryButton")

                    if stageDirectionV4 != nil {
                        Button(role: .destructive) {
                            clearGeminiStageV4()
                        } label: {
                            Label("清除 Gemini V4 演出", systemImage: "arrow.uturn.backward")
                        }
                        .accessibilityIdentifier("lyricDirectorV4ClearButton")
                    }

                    Divider()

                    Button {
                        directLyricsWithLunaV3()
                    } label: {
                        Label(
                            lyricDirectorV3Loading
                                ? "Luna 正在编排 V5.3"
                                : (stageDirectionV3 == nil ? "生成 V5.3 演出（线上 /v3）" : "重新生成 V5.3（线上 /v3）"),
                            systemImage: lyricDirectorV3Loading ? "hourglass" : "wand.and.stars.inverse")
                    }
                    .disabled(track == nil || !hasLyrics || lyricDirectorV3Loading || engine.playbackMode == .mv)
                    .accessibilityIdentifier("lyricDirectorV3GenerateButton")

                    Button {
                        showLyricStageV3Summary = stagePlanV3 != nil
                    } label: {
                        Label("查看 V5.3 演出摘要", systemImage: "list.bullet.rectangle.portrait")
                    }
                    .disabled(stagePlanV3 == nil)
                    .accessibilityIdentifier("lyricStageV3SummaryButton")

                    if stageDirectionV3 != nil {
                        Button(role: .destructive) {
                            clearLunaStageV3()
                        } label: {
                            Label("清除 Luna V5.3 演出", systemImage: "arrow.uturn.backward")
                        }
                        .accessibilityIdentifier("lyricDirectorV3ClearButton")
                    }

                    Divider()

                    Button {
                        directLyricsWithLunaV2()
                    } label: {
                        Label(
                            lyricDirectorV2Loading
                                ? "Luna 正在编排 V5.1"
                                : (stageScoreV2 == nil ? "生成 V5.1 演出（线上 /v2）" : "重新生成（线上 /v2）"),
                            systemImage: lyricDirectorV2Loading ? "hourglass" : "wand.and.stars")
                    }
                    .disabled(track == nil || !hasLyrics || lyricDirectorV2Loading || engine.playbackMode == .mv)
                    .accessibilityIdentifier("lyricDirectorV2GenerateButton")

                    Button {
                        showLyricStageSummary = currentStageSummary != nil
                    } label: {
                        Label("查看演出摘要", systemImage: "list.bullet.rectangle")
                    }
                    .disabled(currentStageSummary == nil)
                    .accessibilityIdentifier("lyricStageSummaryButton")

                    if stageScoreV2 != nil {
                        Button(role: .destructive) {
                            clearLunaStageV2()
                        } label: {
                            Label("清除 Luna 演出", systemImage: "arrow.uturn.backward")
                        }
                        .accessibilityIdentifier("lyricDirectorV2ClearButton")
                    }

                    Button {
                        directLyricsWithLuna()
                    } label: {
                        Label(
                            lyricDirectorLoading
                                ? "Luna 正在编排 V5"
                                : (lyricPerformanceScore == nil ? "用 Luna 编排 V5 演出" : "重新生成 V5 演出"),
                            systemImage: lyricDirectorLoading ? "hourglass" : "wand.and.stars")
                    }
                    .disabled(track == nil || !hasLyrics || lyricDirectorLoading || engine.playbackMode == .mv)
                    .accessibilityIdentifier("lyricDirectorGenerateButton")

                    if lyricPerformanceScore != nil {
                        Button(role: .destructive) {
                            clearLunaLyricPerformance()
                        } label: {
                            Label("恢复本地 V5 导演", systemImage: "arrow.uturn.backward.circle")
                        }
                        .accessibilityIdentifier("lyricDirectorClearButton")
                    }
                }
#endif
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
        .accessibilityIdentifier("playerMoreMenu")
    }

    private var lyricPerformanceLoadID: String {
        guard let track = engine.current, !engine.lyrics.isEmpty else { return "none" }
        return "\(track.key.description)|\(LyricPerformanceFingerprint.lyricsHash(engine.lyrics))"
    }

    private func loadCachedLyricPerformance() async {
        guard let track = engine.current, !engine.lyrics.isEmpty else {
            lyricPerformanceScore = nil
            return
        }
        let expectedKey = track.key
        let expectedHash = LyricPerformanceFingerprint.lyricsHash(engine.lyrics)
        let score = await LyricPerformanceStore.shared.score(for: track, lines: engine.lyrics)
        guard engine.current?.key == expectedKey,
              LyricPerformanceFingerprint.lyricsHash(engine.lyrics) == expectedHash else { return }
        lyricPerformanceScore = score
    }

    private func loadCachedStageScoreV2() async {
        guard let track = engine.current, !engine.lyrics.isEmpty else {
            stageScoreV2 = nil
            return
        }
        let expectedKey = track.key
        let expectedHash = LyricPerformanceFingerprint.lyricsHash(engine.lyrics)
        let score = await LyricStageStoreV2.shared.score(for: track, lines: engine.lyrics)
        guard engine.current?.key == expectedKey,
              LyricPerformanceFingerprint.lyricsHash(engine.lyrics) == expectedHash else { return }
        stageScoreV2 = score
    }

    private func loadCachedStageDirectionV3() async {
        guard let track = engine.current, !engine.lyrics.isEmpty else {
            stageDirectionV3 = nil
            stagePlanV3 = nil
            return
        }
        let lines = engine.lyrics
        let expectedKey = track.key
        let expectedHash = LyricPerformanceFingerprint.lyricsHash(lines)
        let emptySummary = makeEmptyAudioSummaryV3(track: track, lines: lines)
        let audioMap = try? await AudioPerformanceAnalysisService.shared.cachedMap(for: track)
        guard !Task.isCancelled,
              engine.current?.key == expectedKey,
              LyricPerformanceFingerprint.lyricsHash(engine.lyrics) == expectedHash else { return }
        let audioSummary = audioMap?.summary(for: lines) ?? emptySummary
        let direction = await LyricStageStoreV3.shared.direction(
            for: track,
            lines: lines,
            audioSummary: audioSummary)
        guard !Task.isCancelled,
              engine.current?.key == expectedKey,
              LyricPerformanceFingerprint.lyricsHash(engine.lyrics) == expectedHash else { return }
        stageAudioMapV3 = audioMap
        stageAudioSummaryV3 = audioSummary
        stageDirectionV3 = direction
        let resolvedV3 = LyricStageDirectorV3.resolve(
            trackID: track.key.description,
            lines: lines,
            audioSummary: audioSummary,
            direction: direction)
        stagePlanV3 = resolvedV3

        guard let audioMap else {
            stageDirectionV4 = nil
            stagePlanV4 = nil
            stageAudioScoreV4 = nil
            return
        }
        let fullAudioScore = AudioStructureScoreBuilderV4.make(
            map: audioMap,
            lines: lines,
            availability: .ready)
        guard let prepared = try? await LyricStageClientV4.shared.prepareRequest(
            track: track,
            lines: lines,
            audioScore: fullAudioScore) else {
            stageDirectionV4 = nil
            stagePlanV4 = nil
            stageAudioScoreV4 = fullAudioScore
            return
        }
        let audioScore = prepared.audioScore
        let directionV4 = await LyricStageStoreV4.shared.direction(
            for: track,
            lines: lines,
            audioScore: audioScore)
        guard !Task.isCancelled,
              engine.current?.key == expectedKey,
              LyricPerformanceFingerprint.lyricsHash(engine.lyrics) == expectedHash else { return }
        stageAudioScoreV4 = audioScore
        stageDirectionV4 = directionV4
        if let directionV4 {
            let resolvedV4 = LyricStageDirectorV4.resolve(
                trackID: track.key.description,
                lines: lines,
                audioMap: audioMap,
                audioScore: audioScore,
                direction: directionV4)
            stagePlanV3 = resolvedV4.basePlan
            stageDirectionV3 = nil
            stagePlanV4 = resolvedV4
        } else {
            stagePlanV4 = nil
        }
    }

    private func makeEmptyAudioSummaryV3(
        track: Track,
        lines: [PlayerEngine.LyricLine]
    ) -> LyricStageAudioSummaryV3 {
        let duration = max(Double(track.duration), lines.last?.to ?? 0)
        return .empty(duration: duration)
    }

    private var currentStageSummary: LyricStagePerformanceSummary? {
        guard !engine.lyrics.isEmpty else { return nil }
        return LyricStageCompilerV2.compile(
            trackID: engine.current?.key.description ?? "unknown-track",
            lines: engine.lyrics,
            score: stageScoreV2,
            performanceScore: lyricPerformanceScore,
            palette: engine.currentArtworkPalette
        )?.summary
    }

    private func selectLyricStageDisplayMode(_ mode: LyricStageDisplayMode) {
        withAnimation(.easeInOut(duration: 0.28)) {
            lyricStageDisplayMode = mode
        }
    }

    private func startYouAizuGoldenSample() {
        guard engine.current?.bvid == YouAizuGoldenTimeline.targetBVID,
              engine.lyrics.count >= 14 else {
            presentLyricDirectorToast("请先播放已有逐字歌词的 You & 合図")
            return
        }
        withAnimation(.easeInOut(duration: 0.28)) {
            lyricStageDisplayMode = .v52Golden
        }
        engine.seek(to: YouAizuGoldenTimeline.startTime)
        engine.play()
        presentLyricDirectorToast("V5.2 全曲音频舞台 · 176.5 秒")
    }

    private func startGenericV53Stage() {
        guard let track = engine.current, !engine.lyrics.isEmpty else {
            presentLyricDirectorToast("请先播放已有同步歌词的歌曲")
            return
        }
        let lines = engine.lyrics
        lyricDirectorV3Task?.cancel()
        lyricDirectorV3CacheTask?.cancel()
        lyricDirectorV3GenerationID = UUID()
        lyricDirectorV3Loading = false
        lyricDirectorV4Task?.cancel()
        lyricDirectorV4GenerationID = UUID()
        lyricDirectorV4Loading = false
        stageDirectionV4 = nil
        stagePlanV4 = nil
        stageAudioScoreV4 = nil
        let emptySummary = makeEmptyAudioSummaryV3(track: track, lines: lines)
        stageAudioSummaryV3 = emptySummary
        stageAudioMapV3 = nil
        stageDirectionV3 = nil
        stagePlanV3 = LyricStageDirectorV3.localPlan(
            trackID: track.key.description,
            lines: lines,
            audioSummary: emptySummary)
        withAnimation(.easeInOut(duration: 0.28)) {
            lyricStageDisplayMode = .v53Generic
        }
        engine.seek(to: 0)
        engine.play()
        presentLyricDirectorToast("V5.3 通用全曲编舞 · 从头播放")
        lyricDirectorV3CacheTask = Task { @MainActor in
            await loadCachedStageDirectionV3()
        }
    }

    private func directLyricsWithLunaV3() {
        guard let track = engine.current, !engine.lyrics.isEmpty, !lyricDirectorV3Loading else { return }
        lyricDirectorV4Task?.cancel()
        lyricDirectorV4GenerationID = UUID()
        lyricDirectorV4Loading = false
        stageDirectionV4 = nil
        stagePlanV4 = nil
        stageAudioScoreV4 = nil
        lyricDirectorV3CacheTask?.cancel()
        lyricDirectorV3Task?.cancel()
        lyricDirectorV3GenerationID = UUID()
        let generationID = lyricDirectorV3GenerationID
        lyricDirectorV3Loading = true
        presentLyricDirectorToast("Luna 正在编排 V5.3…")
        let lines = engine.lyrics
        let emptySummary = makeEmptyAudioSummaryV3(track: track, lines: lines)
        let expectedKey = track.key
        let expectedHash = LyricPerformanceFingerprint.lyricsHash(lines)
        lyricDirectorV3Task = Task { @MainActor in
            defer {
                if lyricDirectorV3GenerationID == generationID {
                    lyricDirectorV3Loading = false
                }
            }
            do {
                presentLyricDirectorToast("正在分析本地音频结构…")
                let audioMap = try? await AudioPerformanceAnalysisService.shared.analyzeCachedAudio(for: track)
                let audioSummary = audioMap?.summary(for: lines) ?? emptySummary
                guard !Task.isCancelled,
                      lyricDirectorV3GenerationID == generationID,
                      engine.current?.key == expectedKey,
                      LyricPerformanceFingerprint.lyricsHash(engine.lyrics) == expectedHash else { return }
                stageAudioMapV3 = audioMap
                stageAudioSummaryV3 = audioSummary
                stageDirectionV3 = nil
                stagePlanV3 = LyricStageDirectorV3.localPlan(
                    trackID: track.key.description,
                    lines: lines,
                    audioSummary: audioSummary)
                selectLyricStageDisplayMode(.v53Generic)
                presentLyricDirectorToast("Luna 正在编排 V5.3…")
                let direction = try await LyricStageClientV3.shared.direct(
                    track: track,
                    lines: lines,
                    audioSummary: audioSummary)
                guard !Task.isCancelled,
                      lyricDirectorV3GenerationID == generationID,
                      engine.current?.key == expectedKey,
                      LyricPerformanceFingerprint.lyricsHash(engine.lyrics) == expectedHash else { return }
                let saved = await LyricStageStoreV3.shared.save(
                    direction,
                    for: track,
                    lines: lines,
                    audioSummary: audioSummary)
                guard !Task.isCancelled,
                      lyricDirectorV3GenerationID == generationID,
                      engine.current?.key == expectedKey,
                      LyricPerformanceFingerprint.lyricsHash(engine.lyrics) == expectedHash else { return }
                guard saved else {
                    presentLyricDirectorToast("Luna V5.3 演出未通过本地校验")
                    return
                }
                stageDirectionV3 = direction
                stagePlanV3 = LyricStageDirectorV3.resolve(
                    trackID: track.key.description,
                    lines: lines,
                    audioSummary: audioSummary,
                    direction: direction)
                selectLyricStageDisplayMode(.v53Generic)
                presentLyricDirectorToast("V5.3 演出已应用 · \(direction.stageBible.concept)")
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard lyricDirectorV3GenerationID == generationID,
                      engine.current?.key == expectedKey,
                      LyricPerformanceFingerprint.lyricsHash(engine.lyrics) == expectedHash else { return }
                presentLyricDirectorToast(error.localizedDescription)
            }
        }
    }

    private func clearLunaStageV3() {
        guard let track = engine.current else { return }
        let lines = engine.lyrics
        let audioSummary = stageAudioSummaryV3 ?? makeEmptyAudioSummaryV3(track: track, lines: lines)
        lyricDirectorV3CacheTask?.cancel()
        lyricDirectorV3Task?.cancel()
        lyricDirectorV3GenerationID = UUID()
        let clearID = lyricDirectorV3GenerationID
        let expectedKey = track.key
        lyricDirectorV3Loading = false
        stageDirectionV3 = nil
        stagePlanV3 = LyricStageDirectorV3.localPlan(
            trackID: track.key.description,
            lines: lines,
            audioSummary: audioSummary)
        Task { @MainActor in
            await LyricStageStoreV3.shared.clear(for: track)
            guard lyricDirectorV3GenerationID == clearID,
                  engine.current?.key == expectedKey else { return }
            presentLyricDirectorToast("已清除 Luna V5.3 演出，保留本地完整舞台")
        }
    }

    private func directLyricsWithGeminiV4() {
        guard let track = engine.current,
              !engine.lyrics.isEmpty,
              !lyricDirectorV4Loading else { return }

        lyricDirectorV3Task?.cancel()
        lyricDirectorV3CacheTask?.cancel()
        lyricDirectorV4Task?.cancel()
        lyricDirectorV4GenerationID = UUID()
        let generationID = lyricDirectorV4GenerationID
        lyricDirectorV4Loading = true
        presentLyricDirectorToast("正在分析本地音频结构…")

        let lines = engine.lyrics
        let expectedKey = track.key
        let expectedHash = LyricPerformanceFingerprint.lyricsHash(lines)
        lyricDirectorV4Task = Task { @MainActor in
            defer {
                if lyricDirectorV4GenerationID == generationID {
                    lyricDirectorV4Loading = false
                }
            }

            do {
                let audioMap = try await AudioPerformanceAnalysisService.shared.analyzeCachedAudio(for: track)
                try Task.checkCancellation()
                let audioScore = AudioStructureScoreBuilderV4.make(
                    map: audioMap,
                    lines: lines,
                    availability: .ready)
                guard audioScore.availability == .ready,
                      audioScore.validated(lineCount: lines.count) != nil,
                      lyricDirectorV4GenerationID == generationID,
                      engine.current?.key == expectedKey,
                      LyricPerformanceFingerprint.lyricsHash(engine.lyrics) == expectedHash else { return }

                let localPlan = LyricStageDirectorV4.localPlan(
                    trackID: track.key.description,
                    lines: lines,
                    audioMap: audioMap,
                    audioScore: audioScore)
                stageAudioMapV3 = audioMap
                stageAudioSummaryV3 = audioMap.summary(for: lines)
                stageAudioScoreV4 = audioScore
                stageDirectionV4 = nil
                stageDirectionV3 = nil
                stagePlanV3 = localPlan.basePlan
                stagePlanV4 = localPlan
                selectLyricStageDisplayMode(.v53Generic)

                presentLyricDirectorToast("Gemini 正在结合整首音频结构编排…")
                let result = try await LyricStageClientV4.shared.direct(
                    track: track,
                    lines: lines,
                    audioScore: audioScore)
                guard !Task.isCancelled,
                      lyricDirectorV4GenerationID == generationID,
                      engine.current?.key == expectedKey,
                      LyricPerformanceFingerprint.lyricsHash(engine.lyrics) == expectedHash else { return }

                let saved = await LyricStageStoreV4.shared.save(
                    result.direction,
                    for: track,
                    lines: lines,
                    audioScore: result.audioScore)
                guard !Task.isCancelled,
                      lyricDirectorV4GenerationID == generationID,
                      engine.current?.key == expectedKey,
                      LyricPerformanceFingerprint.lyricsHash(engine.lyrics) == expectedHash else { return }
                guard saved else {
                    presentLyricDirectorToast("Gemini V4 演出未通过本地校验，已保留完整本地舞台")
                    return
                }

                let resolved = LyricStageDirectorV4.resolve(
                    trackID: track.key.description,
                    lines: lines,
                    audioMap: audioMap,
                    audioScore: result.audioScore,
                    direction: result.direction)
                stageDirectionV4 = result.direction
                stageAudioScoreV4 = result.audioScore
                stagePlanV3 = resolved.basePlan
                stagePlanV4 = resolved
                selectLyricStageDisplayMode(.v53Generic)
                presentLyricDirectorToast("V4 音频演出已应用 · \(resolved.stageBible.concept)")
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard lyricDirectorV4GenerationID == generationID,
                      engine.current?.key == expectedKey,
                      LyricPerformanceFingerprint.lyricsHash(engine.lyrics) == expectedHash else { return }
                if let analysisError = error as? AudioPerformanceAnalysisError {
                    presentLyricDirectorToast("\(analysisError.localizedDescription)，暂未请求 Gemini")
                } else {
                    presentLyricDirectorToast(error.localizedDescription)
                }
            }
        }
    }

    private func clearGeminiStageV4() {
        guard let track = engine.current else { return }
        let lines = engine.lyrics
        lyricDirectorV4Task?.cancel()
        lyricDirectorV4GenerationID = UUID()
        let clearID = lyricDirectorV4GenerationID
        lyricDirectorV4Loading = false
        stageDirectionV4 = nil
        stagePlanV4 = nil
        stageAudioScoreV4 = nil

        let audioSummary = stageAudioMapV3?.summary(for: lines)
            ?? stageAudioSummaryV3
            ?? makeEmptyAudioSummaryV3(track: track, lines: lines)
        stagePlanV3 = LyricStageDirectorV3.localPlan(
            trackID: track.key.description,
            lines: lines,
            audioSummary: audioSummary)

        Task { @MainActor in
            await LyricStageStoreV4.shared.clear(for: track)
            guard lyricDirectorV4GenerationID == clearID,
                  engine.current?.key == track.key else { return }
            presentLyricDirectorToast("已清除 Gemini V4 演出，保留完整本地舞台")
        }
    }

    private func directLyricsWithLunaV2() {
        guard let track = engine.current, !engine.lyrics.isEmpty, !lyricDirectorV2Loading else { return }
        lyricDirectorV2Task?.cancel()
        lyricDirectorV2Loading = true
        presentLyricDirectorToast("Luna 正在编排 V5.1…")
        let lines = engine.lyrics
        let expectedKey = track.key
        let expectedHash = LyricPerformanceFingerprint.lyricsHash(lines)
        lyricDirectorV2Task = Task { @MainActor in
            defer { lyricDirectorV2Loading = false }
            do {
                let score = try await LyricStageClientV2.shared.direct(track: track, lines: lines)
                guard !Task.isCancelled,
                      engine.current?.key == expectedKey,
                      LyricPerformanceFingerprint.lyricsHash(engine.lyrics) == expectedHash else { return }
                guard await LyricStageStoreV2.shared.save(score, for: track, lines: lines) else {
                    presentLyricDirectorToast("Luna V5.1 演出未通过本地校验")
                    return
                }
                stageScoreV2 = score
                selectLyricStageDisplayMode(.v51Events)
                presentLyricDirectorToast("V5.1 演出已应用 · \(score.styleSheet.concept)")
            } catch is CancellationError {
                return
            } catch {
                presentLyricDirectorToast(error.localizedDescription)
            }
        }
    }

    private func clearLunaStageV2() {
        guard let track = engine.current else { return }
        lyricDirectorV2Task?.cancel()
        lyricDirectorV2Loading = false
        stageScoreV2 = nil
        Task { @MainActor in
            await LyricStageStoreV2.shared.clear(for: track)
            presentLyricDirectorToast("已清除 Luna V5.1 演出")
        }
    }

    private func directLyricsWithLuna() {
        guard let track = engine.current, !engine.lyrics.isEmpty, !lyricDirectorLoading else { return }
        lyricDirectorTask?.cancel()
        lyricDirectorLoading = true
        let lines = engine.lyrics
        let expectedKey = track.key
        let expectedHash = LyricPerformanceFingerprint.lyricsHash(lines)
        lyricDirectorTask = Task { @MainActor in
            defer { lyricDirectorLoading = false }
            do {
                let score = try await LyricPerformanceClient.shared.direct(track: track, lines: lines)
                guard !Task.isCancelled,
                      engine.current?.key == expectedKey,
                      LyricPerformanceFingerprint.lyricsHash(engine.lyrics) == expectedHash else { return }
                guard await LyricPerformanceStore.shared.save(score, for: track, lines: lines) else {
                    presentLyricDirectorToast("Luna 返回的演出未通过本地校验")
                    return
                }
                lyricPerformanceScore = score
                presentLyricDirectorToast("Luna 演出已应用 · \(score.mood)")
            } catch is CancellationError {
                return
            } catch {
                presentLyricDirectorToast(error.localizedDescription)
            }
        }
    }

    private func clearLunaLyricPerformance() {
        guard let track = engine.current else { return }
        lyricDirectorTask?.cancel()
        lyricDirectorLoading = false
        lyricPerformanceScore = nil
        Task { @MainActor in
            await LyricPerformanceStore.shared.clear(for: track)
            presentLyricDirectorToast("已恢复本地歌词导演")
        }
    }

    private func generateWordTimingsOnPrecisionHost() {
        guard engine.canGeneratePrecisionHostWordTimings,
              !precisionHostAlignmentLoading else { return }
        precisionHostAlignmentTask?.cancel()
        precisionHostAlignmentLoading = true
        precisionHostAlignmentStatus = "正在连接高精度主机"
        precisionHostAlignmentTask = Task { @MainActor in
            defer {
                precisionHostAlignmentLoading = false
                precisionHostAlignmentStatus = ""
            }
            do {
                let alignment = try await engine.generatePrecisionHostWordTimings { _, message in
                    Task { @MainActor in
                        precisionHostAlignmentStatus = message
                        presentLyricDirectorToast(message)
                    }
                }
                guard !Task.isCancelled else { return }
                let quality = alignment.quality
                presentLyricDirectorToast(
                    "高精度逐字歌词已生成 · 双模型共识 \(quality.modelConsensusLines)/\(quality.lineCount) 行 · \(Int(quality.elapsedSeconds.rounded())) 秒")
            } catch is CancellationError {
                return
            } catch {
                presentLyricDirectorToast(error.localizedDescription)
            }
        }
    }

    private func presentLyricDirectorToast(_ message: String) {
        lyricDirectorToastTask?.cancel()
        withAnimation { lyricDirectorToast = message }
        lyricDirectorToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation { lyricDirectorToast = nil }
        }
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
        guard playerPage == .artwork, !showFavoriteFolders, !showUPPlaylists else { return }
        guard landscapeMVFullscreenKey?.matches(current) != true else { return }
        landscapeMVFullscreenKey = current.key
        showMVFullscreen = true
    }

    private func formatBitrate(_ bandwidth: Int) -> String {
        if bandwidth >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bandwidth) / 1_000_000)
        }
        return "\(max(1, bandwidth / 1000)) kbps"
    }

    private var contextTransitionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .interactiveSpring(response: 0.42, dampingFraction: 0.90, blendDuration: 0.08)
    }

    private func animate(_ animation: Animation, _ updates: @escaping () -> Void, completion: (() -> Void)? = nil) {
        if reduceMotion {
            updates()
            completion?()
            return
        }
        if let completion {
            withAnimation(animation, completionCriteria: .logicallyComplete, updates, completion: completion)
        } else {
            withAnimation(animation, updates)
        }
    }
}

private extension View {
    @ViewBuilder
    func playerContentReveal(opacity: Double) -> some View {
        self
            .opacity(opacity)
            .animation(.easeOut(duration: 0.12), value: opacity)
    }
}

// MARK: - Control views and sheet views are in separate files:
// PlayerControlViews.swift (PlayerIconButton, PlayerProgressBar, etc.)
// PlayerSheetViews.swift (lyrics sheets, MVFullscreenView, FavoriteFolderPickerView, UPPlaylistsView, etc.)
