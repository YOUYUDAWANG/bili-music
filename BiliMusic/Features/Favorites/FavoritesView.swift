import SwiftUI

/// 收藏夹列表(B 站收藏夹当歌单用)。
struct FavoritesView: View {
    @State private var folders: [BiliClient.FavFolder] = []
    @State private var path: [Int] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var restoredLastFolder = false

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
        guard CookieStore.isLoggedIn else { return }
        loading = folders.isEmpty
        defer { loading = false }
        errorMessage = nil
        do {
            folders = try await BiliClient().favFolders()
            if !restoredLastFolder,
               path.isEmpty,
               let last = FavoriteManager.shared.lastFolderId,
               folders.contains(where: { $0.id == last }) {
                path = [last]
            }
            restoredLastFolder = true
        } catch {
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
                if let errorMessage {
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
                    .sensoryFeedback(.intent(.lightImpact), trigger: trackTapTrigger)
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
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 96)
        }
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
    }

    /// 分页加载收藏夹内容，过滤失效稿件与非音乐。
    private func loadMore() async {
        guard hasMore, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await BiliClient().favItems(folderId: folderId, page: page)
            page += 1
            hasMore = result.has_more
            let newTracks = (result.medias ?? [])
                .filter { $0.attr == 0 }   // 跳过已失效的收藏
                .map { item in
                    Track(bvid: item.bvid, title: item.title, artist: item.upper.name,
                          coverURL: URL(string: item.cover), duration: item.duration)
                }
                .filter(MusicFilter.isMusic)
            tracks += newTracks
            FavoriteManager.shared.markLoaded(folderId: folderId, title: title, tracks: tracks)
            engine.preload(tracks: newTracks, limit: 2, delay: .milliseconds(700))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
