import SwiftUI

struct LyricStageView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let isMotionEnabled: Bool
    let performanceScore: LyricPerformanceScore?
    let action: () -> Void

    var body: some View {
        if let score {
            TimelineView(.animation(
                minimumInterval: 1.0 / 60.0,
                paused: !isClockRunning
            )) { _ in
                stage(score: score, time: preciseLyricTime)
            }
        }
    }

    private var score: LyricStageScore? {
        LyricStageCompiler.compile(
            trackID: engine.current?.key.description ?? "unknown-track",
            lines: engine.lyrics,
            performanceScore: performanceScore)
    }

    private func stage(score: LyricStageScore, time: Double) -> some View {
        let indices = LyricStageCompiler.visibleLineIndices(
            lines: engine.lyrics,
            at: time,
            performanceScore: performanceScore)
        let active = Set(LyricHighlightModel.activeLineIndices(lines: engine.lyrics, at: time))
        return Button(action: action) {
            ZStack {
                ForEach(Array(indices.enumerated()), id: \.element) { position, index in
                    if let line = engine.lyrics[safe: index],
                       let scene = score.scene(for: index) {
                        LyricStageLineView(
                            line: line,
                            scene: scene,
                            wordCue: performanceScore?.wordCue(for: index),
                            time: time,
                            position: position,
                            visibleCount: indices.count,
                            isActive: active.contains(index),
                            reduceMotion: reduceMotion)
                    }
                }
            }
            .frame(maxWidth: 340, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("当前动态歌词")
        .accessibilityHint("打开完整歌词")
        .accessibilityIdentifier("lyricStageView")
    }

    private var isClockRunning: Bool {
        isMotionEnabled && engine.state == .playing && scenePhase == .active && !reduceMotion
    }

    private var preciseLyricTime: Double {
        let playerTime = engine.avPlayer?.currentTime().seconds ?? engine.currentTime
        let base = playerTime.isFinite ? playerTime : engine.currentTime
        return base + Double(engine.lyricOffsetMilliseconds) / 1_000
    }
}

private struct LyricStageLineView: View {
    let line: PlayerEngine.LyricLine
    let scene: LyricStageScene
    let wordCue: LyricWordCue?
    let time: Double
    let position: Int
    let visibleCount: Int
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        let glyphs = LyricStageCompiler.glyphs(for: line)
        LyricStageWrapLayout(alignment: scene.alignment, spacing: glyphSpacing) {
            ForEach(glyphs) { glyph in
                LyricStageGlyphView(
                    glyph: glyph,
                    scene: scene,
                    wordCue: wordCue,
                    role: line.voiceRole,
                    time: time,
                    isActiveLine: isActive,
                    reduceMotion: reduceMotion)
            }
        }
        .frame(maxWidth: 340)
        .offset(x: sentenceOffsetX, y: sentenceOffsetY)
        .scaleEffect(sentenceScale, anchor: scene.alignment.unitPoint)
        .rotationEffect(.degrees(sentenceRotation))
        .opacity(lineOpacity)
        .zIndex(isActive ? 10 : Double(visibleCount - position))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.text)
    }

    private var glyphSpacing: CGFloat {
        switch scene.behavior {
        case .stretch: return 1.4
        case .focus: return 0.8
        default: return 0
        }
    }

    private var normalizedLineTime: Double {
        LyricStageMath.progress(time, start: scene.from, duration: max(0.12, scene.to - scene.from))
    }

    private var sentenceOffsetX: CGFloat {
        guard !reduceMotion else { return 0 }
        let p = LyricStageMath.smooth(LyricStageMath.progress(
            time,
            start: scene.from - 0.2,
            duration: 0.7))
        switch scene.behavior {
        case .drift:
            return CGFloat(scene.direction) * CGFloat(20 * (1 - p) + sin(normalizedLineTime * .pi) * 6)
        case .converge:
            let direction = vocalDirection
            return CGFloat(direction) * CGFloat(72 * (1 - p))
        default:
            return 0
        }
    }

    private var sentenceOffsetY: CGFloat {
        let stackOffset = CGFloat(position) * 34 - CGFloat(max(0, visibleCount - 1)) * 17
        guard !reduceMotion else { return stackOffset }
        switch scene.behavior {
        case .ripple:
            return stackOffset + CGFloat(sin(normalizedLineTime * .pi * 2) * 3)
        case .gravityDrop:
            return stackOffset + CGFloat(5 * sin(normalizedLineTime * .pi))
        default:
            return stackOffset
        }
    }

    private var sentenceScale: CGFloat {
        guard !reduceMotion else { return 1 }
        switch scene.behavior {
        case .gravityDrop:
            return CGFloat(1 + 0.045 * sin(normalizedLineTime * .pi) * scene.intensity)
        case .ripple:
            return CGFloat(1 + 0.018 * sin(normalizedLineTime * .pi * 2))
        default:
            return 1
        }
    }

    private var sentenceRotation: Double {
        guard !reduceMotion else { return 0 }
        switch scene.behavior {
        case .drift: return Double(scene.direction) * sin(normalizedLineTime * .pi) * 0.8
        case .converge: return Double(vocalDirection) * (1 - normalizedLineTime) * 1.2
        default: return 0
        }
    }

    private var lineOpacity: Double {
        if isActive {
            return line.voiceRole.isSecondary ? 0.76 : 1
        }
        return line.voiceRole.isSecondary ? 0.42 : 0.55
    }

    private var vocalDirection: Int {
        switch line.voiceRole {
        case .duetA: -1
        case .duetB: 1
        case .backing: scene.direction
        case .lead, .together: 0
        }
    }
}

private struct LyricStageGlyphView: View {
    let glyph: LyricStageGlyph
    let scene: LyricStageScene
    let wordCue: LyricWordCue?
    let role: LyricVoiceRole
    let time: Double
    let isActiveLine: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            if (scene.behavior == .echo || (isCued && wordCue?.effect == .echoTrail)), !reduceMotion, activation > 0.01 {
                ForEach(1...2, id: \.self) { layer in
                    glyphText
                        .foregroundStyle(stageColor.opacity(0.13 / Double(layer)))
                        .offset(
                            x: CGFloat(scene.direction * layer) * CGFloat(5 + 5 * wave),
                            y: CGFloat(layer) * 1.5)
                        .blur(radius: CGFloat(layer) * 0.5)
                        .accessibilityHidden(true)
                }
            }
            glyphText
                .foregroundStyle(glyphColor)
                .shadow(color: stageColor.opacity(glowOpacity), radius: glowRadius)
        }
        .scaleEffect(x: scaleX, y: scaleY)
        .rotationEffect(.degrees(rotation))
        .offset(x: offsetX, y: offsetY)
        .blur(radius: blurRadius)
        .opacity(opacity)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var glyphText: some View {
        Text(glyph.text)
            .font(.system(size: fontSize, weight: fontWeight))
    }

    private var isCued: Bool {
        guard let wordCue, let wordIndex = glyph.wordIndex else { return false }
        return wordCue.contains(wordIndex: wordIndex)
    }

    private var activation: Double {
        if !isActiveLine { return 1 }
        let start = glyph.performanceFrom - 0.12
        if reduceMotion { return time >= start ? 1 : 0.35 }
        return LyricStageMath.smooth(LyricStageMath.progress(
            time,
            start: start,
            duration: max(0.28, min(0.64, glyph.performanceTo - glyph.performanceFrom + 0.22))))
    }

    private var wave: Double {
        sin(.pi * LyricStageMath.progress(
            time,
            start: glyph.from,
            duration: max(0.08, glyph.to - glyph.from)))
    }

    private var offsetX: CGFloat {
        guard !reduceMotion else { return 0 }
        let seed = Double((glyph.id * 37) % 9 - 4)
        switch scene.behavior {
        case .assemble:
            return CGFloat(seed * 13 * (1 - activation) * scene.intensity)
        case .drift:
            return CGFloat(scene.direction) * CGFloat(44 * (1 - activation))
        case .converge:
            return CGFloat(vocalDirection) * CGFloat(62 * (1 - activation))
        case .echo:
            return CGFloat(scene.direction) * CGFloat(9 * wave)
        default:
            return 0
        }
    }

    private var offsetY: CGFloat {
        guard !reduceMotion else { return 0 }
        switch scene.behavior {
        case .assemble:
            let direction = glyph.id.isMultiple(of: 2) ? -1.0 : 1.0
            return CGFloat(direction * 58 * (1 - activation) * scene.intensity)
        case .gravityDrop:
            return CGFloat(-96 * (1 - LyricStageMath.bounceOut(activation)) * scene.intensity)
        case .ripple:
            return CGFloat(sin(time * 4.2 + Double(glyph.id) * 0.72) * 5 * activation)
        case .echo:
            return CGFloat(-3 * wave)
        default:
            return 0
        }
    }

    private var scaleX: CGFloat {
        guard !reduceMotion else { return 1 }
        if isCued, wordCue?.effect == .impact {
            return CGFloat(1 + 0.16 * wave * (wordCue?.intensity ?? 1))
        }
        if isCued, wordCue?.effect == .stretch {
            return CGFloat(0.62 + 0.38 * activation + 0.18 * wave)
        }
        switch scene.behavior {
        case .stretch: return CGFloat(0.58 + 0.42 * activation + 0.16 * wave * scene.intensity)
        case .gravityDrop: return CGFloat(0.82 + 0.18 * activation)
        default: return CGFloat(0.72 + 0.28 * activation)
        }
    }

    private var scaleY: CGFloat {
        guard !reduceMotion else { return 1 }
        switch scene.behavior {
        case .gravityDrop: return CGFloat(1.20 - 0.20 * activation + 0.06 * wave)
        case .stretch: return CGFloat(1.14 - 0.14 * activation)
        default: return CGFloat(0.84 + 0.16 * activation)
        }
    }

    private var rotation: Double {
        guard !reduceMotion else { return 0 }
        switch scene.behavior {
        case .assemble:
            return Double((glyph.id % 3) - 1) * 18 * (1 - activation)
        case .drift:
            return Double(scene.direction) * 5 * (1 - activation)
        default:
            return 0
        }
    }

    private var blurRadius: CGFloat {
        guard !reduceMotion else { return 0 }
        switch scene.behavior {
        case .focus: return CGFloat(6 * (1 - activation))
        case .echo: return CGFloat(0.4 * wave)
        default: return 0
        }
    }

    private var opacity: Double {
        if !isActiveLine { return role.isSecondary ? 0.54 : 0.68 }
        if glyph.hasRealWordTiming {
            // The stage keeps the complete sentence legible while timing
            // controls emphasis and motion. Unsung glyphs must not disappear.
            return 0.76 + 0.24 * activation
        }
        return max(0.22, activation)
    }

    private var glyphColor: Color {
        guard glyph.hasRealWordTiming, isActiveLine else { return stageColor }
        if time >= glyph.to { return stageColor.opacity(0.98) }
        if time >= glyph.from { return stageColor }
        return stageColor.opacity(0.34)
    }

    private var stageColor: Color {
        switch scene.paletteRole {
        case .primary: return PlayerSurface.textPrimary
        case .secondary: return PlayerSurface.textSecondary
        case .accent: return Color(red: 0.39, green: 0.94, blue: 1)
        case .warm: return Color(red: 1, green: 0.45, blue: 0.58)
        }
    }

    private var fontSize: CGFloat {
        let base = role.isSecondary ? min(scene.fontSize * 0.68, 22) : scene.fontSize
        return CGFloat(base)
    }

    private var fontWeight: Font.Weight {
        role.isSecondary ? .semibold : .black
    }

    private var glowOpacity: Double {
        guard isActiveLine, time >= glyph.from, time < glyph.to else { return 0 }
        return 0.16 + 0.18 * wave * scene.intensity
    }

    private var glowRadius: CGFloat {
        glowOpacity > 0 ? CGFloat(3 + 5 * wave) : 0
    }

    private var vocalDirection: Int {
        switch role {
        case .duetA: -1
        case .duetB: 1
        case .backing: scene.direction
        case .lead, .together: 0
        }
    }
}

enum LyricStageMath {
    static func progress(_ time: Double, start: Double, duration: Double) -> Double {
        guard duration > 0 else { return time >= start ? 1 : 0 }
        return min(max((time - start) / duration, 0), 1)
    }

    static func smooth(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }

    static func bounceOut(_ value: Double) -> Double {
        LyricStagePrototypeTimeline.bounceOut(value)
    }
}

private struct LyricStageWrapLayout: Layout {
    let alignment: LyricMotionAlignment
    let spacing: CGFloat
    private let lineSpacing: CGFloat = 4

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = max(1, proposal.width ?? 340)
        let rows = rows(subviews: subviews, maxWidth: width)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = rows(subviews: subviews, maxWidth: max(1, bounds.width))
        var y = bounds.minY
        for row in rows {
            let originX: CGFloat
            switch alignment {
            case .leading: originX = bounds.minX
            case .center: originX = bounds.midX - row.width / 2
            case .trailing: originX = bounds.maxX - row.width
            }
            var x = originX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: .unspecified)
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func rows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var result: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if proposed > maxWidth, !current.items.isEmpty {
                result.append(current)
                current = Row()
            }
            current.items.append(Item(index: index, size: size))
            current.width = current.items.count == 1 ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
        }
        if !current.items.isEmpty { result.append(current) }
        return result
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
}

private extension LyricMotionAlignment {
    var unitPoint: UnitPoint {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
