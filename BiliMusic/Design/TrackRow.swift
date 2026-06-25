import SwiftUI

/// 通用歌曲行组件：封面 + 标题 + UP 主 + 时长 + 播放状态指示。
/// 行尾 ellipsis 可通过 Menu 展开更多操作（添加到队列、电台播放）。
struct TrackRow: View {
    @Environment(PlayerEngine.self) private var engine
    let track: Track
    var isPlaying = false
    var showsTrailingIcon = true

    var body: some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: thumbnailURL(track.coverURL, size: 160)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    AppTheme.secondaryBackground
                    Image(systemName: "music.note").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(isPlaying ? AppTheme.accent : .primary)
                HStack(spacing: 6) {
                    if isPlaying {
                        Image(systemName: "waveform").font(.caption2).foregroundStyle(AppTheme.accent)
                    }
                    Text(track.artist)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(format(track.duration))
                        .font(.caption.monospacedDigit())
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if showsTrailingIcon {
                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 44, height: 44)
                } else {
                    Menu {
                        Button {
                            engine.appendToQueue([track])
                        } label: {
                            Label("添加到队列", systemImage: "text.badge.plus")
                        }
                        Button {
                            Task { await engine.playRadio(seed: track) }
                        } label: {
                            Label("电台播放", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func format(_ seconds: Int) -> String {
        seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func thumbnailURL(_ url: URL?, size: Int) -> URL? {
        guard let url else { return nil }
        let raw = url.absoluteString
        guard !raw.localizedCaseInsensitiveContains("transparent.png") else { return nil }
        guard raw.contains("hdslb.com"), !raw.contains("@") else { return url }
        return URL(string: raw + "@\(size)w_\(size)h_1c.webp")
    }
}
