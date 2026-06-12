import AVKit
import SwiftUI

/// 全屏正在播放页(从 mini bar 上拉打开)。
struct NowPlayingView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var showQueue = false
    @State private var showUPPlaylists = false
    @State private var showFavoriteFolders = false
    @State private var selectedMode: PlayerEngine.PlaybackMode = .music
    @State private var switchingMode = false
    @State private var favoriteLongPressTriggered = false
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    private var favorites: FavoriteManager { .shared }

    var body: some View {
        @Bindable var bindableEngine = engine
        GeometryReader { proxy in
            let coverSize = min(proxy.size.width - 48, max(230, proxy.size.height * 0.38), 340)
            ZStack {
                playerBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        Capsule()
                            .fill(.secondary.opacity(0.32))
                            .frame(width: 42, height: 5)
                            .padding(.top, 8)

                        Picker("播放模式", selection: $selectedMode) {
                            ForEach(PlayerEngine.PlaybackMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 210)
                        .tint(AppTheme.accent)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .onChange(of: engine.playbackMode) { _, mode in
                            selectedMode = mode
                        }
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
                            .padding(.top, 8)

                        VStack(spacing: 7) {
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

                        HStack(spacing: 38) {
                            PlayerIconButton(systemName: "backward.fill", size: 28) {
                                Task { await engine.playPrevious() }
                            }
                            Button {
                                engine.togglePlayPause()
                            } label: {
                                Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 36, weight: .bold))
                                    .contentTransition(.symbolEffect(.replace))
                                    .frame(width: 82, height: 82)
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

                        HStack(spacing: 12) {
                            favoriteButton
                            downloadIconButton
                            ActionSymbolButton(title: "队列", systemName: "list.bullet") {
                                showQueue = true
                            }
                            ActionSymbolButton(title: "合集", systemName: "rectangle.stack") {
                                showUPPlaylists = true
                            }
                            .disabled(engine.current?.ownerMid == nil)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 24)

                        if let favoriteMessage {
                            Text(favoriteMessage)
                                .font(.caption2)
                                .foregroundStyle(favorites.lastError == nil ? Color.secondary : Color.red)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }

                        lyricsView

                        Toggle(isOn: $bindableEngine.radioMode) {
                            Label("电台模式", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 28)
                        .tint(AppTheme.accent)

                        Spacer(minLength: 18)
                    }
                }
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueView()
        }
        .sheet(isPresented: $showUPPlaylists) {
            UPPlaylistsView()
        }
        .sheet(isPresented: $showFavoriteFolders) {
            FavoriteFolderPickerView()
        }
        .onAppear {
            selectedMode = engine.playbackMode
        }
    }

    /// 中性渐变背景:可靠、内容对比清晰。之前整屏专辑虚化会把封面和文字洗成灰白一片。
    private var playerBackground: some View {
        AppTheme.playerGradient
    }

    @ViewBuilder
    private func mediaView(coverSize: CGFloat) -> some View {
        if engine.playbackMode == .mv, let player = engine.avPlayer {
            VideoPlayer(player: player)
                .frame(width: min(coverSize + 34, 360), height: (min(coverSize + 34, 360)) * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.42), radius: 28, y: 18)
        } else {
            AsyncImage(url: engine.current?.coverURL) { image in
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

    @ViewBuilder
    private var lyricsView: some View {
        let current = currentLyricIndex
        VStack(alignment: .leading, spacing: 10) {
            Label("歌词", systemImage: "text.quote")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if engine.lyrics.isEmpty {
                Text("这首歌没有匹配到在线歌词")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lyricWindow, id: \.id) { line in
                    Text(line.text)
                        .font(line.id == engine.lyrics[safe: current]?.id ? .headline : .subheadline)
                        .foregroundStyle(line.id == engine.lyrics[safe: current]?.id ? AppTheme.label : .secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
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

    private var lyricWindow: [PlayerEngine.LyricLine] {
        guard !engine.lyrics.isEmpty else { return [] }
        let start = max(0, currentLyricIndex - 1)
        let end = min(engine.lyrics.count, currentLyricIndex + 3)
        return Array(engine.lyrics[start..<end])
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

    private var favoriteMessage: String? {
        if let error = favorites.lastError {
            return error
        }
        if let title = favorites.defaultFolderTitle {
            return "默认收藏到 \(title)"
        }
        return nil
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

    private func format(_ seconds: Double) -> String {
        let s = Int(seconds.isFinite ? max(seconds, 0) : 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// 底部常驻迷你播放条。
struct MiniPlayerBar: View {
    @Environment(PlayerEngine.self) private var engine
    @Binding var showFullPlayer: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: engine.current?.coverURL) { image in
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
        .onTapGesture { showFullPlayer = true }
        // 手指按住 mini 播放器上滑即可打开全屏播放页
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.height < -24 {
                        showFullPlayer = true
                    }
                }
        )
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct QueueView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(engine.queue.enumerated()), id: \.element.bvid) { index, track in
                    Button {
                        Task {
                            await engine.jump(to: index)
                            dismiss()
                        }
                    } label: {
                        TrackRow(track: track, isPlaying: index == engine.queueIndex)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if engine.queue.count > 1 {
                            Button("移除", role: .destructive) {
                                engine.removeFromQueue(at: index)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.groupedBackground)
            .navigationTitle("播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("完成") { dismiss() }
            }
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
        guard let mid = engine.current?.ownerMid else {
            errorMessage = "当前歌曲缺少 UP 主信息"
            return
        }
        loading = true
        defer { loading = false }
        do {
            playlists = try await BiliClient().upPlaylists(mid: mid)
        } catch {
            errorMessage = error.localizedDescription
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
