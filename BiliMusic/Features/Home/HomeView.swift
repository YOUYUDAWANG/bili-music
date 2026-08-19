import Foundation
import SwiftUI

/// 封面驱动的私人音乐库。收藏夹旧封面和发现新歌混在同一条瀑布流里；
/// 发现优先走会换页的首页推荐流，并记住最近展示过的 BV。
struct HomeView: View {
    @Environment(PlayerEngine.self) private var engine
    @Binding var showSettings: Bool
    let openPlayer: () -> Void
    @AppStorage(SettingsView.recommendFolderKey) private var libraryFolderId = 0
    @State private var tracks: [Track] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var trackTapTrigger = 0
    @State private var activeLoadID = UUID()
    @State private var discoveryTask: Task<Void, Never>?

    init(
        showSettings: Binding<Bool> = .constant(false),
        openPlayer: @escaping () -> Void = {}
    ) {
        _showSettings = showSettings
        self.openPlayer = openPlayer
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
                colors: [AppTheme.background.opacity(0.88), AppTheme.background.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 72)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)

            topControls
        }
        .background(AppTheme.background.ignoresSafeArea())
        .sensoryFeedback(.intent(.lightImpact), trigger: trackTapTrigger)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topControls: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 0) {
                Button {
                    guard !tracks.isEmpty else { return }
                    playSelection(startAt: Int.random(in: tracks.indices), queueMode: .shuffle)
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
        let isCurrent = engine.current.map { track.key.matches($0) } ?? false
        let pixelWidth = featured ? 1_200 : 620
        return Button {
            playSelection(startAt: index)
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
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                cancelDiscovery()
                Task { await engine.playRadio(seed: track) }
            } label: {
                Label("电台播放", systemImage: PlayerEngine.QueueMode.radio.icon)
            }
            Button {
                playSelection(startAt: index, queueMode: .shuffle)
            } label: {
                Label("随机播放资料库", systemImage: PlayerEngine.QueueMode.shuffle.icon)
            }
            Button {
                engine.appendToQueue([track])
            } label: {
                Label("添加到队列", systemImage: "text.badge.plus")
            }
        } preview: {
            MagazineArtwork(url: track.coverURL, pixelWidth: 640)
                .frame(width: 320)
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
            ? "在设置里选择一个音乐收藏夹。封面墙会把收藏夹和一批新歌混在一起。"
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
        var library = savedSnapshot?.tracks ?? []
        let savedDiscovery = savedSnapshot?.discoveryTracks ?? []
        if !library.isEmpty {
            present(library: library, discovery: savedDiscovery)
            loading = false
        }

        await CacheStore.shared.loadIfNeeded()
        await PlaybackHistoryStore.shared.loadIfNeeded()
        await LibraryStore.shared.loadIfNeeded()

        guard !Task.isCancelled, activeLoadID == loadID else { return }
        let storedLibrary = resolvedStoredLibrary()
        if !storedLibrary.isEmpty {
            library = deduplicated(library + storedLibrary)
            present(library: library, discovery: savedDiscovery)
            loading = false
        } else if library.isEmpty {
            let fallback = deduplicated(
                CacheStore.shared.entries.map(\.track)
                    + PlaybackHistoryStore.shared.entries.map(\.track)
            )
            if !fallback.isEmpty {
                library = fallback
                tracks = fallback
                loading = false
            }
        }

        guard CookieStore.isLoggedIn, let accountID = CookieStore.mid else {
            loading = false
            scheduleDiscovery(
                library: library,
                savedDiscovery: savedDiscovery,
                forceRefresh: forceRemoteRefresh,
                loadID: loadID,
                folderID: savedSnapshot?.folderID)
            return
        }
        if !forceRemoteRefresh,
           let savedAt = savedSnapshot?.savedAt,
           Date().timeIntervalSince(savedAt) < 15 * 60,
           !library.isEmpty {
            loading = false
            scheduleDiscovery(
                library: library,
                savedDiscovery: savedDiscovery,
                forceRefresh: false,
                loadID: loadID,
                folderID: savedSnapshot?.folderID)
            return
        }

        do {
            let client = BiliClient()
            let folders = try await client.favFolders()
            guard !Task.isCancelled, activeLoadID == loadID, CookieStore.mid == accountID else { return }
            guard let folder = selectedFolder(from: folders) else {
                loading = false
                scheduleDiscovery(
                    library: library,
                    savedDiscovery: savedDiscovery,
                    forceRefresh: forceRemoteRefresh,
                    loadID: loadID,
                    folderID: savedSnapshot?.folderID)
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
                    .map(Track.init(fav:))
                favoriteTracks = deduplicated(favoriteTracks + batch)
                hasMore = result.has_more
                page += 1

                if !favoriteTracks.isEmpty {
                    library = favoriteTracks
                    present(library: library, discovery: savedDiscovery)
                    loading = false
                }

                if !forceRemoteRefresh, favoriteTracks.count >= 240 {
                    break
                }
            }

            if !favoriteTracks.isEmpty {
                FavoriteManager.shared.markLoaded(folderId: folder.id, title: folder.title, tracks: favoriteTracks)
                await CoverLibrarySnapshotStore.shared.save(
                    folderID: folder.id,
                    tracks: favoriteTracks,
                    discoveryTracks: savedDiscovery)
                engine.preload(tracks: favoriteTracks, limit: 2, delay: .milliseconds(900))
            }
            scheduleDiscovery(
                library: library,
                savedDiscovery: savedDiscovery,
                forceRefresh: forceRemoteRefresh,
                loadID: loadID,
                folderID: folder.id)
        } catch {
            guard !Task.isCancelled, activeLoadID == loadID, CookieStore.mid == accountID else { return }
            if tracks.isEmpty {
                errorMessage = error.localizedDescription
            }
            scheduleDiscovery(
                library: library,
                savedDiscovery: savedDiscovery,
                forceRefresh: forceRemoteRefresh,
                loadID: loadID,
                folderID: savedSnapshot?.folderID)
        }
        loading = false
    }

    private func resolvedStoredLibrary() -> [Track] {
        if libraryFolderId != 0 {
            return LibraryStore.shared.tracks(forRemoteFolder: libraryFolderId)
        }
        if let lastFolderId = FavoriteManager.shared.lastFolderId {
            return LibraryStore.shared.tracks(forRemoteFolder: lastFolderId)
        }
        return LibraryStore.shared.tracks(in: LibraryCollection.likedID)
    }

    private func playSelection(startAt index: Int, queueMode: PlayerEngine.QueueMode? = nil) {
        guard tracks.indices.contains(index) else { return }
        cancelDiscovery()
        trackTapTrigger += 1
        if let queueMode {
            Task {
                await engine.play(tracks: tracks, startAt: index, queueMode: queueMode)
            }
        } else {
            engine.beginPlayback(tracks: tracks, startAt: index)
            openPlayer()
        }
    }

    private func cancelDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
    }

    private func scheduleDiscovery(
        library: [Track],
        savedDiscovery: [Track],
        forceRefresh: Bool,
        loadID: UUID,
        folderID: Int?
    ) {
        cancelDiscovery()
        let delay: Duration = forceRefresh ? .milliseconds(800) : .seconds(2)
        discoveryTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, activeLoadID == loadID else { return }
            await applyDiscovery(
                library: library,
                savedDiscovery: savedDiscovery,
                forceRefresh: forceRefresh,
                loadID: loadID,
                folderID: folderID)
        }
    }

    private func present(library: [Track], discovery: [Track]) {
        let cleanLibrary = deduplicated(library)
        let cleanDiscovery = deduplicated(discovery)
        tracks = cleanDiscovery.isEmpty
            ? cleanLibrary
            : HomeCoverMixer.mix(library: cleanLibrary, discovery: cleanDiscovery)
    }

    private func applyDiscovery(
        library: [Track],
        savedDiscovery: [Track],
        forceRefresh: Bool,
        loadID: UUID,
        folderID: Int?
    ) async {
        if !savedDiscovery.isEmpty {
            present(library: library, discovery: savedDiscovery)
        }
        await RecommendationMemory.shared.loadIfNeeded()
        let memoryKeys = await RecommendationMemory.shared.recentKeys()
        let excluded = Set(library.map(\.key)).union(memoryKeys)
        let discovery = await RecommendationEngine().recommendations(
            mode: .home,
            context: .init(current: engine.current, excludedKeys: excluded),
            limit: HomeCoverMixer.discoveryBudget(forLibraryCount: library.count),
            policy: .home(trigger: forceRefresh ? .manualRefresh : .initialHomeLoad))
        guard !Task.isCancelled, activeLoadID == loadID else { return }
        let usableDiscovery = deduplicated(discovery)
        if usableDiscovery.isEmpty {
            if !savedDiscovery.isEmpty {
                present(library: library, discovery: savedDiscovery)
            }
            return
        }
        await RecommendationMemory.shared.record(usableDiscovery.map(\.bvid))
        present(library: library, discovery: usableDiscovery)
        if let folderID {
            await CoverLibrarySnapshotStore.shared.save(
                folderID: folderID,
                tracks: deduplicated(library),
                discoveryTracks: usableDiscovery)
        }
        engine.preload(tracks: Array(tracks.prefix(4)), limit: 2, delay: .milliseconds(900))
    }

    private func selectedFolder(from folders: [BiliClient.FavFolder]) -> BiliClient.FavFolder? {
        let nonEmpty = folders.filter { $0.media_count > 0 }
        return FavoriteFolderSelector.targetFolder(from: nonEmpty, preferredId: libraryFolderId)
            ?? FavoriteFolderSelector.targetFolder(from: folders, preferredId: libraryFolderId)
    }

    private func deduplicated(_ source: [Track]) -> [Track] {
        Track.uniquedByBVIDPreferringCID(source.filter { $0.coverURL != nil })
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
