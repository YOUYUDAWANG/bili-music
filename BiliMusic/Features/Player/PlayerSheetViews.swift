import AVKit
import SwiftUI

// MARK: - Lyrics Sheet

struct LyricsSheetView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let active = currentLyricIndex
        return NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(engine.lyrics.enumerated()), id: \.element.id) { index, line in
                            Text(line.text)
                                .font(index == active ? .title3.weight(.semibold) : .title3.weight(.regular))
                                .foregroundStyle(index == active ? AppTheme.label : .secondary)
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

// MARK: - MV Fullscreen

struct MVFullscreenView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mvQuality") private var mvQuality = 0
    @State private var switchingQuality = false
    @State private var showChrome = true
    @State private var chromeHideTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                if let player = engine.avPlayer {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    ProgressView()
                        .tint(.white)
                }

                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        revealChrome()
                    }
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("mvFullscreenTapCatcher")

                fullscreenChrome(safeAreaInsets: proxy.safeAreaInsets)
                    .opacity(showChrome ? 1 : 0)
                    .allowsHitTesting(showChrome)
                    .animation(.easeInOut(duration: 0.22), value: showChrome)
                    .accessibilityIdentifier("mvFullscreenChrome")
            }
        }
        .onAppear {
            revealChrome()
        }
        .onDisappear {
            chromeHideTask?.cancel()
        }
        .task {
            await engine.upgradeMVForFullscreen()
        }
    }

    private func fullscreenChrome(safeAreaInsets: EdgeInsets) -> some View {
        HStack {
            Menu {
                ForEach(BiliClient.videoQualityOptions, id: \.id) { option in
                    Button {
                        Task {
                            revealChrome()
                            switchingQuality = true
                            mvQuality = option.id
                            await engine.setMVQuality(option.id)
                            switchingQuality = false
                            revealChrome()
                        }
                    } label: {
                        Label(option.title, systemImage: mvQuality == option.id ? "checkmark" : "circle")
                    }
                }
                if let quality = engine.currentVideoQuality {
                    Divider()
                    Label("当前: \(BiliClient.videoQualityName(quality))", systemImage: "play.rectangle")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: switchingQuality ? "arrow.triangle.2.circlepath" : "slider.horizontal.3")
                    Text(BiliClient.videoQualityName(selectedMVQuality))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { revealChrome() })
            .accessibilityLabel("MV 画质")
            .accessibilityIdentifier("mvFullscreenQualityButton")

            Spacer()

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
            .accessibilityLabel("退出全屏 MV")
            .accessibilityIdentifier("mvFullscreenCloseButton")
        }
        .padding(.top, max(12, safeAreaInsets.top + 10))
        .padding(.leading, max(16, safeAreaInsets.leading + 16))
        .padding(.trailing, max(16, safeAreaInsets.trailing + 16))
    }

    private func revealChrome() {
        chromeHideTask?.cancel()
        showChrome = true
        chromeHideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2600))
            guard !Task.isCancelled else { return }
            showChrome = false
        }
    }

    private var selectedMVQuality: Int {
        engine.currentVideoQuality ?? mvQuality
    }
}

// MARK: - Favorite Folder Picker

struct FavoriteFolderPickerView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    private var favorites: FavoriteManager { .shared }

    var body: some View {
        NavigationStack {
            List {
                if let error = favorites.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(AppTheme.error)
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
                                    .foregroundStyle(AppTheme.success)
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

// MARK: - UP Playlists

struct UPPlaylistsView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var playlists: [BiliClient.UPPlaylist] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var sourceOwnerMid: Int?
    @State private var sourceArtist = ""

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(AppTheme.error)
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
                if let sourceOwnerMid {
                    UPPlaylistDetailView(
                        playlist: playlist,
                        ownerMid: sourceOwnerMid,
                        artist: sourceArtist)
                }
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
        sourceOwnerMid = mid
        sourceArtist = current.artist
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

// MARK: - UP Playlist Detail

struct UPPlaylistDetailView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    let playlist: BiliClient.UPPlaylist
    let ownerMid: Int
    let artist: String

    @State private var tracks: [Track] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(AppTheme.error)
            }
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    Task {
                        await engine.play(tracks: tracks, startAt: index)
                        dismiss()
                    }
                } label: {
                    TrackRow(track: track, isPlaying: engine.current.map { track.key.matches($0) } ?? false)
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
        guard hasMore, !loading else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let result = try await BiliClient().upPlaylistItems(mid: ownerMid, playlist: playlist, page: page)
            guard !Task.isCancelled else { return }
            page += 1
            hasMore = result.hasMore
            let newTracks = result.items
                .map { Track(playlist: $0, artist: artist, ownerMid: ownerMid) }
                .filter(MusicFilter.isMusic)
            tracks.append(contentsOf: newTracks)
            engine.preload(tracks: newTracks, limit: 2, delay: .milliseconds(700))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
