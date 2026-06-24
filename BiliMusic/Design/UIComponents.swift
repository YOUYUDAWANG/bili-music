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
