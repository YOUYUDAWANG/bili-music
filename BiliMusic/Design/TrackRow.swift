import SwiftUI

/// 通用歌曲行组件：封面 + 标题 + UP 主 + 时长 + 播放状态指示。
/// 行尾 ellipsis 可通过 Menu 展开更多操作（添加到队列、电台播放）。
struct TrackRow: View {
    enum Appearance {
        case standard
        case player
    }

    @Environment(PlayerEngine.self) private var engine
    @AppStorage(TrackTitleFormatter.cleanListTitlesDefaultsKey) private var cleanListTitles = true
    let track: Track
    var isPlaying = false
    var showsTrailingIcon = true
    var appearance: Appearance = .standard

    var body: some View {
        let display = TrackTitleFormatter.displayMetadata(for: track, clean: cleanListTitles)
        HStack(spacing: 14) {
            CachedAsyncImage(
                url: thumbnailURL(track.coverURL, size: 160),
                targetSize: CGSize(width: 64, height: 36)
            ) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    placeholderBackground
                    Image(systemName: "music.note")
                        .font(.caption)
                        .foregroundStyle(secondaryForeground)
                }
            }
            .frame(width: 64, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(titleForeground)
                HStack(spacing: 6) {
                    if isPlaying {
                        Image(systemName: "waveform").font(.caption2).foregroundStyle(AppTheme.accent)
                    }
                    Text(display.artist)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(format(track.duration))
                        .font(.caption.monospacedDigit())
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.caption)
                .foregroundStyle(secondaryForeground)
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
                            .foregroundStyle(trailingForeground)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private var titleForeground: Color {
        if isPlaying { return AppTheme.accent }
        switch appearance {
        case .standard:
            return .primary
        case .player:
            return Color.white.opacity(0.90)
        }
    }

    private var displayTitle: String {
        TrackTitleFormatter.listTitle(for: track, clean: cleanListTitles)
    }

    private var secondaryForeground: Color {
        switch appearance {
        case .standard:
            return .secondary
        case .player:
            return Color.white.opacity(0.48)
        }
    }

    private var trailingForeground: Color {
        switch appearance {
        case .standard:
            return .secondary
        case .player:
            return Color.white.opacity(0.34)
        }
    }

    private var placeholderBackground: Color {
        switch appearance {
        case .standard:
            return AppTheme.secondaryBackground
        case .player:
            return Color.white.opacity(0.08)
        }
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
        let height = max(1, Int(Double(size) * 9.0 / 16.0))
        return URL(string: raw + "@\(size)w_\(height)h_1c.webp")
    }
}
