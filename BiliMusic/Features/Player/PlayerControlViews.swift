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
                .frame(height: 42)
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

// MARK: - Progress Bar

/// 进度条独立成视图,把对 `engine.currentTime` 的订阅限制在这里。
/// scrub 状态也只在本视图持有,避免拖动时反复刷新外层播放器。
struct PlayerProgressBar: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubValue : min(engine.currentTime, engine.duration) },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(engine.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        scrubValue = min(engine.currentTime, engine.duration)
                        isScrubbing = true
                        engine.beginScrub()
                    } else {
                        engine.endScrub(to: scrubValue)
                        isScrubbing = false
                    }
                }
            )
            .tint(AppTheme.label)
            HStack {
                Text(format(isScrubbing ? scrubValue : engine.currentTime))
                Spacer()
                Text(format(engine.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
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
