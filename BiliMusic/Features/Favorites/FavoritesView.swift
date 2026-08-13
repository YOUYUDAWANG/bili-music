import SwiftUI

/// 收藏夹列表(B 站收藏夹当歌单用)。
struct FavoritesView: View {
    @State private var folders: [BiliClient.FavFolder] = []
    @State private var path: [Int] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var requestInFlight = false
    @State private var restoredLastFolder = false
    @State private var authenticationGeneration = UUID()
    @State private var folderPreviewURLs: [Int: [URL]] = [:]

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
                    ForEach(folders) { folder in
                        NavigationLink(value: folder.id) {
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
            .navigationDestination(for: Int.self) { folderId in
                FavFolderDetailView(
                    folderId: folderId,
                    title: folders.first { $0.id == folderId }?.title ?? "收藏夹")
            }
            .overlay {
                if loading {
                    ProgressView()
                } else if !CookieStore.isLoggedIn {
                    ContentUnavailableView("需要登录", systemImage: "person.crop.circle.badge.questionmark",
                                           description: Text("去设置页扫码登录后,这里会显示你的 B 站收藏夹"))
                } else if let errorMessage, folders.isEmpty {
                    ContentUnavailableView(
                        "收藏夹加载失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage))
                } else if folders.isEmpty && errorMessage == nil {
                    ContentUnavailableView("没有收藏夹", systemImage: "star",
                                           description: Text("在 B 站收藏的视频会出现在这里"))
                }
            }
            .task { await load() }
            .onChange(of: path) { _, newValue in
                if let folderId = newValue.last {
                    let title = folders.first { $0.id == folderId }?.title ?? "收藏夹"
                    FavoriteManager.shared.remember(folderId: folderId, title: title)
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
                if CookieStore.isLoggedIn {
                    Task { await load() }
                }
            }
        }
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
        guard !requestInFlight, let accountID = CookieStore.mid else { return }
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
                path = [last]
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
                    .contextMenu { trackMenu(first, index: 0) }
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
                                .contextMenu { trackMenu(track, index: index) }
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
            if tracks.isEmpty { await loadMore() }
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
                    .map { item in
                        Track(bvid: item.bvid, title: item.title, artist: item.upper.name,
                              coverURL: URL(string: item.cover), duration: item.duration)
                    }
                    .filter(MusicFilter.isMusic)
                if !newTracks.isEmpty || !hasMore { break }
            }
            guard !newTracks.isEmpty else { return }
            tracks += newTracks
            FavoriteManager.shared.markLoaded(folderId: folderId, title: title, tracks: tracks)
            engine.preload(tracks: newTracks, limit: 2, delay: .milliseconds(700))
        } catch {
            guard !Task.isCancelled, CookieStore.mid == accountID else { return }
            errorMessage = error.localizedDescription
        }
    }
}
