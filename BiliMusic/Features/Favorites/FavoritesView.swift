import SwiftUI

/// 收藏夹列表(B 站收藏夹当歌单用)。
private enum FavoritesDestination: Hashable {
    case liked
    case remote(Int)
}

struct FavoritesView: View {
    @State private var folders: [BiliClient.FavFolder] = []
    @State private var path: [FavoritesDestination] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var requestInFlight = false
    @State private var restoredLastFolder = false
    @State private var authenticationGeneration = UUID()
    @State private var folderPreviewURLs: [Int: [URL]] = [:]
    private let library = LibraryStore.shared

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    alignment: .leading,
                    spacing: 18
                ) {
                    NavigationLink(value: FavoritesDestination.liked) {
                        likedFolderTile
                    }
                    .buttonStyle(MusicRowButtonStyle())
                    .accessibilityIdentifier("favoriteFolder-liked")

                    ForEach(visibleFolders, id: \.id) { folder in
                        NavigationLink(value: FavoritesDestination.remote(folder.id)) {
                            favoriteFolderTile(folder)
                        }
                        .buttonStyle(MusicRowButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded {
                            FavoriteManager.shared.remember(folderId: folder.id, title: folder.title)
                        })
                        .accessibilityIdentifier("favoriteFolder-\(folder.id)")
                        .task(id: authenticationGeneration) {
                            await loadPreview(for: folder)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .accessibilityIdentifier("favoritesGrid")
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("收藏夹")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: FavoritesDestination.self) { destination in
                switch destination {
                case .liked:
                    LikedLibraryView()
                case .remote(let folderId):
                    FavFolderDetailView(
                        folderId: folderId,
                        title: folderTitle(folderId))
                }
            }
            .overlay {
                if !library.isLoaded || (loading && folders.isEmpty && library.remoteCollections().isEmpty) {
                    ProgressView()
                } else if !CookieStore.isLoggedIn,
                          library.likedCollection.itemCount == 0,
                          library.remoteCollections().isEmpty {
                    ContentUnavailableView(
                        CookieStore.isExpired ? "登录已失效" : "需要登录",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text(CookieStore.isExpired
                            ? "重新扫码后会继续同步 B 站收藏夹；本地「我喜欢」仍可使用。"
                            : "去设置页扫码登录后，这里会显示你的 B 站收藏夹。也可以先把歌曲加入「我喜欢」。"))
                } else if let errorMessage, folders.isEmpty, library.remoteCollections().isEmpty {
                    ContentUnavailableView(
                        "收藏夹加载失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage))
                }
            }
            .task { await load() }
            .onChange(of: path) { _, newValue in
                if case .remote(let folderId) = newValue.last {
                    FavoriteManager.shared.remember(folderId: folderId, title: folderTitle(folderId))
                }
            }
            .refreshable { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .biliAuthenticationDidChange)) { _ in
                authenticationGeneration = UUID()
                folders = []
                folderPreviewURLs = [:]
                path = []
                loading = false
                requestInFlight = false
                errorMessage = nil
                restoredLastFolder = false
                Task {
                    await library.loadIfNeeded()
                    if CookieStore.isLoggedIn {
                        await load()
                    }
                }
            }
        }
    }

    private var visibleFolders: [BiliClient.FavFolder] {
        if !folders.isEmpty { return folders }
        return library.remoteCollections().compactMap { collection in
            guard let remoteId = collection.remoteId else { return nil }
            return BiliClient.FavFolder(id: remoteId, title: collection.name, media_count: collection.itemCount)
        }
    }

    private var likedFolderTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            MagazineArtworkCollage(urls: library.tracks(in: LibraryCollection.likedID).prefix(4).compactMap(\.coverURL))
            VStack(alignment: .leading, spacing: 2) {
                Text("我喜欢")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(library.likedCollection.itemCount) 首本地收藏")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
    }

    private func folderTitle(_ folderId: Int) -> String {
        folders.first { $0.id == folderId }?.title
            ?? library.remoteCollections().first { $0.remoteId == folderId }?.name
            ?? "收藏夹"
    }

    private func favoriteFolderTile(_ folder: BiliClient.FavFolder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MagazineArtworkCollage(urls: folderPreviewURLs[folder.id] ?? [])
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(folder.media_count) 个内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
    }

    /// 拉取收藏夹列表，并在首次进入时恢复上次打开的夹。
    private func load() async {
        await library.loadIfNeeded()
        guard !requestInFlight else { return }
        guard CookieStore.isLoggedIn, let accountID = CookieStore.mid else { return }
        let generation = authenticationGeneration
        requestInFlight = true
        loading = folders.isEmpty
        defer {
            if authenticationGeneration == generation {
                loading = false
                requestInFlight = false
            }
        }
        errorMessage = nil
        do {
            let loadedFolders = try await BiliClient().favFolders()
            guard authenticationGeneration == generation,
                  CookieStore.mid == accountID else { return }
            folders = loadedFolders
            if !restoredLastFolder,
               path.isEmpty,
               let last = FavoriteManager.shared.lastFolderId,
               folders.contains(where: { $0.id == last }) {
                path = [.remote(last)]
            }
            restoredLastFolder = true
        } catch {
            guard !Task.isCancelled,
                  authenticationGeneration == generation,
                  CookieStore.mid == accountID else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// 只为已经进入可视区域的收藏夹取前四张图，避免目录页抢占详情与播放请求。
    private func loadPreview(for folder: BiliClient.FavFolder) async {
        guard folder.media_count > 0,
              folderPreviewURLs[folder.id] == nil,
              let accountID = CookieStore.mid else { return }
        let generation = authenticationGeneration
        let page = try? await BiliClient().favItems(folderId: folder.id, page: 1, pageSize: 4)
        guard !Task.isCancelled,
              authenticationGeneration == generation,
              CookieStore.mid == accountID else { return }
        folderPreviewURLs[folder.id] = (page?.medias ?? [])
            .filter { $0.attr == 0 }
            .compactMap { URL(string: $0.cover) }
    }
}

/// 收藏夹内容,分页加载,点击播放。
struct FavFolderDetailView: View {
    let folderId: Int
    let title: String
    @Environment(PlayerEngine.self) private var engine
    @State private var tracks: [Track] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var trackTapTrigger = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let first = tracks.first {
                    Button {
                        playTrack(at: 0)
                    } label: {
                        MagazineTrackTile(
                            track: first,
                            isPlaying: isCurrent(first),
                            prominent: true)
                    }
                    .buttonStyle(MusicRowButtonStyle())
                    .contextMenu { trackMenu(first, index: 0) } preview: {
                        MagazineArtwork(url: first.coverURL, pixelWidth: 640)
                            .frame(width: 320)
                    }
                }

                if tracks.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        MusicSectionHeader(title: "曲目", subtitle: "\(tracks.count) 首已加载")
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ],
                            alignment: .leading,
                            spacing: 18
                        ) {
                            ForEach(Array(tracks.dropFirst().enumerated()), id: \.element.id) { offset, track in
                                let index = offset + 1
                                Button {
                                    playTrack(at: index)
                                } label: {
                                    MagazineTrackTile(track: track, isPlaying: isCurrent(track))
                                }
                                .buttonStyle(MusicRowButtonStyle())
                                .contextMenu { trackMenu(track, index: index) } preview: {
                                    MagazineArtwork(url: track.coverURL, pixelWidth: 640)
                                        .frame(width: 320)
                                }
                                .onAppear {
                                    if track == tracks.last { Task { await loadMore() } }
                                }
                            }
                        }
                    }
                }

                loadingAndErrorFooter
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .accessibilityIdentifier("favoriteFolderDetail")
        .background(AppTheme.background.ignoresSafeArea())
        .sensoryFeedback(.intent(.lightImpact), trigger: trackTapTrigger)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if loading && tracks.isEmpty {
                ProgressView()
            } else if tracks.isEmpty && errorMessage == nil {
                ContentUnavailableView("没有可播放音乐", systemImage: "music.note.list",
                                       description: Text("这个收藏夹里暂时没有符合音乐筛选的内容"))
            }
        }
        .task {
            await LibraryStore.shared.loadIfNeeded()
            if CookieStore.isLoggedIn {
                if tracks.isEmpty { await loadMore() }
            } else if tracks.isEmpty {
                tracks = LibraryStore.shared.tracks(forRemoteFolder: folderId).filter(MusicFilter.isMusic)
            }
        }
        .refreshable { await reload() }
    }

    @ViewBuilder
    private var loadingAndErrorFooter: some View {
        if loading && !tracks.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(minHeight: 64)
        } else if let errorMessage, !tracks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("加载更多失败", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.headline)
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("重试加载") {
                    Task { await loadMore() }
                }
                .buttonStyle(.bordered)
            }
        } else if hasMore, !tracks.isEmpty {
            Button("加载更多", systemImage: "arrow.down.circle") {
                Task { await loadMore() }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
    }

    private func playTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        trackTapTrigger += 1
        Task { await engine.play(tracks: tracks, startAt: index) }
    }

    private func isCurrent(_ track: Track) -> Bool {
        engine.current.map { track.key.matches($0) } ?? false
    }

    @ViewBuilder
    private func trackMenu(_ track: Track, index: Int) -> some View {
        Button {
            Task { await engine.playRadio(seed: track) }
        } label: {
            Label("电台播放", systemImage: PlayerEngine.QueueMode.radio.icon)
        }
        Button {
            Task { await engine.play(tracks: tracks, startAt: index, queueMode: .shuffle) }
        } label: {
            Label("随机播放这个收藏夹", systemImage: PlayerEngine.QueueMode.shuffle.icon)
        }
    }

    /// 下拉刷新：重置分页状态后从第一页重新加载。
    private func reload() async {
        guard !loading else { return }
        page = 1
        hasMore = true
        tracks = []
        errorMessage = nil
        await loadMore()
    }

    /// 分页加载收藏夹内容，过滤失效稿件与非音乐。
    /// 单页可能被「失效稿件 + 非音乐」双重过滤掏空:循环拉页直到有新曲目或没有更多,
    /// 连续 3 页空页则先停(与 SearchStore 的连跳空批策略对齐),由底部「加载更多」继续。
    private func loadMore() async {
        guard hasMore, !loading else { return }
        guard let accountID = CookieStore.mid else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            var newTracks: [Track] = []
            for _ in 0..<3 {
                let result = try await BiliClient().favItems(folderId: folderId, page: page)
                guard !Task.isCancelled, CookieStore.mid == accountID else { return }
                page += 1
                hasMore = result.has_more
                newTracks = (result.medias ?? [])
                    .filter { $0.attr == 0 }   // 跳过已失效的收藏
                    .map(Track.init(fav:))
                    .filter(MusicFilter.isMusic)
                if !newTracks.isEmpty || !hasMore { break }
            }
            guard !newTracks.isEmpty else { return }
            tracks += newTracks
            FavoriteManager.shared.markLoaded(folderId: folderId, title: title, tracks: tracks)
            engine.preload(tracks: newTracks, limit: 2, delay: .milliseconds(700))
        } catch {
            guard !Task.isCancelled, CookieStore.mid == accountID else { return }
            if tracks.isEmpty {
                tracks = LibraryStore.shared.tracks(forRemoteFolder: folderId).filter(MusicFilter.isMusic)
            }
            errorMessage = error.localizedDescription
        }
    }
}

/// 本地「我喜欢」，未登录也可播放。
struct LikedLibraryView: View {
    @Environment(PlayerEngine.self) private var engine
    private let library = LibraryStore.shared
    @State private var trackTapTrigger = 0

    var body: some View {
        let tracks = library.tracks(in: LibraryCollection.likedID)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        trackTapTrigger += 1
                        Task { await engine.play(tracks: tracks, startAt: index) }
                    } label: {
                        TrackRow(
                            track: track,
                            isPlaying: engine.current.map { track.key.matches($0) } ?? false)
                    }
                    .buttonStyle(MusicRowButtonStyle())
                    .contextMenu {
                        Button {
                            Task { await engine.playRadio(seed: track) }
                        } label: {
                            Label("电台播放", systemImage: PlayerEngine.QueueMode.radio.icon)
                        }
                        Button(role: .destructive) {
                            library.toggleLiked(track)
                        } label: {
                            Label("从我喜欢移除", systemImage: "heart.slash")
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("我喜欢")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.intent(.lightImpact), trigger: trackTapTrigger)
        .overlay {
            if tracks.isEmpty {
                ContentUnavailableView(
                    "还没有喜欢的歌",
                    systemImage: "heart",
                    description: Text("未登录时点收藏会加入这里；登录后收藏到 B 站也会写入本地库。"))
            }
        }
        .task { await library.loadIfNeeded() }
    }
}
