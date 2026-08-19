import SwiftUI

@Observable
@MainActor
final class LyricStageRenderCache {
    private var identity: String?
    private(set) var resolved: ResolvedStageScore?
    private(set) var compileFailed = false

    func update(
        trackID: String,
        lines: [PlayerEngine.LyricLine],
        score: LyricStageScoreV2?,
        performanceScore: LyricPerformanceScore?,
        canvasSize: CGSize,
        dynamicTypeScale: CGFloat,
        reduceMotion: Bool,
        palette: PlayerArtworkPalette
    ) {
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(lines)
        let next = LyricStageFingerprint.cacheKey(
            trackID: trackID,
            lyricsHash: lyricsHash,
            score: score,
            performanceScore: performanceScore,
            palette: palette,
            canvasSize: canvasSize,
            dynamicTypeScale: dynamicTypeScale,
            reduceMotion: reduceMotion)
        guard next != identity else { return }
        identity = next
        resolved = LyricStageCompilerV2.compile(
            trackID: trackID,
            lines: lines,
            score: score,
            performanceScore: performanceScore,
            canvasSize: canvasSize,
            dynamicTypeScale: dynamicTypeScale,
            reduceMotion: reduceMotion,
            palette: palette)
        compileFailed = resolved == nil
    }
}

struct LyricStageCanvasView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let isMotionEnabled: Bool
    let score: LyricStageScoreV2?
    let performanceScore: LyricPerformanceScore?
    let action: () -> Void

    @State private var cache = LyricStageRenderCache()

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = CGSize(width: min(340, proxy.size.width), height: proxy.size.height)
            let _ = cache.update(
                trackID: engine.current?.key.description ?? "unknown-track",
                lines: engine.lyrics,
                score: score,
                performanceScore: performanceScore,
                canvasSize: canvasSize,
                dynamicTypeScale: Self.scale(for: dynamicTypeSize),
                reduceMotion: reduceMotion,
                palette: engine.currentArtworkPalette)
            Button(action: action) {
                ZStack {
                    if let resolved = cache.resolved, !resolved.glyphs.isEmpty {
                        TimelineView(.animation(minimumInterval: clockInterval, paused: !shouldRefreshClock)) { tick in
                            let renderTime = preciseLyricTime(at: tick.date)
                            Canvas { context, size in
                                draw(resolved, in: context, size: size, time: renderTime)
                            }
                            .frame(width: canvasSize.width, height: canvasSize.height)
                        }
                    } else {
                        LyricStageStaticFallback(lines: engine.lyrics, time: engine.currentTime)
                    }
                }
                .frame(maxWidth: 340, maxHeight: .infinity)
                .clipped()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 340, maxHeight: .infinity)
        .accessibilityLabel("当前动态歌词")
        .accessibilityHint("打开完整歌词")
        .accessibilityIdentifier("lyricStageCanvasView")
    }

    private var shouldRefreshClock: Bool {
        scenePhase == .active && engine.current != nil
    }

    private var clockInterval: TimeInterval {
        let activelyPlaying = engine.state == .playing || (engine.avPlayer?.rate ?? 0) > 0
        guard activelyPlaying, !reduceMotion else { return 0.25 }
        return isMotionEnabled ? 1.0 / 60.0 : 1.0 / 30.0
    }

    private func preciseLyricTime(at tickDate: Date) -> Double {
        _ = tickDate.timeIntervalSinceReferenceDate
        let playerTime = engine.avPlayer?.currentTime().seconds ?? engine.currentTime
        let base = playerTime.isFinite ? playerTime : engine.currentTime
        return base + Double(engine.lyricOffsetMilliseconds) / 1_000
    }

    private func draw(
        _ resolved: ResolvedStageScore,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let sampled = resolved.sample(at: time)
        for glyph in sampled where glyph.isBackdrop {
            paint(glyph, in: context, backdrop: true)
        }
        for glyph in sampled where !glyph.isBackdrop {
            paint(glyph, in: context, backdrop: false)
        }
        _ = size
    }

    private func paint(_ glyph: SampledStageGlyph, in context: GraphicsContext, backdrop: Bool) {
        let color = Color(
            red: glyph.color.r,
            green: glyph.color.g,
            blue: glyph.color.b,
            opacity: glyph.color.a * (backdrop ? min(glyph.opacity, 0.18) : glyph.opacity))
        if glyph.echoLayers > 0, !backdrop {
            for layer in 1...glyph.echoLayers {
                var echo = context
                echo.opacity = 0.13 / Double(layer)
                echo.translateBy(
                    x: glyph.origin.x + glyph.offset.width + glyph.echoOffset.width * CGFloat(layer),
                    y: glyph.origin.y + glyph.offset.height + CGFloat(layer) * 1.5)
                echo.draw(
                    Text(glyph.text)
                        .font(.system(size: glyph.fontSize, weight: glyph.isBold ? .black : .semibold))
                        .foregroundStyle(color),
                    at: .zero,
                    anchor: .topLeading)
            }
        }
        var local = context
        let center = CGPoint(
            x: glyph.origin.x + glyph.size.width / 2 + glyph.offset.width,
            y: glyph.origin.y + glyph.size.height / 2 + glyph.offset.height)
        local.translateBy(x: center.x, y: center.y)
        local.rotate(by: .degrees(glyph.rotation))
        local.scaleBy(x: glyph.scaleX, y: glyph.scaleY)
        if glyph.syncGlow > 0 {
            local.addFilter(.shadow(color: color.opacity(glyph.syncGlow), radius: 4))
        }
        local.draw(
            Text(glyph.text)
                .font(.system(size: glyph.fontSize, weight: glyph.isBold ? .black : .semibold))
                .foregroundStyle(color),
            at: CGPoint(x: -glyph.size.width / 2, y: -glyph.size.height / 2),
            anchor: .topLeading)
    }

    static func scale(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: 0.86
        case .small: 0.92
        case .medium: 0.96
        case .large: 1
        case .xLarge: 1.06
        case .xxLarge: 1.12
        case .xxxLarge: 1.16
        default: 1.12
        }
    }
}

private struct LyricStageStaticFallback: View {
    let lines: [PlayerEngine.LyricLine]
    let time: Double

    var body: some View {
        let indices = LyricStageCompiler.visibleLineIndices(lines: lines, at: time, performanceScore: nil)
        VStack(spacing: 8) {
            ForEach(indices, id: \.self) { index in
                if let line = lines[safe: index] {
                    Text(line.text)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(PlayerSurface.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: 340)
        .accessibilityIdentifier("lyricStageCanvasFallback")
    }
}

private extension SampledStageGlyph {
    var syncGlow: Double {
        opacity > 0.9 ? 0.18 : 0
    }
}

struct LyricStageSummarySheet: View {
    let summary: LyricStagePerformanceSummary

    var body: some View {
        NavigationStack {
            List {
                Section("Style") {
                    Text(summary.concept)
                    Text(summary.paletteStrategy.rawValue)
                }
                if !summary.motifs.isEmpty {
                    Section("Motifs") {
                        ForEach(summary.motifs, id: \.self, content: Text.init)
                    }
                }
                if !summary.sections.isEmpty {
                    Section("Sections") {
                        ForEach(summary.sections, id: \.self, content: Text.init)
                    }
                }
                if !summary.heroScenes.isEmpty {
                    Section("Hero scenes") {
                        ForEach(summary.heroScenes, id: \.self, content: Text.init)
                    }
                }
                if !summary.handoffs.isEmpty {
                    Section("Handoffs") {
                        ForEach(summary.handoffs, id: \.self, content: Text.init)
                    }
                }
                if !summary.droppedEvents.isEmpty {
                    Section("被预算删除的事件") {
                        ForEach(Array(summary.droppedEvents.enumerated()), id: \.offset) { _, event in
                            Text("\(event.sceneID) \(event.actorID) \(event.verb.rawValue) · \(event.reason)")
                        }
                    }
                }
                if !summary.events.isEmpty {
                    Section("Events") {
                        ForEach(summary.events, id: \.self, content: Text.init)
                    }
                }
            }
            .navigationTitle("演出摘要")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("lyricStageSummarySheet")
    }
}
