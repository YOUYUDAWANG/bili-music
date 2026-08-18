import AVKit
import SwiftUI

// MARK: - Lyrics Sheet

struct LyricsSheetView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var showSearch = false
    @State private var showTranslation = true

    var body: some View {
        let active = currentLyricIndex
        return NavigationStack {
            Group {
                if engine.lyricsLoading && engine.lyrics.isEmpty {
                    ProgressView("正在从 \(engine.lyricProvider.displayName) 查找歌词")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if engine.lyrics.isEmpty {
                    ContentUnavailableView {
                        Label("暂无歌词", systemImage: "quote.bubble")
                    } description: {
                        Text(engine.lyricSearchError ?? "自动匹配失败，可以手动选择歌词来源。")
                    } actions: {
                        Button("手动搜索") { showSearch = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 30) {
                                ForEach(Array(engine.lyrics.enumerated()), id: \.element.id) { index, line in
                                    lyricRow(line, isActive: index == active)
                                        .id(line.id)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 96)
                        }
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.13),
                                    .init(color: .black, location: 0.82),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom)
                        }
                        .onChange(of: currentLyricIndex) { _, index in
                            guard let line = engine.lyrics[safe: index] else { return }
                            withAnimation(.easeInOut(duration: 0.28)) {
                                proxy.scrollTo(line.id, anchor: .center)
                            }
                        }
                        .task(id: engine.lyricsDocument?.result.stableID) {
                            guard let line = engine.lyrics[safe: currentLyricIndex] else { return }
                            proxy.scrollTo(line.id, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle(engine.lyricsDocument?.result.title ?? "歌词")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                lyricControls
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showSearch) {
                LyricsSearchSheet()
            }
        }
    }

    private func lyricRow(_ line: PlayerEngine.LyricLine, isActive: Bool) -> some View {
        Button {
            engine.seek(to: line)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                highlightedText(for: line, isActive: isActive)
                    .font(.system(size: isActive ? 30 : 24, weight: isActive ? .bold : .medium))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showTranslation,
                   let translation = line.translation,
                   !translation.isEmpty {
                    Text(translation)
                        .font(.system(size: isActive ? 16 : 14, weight: .medium))
                        .foregroundStyle(isActive ? AppTheme.label.opacity(0.72) : .secondary.opacity(0.68))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isActive ? 1 : 0.58)
        .accessibilityLabel(line.text)
        .accessibilityHint("跳转到这句歌词")
    }

    private func highlightedText(for line: PlayerEngine.LyricLine, isActive: Bool) -> Text {
        guard isActive, !line.words.isEmpty else {
            return Text(line.text).foregroundColor(isActive ? AppTheme.label : .secondary)
        }
        var attributed = AttributedString()
        for word in line.words {
            let isPast = engine.adjustedLyricTime >= word.from
            var segment = AttributedString(word.text)
            segment.foregroundColor = isPast ? AppTheme.label : AppTheme.label.opacity(0.34)
            attributed.append(segment)
        }
        return Text(attributed)
    }

    private var lyricControls: some View {
        HStack(spacing: 18) {
            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("手动匹配歌词")

            Button { engine.adjustLyricOffset(by: -500) } label: {
                Image(systemName: "minus")
            }
            .accessibilityLabel("歌词延后半秒")

            Button { engine.resetLyricOffset() } label: {
                Text(offsetLabel)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 48)
            }
            .accessibilityLabel("重置歌词偏移")
            .accessibilityIdentifier("lyricsOffsetControl")

            Button { engine.adjustLyricOffset(by: 500) } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("歌词提前半秒")

            if engine.lyrics.contains(where: { $0.translation?.isEmpty == false }) {
                Button { showTranslation.toggle() } label: {
                    Image(systemName: showTranslation ? "character.book.closed.fill" : "character.book.closed")
                }
                .accessibilityLabel(showTranslation ? "隐藏翻译" : "显示翻译")
            }
        }
        .font(.system(size: 18, weight: .semibold))
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private var offsetLabel: String {
        let seconds = Double(engine.lyricOffsetMilliseconds) / 1000
        return String(format: "%+.1fs", seconds)
    }

    private var currentLyricIndex: Int {
        guard !engine.lyrics.isEmpty else { return 0 }
        if let active = engine.lyrics.firstIndex(where: { line in
            engine.adjustedLyricTime >= line.from && engine.adjustedLyricTime < line.to
        }) {
            return active
        }
        return engine.lyrics.lastIndex { line in engine.adjustedLyricTime >= line.from } ?? 0
    }
}

private struct LyricsSearchSheet: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var provider: LyricsProvider = .netease

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    TextField("歌名或歌手", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { search() }

                    Menu(provider.displayName) {
                        ForEach(LyricsProvider.allCases) { value in
                            Button(value.displayName) {
                                provider = value
                                search()
                            }
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("搜索") { search() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                if engine.lyricsLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if engine.lyricSearchResults.isEmpty {
                    ContentUnavailableView(
                        "没有候选",
                        systemImage: "magnifyingglass",
                        description: Text(engine.lyricSearchError ?? "换一个关键词或歌词平台试试。"))
                } else {
                    List(engine.lyricSearchResults) { result in
                        Button {
                            Task {
                                await engine.selectLyricsResult(result)
                                if engine.lyricsDocument?.result.stableID == result.stableID {
                                    dismiss()
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text([result.artist, result.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("匹配歌词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .task {
                guard query.isEmpty else { return }
                query = engine.lyricSearchKeyword.isEmpty
                    ? (engine.current?.title ?? "")
                    : engine.lyricSearchKeyword
                provider = engine.lyricProvider
                if engine.lyricSearchResults.isEmpty {
                    await engine.searchLyrics(keyword: query, provider: provider)
                }
            }
        }
    }

    private func search() {
        Task {
            await engine.searchLyrics(keyword: query, provider: provider)
        }
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
            }
            .buttonStyle(.glass)
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
            }
            .buttonStyle(.glass)
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
    @Environment(\.dismiss) private var dismiss
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
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
