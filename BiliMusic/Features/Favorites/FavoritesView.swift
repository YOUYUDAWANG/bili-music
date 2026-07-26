import SwiftUI

/// 收藏夹列表(B 站收藏夹当歌单用)。
struct FavoritesView: View {
    @State private var folders: [BiliClient.FavFolder] = []
    @State private var path: [Int] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var restoredLastFolder = false
    @State private var authenticationGeneration = UUID()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.error)
                            .font(.caption)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                    }
                    ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                        NavigationLink(value: folder.id) {
                            favoriteFolderRow(folder)
                        }
                        .buttonStyle(MusicRowButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded {
                            FavoriteManager.shared.remember(folderId: folder.id, title: folder.title)
                        })

                        if index != folders.count - 1 {
                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 96)
            }
            .background(AppTheme.groupedBackground)
            .navigationTitle("收藏夹")
            .navigationBarTitleDisplayMode(.inline)
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
                path = []
                loading = false
                errorMessage = nil
                restoredLastFolder = false
                if CookieStore.isLoggedIn {
                    Task { await load() }
                }
            }
        }
    }

    private func favoriteFolderRow(_ folder: BiliClient.FavFolder) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppTheme.accent.opacity(0.12))
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(folder.media_count) 个内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// 拉取收藏夹列表，并在首次进入时恢复上次打开的夹。
    private func load() async {
        guard let accountID = CookieStore.mid else { return }
        let generation = authenticationGeneration
        loading = folders.isEmpty
        defer {
            if authenticationGeneration == generation {
                loading = false
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
            LazyVStack(alignment: .leading, spacing: 0) {
                // 首屏失败时在顶部提示;分页失败改在底部展示(用户正停在列表底部)
                if let errorMessage, tracks.isEmpty {
                    Text(errorMessage)
                        .foregroundStyle(AppTheme.error)
                        .font(.caption)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        trackTapTrigger += 1
                        Task { await engine.play(tracks: tracks, startAt: index) }
                    } label: {
                        TrackRow(track: track, isPlaying: engine.current.map { track.key.matches($0) } ?? false)
                    }
                    .buttonStyle(MusicRowButtonStyle())
                    .contextMenu {
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
                    .onAppear {
                        if track == tracks.last { Task { await loadMore() } }
                    }

                    if index != tracks.count - 1 {
                        Divider()
                            .padding(.leading, 82)
                    }
                }
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else if let errorMessage, !tracks.isEmpty {
                    // 分页失败:在底部就地提示并可重试(参照搜索页 paginationControl 的样式)
                    VStack(spacing: 8) {
                        Text("加载更多失败")
                            .font(.caption.weight(.semibold))
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            Task { await loadMore() }
                        } label: {
                            Text("重试加载")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if hasMore, !tracks.isEmpty {
                    // 连跳空页达到上限时 onAppear 不会对最后一行重新触发,提供手动继续入口
                    Button {
                        Task { await loadMore() }
                    } label: {
                        Text("加载更多")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 96)
        }
        .sensoryFeedback(.intent(.lightImpact), trigger: trackTapTrigger)
        .background(AppTheme.groupedBackground)
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
