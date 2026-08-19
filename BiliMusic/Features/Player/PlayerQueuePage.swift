import SwiftUI

private struct GuardedPlayerRowButton<Label: View>: View {
    let action: () -> Void
    let label: Label
    @GestureState private var isPressed = false

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        label
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isPressed ? 0.08 : 0))
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
                    .onEnded { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        guard distance < 8 else { return }
                        action()
                    }
            )
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                action()
            }
    }
}

private enum PlayerQueueLayout {
    static let bottomSheetRowHeight: CGFloat = 52
}

struct PlayerQueuePage<HeaderTrailing: View, Progress: View, Transport: View>: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(TrackTitleFormatter.cleanListTitlesDefaultsKey) private var cleanListTitles = false

    let pageWidth: CGFloat
    var contextStore: PlayerContextStore
    let displayTitle: String
    let displayArtist: String
    let headerTrailing: HeaderTrailing
    let progressView: Progress
    let transportControls: Transport

    init(
        pageWidth: CGFloat,
        contextStore: PlayerContextStore,
        displayTitle: String,
        displayArtist: String,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder progressView: () -> Progress,
        @ViewBuilder transportControls: () -> Transport
    ) {
        self.pageWidth = pageWidth
        self.contextStore = contextStore
        self.displayTitle = displayTitle
        self.displayArtist = displayArtist
        self.headerTrailing = headerTrailing()
        self.progressView = progressView()
        self.transportControls = transportControls()
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 760
            VStack(spacing: 0) {
                appleMusicQueueHeader
                    .padding(.horizontal, 30)
                    .padding(.top, isCompact ? 2 : 8)

                appleMusicQueueModeControls
                    .padding(.horizontal, 30)
                    .padding(.top, 14)

                appleMusicQueueList
                    .padding(.top, 14)
                    .frame(maxWidth: min(pageWidth, 520), maxHeight: .infinity)

                progressView
                    .padding(.top, 8)

                transportControls
                    .padding(.top, isCompact ? 8 : 12)
                    .padding(.bottom, isCompact ? 12 : 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            contextStore.ensureRecommendationsLoadedIfVisible(
                engine: engine,
                recommendationContextVisible: true)
        }
    }

    private var appleMusicQueueHeader: some View {
        HStack(spacing: 12) {
            fullQueueHeaderArtwork

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

            headerTrailing
        }
        .frame(height: 56)
    }

    private var appleMusicQueueModeControls: some View {
        HStack(spacing: 12) {
            appleMusicQueueModeButton(
                systemName: "shuffle",
                isActive: engine.queueMode == .shuffle,
                accessibilityLabel: "随机播放"
            ) {
                engine.setQueueMode(engine.queueMode == .shuffle ? .sequential : .shuffle)
            }

            appleMusicQueueModeButton(
                systemName: "repeat",
                isActive: engine.queueMode == .repeatOne,
                accessibilityLabel: "单曲循环"
            ) {
                engine.setQueueMode(engine.queueMode == .repeatOne ? .sequential : .repeatOne)
            }

            appleMusicQueueModeButton(
                systemName: "infinity",
                isActive: engine.queueMode == .radio,
                accessibilityLabel: "自动播放推荐"
            ) {
                engine.setQueueMode(engine.queueMode == .radio ? .sequential : .radio)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func appleMusicQueueModeButton(
        systemName: String,
        isActive: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isActive ? Color.black.opacity(0.78) : PlayerSurface.controlEmphasized)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(isActive ? PlayerSurface.fillStrong : PlayerSurface.fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private var appleMusicQueueList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    HStack {
                        Text("队列")
                            .font(.headline)
                            .foregroundStyle(PlayerSurface.textPrimary)
                        Spacer()
                        Text("\(engine.queue.count) 首")
                            .font(.subheadline)
                            .foregroundStyle(PlayerSurface.textSecondary)
                    }
                    .padding(.bottom, 8)

                    ForEach(engine.queue.indices, id: \.self) { index in
                        GuardedPlayerRowButton {
                            Task { await engine.jump(to: index) }
                        } label: {
                            bottomSheetTrackRow(track: engine.queue[index], index: index)
                                .id(index)
                        }
                        if index != engine.queue.indices.last {
                            playerDivider.padding(.leading, 54)
                        }
                    }

                    HStack(spacing: 7) {
                        Image(systemName: "infinity")
                        Text("自动播放")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                    appleMusicAutoPlayRows
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 16)
            }
            .onAppear {
                scrollCurrentQueue(proxy)
                contextStore.ensureRecommendationsLoadedIfVisible(
                    engine: engine,
                    recommendationContextVisible: true)
            }
            .onChange(of: engine.queueIndex) { _, _ in
                scrollCurrentQueue(proxy)
            }
        }
        .accessibilityIdentifier("playerAppleMusicQueue")
    }

    @ViewBuilder
    private var appleMusicAutoPlayRows: some View {
        if contextStore.recommendationsLoading || !contextStore.recommendationsMatchCurrentTrack(engine: engine) {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("正在准备当前歌曲推荐")
                    .foregroundStyle(PlayerSurface.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: PlayerQueueLayout.bottomSheetRowHeight)
        } else if contextStore.recommendedTracks.isEmpty {
            Text(contextStore.recommendationsError ?? "暂无相关歌曲")
                .font(.subheadline)
                .foregroundStyle(PlayerSurface.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: PlayerQueueLayout.bottomSheetRowHeight)
        } else {
            ForEach(contextStore.recommendedTracks.indices, id: \.self) { index in
                GuardedPlayerRowButton {
                    contextStore.suppressNextRecommendationRefresh = true
                    Task { await engine.play(tracks: contextStore.recommendedTracks, startAt: index, queueMode: .radio) }
                } label: {
                    bottomSheetTrackRow(track: contextStore.recommendedTracks[index], index: index)
                }
                if index != contextStore.recommendedTracks.indices.last {
                    playerDivider.padding(.leading, 54)
                }
            }
        }
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
                    .foregroundStyle(isCurrent ? Color.white : PlayerSurface.textPrimary)
                    .lineLimit(1)
                Text("\(display.artist) · \(MusicFormatters.playbackTime(Double(track.duration)))")
                    .font(.caption)
                    .foregroundStyle(PlayerSurface.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isCurrent {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 24, height: 32)
            }
        }
        .frame(height: PlayerQueueLayout.bottomSheetRowHeight)
        .contentShape(Rectangle())
        .accessibilityIdentifier("playerTrackRow-\(track.id)")
        .accessibilityLabel("\(index + 1). \(display.title)")
    }

    private var playerDivider: some View {
        PlayerSurface.divider.frame(height: 0.5)
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

    private func scrollCurrentQueue(_ proxy: ScrollViewProxy) {
        guard engine.queue.indices.contains(engine.queueIndex) else { return }
        DispatchQueue.main.async {
            if reduceMotion {
                proxy.scrollTo(engine.queueIndex, anchor: .center)
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(engine.queueIndex, anchor: .center)
                }
            }
        }
    }
}
