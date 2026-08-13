import SwiftUI
import UIKit

// MARK: - Mini 播放器控制按钮按压缩放

struct MiniPlayerControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct MusicRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.62 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Music Page Components

struct MusicSectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
    }
}

struct MusicStatusBlock<ActionLabel: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actionLabel: () -> ActionLabel
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let action {
                Button(action: action) {
                    actionLabel()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

extension MusicStatusBlock where ActionLabel == EmptyView {
    init(systemImage: String, title: String, message: String) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionLabel = { EmptyView() }
        self.action = nil
    }
}

struct MusicLoadingBlock: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

struct FeaturedTrackCard: View {
    @AppStorage(TrackTitleFormatter.cleanListTitlesDefaultsKey) private var cleanListTitles = false
    let track: Track
    var isPlaying = false

    var body: some View {
        let display = TrackTitleFormatter.displayMetadata(for: track, clean: cleanListTitles)
        VStack(alignment: .leading, spacing: 10) {
            CachedAsyncImage(
                url: BiliArtworkURL.thumbnail(track.coverURL, width: 640, height: 360),
                targetSize: CGSize(width: 320, height: 180)
            ) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    AppTheme.secondaryBackground
                    Image(systemName: "music.note")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    Text(display.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(isPlaying ? AppTheme.accent : .primary)
                }

                Text("\(display.artist) · \(MusicFormatters.duration(track.duration))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

}

// MARK: - Cover Magazine Components

/// 杂志式页面的统一封面。固定 16:9、8pt 圆角，避免各页面形成不同的图片语言。
struct MagazineArtwork: View {
    let url: URL?
    var pixelWidth = 640
    var fallbackImage: UIImage?

    var body: some View {
        CachedAsyncImage(
            url: BiliArtworkURL.widescreenThumbnail(url, width: pixelWidth),
            targetSize: CGSize(width: pixelWidth / 2, height: pixelWidth * 9 / 32),
            fallbackImage: fallbackImage
        ) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Color.secondary.opacity(0.10)
                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// 收藏夹目录封面的自适应拼贴：按 0...4 张内容重排，不用空白格凑版面。
struct MagazineArtworkCollage: View {
    let urls: [URL]

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 2
            let halfWidth = (proxy.size.width - gap) / 2
            let halfHeight = (proxy.size.height - gap) / 2
            switch urls.count {
            case 0:
                emptyCollage
                    .frame(width: proxy.size.width, height: proxy.size.height)
            case 1:
                collageCell(index: 0, width: proxy.size.width, height: proxy.size.height)
            case 2:
                HStack(spacing: gap) {
                    collageCell(index: 0, width: halfWidth, height: proxy.size.height)
                    collageCell(index: 1, width: halfWidth, height: proxy.size.height)
                }
            case 3:
                HStack(spacing: gap) {
                    collageCell(index: 0, width: halfWidth, height: proxy.size.height)
                    VStack(spacing: gap) {
                        collageCell(index: 1, width: halfWidth, height: halfHeight)
                        collageCell(index: 2, width: halfWidth, height: halfHeight)
                    }
                }
            default:
                VStack(spacing: gap) {
                    collageRow(start: 0, width: halfWidth, height: halfHeight)
                    collageRow(start: 2, width: halfWidth, height: halfHeight)
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func collageRow(start: Int, width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 2) {
            collageCell(index: start, width: width, height: height)
            collageCell(index: start + 1, width: width, height: height)
        }
    }

    @ViewBuilder
    private func collageCell(index: Int, width: CGFloat, height: CGFloat) -> some View {
        CachedAsyncImage(
            url: BiliArtworkURL.widescreenThumbnail(urls[safe: index], width: 360),
            targetSize: CGSize(width: width, height: height)
        ) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            collagePlaceholder
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private var collagePlaceholder: some View {
        ZStack {
            AppTheme.secondaryBackground
            Image(systemName: "music.note")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var emptyCollage: some View {
        ZStack {
            AppTheme.secondaryBackground
            Image(systemName: "rectangle.stack")
                .font(.title3.weight(.medium))
                .foregroundStyle(.tertiary)
        }
    }
}

/// 专题页和横向书架共用的曲目卡。图片是第一层，文字仅作为索引信息。
struct MagazineTrackTile: View {
    @AppStorage(TrackTitleFormatter.cleanListTitlesDefaultsKey) private var cleanListTitles = false
    let track: Track
    var isPlaying = false
    var prominent = false

    var body: some View {
        let display = TrackTitleFormatter.displayMetadata(for: track, clean: cleanListTitles)
        VStack(alignment: .leading, spacing: prominent ? 10 : 7) {
            MagazineArtwork(url: track.coverURL, pixelWidth: prominent ? 960 : 560)
                .overlay(alignment: .bottomTrailing) {
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(9)
                            .shadow(color: .black.opacity(0.55), radius: 4)
                            .accessibilityHidden(true)
                    }
                }
                .overlay {
                    if isPlaying {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.82), lineWidth: 2)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(TrackTitleFormatter.listTitle(for: track, clean: cleanListTitles))
                    .font(prominent ? .headline.weight(.bold) : .subheadline.weight(.semibold))
                    .foregroundStyle(isPlaying ? AppTheme.accent : .primary)
                    .lineLimit(prominent ? 2 : 1)
                Text(display.artist)
                    .font(prominent ? .subheadline : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isPlaying ? "正在播放" : "")
    }
}

enum MusicFormatters {
    static func duration(_ seconds: Int) -> String {
        seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func playbackTime(_ seconds: Double) -> String {
        let value = Int(seconds.isFinite ? max(seconds, 0) : 0)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
