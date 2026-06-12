import SwiftUI

/// 首页推荐:不用 B 站首页 feed(那是大杂烩)。种子优先从你的 B 站收藏夹随机抽取,
/// 再用「相关推荐」扩展,音乐关键词兜底。未登录/无收藏夹时回退到当前在播 + 最近缓存。
struct HomeView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var tracks: [Track] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var keywordIndex = 0

    private let fallbackKeywords = [
        "华语音乐 MV",
        "日语歌 翻唱",
        "粤语歌 live",
        "纯音乐 piano",
        "动漫 OST 音乐",
    ]

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
                if !tracks.isEmpty {
                    Section {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            Button {
                                Task { await engine.play(tracks: tracks, startAt: index) }
                            } label: {
                                TrackRow(track: track, isPlaying: engine.current?.bvid == track.bvid)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("为你推荐")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.groupedBackground)
            .navigationTitle("推荐")
            .toolbar {
                Button {
                    Task { await load() }
                } label: {
                    Label("换一批", systemImage: "arrow.clockwise")
                }
                .disabled(loading)
            }
            .refreshable { await load() }
            .overlay {
                if loading && tracks.isEmpty { ProgressView() }
                else if tracks.isEmpty && errorMessage == nil {
                    ContentUnavailableView("还没有音乐推荐", systemImage: "music.note.list",
                                           description: Text(CookieStore.isLoggedIn
                                               ? "在 B 站收藏些喜欢的歌,这里会按收藏夹给你推荐"
                                               : "去设置扫码登录,即可用你的收藏夹生成推荐"))
                }
            }
            .task {
                if tracks.isEmpty { await load() }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        errorMessage = nil
        do {
            var collected: [Track] = []

            for seed in await recommendationSeeds() {
                let related = try await BiliClient().related(bvid: seed.bvid)
                    .map(Track.init(related:))
                    .filter(MusicFilter.isStrictMusic)
                collected.append(contentsOf: related)
                if collected.count >= 20 { break }
            }

            if collected.count < 12 {
                let keyword = fallbackKeywords[keywordIndex % fallbackKeywords.count]
                keywordIndex += 1
                let searched = try await BiliClient().search(keyword: keyword)
                    .map(Track.init(search:))
                    .filter(MusicFilter.isStrictMusic)
                collected.append(contentsOf: searched)
            }

            // 打散,让多个种子的相关推荐混在一起,"换一批" 观感更新鲜
            let result = dedupe(collected)
                .filter { engine.current?.bvid != $0.bvid }
                .shuffled()
            tracks = result
            engine.preload(tracks: result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recommendationSeeds() async -> [Track] {
        // 优先用收藏夹随机种子
        let favSeeds = await favoriteSeeds()
        if !favSeeds.isEmpty { return favSeeds }
        // 兜底:当前在播 + 最近缓存
        var seeds: [Track] = []
        if let current = engine.current {
            seeds.append(current)
        }
        seeds.append(contentsOf: CacheStore.shared.entries.prefix(4).map(\.track))
        return dedupe(seeds)
    }

    /// 从设置里指定的收藏夹(默认用"默认收藏夹")随机抽几个视频当种子:
    /// 收藏夹固定 → 随机翻一页 → 随机取 3 个,这样口味稳定、每次内容又有变化。
    private func favoriteSeeds() async -> [Track] {
        guard CookieStore.isLoggedIn else { return [] }
        let manager = FavoriteManager.shared
        if manager.folders.isEmpty { await manager.loadFolders() }
        let chosenId = UserDefaults.standard.integer(forKey: "recommendFolderId")
        let folder = manager.folders.first(where: { $0.id == chosenId && $0.media_count > 0 })
            ?? manager.folders.first(where: { $0.title.contains("默认") && $0.media_count > 0 })
            ?? manager.folders.first(where: { $0.media_count > 0 })
        guard let folder else { return [] }
        let pageCount = max(1, Int(ceil(Double(folder.media_count) / 40.0)))
        let page = Int.random(in: 1...pageCount)
        do {
            let result = try await BiliClient().favItems(folderId: folder.id, page: page)
            let items = (result.medias ?? [])
                .filter { $0.attr == 0 }   // 跳过已失效收藏
                .map { Track(bvid: $0.bvid, title: $0.title, artist: $0.upper.name,
                             coverURL: URL(string: $0.cover), duration: $0.duration) }
            return Array(items.shuffled().prefix(3))
        } catch {
            return []
        }
    }

    private func dedupe(_ input: [Track]) -> [Track] {
        var seen = Set<String>()
        return input.filter { track in
            guard !seen.contains(track.bvid) else { return false }
            seen.insert(track.bvid)
            return true
        }
    }
}
