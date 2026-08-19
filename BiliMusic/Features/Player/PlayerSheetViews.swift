import AVKit
import SwiftUI

struct LyricsOffsetSheet: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var alignedTick = 0
    @State private var didBeginOffsetEditing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(offsetTitle)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("lyricsOffsetValue")

                Slider(
                    value: offsetBinding,
                    in: -10...10,
                    step: 0.05,
                    onEditingChanged: persistIfNeeded
                )
                .tint(AppTheme.accent)
                .accessibilityLabel("歌词偏移")
                .accessibilityIdentifier("lyricsOffsetControl")

                HStack {
                    Text("延后")
                    Spacer()
                    Text("提前")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("自动对齐") {
                    Task { await engine.autoAlignLyricOffset() }
                }
                .disabled(!engine.canAutoAlignLyricOffset)
                .accessibilityIdentifier("lyricsAutoAlignButton")

                Button("重置") {
                    engine.resetLyricOffset()
                }
                .disabled(engine.lyricOffsetMilliseconds == 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityIdentifier("lyricsOffsetSheet")
            .navigationTitle("歌词校准")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.intent(.selection), trigger: alignedTick)
    }

    private var offsetTitle: String {
        let seconds = Double(engine.lyricOffsetMilliseconds) / 1000
        if abs(seconds) < 0.001 { return "已对齐" }
        if seconds > 0 { return String(format: "提前 %.2f 秒", seconds) }
        return String(format: "延后 %.2f 秒", -seconds)
    }

    private var offsetBinding: Binding<Double> {
        Binding(
            get: { Double(engine.lyricOffsetMilliseconds) / 1000 },
            set: { newValue in
                let snapped = abs(newValue) < 0.08 ? 0 : newValue
                let milliseconds = Int((snapped * 1000).rounded())
                if milliseconds == 0, engine.lyricOffsetMilliseconds != 0 {
                    alignedTick += 1
                }
                engine.setLyricOffset(milliseconds: milliseconds, persist: false)
            }
        )
    }

    private func persistIfNeeded(_ editing: Bool) {
        if editing {
            didBeginOffsetEditing = true
            return
        }
        guard didBeginOffsetEditing else { return }
        didBeginOffsetEditing = false
        engine.setLyricOffset(milliseconds: engine.lyricOffsetMilliseconds, persist: true)
    }
}

struct ImportLyricsSheet: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var importText = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $importText)
                .padding()
                .navigationTitle("导入歌词")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("导入") {
                            Task {
                                await engine.importPlainLyrics(importText)
                                dismiss()
                            }
                        }
                        .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}

struct LyricsSearchSheet: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    TextField("歌名或歌手", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { search() }

                    Button("搜索") { search() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                if engine.lyricsLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
                if let error = engine.lyricSearchError, !engine.lyricSearchResults.isEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                if engine.lyricSearchResults.isEmpty, !engine.lyricsLoading {
                    ContentUnavailableView(
                        "没有候选",
                        systemImage: "magnifyingglass",
                        description: Text(engine.lyricSearchError ?? "会同时搜索网易云、QQ、酷狗、LRCLIB 和 VocaDB。"))
                } else if !engine.lyricSearchResults.isEmpty {
                    List(engine.lyricSearchResults, id: \.stableID) { result in
                        Button {
                            Task {
                                await engine.selectLyricsResult(result)
                                if engine.lyricsDocument != nil, engine.lyricSearchError == nil {
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(spacing: 5) {
                                    Text(result.provider.displayName)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.fill.tertiary, in: Capsule())
                                    if result.timingKindHint == .word {
                                        Text(MetingLyricsClient.hasReliableWordTiming(
                                            result,
                                            expectedDuration: engine.current?.duration
                                        ) ? "逐字" : "逐字\n时长不符")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.tint)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(candidateSubtitle(for: result))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(engine.lyricsLoading)
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
                if let track = engine.current {
                    let metadata = TrackMetadataStore.shared.entry(for: track)?.metadata
                    query = LyricsAutoMatchGate.defaultSearchKeyword(
                        track: track,
                        metadata: metadata,
                        lastKeyword: engine.lyricSearchKeyword)
                }
                if engine.lyricSearchResults.isEmpty {
                    await engine.searchLyrics(keyword: query)
                }
            }
        }
    }

    private func search() {
        Task {
            await engine.searchLyrics(keyword: query)
        }
    }

    private func candidateSubtitle(for result: LyricsSearchResult) -> String {
        let metadata = engine.current.flatMap { TrackMetadataStore.shared.entry(for: $0)?.metadata }
        let scope = LyricsVersionClassifier.scope(
            for: result,
            originalArtists: metadata?.originalArtists ?? [],
            coverPerformers: metadata?.coverPerformers ?? [],
            isCoverSearch: metadata?.isCover == true)
        let scopeLabel: String
        switch scope {
        case .exactCover: scopeLabel = "翻唱版"
        case .sameRecording: scopeLabel = "当前版本"
        case .canonicalOriginal: scopeLabel = "原唱"
        case .textOnlyFallback: scopeLabel = "文本候选"
        case .manual: scopeLabel = "手动"
        }
        let duration = result.duration.map { "\($0)s" } ?? "时长未知"
        return [scopeLabel, result.artist, duration]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

struct TrackIdentityEditorSheet: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var originals = ""
    @State private var covers = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("干净歌名", text: $title)
                TextField("原唱，用逗号分隔", text: $originals)
                TextField("翻唱者，用逗号分隔", text: $covers)
            }
            .navigationTitle("手动修正")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            await engine.applyManualTrackIdentity(
                                canonicalTitle: title,
                                originalArtists: splitNames(originals),
                                coverPerformers: splitNames(covers))
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let track = engine.current {
                    let stored = TrackMetadataStore.shared.entry(for: track)?.metadata
                    title = LyricsAutoMatchGate.searchTitle(track: track, metadata: stored)
                        ?? stored?.canonicalTitle
                        ?? track.title
                    originals = stored?.originalArtists.joined(separator: "，") ?? ""
                    covers = stored?.coverPerformers.joined(separator: "，") ?? ""
                }
            }
        }
    }

    private func splitNames(_ value: String) -> [String] {
        value
            .split(whereSeparator: { ",，、/".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
