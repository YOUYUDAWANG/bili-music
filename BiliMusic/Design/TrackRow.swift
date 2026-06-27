import SwiftUI

/// 通用歌曲行组件：封面 + 标题 + UP 主 + 时长 + 播放状态指示。
/// 行尾 ellipsis 可通过 Menu 展开更多操作（添加到队列、电台播放）。
struct TrackRow: View {
    enum Appearance {
        case standard
        case prominent
        case player
    }

    @Environment(PlayerEngine.self) private var engine
    @AppStorage(TrackTitleFormatter.cleanListTitlesDefaultsKey) private var cleanListTitles = true
    let track: Track
    var isPlaying = false
    var showsTrailingIcon = true
    var isLoading = false
    var appearance: Appearance = .standard

    var body: some View {
        let display = TrackTitleFormatter.displayMetadata(for: track, clean: cleanListTitles)
        HStack(spacing: metrics.horizontalSpacing) {
            CachedAsyncImage(
                url: thumbnailURL(track.coverURL, size: metrics.thumbnailWidth),
                targetSize: CGSize(width: metrics.coverWidth, height: metrics.coverHeight)
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
            .frame(width: metrics.coverWidth, height: metrics.coverHeight)
            .clipShape(RoundedRectangle(cornerRadius: metrics.coverCornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: metrics.textSpacing) {
                Text(displayTitle)
                    .font(metrics.titleFont)
                    .lineLimit(2)
                    .foregroundStyle(titleForeground)
                HStack(spacing: 6) {
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(metrics.waveformFont)
                            .foregroundStyle(AppTheme.accent)
                    }
                    Text(display.artist)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(format(track.duration))
                        .font(.caption.monospacedDigit())
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(metrics.metadataFont)
                .foregroundStyle(secondaryForeground)
            }

            Spacer(minLength: metrics.trailingSpacing)

            if showsTrailingIcon {
                if isLoading {
                    ProgressView()
                        .scaleEffect(metrics.progressScale)
                        .frame(width: metrics.trailingControlSize, height: metrics.trailingControlSize)
                } else if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: metrics.trailingControlSize, height: metrics.trailingControlSize)
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
                            .frame(width: metrics.trailingControlSize, height: metrics.trailingControlSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, metrics.verticalPadding)
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(maxWidth: .infinity, minHeight: metrics.minHeight, alignment: .leading)
        .background {
            if isPlaying {
                RoundedRectangle(cornerRadius: metrics.highlightCornerRadius, style: .continuous)
                    .fill(rowHighlightFill)
            }
        }
        .contentShape(Rectangle())
    }

    private var titleForeground: Color {
        if isPlaying { return AppTheme.accent }
        switch appearance {
        case .standard:
            return .primary
        case .prominent:
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
        case .prominent:
            return .secondary
        case .player:
            return Color.white.opacity(0.48)
        }
    }

    private var trailingForeground: Color {
        switch appearance {
        case .standard:
            return .secondary
        case .prominent:
            return .secondary
        case .player:
            return Color.white.opacity(0.34)
        }
    }

    private var placeholderBackground: Color {
        switch appearance {
        case .standard:
            return AppTheme.secondaryBackground
        case .prominent:
            return AppTheme.secondaryBackground
        case .player:
            return Color.white.opacity(0.08)
        }
    }

    private var rowHighlightFill: Color {
        switch appearance {
        case .standard:
            return AppTheme.brandSoft
        case .prominent:
            return AppTheme.accent.opacity(0.12)
        case .player:
            return AppTheme.accent.opacity(0.14)
        }
    }

    private var metrics: Metrics {
        switch appearance {
        case .standard:
            return Metrics(
                horizontalSpacing: 14,
                thumbnailWidth: 160,
                coverWidth: 64,
                coverHeight: 36,
                coverCornerRadius: 5,
                textSpacing: 4,
                titleFont: .subheadline,
                metadataFont: .caption,
                waveformFont: .caption2,
                trailingSpacing: 8,
                trailingControlSize: 44,
                progressScale: 0.84,
                verticalPadding: 5,
                horizontalPadding: 8,
                minHeight: nil,
                highlightCornerRadius: 8)
        case .prominent:
            return Metrics(
                horizontalSpacing: 12,
                thumbnailWidth: 192,
                coverWidth: 72,
                coverHeight: 40.5,
                coverCornerRadius: 6,
                textSpacing: 4,
                titleFont: .subheadline.weight(.semibold),
                metadataFont: .caption,
                waveformFont: .caption2.weight(.semibold),
                trailingSpacing: 8,
                trailingControlSize: 36,
                progressScale: 0.74,
                verticalPadding: 8,
                horizontalPadding: 10,
                minHeight: 58,
                highlightCornerRadius: 7)
        case .player:
            return Metrics(
                horizontalSpacing: 14,
                thumbnailWidth: 160,
                coverWidth: 64,
                coverHeight: 36,
                coverCornerRadius: 5,
                textSpacing: 4,
                titleFont: .subheadline,
                metadataFont: .caption,
                waveformFont: .caption2,
                trailingSpacing: 8,
                trailingControlSize: 44,
                progressScale: 0.84,
                verticalPadding: 5,
                horizontalPadding: 8,
                minHeight: nil,
                highlightCornerRadius: 8)
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

private struct Metrics {
    let horizontalSpacing: CGFloat
    let thumbnailWidth: Int
    let coverWidth: CGFloat
    let coverHeight: CGFloat
    let coverCornerRadius: CGFloat
    let textSpacing: CGFloat
    let titleFont: Font
    let metadataFont: Font
    let waveformFont: Font
    let trailingSpacing: CGFloat
    let trailingControlSize: CGFloat
    let progressScale: CGFloat
    let verticalPadding: CGFloat
    let horizontalPadding: CGFloat
    let minHeight: CGFloat?
    let highlightCornerRadius: CGFloat
}
