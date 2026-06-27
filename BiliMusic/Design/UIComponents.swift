import SwiftUI

// MARK: - 长文本右侧渐变淡出

struct FadeOutRightModifier: ViewModifier {
    var fadeWidth: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .mask(
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: fadeWidth)
                }
            )
    }
}

extension View {
    func fadeOutRight(width: CGFloat = 16) -> some View {
        modifier(FadeOutRightModifier(fadeWidth: width))
    }
}

// MARK: - Mini 播放器微进度条（隔离渲染，只订阅 currentTime）

struct MiniProgressBar: View {
    @Environment(PlayerEngine.self) private var engine

    var body: some View {
        GeometryReader { geo in
            let progress = engine.duration > 0 ? CGFloat(engine.currentTime / engine.duration) : 0
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: geo.size.width * progress),
                    alignment: .leading
                )
        }
        .frame(height: 1.5)
    }
}

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
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
                .background(AppTheme.secondaryBackground, in: Circle())

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let action {
                Button(action: action) {
                    actionLabel()
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(.horizontal, 20)
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
    @AppStorage(TrackTitleFormatter.cleanListTitlesDefaultsKey) private var cleanListTitles = true
    let track: Track
    var isPlaying = false

    var body: some View {
        let display = TrackTitleFormatter.displayMetadata(for: track, clean: cleanListTitles)
        VStack(alignment: .leading, spacing: 10) {
            CachedAsyncImage(
                url: thumbnailURL(track.coverURL, width: 640, height: 360),
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

    private func thumbnailURL(_ url: URL?, width: Int, height: Int) -> URL? {
        guard let url else { return nil }
        let raw = url.absoluteString
        guard !raw.localizedCaseInsensitiveContains("transparent.png") else { return nil }
        guard raw.contains("hdslb.com"), !raw.contains("@") else { return url }
        return URL(string: raw + "@\(width)w_\(height)h_1c.webp")
    }
}

struct MusicTrackRow: View {
    @Environment(PlayerEngine.self) private var engine
    @AppStorage(TrackTitleFormatter.cleanListTitlesDefaultsKey) private var cleanListTitles = true
    let track: Track
    var isPlaying = false
    var showsMenu = true
    var isLoading = false

    var body: some View {
        let display = TrackTitleFormatter.displayMetadata(for: track, clean: cleanListTitles)
        HStack(spacing: 12) {
            CachedAsyncImage(
                url: thumbnailURL(track.coverURL, width: 192, height: 108),
                targetSize: CGSize(width: 72, height: 40.5)
            ) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    AppTheme.secondaryBackground
                    Image(systemName: "music.note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 40.5)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    Text(display.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(isPlaying ? AppTheme.accent : .primary)
                }

                Text("\(display.artist) · \(MusicFormatters.duration(track.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailingControl
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background {
            if isPlaying {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.12))
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isLoading {
            ProgressView()
                .scaleEffect(0.74)
                .frame(width: 36, height: 36)
        } else if showsMenu {
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 36, height: 36)
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
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func thumbnailURL(_ url: URL?, width: Int, height: Int) -> URL? {
        guard let url else { return nil }
        let raw = url.absoluteString
        guard !raw.localizedCaseInsensitiveContains("transparent.png") else { return nil }
        guard raw.contains("hdslb.com"), !raw.contains("@") else { return url }
        return URL(string: raw + "@\(width)w_\(height)h_1c.webp")
    }
}

enum MusicFormatters {
    static func duration(_ seconds: Int) -> String {
        seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
