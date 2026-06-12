import SwiftUI

/// 全屏正在播放页(从 mini bar 上拉打开)。
struct NowPlayingView: View {
    @Environment(PlayerEngine.self) private var engine

    var body: some View {
        @Bindable var engine = engine
        VStack(spacing: 28) {
            Capsule().fill(.tertiary).frame(width: 36, height: 5).padding(.top, 8)
            Spacer()
            AsyncImage(url: engine.current?.coverURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Color.gray.opacity(0.15)
                    Image(systemName: "music.note").font(.system(size: 50)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 320, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 8)

            VStack(spacing: 6) {
                Text(engine.current?.title ?? "")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(engine.current?.artist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if case .failed(let message) = engine.state {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(.horizontal)

            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { min(engine.currentTime, engine.duration) },
                        set: { engine.seek(to: $0) }
                    ),
                    in: 0...max(engine.duration, 1)
                )
                HStack {
                    Text(format(engine.currentTime))
                    Spacer()
                    Text(format(engine.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            HStack(spacing: 48) {
                Button {
                    Task { await engine.playPrevious() }
                } label: {
                    Image(systemName: "backward.fill").font(.title)
                }
                Button {
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }
                .overlay { if engine.state == .loading { ProgressView() } }
                Button {
                    Task { await engine.playNext() }
                } label: {
                    Image(systemName: "forward.fill").font(.title)
                }
                .disabled(!engine.hasNext)
            }
            .foregroundStyle(.primary)

            Toggle(isOn: $engine.radioMode) {
                Label("电台模式 · 播完自动连播相似歌曲", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption)
            }
            .padding(.horizontal, 24)

            downloadButton

            Spacer()
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        let downloads = DownloadManager.shared
        if let track = engine.current {
            if CacheStore.shared.entry(bvid: track.bvid) != nil {
                Label("已缓存", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if let p = downloads.progress[track.bvid] {
                HStack(spacing: 8) {
                    ProgressView(value: p).frame(width: 120)
                    Text("\(Int(p * 100))%").font(.caption.monospacedDigit())
                }
            } else {
                Button {
                    Task { await downloads.download(track: track) }
                } label: {
                    Label("缓存这首歌", systemImage: "arrow.down.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func format(_ seconds: Double) -> String {
        let s = Int(seconds.isFinite ? max(seconds, 0) : 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// 底部常驻迷你播放条。
struct MiniPlayerBar: View {
    @Environment(PlayerEngine.self) private var engine
    @Binding var showFullPlayer: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: engine.current?.coverURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 48, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(engine.current?.title ?? "").font(.caption).lineLimit(1)
                Text(engine.current?.artist ?? "").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .overlay { if engine.state == .loading { ProgressView().scaleEffect(0.7) } }
            Button {
                Task { await engine.playNext() }
            } label: {
                Image(systemName: "forward.fill").font(.title3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .contentShape(Rectangle())
        .onTapGesture { showFullPlayer = true }
    }
}
