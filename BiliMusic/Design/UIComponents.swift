import SwiftUI

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
