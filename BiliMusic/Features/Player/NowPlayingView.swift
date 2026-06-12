import AVKit
import SwiftUI

/// 全屏正在播放页(从 mini bar 上拉打开)。
struct NowPlayingView: View {
    @Environment(PlayerEngine.self) private var engine
    var onDismiss: (() -> Void)? = nil
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
    @State private var showLyrics = false
    @State private var showMVFullscreen = false
    @State private var showMVControls = false
    @State private var showUPPlaylists = false
    @State private var showFavoriteFolders = false
    @State private var selectedMode: PlayerEngine.PlaybackMode = .music
    @State private var switchingMode = false
    @State private var favoriteLongPressTriggered = false
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    private var favorites: FavoriteManager { .shared }

    var body: some View {
        GeometryReader { proxy in
            let coverSize = min(proxy.size.width - 28, max(260, proxy.size.height * 0.46), 420)
            ZStack {
                if isLandscapeMV(size: proxy.size), let player = engine.avPlayer {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    playerBackground
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        playerHeader
                        TabView(selection: $selectedPage) {
                            playerListPage(title: "播放列表", systemName: "list.bullet") {
                                queueList
                            }
                            .tag(PlayerPage.queue.rawValue)

                            ScrollView(showsIndicators: false) {
                                nowPlayingPage(coverSize: coverSize)
                            }
                            .tag(PlayerPage.nowPlaying.rawValue)

                            playerListPage(title: "推荐歌曲", systemName: "sparkles") {
                                recommendationsList
                            }
                            .tag(PlayerPage.recommendations.rawValue)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                    }
                }
            }
            .offset(y: dragOffset)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: dragOffset)
            .simultaneousGesture(pageDismissDrag)
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
            Task { await loadRecommendations() }
            Task { await loadCurrentPlaylistIfNeeded(force: true) }
        }
        .onChange(of: engine.playbackMode) { _, mode in
            selectedMode = mode
        }
        .onChange(of: engine.current?.bvid) {
            Task { await loadCurrentPlaylistIfNeeded(force: false) }
            if suppressNextRecommendationRefresh {
                suppressNextRecommendationRefresh = false
                return
            }
            if selectedPage == PlayerPage.recommendations.rawValue {
                return
            }
            recommendedTracks = []
            recommendationsError = nil
            Task { await loadRecommendations() }
        }
        .onChange(of: selectedPage) { _, page in
            guard page != PlayerPage.recommendations.rawValue else { return }
            recommendedTracks = []
            recommendationsError = nil
            Task { await loadRecommendations() }
        }
    }

    /// 中性渐变背景:可靠、内容对比清晰。之前整屏专辑虚化会把封面和文字洗成灰白一片。
    private var playerBackground: some View {
        AppTheme.playerGradient
    }

    private func isLandscapeMV(size: CGSize) -> Bool {
        engine.playbackMode == .mv && size.width > size.height
    }

    private var playerHeader: some View {
        HStack {
            Button {
                closePlayer()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            Spacer()
        }
        .overlay {
            Capsule()
                .fill(.secondary.opacity(0.32))
                .frame(width: 42, height: 5)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .gesture(dismissDrag)
    }

    private func nowPlayingPage(coverSize: CGFloat) -> some View {
        VStack(spacing: 15) {
            Picker("播放模式", selection: $selectedMode) {
                ForEach(PlayerEngine.PlaybackMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 210)
            .tint(AppTheme.accent)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: selectedMode) { _, mode in
                guard mode != engine.playbackMode else { return }
                Task {
                    switchingMode = true
                    await engine.setPlaybackMode(mode)
                    selectedMode = engine.playbackMode
                    switchingMode = false
                }
            }
            .disabled(switchingMode || (!engine.videoAvailable && engine.playbackMode == .music))

            mediaView(coverSize: coverSize)
                .padding(.top, 2)

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
                        .foregroundStyle(.red)
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
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            bottomContextPanel

            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func mediaView(coverSize: CGFloat) -> some View {
        if engine.playbackMode == .mv, let player = engine.avPlayer {
            ZStack(alignment: .topTrailing) {
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
            .clipShape(RoundedRectangle(cornerRadius: 14))
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
            AsyncImage(url: thumbnailURL(engine.current?.coverURL, width: 960, height: 540)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    AppTheme.secondaryBackground
                    Image(systemName: "music.note")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: coverSize, height: coverSize * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.42), radius: 28, y: 18)
        }
    }

    private var progressView: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubValue : min(engine.currentTime, engine.duration) },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(engine.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        scrubValue = min(engine.currentTime, engine.duration)
                        isScrubbing = true
                        engine.beginScrub()
                    } else {
                        engine.endScrub(to: scrubValue)
                        isScrubbing = false
                    }
                }
            )
            .tint(AppTheme.label)
            HStack {
                Text(format(isScrubbing ? scrubValue : engine.currentTime))
                Spacer()
                Text(format(engine.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
    }

    private var transportControls: some View {
        HStack(spacing: 34) {
            PlayerIconButton(systemName: "backward.fill", size: 28) {
                Task { await engine.playPrevious() }
            }
            Button {
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
            PlayerIconButton(systemName: "forward.fill", size: 28) {
                Task { await engine.playNext() }
            }
            .disabled(!engine.hasNext)
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
            qualityMenu
            ActionSymbolButton(title: "合集", systemName: "rectangle.stack") {
                showUPPlaylists = true
            }
            .disabled(engine.current?.ownerMid == nil)
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
                if favoriteLongPressTriggered {
                    favoriteLongPressTriggered = false
                    return
                }
                Task { await favorites.toggle(track: track) }
            }
                .opacity(favorites.busyBVIDs.contains(track.bvid) ? 0.55 : 1)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .onEnded { _ in
                            guard !favorites.busyBVIDs.contains(track.bvid) else { return }
                            favoriteLongPressTriggered = true
                            Task { await favorites.loadFolders() }
                            showFavoriteFolders = true
                        }
                )
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("短按收藏到默认收藏夹,长按选择收藏夹")
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
            if CacheStore.shared.entry(bvid: track.bvid) != nil {
                ActionSymbolButton(title: "已缓存", systemName: "arrow.down.circle.fill") {}
                    .foregroundStyle(.green)
            } else if downloads.progress[track.bvid] != nil {
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
                    Task { await downloads.download(track: track) }
                }
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

    private var qualityMenu: some View {
        Menu {
            ForEach(qualityOptions, id: \.id) { option in
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
        } label: {
            ActionSymbolLabel(title: "播放音质", systemName: "hifispeaker")
        }
        .buttonStyle(.plain)
    }

    private var qualityOptions: [(id: Int, title: String)] {
        [
            (0, "最高可用"),
            (30251, "Hi-Res"),
            (30280, "高码率"),
            (30232, "132K"),
            (30216, "64K"),
        ]
    }

    private func playerListPage<Content: View>(title: String, systemName: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                content()
                    .padding(.horizontal, 20)
                Spacer(minLength: 32)
            }
        }
    }

    @ViewBuilder
    private var queueList: some View {
        if engine.queue.isEmpty {
            ContentUnavailableView("播放列表为空", systemImage: "list.bullet")
                .frame(minHeight: 160)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(engine.queue.enumerated()), id: \.element.bvid) { index, track in
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
                ForEach(Array(recommendedTracks.prefix(12).enumerated()), id: \.element.bvid) { index, track in
                    Button {
                        suppressNextRecommendationRefresh = true
                        Task { await engine.play(tracks: recommendedTracks, startAt: index, queueMode: .radio) }
                    } label: {
                        TrackRow(track: track, isPlaying: engine.current?.bvid == track.bvid)
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
                            ForEach(Array(currentPlaylistTracks.enumerated()), id: \.element.bvid) { index, track in
                                Button {
                                    Task { await playCurrentPlaylistTrack(at: index) }
                                } label: {
                                    compactPlaylistRow(track: track, index: index)
                                        .id(track.bvid)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 148)
                    .onAppear { scrollCurrentPlaylist(proxy) }
                    .onChange(of: engine.current?.bvid) { _, _ in
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

                VStack(spacing: 0) {
                    ForEach(queuePreviewItems, id: \.track.bvid) { item in
                        Button {
                            Task { await engine.jump(to: item.index) }
                        } label: {
                            compactPlaylistRow(track: item.track, index: item.index)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 24)
        }
    }

    private func compactPlaylistRow(track: Track, index: Int) -> some View {
        let isCurrent = track.bvid == engine.current?.bvid
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
        guard !engine.queue.isEmpty else { return [] }
        let start = max(0, min(engine.queueIndex, engine.queue.count - 1))
        let end = min(engine.queue.count, start + 3)
        return Array(engine.queue[start..<end].enumerated()).map { offset, track in
            (start + offset, track)
        }
    }

    private func loadRecommendations() async {
        guard let bvid = engine.current?.bvid else { return }
        recommendationsLoading = recommendedTracks.isEmpty
        defer { recommendationsLoading = false }
        let tracks = await RecommendationEngine().recommendations(
            mode: .relatedPanel,
            context: .init(
                current: engine.current,
                queue: engine.queue,
                playlistTracks: currentPlaylistTracks,
                excludedBVIDs: [bvid]),
            limit: 24)
        guard engine.current?.bvid == bvid else { return }
        recommendedTracks = tracks
        recommendationsError = tracks.isEmpty ? "没有找到合适的推荐歌曲" : nil
        engine.preload(tracks: recommendedTracks)
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
                currentPlaylist = nil
                currentPlaylistTracks = []
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
            currentPlaylist = playlist
            currentPlaylistTracks = tracks
            engine.preload(tracks: tracks)
        } catch {
            guard engine.current?.bvid == bvid else { return }
            currentPlaylist = nil
            currentPlaylistTracks = []
            currentPlaylistError = "合集检测失败: \(error.localizedDescription)"
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
        guard let bvid = engine.current?.bvid,
              currentPlaylistTracks.contains(where: { $0.bvid == bvid }) else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(bvid, anchor: .center)
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

    /// 从顶部抓手下拉关闭播放页;拖动时整页跟手,超过阈值松手即收起。
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width),
                      value.translation.height > 0 else { return }
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 130 || value.predictedEndTranslation.height > 260 {
                    closePlayer()
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        dragOffset = 0
                    }
                }
            }
    }

    /// 只在当前播放主页面启用整页下滑收起;左右列表页保留正常列表滚动。
    private var pageDismissDrag: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard selectedPage == PlayerPage.nowPlaying.rawValue,
                      abs(value.translation.height) > abs(value.translation.width),
                      value.translation.height > 0 else { return }
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard selectedPage == PlayerPage.nowPlaying.rawValue else { return }
                if value.translation.height > 130 || value.predictedEndTranslation.height > 260 {
                    closePlayer()
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        dragOffset = 0
                    }
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

    private func thumbnailURL(_ url: URL?, width: Int, height: Int) -> URL? {
        guard let url else { return nil }
        let raw = url.absoluteString
        guard raw.contains("hdslb.com"), !raw.contains("@") else { return url }
        return URL(string: raw + "@\(width)w_\(height)h_1c.webp")
    }
}

/// 底部常驻迷你播放条。
struct MiniPlayerBar: View {
    @Environment(PlayerEngine.self) private var engine
    @Binding var showFullPlayer: Bool
    @Binding var isDraggingFullPlayer: Bool
    @Binding var openPlayerTranslation: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: thumbnailURL(engine.current?.coverURL, width: 160, height: 90)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                AppTheme.secondaryBackground
            }
            .frame(width: 52, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(engine.current?.title ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(engine.current?.artist ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button {
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .overlay { if engine.state == .loading { ProgressView().scaleEffect(0.7) } }
            Button {
                Task { await engine.playNext() }
            } label: {
                Image(systemName: "forward.fill").font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.separator.opacity(0.7))
                .frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { openFullPlayer() }
        // 手指按住 mini 播放器上滑即可打开全屏播放页
        .gesture(
            DragGesture(minimumDistance: 22)
                .onChanged { value in
                    guard abs(value.translation.height) > abs(value.translation.width),
                          value.translation.height < 0 else { return }
                    isDraggingFullPlayer = true
                    openPlayerTranslation = value.translation.height
                }
                .onEnded { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    if value.translation.height < -110 || value.predictedEndTranslation.height < -180 {
                        openFullPlayer()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            isDraggingFullPlayer = false
                            openPlayerTranslation = 0
                        }
                    }
                }
        )
    }

    private func openFullPlayer() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            isDraggingFullPlayer = false
            openPlayerTranslation = 0
            showFullPlayer = true
        }
    }

    private func thumbnailURL(_ url: URL?, width: Int, height: Int) -> URL? {
        guard let url else { return nil }
        let raw = url.absoluteString
        guard raw.contains("hdslb.com"), !raw.contains("@") else { return url }
        return URL(string: raw + "@\(width)w_\(height)h_1c.webp")
    }
}

private struct PlayerIconButton: View {
    let systemName: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 56, height: 56)
        }
    }
}

private struct ActionSymbolButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.accent)
        .accessibilityLabel(title)
    }
}

private struct ActionSymbolLabel: View {
    let title: String
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(AppTheme.accent)
            .accessibilityLabel(title)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct LyricsSheetView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(engine.lyrics.enumerated()), id: \.element.id) { index, line in
                            Text(line.text)
                                .font(index == currentLyricIndex ? .title3.weight(.semibold) : .title3.weight(.regular))
                                .foregroundStyle(index == currentLyricIndex ? AppTheme.label : .secondary)
                                .id(line.id)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                }
                .background(AppTheme.background)
                .navigationTitle("歌词")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button("完成") { dismiss() }
                }
                .onChange(of: currentLyricIndex) { _, index in
                    guard let line = engine.lyrics[safe: index] else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(line.id, anchor: .center)
                    }
                }
            }
        }
    }

    private var currentLyricIndex: Int {
        guard !engine.lyrics.isEmpty else { return 0 }
        if let active = engine.lyrics.firstIndex(where: { line in
            engine.currentTime >= line.from && engine.currentTime < line.to
        }) {
            return active
        }
        return engine.lyrics.lastIndex { line in engine.currentTime >= line.from } ?? 0
    }
}

private struct MVFullscreenView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player = engine.avPlayer {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.48), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .task {
            await engine.upgradeMVForFullscreen()
        }
    }
}

private struct FavoriteFolderPickerView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    private var favorites: FavoriteManager { .shared }

    var body: some View {
        NavigationStack {
            List {
                if let error = favorites.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                ForEach(favorites.folders) { folder in
                    Button {
                        guard let track = engine.current else { return }
                        Task {
                            await favorites.toggle(track: track, folder: folder)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(folder.title)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(folder.media_count) 个内容")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if favorites.lastFolderId == folder.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.groupedBackground)
            .navigationTitle("选择收藏夹")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if favorites.foldersLoading {
                    ProgressView()
                } else if favorites.folders.isEmpty && favorites.lastError == nil {
                    ContentUnavailableView("没有收藏夹", systemImage: "heart",
                                           description: Text("请先在 B 站创建收藏夹"))
                }
            }
            .toolbar {
                Button("完成") { dismiss() }
            }
            .task {
                await favorites.loadFolders()
            }
        }
    }
}

private struct UPPlaylistsView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var playlists: [BiliClient.UPPlaylist] = []
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                ForEach(playlists) { playlist in
                    NavigationLink(value: playlist) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playlist.title)
                                .font(.subheadline.weight(.semibold))
                            Text("\(playlist.mediaCount) 首")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.groupedBackground)
            .navigationTitle("合集")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: BiliClient.UPPlaylist.self) { playlist in
                UPPlaylistDetailView(playlist: playlist)
            }
            .overlay {
                if loading {
                    ProgressView()
                } else if playlists.isEmpty && errorMessage == nil {
                    ContentUnavailableView("没有公开歌单", systemImage: "rectangle.stack",
                                           description: Text("这个 UP 主可能没有公开合集或系列"))
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard let current = engine.current, let mid = current.ownerMid else {
            errorMessage = "当前歌曲缺少 UP 主信息"
            return
        }
        loading = true
        defer { loading = false }
        do {
            let client = BiliClient()
            var loaded: [BiliClient.UPPlaylist] = []
            if let currentPlaylist = try await client.currentVideoPlaylist(bvid: current.bvid) {
                loaded.append(currentPlaylist)
            }
            loaded.append(contentsOf: try await client.upPlaylists(mid: mid))
            playlists = dedupePlaylists(loaded)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dedupePlaylists(_ playlists: [BiliClient.UPPlaylist]) -> [BiliClient.UPPlaylist] {
        var seen = Set<String>()
        return playlists.filter { playlist in
            let key = "\(playlist.type)-\(playlist.id)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}

private struct UPPlaylistDetailView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    let playlist: BiliClient.UPPlaylist

    @State private var tracks: [Track] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            ForEach(Array(tracks.enumerated()), id: \.element.bvid) { index, track in
                Button {
                    Task {
                        await engine.play(tracks: tracks, startAt: index)
                        dismiss()
                    }
                } label: {
                    TrackRow(track: track, isPlaying: engine.current?.bvid == track.bvid)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if track == tracks.last {
                        Task { await loadMore() }
                    }
                }
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.groupedBackground)
        .navigationTitle(playlist.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !tracks.isEmpty {
                Button {
                    engine.appendToQueue(tracks)
                } label: {
                    Label("加入队列", systemImage: "text.badge.plus")
                }
            }
        }
        .task {
            if tracks.isEmpty {
                await loadMore()
            }
        }
    }

    private func loadMore() async {
        guard hasMore, !loading, let mid = engine.current?.ownerMid else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await BiliClient().upPlaylistItems(mid: mid, playlist: playlist, page: page)
            page += 1
            hasMore = result.hasMore
            let artist = engine.current?.artist ?? ""
            let newTracks = result.items
                .map { Track(playlist: $0, artist: artist, ownerMid: mid) }
                .filter(MusicFilter.isMusic)
            tracks.append(contentsOf: newTracks)
            engine.preload(tracks: newTracks)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
