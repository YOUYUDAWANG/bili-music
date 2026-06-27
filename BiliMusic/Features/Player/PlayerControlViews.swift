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
            if isActive || isBusy {
                Circle()
                    .fill(backgroundColor)
            }

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(foregroundColor)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: isActive ? .semibold : .medium))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: 44, height: 44)
        .foregroundStyle(foregroundColor)
        .opacity(isEnabled ? 1 : 0.34)
        .contentShape(Circle())
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.white.opacity(0.16)
        }
        return Color.white.opacity(0.10)
    }

    private var foregroundColor: Color {
        guard isEnabled else { return Color.white.opacity(0.40) }
        return isActive ? Color.white : Color.white.opacity(0.76)
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
    @State private var trackWidth: CGFloat = 0
    @State private var scrubHapticTrigger = 0

    private enum Metrics {
        static let horizontalPadding: CGFloat = 28
    }

    private var displayProgress: CGFloat {
        let current = isScrubbing ? scrubValue : engine.currentTime
        guard engine.duration > 0 else { return 0 }
        return CGFloat(min(current, engine.duration) / engine.duration)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                // 底槽
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.22))
                    .frame(height: 3)

                // 进度轨
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.92))
                    .frame(width: max(0, trackWidth * displayProgress), height: 3)

                // 拇指球
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .offset(x: max(0, trackWidth * displayProgress - 6))
                    .scaleEffect(isScrubbing ? 1.15 : 1.0)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isScrubbing)
            }
            .frame(height: 44)
            .sensoryFeedback(.selection, trigger: scrubHapticTrigger)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { trackWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in trackWidth = w }
                }
            )

            HStack {
                Text(format(isScrubbing ? scrubValue : engine.currentTime))
                Spacer()
                Text(format(engine.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.58))
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(format(isScrubbing ? scrubValue : engine.currentTime)) / \(format(engine.duration))")
        .accessibilityIdentifier("nowPlayingProgress")
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isScrubbing {
                        scrubValue = min(engine.currentTime, engine.duration)
                        isScrubbing = true
                        engine.beginScrub()
                        onScrubChanged(true)
                        scrubHapticTrigger += 1
                    }
                    let x = value.location.x - Metrics.horizontalPadding
                    let progress = max(0, min(1, x / max(trackWidth, 1)))
                    scrubValue = progress * engine.duration
                }
                .onEnded { _ in
                    engine.endScrub(to: scrubValue)
                    isScrubbing = false
                    onScrubChanged(false)
                    scrubHapticTrigger += 1
                },
            including: .all
        )
        .onDisappear {
            guard isScrubbing else { return }
            engine.endScrub(to: scrubValue)
            isScrubbing = false
            onScrubChanged(false)
        }
    }

    private func format(_ seconds: Double) -> String {
        let s = Int(seconds.isFinite ? max(seconds, 0) : 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
