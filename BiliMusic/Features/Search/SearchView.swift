import SwiftUI

struct SearchView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var query = ""
    @State private var results: [Track] = []
    @State private var searching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
                ForEach(Array(results.enumerated()), id: \.element.id) { index, track in
                    Button {
                        Task { await engine.play(tracks: results, startAt: index) }
                    } label: {
                        TrackRow(track: track, isPlaying: engine.current?.bvid == track.bvid)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("搜索")
            .searchable(text: $query, prompt: "歌名、UP主,或直接粘贴 BV 号/链接")
            .onSubmit(of: .search) { Task { await search() } }
            .overlay {
                if searching { ProgressView() }
                else if results.isEmpty && errorMessage == nil {
                    ContentUnavailableView("搜点什么吧", systemImage: "music.note.list",
                                           description: Text("点击结果即开始播放,播完自动连播相似歌曲"))
                }
            }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorMessage = nil
        // 粘贴 BV 号或链接 → 直接播放
        if let range = text.range(of: "BV[0-9A-Za-z]{10}", options: .regularExpression) {
            await engine.play(bvid: String(text[range]))
            return
        }
        searching = true
        defer { searching = false }
        do {
            results = try await BiliClient().search(keyword: text).map(Track.init(search:))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TrackRow: View {
    let track: Track
    var isPlaying = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: track.coverURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 80, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(isPlaying ? Color.accentColor : .primary)
                HStack(spacing: 6) {
                    if isPlaying {
                        Image(systemName: "waveform").font(.caption2).foregroundStyle(Color.accentColor)
                    }
                    Text(track.artist)
                    Text(format(track.duration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func format(_ seconds: Int) -> String {
        seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
