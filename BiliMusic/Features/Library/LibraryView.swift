import SwiftUI

/// 已缓存曲目列表,可离线播放。
struct LibraryView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var confirmClear = false

    private var cache: CacheStore { .shared }

    var body: some View {
        NavigationStack {
            List {
                if !cache.entries.isEmpty {
                    Text("\(cache.entries.count) 首 · \(format(bytes: cache.totalSize))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
                ForEach(cache.entries) { entry in
                    Button {
                        let tracks = cache.entries.map(\.track)
                        let index = cache.entries.firstIndex(of: entry) ?? 0
                        Task { await engine.play(tracks: tracks, startAt: index) }
                    } label: {
                        HStack {
                            TrackRow(track: entry.track, isPlaying: engine.current?.bvid == entry.bvid)
                            if let q = entry.quality {
                                Text(BiliClient.qualityName(q))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    offsets.map { cache.entries[$0] }.forEach { cache.remove($0) }
                }
            }
            .listStyle(.plain)
            .navigationTitle("缓存")
            .toolbar {
                if !cache.entries.isEmpty {
                    Button("清空", role: .destructive) { confirmClear = true }
                }
            }
            .confirmationDialog("删除全部 \(cache.entries.count) 首缓存?", isPresented: $confirmClear,
                                titleVisibility: .visible) {
                Button("全部删除", role: .destructive) { cache.removeAll() }
            }
            .overlay {
                if cache.entries.isEmpty {
                    ContentUnavailableView("还没有缓存", systemImage: "arrow.down.circle",
                                           description: Text("在播放页点下载,或在设置里打开自动缓存"))
                }
            }
        }
    }

    private func format(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
