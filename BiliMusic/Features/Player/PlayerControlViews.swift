import AVKit
import MediaPlayer
import SwiftUI

// MARK: - Playback Controls

struct PlayerIconButton: View {
    let systemName: String
    let size: CGFloat
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ActionSymbolButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.accent)
        .accessibilityLabel(title)
    }
}

struct ActionSymbolLabel: View {
    let title: String
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(AppTheme.accent)
            .accessibilityLabel(title)
    }
}

struct PlayerToolbarActionButton: View {
    let title: String
    let systemName: String
    var isActive = false
    var isEnabled = true
    var isBusy = false
    var accessibilityLabel: String? = nil
    var accessibilityValue: String? = nil
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled, !isBusy else { return }
            action()
        } label: {
            PlayerToolbarActionVisual(
                title: title,
                systemName: systemName,
                isActive: isActive,
                isEnabled: isEnabled,
                isBusy: isBusy
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityValue(accessibilityValue ?? (isActive ? "已开启" : ""))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifierIfPresent(accessibilityIdentifier)
    }
}

private extension View {
    @ViewBuilder
    func accessibilityIdentifierIfPresent(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

struct PlayerToolbarActionLabel: View {
    let title: String
    let systemName: String
    var isActive = false
    var isEnabled = true
    var isBusy = false
    var accessibilityLabel: String? = nil
    var accessibilityValue: String? = nil

    var body: some View {
        PlayerToolbarActionVisual(
            title: title,
            systemName: systemName,
            isActive: isActive,
            isEnabled: isEnabled,
            isBusy: isBusy
        )
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityValue(accessibilityValue ?? (isActive ? "已开启" : ""))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct PlayerToolbarActionVisual: View {
    let title: String
    let systemName: String
    let isActive: Bool
    let isEnabled: Bool
    let isBusy: Bool

    var body: some View {
        ZStack {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(foregroundColor)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 19, weight: isActive ? .semibold : .medium))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: 46, height: 38)
        .foregroundStyle(foregroundColor)
        .opacity(isEnabled ? 1 : 0.34)
        .contentShape(Circle())
    }

    private var foregroundColor: Color {
        guard isEnabled else { return Color.white.opacity(0.40) }
        return isActive ? Color.white.opacity(0.96) : Color.white.opacity(0.72)
    }
}

// MARK: - Progress Bar

/// 进度条独立成视图,把对 `engine.currentTime` 的订阅限制在这里。
/// scrub 状态也只在本视图持有,避免拖动时反复刷新外层播放器。
struct PlayerProgressBar: View {
    @Environment(PlayerEngine.self) private var engine
    var onScrubChanged: (Bool) -> Void = { _ in }
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var scrubHapticTrigger = 0

    private enum Metrics {
        static let horizontalPadding: CGFloat = 30
        static let sliderHeight: CGFloat = 22
    }

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: progressBinding,
                in: 0...max(engine.duration, 1),
                onEditingChanged: handleEditingChanged
            )
            .sliderThumbVisibility(.hidden)
            .tint(Color.white.opacity(0.94))
            .frame(height: Metrics.sliderHeight)
            .sensoryFeedback(.selection, trigger: scrubHapticTrigger)

            HStack {
                Text(MusicFormatters.playbackTime(isScrubbing ? scrubValue : engine.currentTime))
                Spacer()
                Text(MusicFormatters.playbackTime(engine.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.58))
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放进度")
        .accessibilityValue(
            "\(MusicFormatters.playbackTime(isScrubbing ? scrubValue : engine.currentTime)) / \(MusicFormatters.playbackTime(engine.duration))"
        )
        .accessibilityIdentifier("nowPlayingProgress")
        .onDisappear {
            guard isScrubbing else { return }
            engine.endScrub(to: scrubValue)
            isScrubbing = false
            onScrubChanged(false)
        }
        .onChange(of: engine.current?.key) { oldKey, newKey in
            if let oldKey, let newKey, oldKey.isCIDEnrichment(to: newKey) {
                return
            }
            guard isScrubbing else { return }
            isScrubbing = false
            onScrubChanged(false)
        }
    }

    private var progressBinding: Binding<Double> {
        Binding(
            get: {
                isScrubbing
                    ? scrubValue
                    : ProgressScrubMath.clampedTime(engine.currentTime, duration: engine.duration)
            },
            set: { value in
                scrubValue = ProgressScrubMath.clampedTime(value, duration: engine.duration)
            }
        )
    }

    private func handleEditingChanged(_ editing: Bool) {
        if editing {
            guard !isScrubbing else { return }
            scrubValue = ProgressScrubMath.clampedTime(engine.currentTime, duration: engine.duration)
            isScrubbing = true
            engine.beginScrub()
            onScrubChanged(true)
            scrubHapticTrigger += 1
        } else {
            guard isScrubbing else { return }
            engine.endScrub(to: scrubValue)
            isScrubbing = false
            onScrubChanged(false)
            scrubHapticTrigger += 1
        }
    }
}

enum ProgressScrubMath {
    static func clampedTime(_ time: Double, duration: Double) -> Double {
        guard time.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(max(time, 0), duration)
    }
}

// MARK: - System Media Controls

/// Uses the same system volume control as the Now Playing experience.
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.showsVolumeSlider = true
        configure(view)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        configure(uiView)
    }

    private func configure(_ view: MPVolumeView) {
        view.tintColor = UIColor.white.withAlphaComponent(0.92)
        guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.minimumTrackTintColor = UIColor.white.withAlphaComponent(0.92)
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.26)
        slider.thumbTintColor = .white
    }
}

/// Keeps AirPlay routing in the system-owned picker rather than recreating it.
struct SystemRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.prioritizesVideoDevices = false
        picker.tintColor = UIColor.white.withAlphaComponent(0.72)
        picker.activeTintColor = .white
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = UIColor.white.withAlphaComponent(0.72)
        uiView.activeTintColor = .white
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
