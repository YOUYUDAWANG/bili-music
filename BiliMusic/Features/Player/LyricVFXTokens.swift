import SwiftUI

// MARK: - 电影级场景编舞模式 (Cinematic Scene Motion Modes)

enum LyricCinematicSceneMode: String, CaseIterable, Codable, Sendable {
    case assemble    // 构筑凝聚模式 (Verse 叙事段落：单字错峰吸附、散焦到清晰聚焦)
    case gravity     // 重力下坠模式 (Chorus 副歌高潮：重力下落、冲击波与微震)
    case duet        // 多声部对唱模式 (Duet/Backing：立体左右空间排布、双向声部对话)
    case cosmicDrift // 星海浮游模式 (Outro/慢歌长音：正弦波双轴微浮游、流光漫游)

    static func resolve(
        for line: PlayerEngine.LyricLine,
        index: Int,
        aiMood: String?,
        totalLines: Int
    ) -> LyricCinematicSceneMode {
        // 1. 多声部优先进入对唱分镜
        if line.voiceRole.isSecondary {
            return .duet
        }
        // 2. 尾奏或慢歌长音进入星海浮游
        let duration = max(0.2, line.to - line.from)
        if index >= totalLines - 2 || duration >= 5.2 {
            return .cosmicDrift
        }
        // 3. 高潮短句或感叹句进入重力冲击
        let text = line.text
        if text.contains("！") || text.contains("!") || (text.count <= 10 && duration <= 2.2) {
            return .gravity
        }
        // 4. 默认叙事段落采用构筑凝聚
        return .assemble
    }
}

// MARK: - 高能字级与词级视觉特效组件 (Lyric VFX Tokens)

struct LyricVFXWordToken: View {
    let text: String
    let state: LyricWordState
    let style: LyricEmbellishmentStyle
    let fontSize: CGFloat
    let alignment: TextAlignment
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            // 1. 底层特效 (残影/冲击波/涟漪/心跳光晕)
            if isCurrent, !reduceMotion {
                backgroundVFX
            }

            // 2. 未唱基底文字 (浅暗色，保持排版骨架)
            Text(text)
                .font(tokenFont)
                .tracking(tracking)
                .italic(isItalic)
                .foregroundStyle(PlayerSurface.lyricUnsung)

            // 3. 活跃流光扫亮文字 (Mask Sweep + 色彩/色散/高光)
            if fillProgress > 0 {
                revealedText
                    .mask(alignment: .leading) {
                        GeometryReader { proxy in
                            Rectangle()
                                .frame(width: proxy.size.width * CGFloat(fillProgress))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .blur(radius: 0.65)
                        }
                    }
            }

            // 4. 活跃唱响流光光斑 (Traveling Light Head)
            if isCurrent, !reduceMotion {
                GeometryReader { proxy in
                    let headX = proxy.size.width * CGFloat(fillProgress)
                    Circle()
                        .fill(glowColor)
                        .frame(width: 8, height: 8)
                        .blur(radius: 3)
                        .position(x: headX, y: proxy.size.height * 0.5)
                        .opacity(sin(fillProgress * .pi) * 0.85)
                        .blendMode(.plusLighter)
                }
            }

            // 5. 顶层高亮特效 (钻石十字星芒/电弧/余烬)
            if isCurrent, !reduceMotion {
                foregroundVFX
            }
        }
        .scaleEffect(activeScale, anchor: .center)
        .offset(x: activeHorizontalOffset, y: activeVerticalOffset)
        .shadow(color: glowColor.opacity(glowOpacity), radius: glowRadius)
        .fixedSize()
        .accessibilityHidden(true)
    }

    // MARK: - Typography

    private var tokenFont: Font {
        let weight: Font.Weight
        switch style {
        case .impact: weight = isCurrent ? .black : .heavy
        case .blaze, .neon: weight = isCurrent ? .heavy : .bold
        case .whisper, .crystallize: weight = isCurrent ? .medium : .light
        case .heartbeat: weight = isCurrent ? .bold : .semibold
        default: weight = isCurrent ? .bold : .semibold
        }

        let design: Font.Design
        switch style {
        case .digital: design = .monospaced
        case .whisper, .vintage: design = .serif
        case .neon: design = .rounded
        default: design = .default
        }

        return .system(size: fontSize, weight: weight, design: design)
    }

    private var tracking: CGFloat {
        switch style {
        case .whisper: return 1.2
        case .vintage: return 0.8
        case .impact: return -0.3
        case .digital: return 0.8
        case .sway: return 0.5
        case .crystallize: return 0.4
        default: return 0
        }
    }

    private var isItalic: Bool {
        style == .floating
    }

    // MARK: - State Helpers

    private var isCurrent: Bool {
        if case .current = state { return true }
        return false
    }

    private var fillProgress: Double {
        LyricHighlightModel.fillProgress(for: state)
    }

    // MARK: - Micro Dynamics (预备后撤 + 爆发弹跳 + 悬浮生命力)

    private var activeScale: CGFloat {
        guard !reduceMotion, isCurrent else { return 1.0 }
        let p = fillProgress
        switch style {
        case .impact:
            // 呐喊爆发瞬时弹性爆破 (1.0 -> 1.16 -> 1.0)
            let pop = p < 0.35 ? (p / 0.35) * 0.16 : (1.0 - (p - 0.35) / 0.65) * 0.16
            return 1.0 + CGFloat(pop)
        case .heartbeat:
            // 双阶段心跳脉冲 (咚-咚)
            let phase1 = p < 0.25 ? (p / 0.25) * 0.10 : (p < 0.5 ? (1.0 - (p - 0.25) / 0.25) * 0.10 : 0)
            let phase2 = (p >= 0.5 && p < 0.75) ? ((p - 0.5) / 0.25) * 0.05 : (p >= 0.75 ? (1.0 - (p - 0.75) / 0.25) * 0.05 : 0)
            return 1.0 + CGFloat(phase1 + phase2)
        default:
            // 预备微后撤 (0.96) -> 唱响弹跳 (1.06) -> 回归平稳
            if p < 0.10 {
                let ant = (p / 0.10) * 0.04
                return 1.0 - CGFloat(ant)
            } else {
                let pop = sin((p - 0.10) / 0.90 * .pi) * 0.06
                return 1.0 + CGFloat(pop)
            }
        }
    }

    private var activeVerticalOffset: CGFloat {
        guard !reduceMotion, isCurrent else { return 0 }
        let p = fillProgress
        switch style {
        case .floating:
            return CGFloat(sin(p * .pi * 2) * -3.2)
        default:
            // 唱响时轻微浮起 -2.2pt，唱完平滑落回
            return CGFloat(sin(p * .pi) * -2.2)
        }
    }

    private var activeHorizontalOffset: CGFloat {
        guard !reduceMotion, isCurrent else { return 0 }
        switch style {
        case .sway:
            return CGFloat(sin(fillProgress * .pi * 2) * 2.2)
        default:
            return 0
        }
    }

    // MARK: - Glow & Colors

    private var glowColor: Color {
        guard isCurrent else { return .clear }
        switch style {
        case .neon: return Color.cyan
        case .shimmer: return Color.white
        case .blaze: return Color.orange
        case .crystallize: return Color.cyan
        case .heartbeat: return Color.pink
        case .impact: return Color.white
        case .whisper, .vintage: return Color.white.opacity(0.4)
        default: return Color.white
        }
    }

    private var glowOpacity: Double {
        guard isCurrent else { return 0 }
        let p = fillProgress
        switch style {
        case .neon: return 0.88
        case .blaze: return 0.78
        case .shimmer, .crystallize: return 0.70
        case .impact: return 0.60
        default: return sin(p * .pi) * 0.50
        }
    }

    private var glowRadius: CGFloat {
        guard isCurrent else { return 0 }
        switch style {
        case .neon: return 14
        case .shimmer, .blaze: return 12
        case .crystallize, .heartbeat, .impact: return 10
        default: return 6
        }
    }

    // MARK: - Revealed Text Layer

    @ViewBuilder
    private var revealedText: some View {
        switch style {
        case .blaze:
            // 烈焰金红双色渐变字
            Text(text)
                .font(tokenFont)
                .tracking(tracking)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.95, blue: 0.55), Color(red: 1.0, green: 0.45, blue: 0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        case .neon:
            // 霓虹青蓝发光字
            Text(text)
                .font(tokenFont)
                .tracking(tracking)
                .foregroundStyle(Color(red: 0.65, green: 0.95, blue: 1.0))
        case .impact:
            // 赛博微色散瞬闪
            ZStack {
                Text(text)
                    .font(tokenFont)
                    .tracking(tracking)
                    .foregroundStyle(Color.red.opacity(0.6))
                    .offset(x: fillProgress < 0.25 ? -1.8 : 0)
                Text(text)
                    .font(tokenFont)
                    .tracking(tracking)
                    .foregroundStyle(Color.cyan.opacity(0.6))
                    .offset(x: fillProgress < 0.25 ? 1.8 : 0)
                Text(text)
                    .font(tokenFont)
                    .tracking(tracking)
                    .foregroundStyle(PlayerSurface.textPrimary)
            }
        default:
            Text(text)
                .font(tokenFont)
                .tracking(tracking)
                .italic(isItalic)
                .foregroundStyle(PlayerSurface.textPrimary)
        }
    }

    // MARK: - VFX Backgrounds & Overlays

    @ViewBuilder
    private var backgroundVFX: some View {
        switch style {
        case .impact:
            // 爆发冲击光环 (Shockwave Ring)
            let p = fillProgress
            let waveScale = 0.8 + CGFloat(p) * 0.9
            let waveOpacity = max(0, 1.0 - p * 1.4)
            Circle()
                .stroke(Color.white.opacity(waveOpacity * 0.55), lineWidth: 2)
                .scaleEffect(waveScale)
        case .ripple:
            // 回音双重残影 (Phantom Echo)
            HStack(spacing: 0) {
                Text(text)
                    .font(tokenFont)
                    .tracking(tracking)
                    .foregroundStyle(PlayerSurface.textPrimary.opacity(0.25))
                    .offset(x: -10)
                Text(text)
                    .font(tokenFont)
                    .tracking(tracking)
                    .foregroundStyle(PlayerSurface.textPrimary.opacity(0.12))
                    .offset(x: -20)
            }
            .accessibilityHidden(true)
        case .heartbeat:
            // 心跳粉红光晕脉冲 (Heartbeat Pulse Aura)
            let p = fillProgress
            let pulseOpacity = sin(p * .pi * 2) * 0.45
            Circle()
                .fill(Color.pink.opacity(max(0, pulseOpacity)))
                .scaleEffect(1.4)
                .blur(radius: 10)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var foregroundVFX: some View {
        switch style {
        case .shimmer:
            // 白金流光遮罩
            GeometryReader { proxy in
                let width = proxy.size.width
                let shimmerWidth = max(width * 0.7, 28)
                let offset = (width + shimmerWidth) * CGFloat(fillProgress) - shimmerWidth
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.95), location: 0.5),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: shimmerWidth)
                .offset(x: offset)
                .blendMode(.plusLighter)
                .mask { Rectangle().frame(width: width) }
            }
        case .crystallize:
            // 钻石折射八芒星光 (8-Point Diamond Star)
            GeometryReader { proxy in
                let p = fillProgress
                let flareOpacity = p < 0.5 ? (p / 0.5) : (1.0 - (p - 0.5) / 0.5)
                let size = min(proxy.size.width, proxy.size.height)
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(flareOpacity * 0.95))
                        .frame(width: 5, height: 5)
                    Rectangle()
                        .fill(Color.white.opacity(flareOpacity * 0.85))
                        .frame(width: size * 1.2, height: 1.5)
                    Rectangle()
                        .fill(Color.white.opacity(flareOpacity * 0.85))
                        .frame(width: 1.5, height: size * 1.2)
                    Rectangle()
                        .fill(Color.cyan.opacity(flareOpacity * 0.6))
                        .frame(width: size * 0.8, height: 1)
                        .rotationEffect(.degrees(45))
                }
                .rotationEffect(.degrees(p * 75))
                .position(x: proxy.size.width * CGFloat(p), y: proxy.size.height * 0.35)
                .blendMode(.plusLighter)
            }
        case .blaze:
            // 升腾微余烬微粒 (Ember Particles)
            GeometryReader { proxy in
                let p = fillProgress
                Circle()
                    .fill(Color.orange.opacity(max(0, 1.0 - p)))
                    .frame(width: 3.5, height: 3.5)
                    .offset(x: proxy.size.width * 0.3 + CGFloat(sin(p * .pi * 4)) * 4.5, y: -CGFloat(p * 20))
                Circle()
                    .fill(Color.yellow.opacity(max(0, 1.0 - p * 1.2)))
                    .frame(width: 2.8, height: 2.8)
                    .offset(x: proxy.size.width * 0.7 - CGFloat(cos(p * .pi * 3)) * 5.5, y: -CGFloat(p * 24))
            }
        default:
            EmptyView()
        }
    }
}

// MARK: - Line-Level Dynamic Fluid Sweep View (适用于非逐字 LRC 歌词的整行流光动效)

struct LyricVFXLineView: View {
    let line: PlayerEngine.LyricLine
    let time: Double
    let style: LyricEmbellishmentStyle
    let fontSize: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let progress = lineProgress

        ZStack(alignment: .leading) {
            // 1. 未唱暗色基底文字
            Text(line.text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(PlayerSurface.lyricUnsung)

            // 2. 随音频秒数动态向前推进的流光扫亮层 (Progressive Liquid Mask)
            if progress > 0 {
                revealedLineText
                    .mask(alignment: .leading) {
                        GeometryReader { proxy in
                            Rectangle()
                                .frame(width: proxy.size.width * CGFloat(progress))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .blur(radius: 1.2)
                        }
                    }
            }

            // 3. 推进光针与微光晕 (Progressive Traveling Flare)
            if progress > 0 && progress < 1.0, !reduceMotion {
                GeometryReader { proxy in
                    let headX = proxy.size.width * CGFloat(progress)
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 6, height: 6)
                            .blur(radius: 1)
                        Circle()
                            .fill(Color.cyan.opacity(0.65))
                            .frame(width: 15, height: 15)
                            .blur(radius: 5)
                    }
                    .position(x: headX, y: proxy.size.height * 0.5)
                    .blendMode(.plusLighter)
                }
            }
        }
        .scaleEffect(reduceMotion ? 1.0 : (1.0 + CGFloat(sin(progress * .pi) * 0.035)), anchor: .leading)
        .offset(y: reduceMotion ? 0 : CGFloat(sin(progress * .pi) * -2.0))
        .shadow(
            color: Color.white.opacity(sin(progress * .pi) * 0.38),
            radius: 8
        )
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHidden(true)
    }

    private var lineProgress: Double {
        let duration = max(0.4, line.to - line.from)
        let elapsed = time - line.from
        return max(0, min(1.0, elapsed / duration))
    }

    @ViewBuilder
    private var revealedLineText: some View {
        switch style {
        case .blaze:
            Text(line.text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.95, blue: 0.55), Color(red: 1.0, green: 0.45, blue: 0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        case .neon:
            Text(line.text)
                .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.65, green: 0.95, blue: 1.0))
        case .whisper:
            Text(line.text)
                .font(.system(size: fontSize, weight: .medium, design: .serif))
                .foregroundStyle(PlayerSurface.textPrimary)
        default:
            Text(line.text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(PlayerSurface.textPrimary)
        }
    }
}
