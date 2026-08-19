import CoreGraphics
import Foundation

struct ResolvedStageGlyph: Equatable, Sendable {
    let id: Int
    let text: String
    let lineIndex: Int
    let tokenID: Int
    let actorID: String
    let origin: CGPoint
    let size: CGSize
    let fontSize: Double
    let isBold: Bool
    let paletteRole: StagePaletteRole
    let syncWindow: ClosedRange<Double>?
    let performanceWindow: ClosedRange<Double>
    let visibleWindow: ClosedRange<Double>
    let events: [ResolvedGlyphEvent]
    let handoffs: [ResolvedHandoffWindow]
    let echoLayers: Int
    let isBackdrop: Bool
    let seed: Int
}

struct ResolvedGlyphEvent: Equatable, Sendable {
    let phase: StageEventPhase
    let verb: StageVerb
    let start: Double
    let end: Double
    let intensity: Double
    let direction: Int
    let relationOffset: CGSize
}

struct ResolvedHandoffWindow: Equatable, Sendable {
    let kind: StageHandoff
    let start: Double
    let end: Double
    let outgoing: Bool
}

struct SampledStageGlyph: Equatable, Sendable {
    let id: Int
    let text: String
    let origin: CGPoint
    let size: CGSize
    let fontSize: Double
    let isBold: Bool
    let offset: CGSize
    let scaleX: Double
    let scaleY: Double
    let rotation: Double
    let opacity: Double
    let color: StageResolvedPalette.RGBA
    let echoLayers: Int
    let echoOffset: CGSize
    let isBackdrop: Bool
}

struct ResolvedStageScore: Equatable, Sendable {
    let version: String
    let trackID: String
    let lyricsHash: String
    let canvasSize: CGSize
    let glyphs: [ResolvedStageGlyph]
    let palette: StageResolvedPalette
    let summary: LyricStagePerformanceSummary
    let reduceMotion: Bool

    func sample(at time: Double) -> [SampledStageGlyph] {
        LyricStageTimeline.sample(glyphs, at: time, palette: palette, reduceMotion: reduceMotion)
    }
}

enum LyricStageTimeline {
    static func sample(
        _ glyphs: [ResolvedStageGlyph],
        at time: Double,
        palette: StageResolvedPalette,
        reduceMotion: Bool
    ) -> [SampledStageGlyph] {
        var sampled: [SampledStageGlyph] = []
        sampled.reserveCapacity(glyphs.count)
        for glyph in glyphs {
            guard glyph.visibleWindow.contains(time) || padded(glyph.visibleWindow, 0.08).contains(time) else {
                continue
            }
            let state = sample(glyph, at: time, palette: palette, reduceMotion: reduceMotion)
            if state.opacity > 0.01 {
                sampled.append(state)
            }
        }
        return sampled
    }

    static func sample(
        _ glyph: ResolvedStageGlyph,
        at time: Double,
        palette: StageResolvedPalette,
        reduceMotion: Bool
    ) -> SampledStageGlyph {
        let window = glyph.performanceWindow
        let span = max(0.12, window.upperBound - window.lowerBound)
        let local = LyricStageMath.progress(time, start: window.lowerBound, duration: span)
        var opacity = baselineOpacity(local)
        var scaleX = 1.0
        var scaleY = 1.0
        var offsetX = 0.0
        var offsetY = 0.0
        var rotation = 0.0
        var echoLayers = 0
        var echoOffset = CGSize.zero

        for event in glyph.events where StageChoreography.allows(event.verb, in: event.phase) {
            let progress = LyricStageMath.smooth(
                LyricStageMath.progress(time, start: event.start, duration: max(0.04, event.end - event.start)))
            apply(
                event,
                progress: progress,
                seed: glyph.seed,
                reduceMotion: reduceMotion,
                opacity: &opacity,
                scaleX: &scaleX,
                scaleY: &scaleY,
                offsetX: &offsetX,
                offsetY: &offsetY,
                rotation: &rotation,
                echoLayers: &echoLayers,
                echoOffset: &echoOffset)
        }

        for handoff in glyph.handoffs {
            applyHandoff(
                handoff,
                time: time,
                reduceMotion: reduceMotion,
                opacity: &opacity,
                offsetX: &offsetX,
                offsetY: &offsetY)
        }

        let color = highlightedColor(
            of: palette.color(for: glyph.paletteRole),
            glyph: glyph,
            time: time)

        if reduceMotion {
            offsetX *= 0.08
            offsetY *= 0.08
            rotation = 0
            echoLayers = min(echoLayers, 1)
        }

        return SampledStageGlyph(
            id: glyph.id,
            text: glyph.text,
            origin: glyph.origin,
            size: glyph.size,
            fontSize: glyph.fontSize,
            isBold: glyph.isBold,
            offset: CGSize(width: offsetX, height: offsetY),
            scaleX: scaleX,
            scaleY: scaleY,
            rotation: rotation,
            opacity: min(max(opacity, 0), 1),
            color: color,
            echoLayers: min(echoLayers, LyricStageBudget.maxEchoLayers),
            echoOffset: echoOffset,
            isBackdrop: glyph.isBackdrop)
    }

    private static func baselineOpacity(_ local: Double) -> Double {
        if local < 0.35 {
            return 0.22 + 0.78 * LyricStageMath.smooth(local / 0.35)
        }
        if local > 0.80 {
            return 1 - 0.62 * LyricStageMath.smooth((local - 0.80) / 0.20)
        }
        return 1
    }

    private static func apply(
        _ event: ResolvedGlyphEvent,
        progress: Double,
        seed: Int,
        reduceMotion: Bool,
        opacity: inout Double,
        scaleX: inout Double,
        scaleY: inout Double,
        offsetX: inout Double,
        offsetY: inout Double,
        rotation: inout Double,
        echoLayers: inout Int,
        echoOffset: inout CGSize
    ) {
        let intensity = phaseIntensity(event.phase, event.intensity)
        let inverse = event.phase == .exit ? progress : (1 - progress)
        let wave = event.phase == .hold ? sin(.pi * progress) * 0.35 : sin(.pi * progress)
        switch event.verb {
        case .appear:
            if event.phase == .hold {
                opacity = max(opacity, 1)
            } else {
                opacity = max(opacity, 0.25 + 0.75 * progress)
                scaleX *= 0.94 + 0.06 * progress
                scaleY *= 0.94 + 0.06 * progress
            }
        case .assemble:
            let scatterX = Double((seed * 37) % 9 - 4)
            let scatterY = seed.isMultiple(of: 2) ? -1.0 : 1.0
            offsetX += scatterX * 13 * inverse * intensity
            offsetY += scatterY * 48 * inverse * intensity
            rotation += Double((seed % 3) - 1) * 16 * inverse
            opacity = max(opacity, progress)
        case .drift:
            offsetX += Double(event.direction) * 36 * inverse * intensity
            offsetX += Double(event.direction) * sin(progress * .pi) * 5
            rotation += Double(event.direction) * 4 * inverse
        case .drop:
            let drop = reduceMotion ? inverse : (1 - LyricStageMath.bounceOut(progress))
            offsetY += -86 * drop * intensity
            scaleX *= 0.84 + 0.16 * progress
            scaleY *= 1.16 - 0.16 * progress
        case .pulse:
            scaleX *= 1 + 0.16 * wave * intensity
            scaleY *= 1 + 0.10 * wave * intensity
        case .stretch:
            scaleX *= 0.64 + 0.36 * progress + 0.16 * wave * intensity
            scaleY *= 1.12 - 0.12 * progress
        case .echo:
            echoLayers = max(echoLayers, 2)
            echoOffset = CGSize(
                width: Double(event.direction) * (5 + 5 * wave),
                height: 1.5 * wave)
            opacity = max(opacity, 0.85)
        case .scatter:
            let scatterX = Double((seed * 19) % 11 - 5)
            offsetX += scatterX * 22 * progress * intensity
            offsetY += Double(seed.isMultiple(of: 2) ? -1 : 1) * 28 * progress * intensity
            opacity *= 1 - 0.75 * progress
            rotation += Double((seed % 5) - 2) * 10 * progress
        case .dissolve:
            opacity *= 1 - 0.72 * progress
        }
        offsetX += event.relationOffset.width * wave * intensity
        offsetY += event.relationOffset.height * wave * intensity
    }

    private static func phaseIntensity(_ phase: StageEventPhase, _ intensity: Double) -> Double {
        phase == .hold ? intensity * 0.4 : intensity
    }

    private static func applyHandoff(
        _ handoff: ResolvedHandoffWindow,
        time: Double,
        reduceMotion: Bool,
        opacity: inout Double,
        offsetX: inout Double,
        offsetY: inout Double
    ) {
        let progress = LyricStageMath.smooth(
            LyricStageMath.progress(time, start: handoff.start, duration: max(0.04, handoff.end - handoff.start)))
        switch handoff.kind {
        case .cut:
            if handoff.outgoing, progress > 0 { opacity = 0 }
        case .dissolve, .residue:
            opacity *= handoff.outgoing ? (1 - progress) : progress
        case .push(let direction):
            if reduceMotion {
                opacity *= handoff.outgoing ? (1 - progress) : progress
                return
            }
            let signed: Double
            switch direction {
            case .leading: signed = handoff.outgoing ? -1 : 1
            case .trailing: signed = handoff.outgoing ? 1 : -1
            case .up: signed = 0
            case .down: signed = 0
            }
            if direction == .up || direction == .down {
                let vertical: Double = direction == .up
                    ? (handoff.outgoing ? -1 : 1)
                    : (handoff.outgoing ? 1 : -1)
                offsetY += vertical * 36 * (handoff.outgoing ? progress : 1 - progress)
            } else {
                offsetX += signed * 48 * (handoff.outgoing ? progress : 1 - progress)
            }
            opacity *= handoff.outgoing ? (1 - 0.35 * progress) : (0.55 + 0.45 * progress)
        }
    }

    private static func highlightedColor(
        of base: StageResolvedPalette.RGBA,
        glyph: ResolvedStageGlyph,
        time: Double
    ) -> StageResolvedPalette.RGBA {
        guard let sync = glyph.syncWindow else { return base }
        if time >= sync.upperBound { return base.mixed(with: .white, amount: 0.04) }
        if time >= sync.lowerBound { return base }
        return base.mixed(with: StageResolvedPalette.RGBA(r: base.r, g: base.g, b: base.b, a: 0.34), amount: 0.66)
    }

    private static func padded(_ range: ClosedRange<Double>, _ pad: Double) -> ClosedRange<Double> {
        (range.lowerBound - pad)...(range.upperBound + pad)
    }
}