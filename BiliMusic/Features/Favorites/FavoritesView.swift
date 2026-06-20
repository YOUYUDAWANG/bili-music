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
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
                ForEach(folders) { folder in
                    NavigationLink(value: folder.id) {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(AppTheme.accent.opacity(0.14))
                                .frame(width: 46, height: 46)
                                .overlay {
                                    Image(systemName: "music.note.list")
                                        .foregroundStyle(AppTheme.accent)
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.title)
                                    .font(.subheadline)
                                Text("\(folder.media_count) 个内容")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        FavoriteManager.shared.remember(folderId: folder.id, title: folder.title)
                    })
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.groupedBackground)
            .navigationTitle("收藏夹")
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

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    Task { await engine.play(tracks: tracks, startAt: index) }
                } label: {
                    TrackRow(track: track, isPlaying: engine.current?.bvid == track.bvid)
                }
                .buttonStyle(.plain)
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
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.groupedBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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
            tracks += (result.medias ?? [])
                .filter { $0.attr == 0 }   // 跳过已失效的收藏
                .map { item in
                    Track(bvid: item.bvid, title: item.title, artist: item.upper.name,
                          coverURL: URL(string: item.cover), duration: item.duration)
                }
                .filter(MusicFilter.isMusic)
            FavoriteManager.shared.markLoaded(folderId: folderId, title: title, tracks: tracks)
            engine.preload(tracks: tracks)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
