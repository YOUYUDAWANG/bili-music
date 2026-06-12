import SwiftUI

/// 首页推荐:B 站推荐流按时长过滤出"像歌"的内容。登录后是个性化推荐。
struct HomeView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var tracks: [Track] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var freshIdx = 1

    var body: some View {
        NavigationStack {
            List {
                if !CookieStore.isLoggedIn {
                    Label("未登录,当前为大众推荐;去设置页扫码登录后才是你的个性化推荐",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
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
                }
            }
            .listStyle(.plain)
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
            // 推荐流混着各种视频,按时长 1~11 分钟过滤出音乐形态的内容;不够就多拉几批
            var collected: [Track] = []
            for _ in 0..<3 {
                let items = try await BiliClient().homeFeed(freshIdx: freshIdx)
                freshIdx += 1
                collected += items.compactMap { item -> Track? in
                    guard let bvid = item.bvid, let title = item.title,
                          let duration = item.duration, (60...660).contains(duration) else { return nil }
                    return Track(bvid: bvid, title: title, artist: item.owner?.name ?? "",
                                 coverURL: item.pic.flatMap(URL.init(string:)), duration: duration)
                }
                if collected.count >= 15 { break }
            }
            tracks = collected
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
