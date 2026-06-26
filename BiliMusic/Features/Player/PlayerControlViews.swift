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
        }
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? AppTheme.accent.opacity(0.14) : Color.primary.opacity(0.055))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(isActive ? 0.12 : 0.06), lineWidth: 1)
                }

            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
        .frame(height: 48)
        .foregroundStyle(foregroundColor)
        .opacity(isEnabled ? 1 : 0.46)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var foregroundColor: Color {
        guard isEnabled else { return .secondary }
        return isActive ? AppTheme.accent : AppTheme.label
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
                    .fill(.quaternary)
                    .frame(height: 3)

                // 进度轨
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(AppTheme.label)
                    .frame(width: max(0, trackWidth * displayProgress), height: 3)

                // 拇指球
                Circle()
                    .fill(AppTheme.label)
                    .frame(width: 12, height: 12)
                    .offset(x: max(0, trackWidth * displayProgress - 6))
                    .scaleEffect(isScrubbing ? 1.15 : 1.0)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isScrubbing)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
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
                        let progress = max(0, min(1, value.location.x / max(trackWidth, 1)))
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
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
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
