import SwiftUI

/// 已缓存曲目列表,可离线播放。
struct LibraryView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var confirmClear = false
    @State private var searchText = ""
    @State private var sortOrder: CacheSortOrder = .recentlyCached
    @State private var clearHapticTrigger = 0

    private var cache: CacheStore { .shared }

    /// 按搜索词过滤 + 按所选规则排序后的可见条目。
    private var visibleEntries: [CachedEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? cache.entries : cache.entries.filter { entry in
            entry.title.localizedCaseInsensitiveContains(query)
                || entry.artist.localizedCaseInsensitiveContains(query)
                || entry.bvid.localizedCaseInsensitiveContains(query)
        }

        switch sortOrder {
        case .recentlyCached:
            return filtered.sorted { $0.downloadedAt > $1.downloadedAt }
        case .title:
            return filtered.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .artist:
            return filtered.sorted {
                let artistCompare = $0.artist.localizedStandardCompare($1.artist)
                if artistCompare != .orderedSame { return artistCompare == .orderedAscending }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .size:
            return filtered.sorted { $0.fileSize > $1.fileSize }
        case .quality:
            return filtered.sorted {
                let lhs = $0.quality ?? 0
                let rhs = $1.quality ?? 0
                if lhs != rhs { return lhs > rhs }
                return $0.downloadedAt > $1.downloadedAt
            }
        }
    }

    var body: some View {
        let entries = visibleEntries
        let isFiltered = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        NavigationStack {
            List {
                if !cache.entries.isEmpty {
                    Section {
                        CacheSummaryView(count: entries.count,
                                         totalCount: cache.entries.count,
                                         bytes: entries.reduce(0) { $0 + $1.fileSize },
                                         isFiltered: isFiltered)
                    }
                }

                ForEach(entries) { entry in
                    Button {
                        let tracks = entries.map(\.track)
                        let index = entries.firstIndex(of: entry) ?? 0
                        Task { await engine.play(tracks: tracks, startAt: index) }
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            TrackRow(track: entry.track, isPlaying: engine.current.map { entry.track.key.matches($0) } ?? false)
                            VStack(alignment: .trailing, spacing: 6) {
                                if let q = entry.quality {
                                    Text(BiliClient.qualityName(q))
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary, in: Capsule())
                                }
                                Text(format(bytes: entry.fileSize))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            Task { await engine.playRadio(seed: entry.track) }
                        } label: {
                            Label("电台播放", systemImage: PlayerEngine.QueueMode.radio.icon)
                        }
                        Button {
                            let tracks = entries.map(\.track)
                            let index = entries.firstIndex(of: entry) ?? 0
                            Task { await engine.play(tracks: tracks, startAt: index, queueMode: .shuffle) }
                        } label: {
                            Label("随机播放当前列表", systemImage: PlayerEngine.QueueMode.shuffle.icon)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { entries[$0] }.forEach { cache.remove($0) }
                }
            }
            .listStyle(.insetGrouped)
            .hideMiniPlayerOnScroll()
            .scrollContentBackground(.hidden)
            .background(AppTheme.groupedBackground)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜索缓存")
            .task {
                await cache.loadIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("排序", selection: $sortOrder) {
                            ForEach(CacheSortOrder.allCases) { order in
                                Label(order.title, systemImage: order.icon).tag(order)
                            }
                        }
                    } label: {
                        Label("排序", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(cache.entries.isEmpty)
                }

                if !cache.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("清空", role: .destructive) { confirmClear = true }
                    }
                }
            }
            .confirmationDialog("删除全部 \(cache.entries.count) 首缓存?", isPresented: $confirmClear,
                                titleVisibility: .visible) {
                Button("全部删除", role: .destructive) {
                    clearHapticTrigger += 1
                    cache.removeAll()
                }
            }
            .sensoryFeedback(.intent(.warning), trigger: clearHapticTrigger)
            .overlay {
                if cache.entries.isEmpty {
                    ContentUnavailableView("还没有缓存", systemImage: "arrow.down.circle",
                                           description: Text("在播放页点下载,或在设置里打开自动缓存"))
                } else if entries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    /// 字节数格式化为人类可读大小。
    private func format(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// 缓存列表的排序方式。
private enum CacheSortOrder: String, CaseIterable, Identifiable {
    case recentlyCached
    case title
    case artist
    case size
    case quality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyCached: "最近缓存"
        case .title: "标题"
        case .artist: "UP 主"
        case .size: "文件大小"
        case .quality: "音质"
        }
    }

    var icon: String {
        switch self {
        case .recentlyCached: "clock"
        case .title: "textformat"
        case .artist: "person"
        case .size: "externaldrive"
        case .quality: "hifispeaker"
        }
    }
}

/// 缓存列表顶部的汇总行（数量 + 占用大小）。
private struct CacheSummaryView: View {
    let count: Int
    let totalCount: Int
    let bytes: Int64
    let isFiltered: Bool

    var body: some View {
        HStack {
            Text(summary)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var summary: String {
        if isFiltered {
            "显示 \(count) / \(totalCount) 首"
        } else {
            "\(totalCount) 首"
        }
    }
}
