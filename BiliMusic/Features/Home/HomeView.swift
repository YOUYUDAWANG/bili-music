import Foundation
import SwiftUI

/// 封面驱动的私人音乐库。首页不生成推荐，优先展示持久化收藏快照、缓存和播放历史，
/// 再在后台用用户指定的 B 站收藏夹补齐封面。
struct HomeView: View {
    @Environment(PlayerEngine.self) private var engine
    @Binding var showSettings: Bool
    @Binding var isCoverPlayerPresented: Bool
    @Namespace private var coverTransitionNamespace
    @AppStorage(SettingsView.recommendFolderKey) private var libraryFolderId = 0
    @State private var tracks: [Track] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var trackTapTrigger = 0
    @State private var activeLoadID = UUID()
    @State private var presentedCoverPlayerID: String?
    @State private var isClosingCoverPlayer = false
    @State private var coverPlayerDismissTask: Task<Void, Never>?

    init(
        showSettings: Binding<Bool> = .constant(false),
        isCoverPlayerPresented: Binding<Bool> = .constant(false)
    ) {
        _showSettings = showSettings
        _isCoverPlayerPresented = isCoverPlayerPresented
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                Group {
                    if tracks.isEmpty {
                        emptyContent
                    } else {
                        coverWall
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 44)
            }
            .accessibilityIdentifier("homeList")
            .safeAreaPadding(.bottom, 8)
            .refreshable { await loadLibrary(forceRemoteRefresh: true) }
            .task {
                if tracks.isEmpty { await loadLibrary() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .biliAuthenticationDidChange)) { _ in
                tracks = []
                errorMessage = nil
                Task { await loadLibrary(forceRemoteRefresh: true) }
            }
            .onChange(of: libraryFolderId) { _, _ in
                Task { await loadLibrary(forceRemoteRefresh: true) }
            }

            LinearGradient(
                colors: [Color.black.opacity(0.65), Color.black.opacity(0.20), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 72)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)

            topControls

            if let sourceID = presentedCoverPlayerID {
                coverPlayerOverlay(sourceID: sourceID)
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .sensoryFeedback(.intent(.lightImpact), trigger: trackTapTrigger)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(presentedCoverPlayerID == nil ? .visible : .hidden, for: .tabBar)
        .onDisappear {
            coverPlayerDismissTask?.cancel()
        }
    }

    private func coverPlayerOverlay(sourceID: String) -> some View {
        NowPlayingView(isPresented: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .matchedGeometryEffect(
                id: sourceID,
                in: coverTransitionNamespace,
                properties: .frame,
                anchor: .center
            )
            .zIndex(10)
            .overlay(alignment: .top) {
                Button {
                    closeCoverPlayer()
                } label: {
                    Capsule()
                        .fill(Color.white.opacity(0.72))
                        .frame(width: 60, height: 5)
                        .frame(width: 100, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收起播放器")
                .accessibilityIdentifier("coverPlayerCloseButton")
            }
            .allowsHitTesting(!isClosingCoverPlayer)
    }

    private var coverPlayerAnimation: Animation {
        .spring(duration: 0.50, bounce: 0.08)
    }

    private func openCoverPlayer(sourceID: String) {
        guard presentedCoverPlayerID == nil, !isClosingCoverPlayer else { return }
        coverPlayerDismissTask?.cancel()
        isCoverPlayerPresented = true
        withAnimation(coverPlayerAnimation) {
            presentedCoverPlayerID = sourceID
        }
    }

    /// 动画层和手势层分离：播放器继续缩回原封面，但关闭一开始就不再拦截触摸。
    private func closeCoverPlayer() {
        guard presentedCoverPlayerID != nil, !isClosingCoverPlayer else { return }
        isClosingCoverPlayer = true
        coverPlayerDismissTask?.cancel()
        coverPlayerDismissTask = Task { @MainActor in
            // 先提交 allowsHitTesting(false)，再开始缩回，确保第一帧就把触摸交还给瀑布流。
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(coverPlayerAnimation) {
                presentedCoverPlayerID = nil
            }
            try? await Task.sleep(for: .milliseconds(520))
            guard !Task.isCancelled, presentedCoverPlayerID == nil else { return }
            isCoverPlayerPresented = false
            isClosingCoverPlayer = false
        }
    }

    private var topControls: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 0) {
                Button {
                    guard !tracks.isEmpty else { return }
                    trackTapTrigger += 1
                    let randomIndex = Int.random(in: tracks.indices)
                    Task {
                        await engine.play(
                            tracks: tracks,
                            startAt: randomIndex,
                            queueMode: .shuffle)
                    }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .frame(width: 42, height: 34)
                        .contentShape(Rectangle())
                }
                .disabled(tracks.isEmpty)
                .accessibilityLabel("随机播放资料库")

                Divider()
                    .frame(height: 14)
                    .background(Color.white.opacity(0.25))

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .frame(width: 42, height: 34)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("设置")
            }
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private var coverWall: some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(coverGroups.enumerated()), id: \.offset) { groupIndex, group in
                VStack(spacing: 4) {
                    if let featured = group.first {
                        coverTile(for: featured, featured: true)
                            .accessibilityIdentifier("homeTrackRow\(featured.index)")
                    }

                    coverPair(Array(group.dropFirst().prefix(2)), groupIndex: groupIndex, row: 0)
                    coverPair(Array(group.dropFirst(3).prefix(2)), groupIndex: groupIndex, row: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func coverPair(_ pair: [CoverLibraryItem], groupIndex: Int, row: Int) -> some View {
        if !pair.isEmpty {
            HStack(spacing: 4) {
                ForEach(pair) { item in
                    coverTile(for: item, featured: false)
                        .accessibilityIdentifier("homeTrackRow\(item.index)")
                }
                if pair.count == 1 {
                    Color.clear
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .accessibilityHidden(true)
                }
            }
            .id("\(groupIndex)-\(row)")
        }
    }

    private func coverTile(for item: CoverLibraryItem, featured: Bool) -> some View {
        let track = item.track
        let index = item.index
        let transitionSourceID = item.id
        let isCurrent = engine.current.map { track.key.matches($0) } ?? false
        let pixelWidth = featured ? 1_200 : 620
        return Button {
            trackTapTrigger += 1
            engine.beginPlayback(tracks: tracks, startAt: index)
            openCoverPlayer(sourceID: transitionSourceID)
        } label: {
            CachedAsyncImage(
                url: BiliArtworkURL.widescreenThumbnail(track.coverURL, width: pixelWidth),
                targetSize: featured ? CGSize(width: 760, height: 428) : CGSize(width: 360, height: 203)
            ) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Color.secondary.opacity(0.10)
                    Image(systemName: "music.note")
                        .font(featured ? .title : .body)
                        .foregroundStyle(.tertiary)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if isCurrent {
                    HomePlaybackProgressRail()
                }
            }
            .modifier(CoverTransitionSourceModifier(
                id: transitionSourceID,
                namespace: coverTransitionNamespace,
                isPlayerPresented: presentedCoverPlayerID == transitionSourceID
            ))
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isClosingCoverPlayer)
        .contextMenu {
            Button {
                Task { await engine.playRadio(seed: track) }
            } label: {
                Label("电台播放", systemImage: PlayerEngine.QueueMode.radio.icon)
            }
            Button {
                trackTapTrigger += 1
                Task {
                    await engine.play(tracks: tracks, startAt: index, queueMode: .shuffle)
                }
            } label: {
                Label("随机播放资料库", systemImage: PlayerEngine.QueueMode.shuffle.icon)
            }
            Button {
                engine.appendToQueue([track])
            } label: {
                Label("添加到队列", systemImage: "text.badge.plus")
            }
        }
        .accessibilityLabel("\(track.title)，\(track.artist)")
        .accessibilityValue(isCurrent ? "正在播放" : "")
    }

    @ViewBuilder
    private var emptyContent: some View {
        if loading {
            MusicLoadingBlock(title: "正在整理音乐封面…")
                .padding(.top, 80)
        } else {
            ContentUnavailableView {
                Label("还没有音乐封面", systemImage: "square.grid.2x2")
            } description: {
                Text(emptyMessage)
            } actions: {
                Button(CookieStore.isLoggedIn ? "重新载入" : "打开设置") {
                    if CookieStore.isLoggedIn {
                        Task { await loadLibrary(forceRemoteRefresh: true) }
                    } else {
                        showSettings = true
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 56)
        }
    }

    private var emptyMessage: String {
        if let errorMessage { return errorMessage }
        return CookieStore.isLoggedIn
            ? "在设置里选择一个音乐收藏夹，封面会成为首页的播放入口。"
            : "登录 B 站账号后选择音乐收藏夹，或先缓存几首歌曲。"
    }

    private var coverGroups: [[CoverLibraryItem]] {
        let indexedTracks = tracks.enumerated().map { CoverLibraryItem(index: $0.offset, track: $0.element) }
        return stride(from: 0, to: indexedTracks.count, by: 5).map { start in
            Array(indexedTracks[start..<min(start + 5, indexedTracks.count)])
        }
    }

    private func loadLibrary(forceRemoteRefresh: Bool = false) async {
#if DEBUG
        if UITestFixtures.enabled {
            tracks = UITestFixtures.homeTracks
            loading = false
            errorMessage = nil
            return
        }
#endif
        let loadID = UUID()
        activeLoadID = loadID
        loading = tracks.isEmpty
        errorMessage = nil

        let savedSnapshot = await CoverLibrarySnapshotStore.shared.load(preferredFolderID: libraryFolderId)
        guard !Task.isCancelled, activeLoadID == loadID else { return }
        let persisted = savedSnapshot?.tracks ?? []
        if !persisted.isEmpty {
            tracks = persisted
            loading = false
        }

        await CacheStore.shared.loadIfNeeded()
        await PlaybackHistoryStore.shared.loadIfNeeded()

        guard !Task.isCancelled, activeLoadID == loadID else { return }
        let localTracks = deduplicated(
            persisted
                + CacheStore.shared.entries.map(\.track)
                + PlaybackHistoryStore.shared.entries.map(\.track)
        )
        if !localTracks.isEmpty {
            tracks = localTracks
            loading = false
        }

        guard CookieStore.isLoggedIn, let accountID = CookieStore.mid else {
            loading = false
            return
        }
        if !forceRemoteRefresh,
           let savedAt = savedSnapshot?.savedAt,
           Date().timeIntervalSince(savedAt) < 15 * 60 {
            loading = false
            return
        }

        do {
            let client = BiliClient()
            let folders = try await client.favFolders()
            guard !Task.isCancelled, activeLoadID == loadID, CookieStore.mid == accountID else { return }
            guard let folder = selectedFolder(from: folders) else {
                loading = false
                return
            }

            var page = 1
            var hasMore = true
            var favoriteTracks: [Track] = []
            while hasMore, page <= 12 {
                let result = try await client.favItems(folderId: folder.id, page: page)
                guard !Task.isCancelled, activeLoadID == loadID, CookieStore.mid == accountID else { return }
                let batch = (result.medias ?? [])
                    .filter { $0.attr == 0 }
                    .map { item in
                        Track(
                            bvid: item.bvid,
                            title: item.title,
                            artist: item.upper.name,
                            coverURL: URL(string: item.cover),
                            duration: item.duration)
                    }
                favoriteTracks = deduplicated(favoriteTracks + batch)
                hasMore = result.has_more
                page += 1

                if !favoriteTracks.isEmpty {
                    tracks = deduplicated(favoriteTracks + localTracks)
                    loading = false
                }

                if !forceRemoteRefresh, favoriteTracks.count >= 240 {
                    break
                }
            }

            if !favoriteTracks.isEmpty {
                FavoriteManager.shared.markLoaded(folderId: folder.id, title: folder.title, tracks: favoriteTracks)
                await CoverLibrarySnapshotStore.shared.save(folderID: folder.id, tracks: favoriteTracks)
                engine.preload(tracks: favoriteTracks, limit: 2, delay: .milliseconds(900))
            }
        } catch {
            guard !Task.isCancelled, activeLoadID == loadID, CookieStore.mid == accountID else { return }
            if tracks.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        loading = false
    }

    private func selectedFolder(from folders: [BiliClient.FavFolder]) -> BiliClient.FavFolder? {
        let nonEmpty = folders.filter { $0.media_count > 0 }
        if libraryFolderId != 0,
           let selected = nonEmpty.first(where: { $0.id == libraryFolderId }) {
            return selected
        }
        if let lastFolderId = FavoriteManager.shared.lastFolderId,
           let last = nonEmpty.first(where: { $0.id == lastFolderId }) {
            return last
        }
        return nonEmpty.first(where: {
            $0.title.localizedCaseInsensitiveContains("music")
                || $0.title.contains("音乐")
                || $0.title.contains("歌曲")
        }) ?? nonEmpty.first
    }

    private func deduplicated(_ source: [Track]) -> [Track] {
        var seen = Set<String>()
        return source.filter { track in
            guard track.coverURL != nil else { return false }
            return seen.insert(track.id).inserted
        }
    }
}

/// 只让当前可见的一侧参与 matched geometry。封面占位始终留在 LazyVStack 中，
/// 因此播放器展开/收回和用户在收回期间滚动都不会改变瀑布流排版。
private struct CoverTransitionSourceModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let isPlayerPresented: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isPlayerPresented {
            content.opacity(0)
        } else {
            content.matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .frame,
                anchor: .center
            )
        }
    }
}

private struct HomePlaybackProgressRail: View {
    @Environment(PlayerEngine.self) private var engine

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.65)
                Color.white.opacity(0.95)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 3)
        .animation(.linear(duration: 0.45), value: progress)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var progress: CGFloat {
        guard engine.duration.isFinite, engine.duration > 0, engine.currentTime.isFinite else { return 0 }
        return CGFloat(min(max(engine.currentTime / engine.duration, 0), 1))
    }
}

private struct CoverLibraryItem: Identifiable {
    let index: Int
    let track: Track
    var id: String { "\(index)-\(track.id)" }
}

private struct CoverLibrarySnapshot: Codable {
    let folderID: Int
    let savedAt: Date
    let tracks: [Track]
}

private actor CoverLibrarySnapshotStore {
    static let shared = CoverLibrarySnapshotStore()

    private let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("cover-library.json")

    func load(preferredFolderID: Int) -> CoverLibrarySnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(CoverLibrarySnapshot.self, from: data),
              preferredFolderID == 0 || preferredFolderID == snapshot.folderID else {
            return nil
        }
        return snapshot
    }

    func save(folderID: Int, tracks: [Track]) {
        let snapshot = CoverLibrarySnapshot(
            folderID: folderID,
            savedAt: Date(),
            tracks: Array(tracks.prefix(480)))
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
