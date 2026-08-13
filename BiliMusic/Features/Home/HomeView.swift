import Foundation
import SwiftUI

/// 封面驱动的私人音乐库。首页不生成推荐，优先展示持久化收藏快照、缓存和播放历史，
/// 再在后台用用户指定的 B 站收藏夹补齐封面。
struct HomeView: View {
    @Environment(PlayerEngine.self) private var engine
    @Binding var showSettings: Bool
    @AppStorage(SettingsView.recommendFolderKey) private var libraryFolderId = 0
    @State private var tracks: [Track] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var trackTapTrigger = 0
    @State private var activeLoadID = UUID()

    init(showSettings: Binding<Bool> = .constant(false)) {
        _showSettings = showSettings
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                Group {
                    if tracks.isEmpty {
                        emptyContent
                    } else {
                        coverWall
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 28)
            }
            .accessibilityIdentifier("homeList")
            .background(AppTheme.background.ignoresSafeArea())
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

            HStack(spacing: 10) {
                Button {
                    guard !tracks.isEmpty else { return }
                    trackTapTrigger += 1
                    Task {
                        await engine.play(
                            tracks: tracks,
                            startAt: Int.random(in: tracks.indices),
                            queueMode: .shuffle)
                    }
                } label: {
                    Image(systemName: "shuffle")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(tracks.isEmpty)
                .accessibilityLabel("随机播放资料库")

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityLabel("设置")
            }
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
        .sensoryFeedback(.intent(.lightImpact), trigger: trackTapTrigger)
    }

    private var coverWall: some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(coverGroups.enumerated()), id: \.offset) { groupIndex, group in
                if let featured = group.first {
                    coverTile(for: featured, featured: true)
                        .accessibilityIdentifier("homeTrackRow\(featured.index)")
                }

                coverPair(Array(group.dropFirst().prefix(2)), groupIndex: groupIndex, row: 0)
                coverPair(Array(group.dropFirst(3).prefix(2)), groupIndex: groupIndex, row: 1)
            }
        }
    }

    @ViewBuilder
    private func coverPair(_ pair: [CoverLibraryItem], groupIndex: Int, row: Int) -> some View {
        if !pair.isEmpty {
            HStack(spacing: 8) {
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
            trackTapTrigger += 1
            Task { await engine.play(tracks: tracks, startAt: index) }
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
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if isCurrent {
                    Image(systemName: engine.state == .playing ? "waveform" : "pause.fill")
                        .font(.system(size: featured ? 17 : 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(featured ? 12 : 8)
                        .shadow(color: .black.opacity(0.55), radius: 5)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.82), lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
