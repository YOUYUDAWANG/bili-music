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
    @State private var selectedMode: PlayerEngine.PlaybackMode = .music
    @State private var switchingMode = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    private var favorites: FavoriteManager { .shared }

    private struct PlaylistLookupResult {
        let playlist: BiliClient.UPPlaylist?
        let tracks: [Track]
        let error: String?
    }

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
            if suppressNextRecommendationRefresh {
                suppressNextRecommendationRefresh = false
                return
            }
            recommendationsStale = true
            if selectedPage == PlayerPage.recommendations.rawValue {
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
            CachedAsyncImage(url: thumbnailURL(engine.current?.coverURL, width: 600, height: 600)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    AppTheme.secondaryBackground
                    Image(systemName: "music.note")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: coverSize, height: coverSize)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.42), radius: 28, y: 18)
        }
    }

    private var progressView: some View {
        // 独立子视图:只有它订阅 engine.currentTime(每 0.5s 变),
        // 避免整个播放器 body(封面、操作栏、TabView)跟着每半秒重渲染。
        PlayerProgressBar()
    }

    private var transportControls: some View {
        HStack(spacing: 34) {
            PlayerIconButton(systemName: "backward.fill", size: 28, accessibilityLabel: "上一曲") {
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
            PlayerIconButton(systemName: "forward.fill", size: 28, accessibilityLabel: "下一曲") {
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
                Task { await favorites.toggle(track: track) }
            }
            .opacity(favorites.busyBVIDs.contains(track.bvid) ? 0.55 : 1)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("收藏到默认收藏夹")
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
                    .foregroundStyle(.green)
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
        } label: {
            ActionSymbolLabel(title: "播放音质", systemName: "hifispeaker")
        }
        .buttonStyle(.plain)
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
                    .frame(maxHeight: 148)
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
                    ForEach(queuePreviewItems, id: \.track.id) { item in
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
        guard !engine.queue.isEmpty else { return [] }
        let start = max(0, min(engine.queueIndex, engine.queue.count - 1))
        let end = min(engine.queue.count, start + 3)
        return Array(engine.queue[start..<end].enumerated()).map { offset, track in
            (start + offset, track)
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
            withAnimation(.easeInOut(duration: 0.2)) {
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
            CachedAsyncImage(url: thumbnailURL(engine.current?.coverURL, width: 160, height: 90)) { image in
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

// MARK: - Control views and sheet views are in separate files:
// PlayerControlViews.swift (PlayerIconButton, ActionSymbolButton, PlayerProgressBar, etc.)
// PlayerSheetViews.swift (LyricsSheetView, MVFullscreenView, FavoriteFolderPickerView, UPPlaylistsView, etc.)
