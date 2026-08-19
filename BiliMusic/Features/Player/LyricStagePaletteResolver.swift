import UIKit

struct StageResolvedPalette: Equatable, Sendable {
    let primary: RGBA
    let secondary: RGBA
    let accent: RGBA
    let warm: RGBA
    let backgroundContrast: RGBA

    struct RGBA: Equatable, Sendable {
        var r: Double
        var g: Double
        var b: Double
        var a: Double

        static let white = RGBA(r: 0.96, g: 0.97, b: 0.98, a: 0.94)

        var uiColor: UIColor {
            UIColor(red: r, green: g, blue: b, alpha: a)
        }

        func mixed(with other: RGBA, amount: Double) -> RGBA {
            let t = amount.clamped(to: 0...1)
            return RGBA(
                r: r + (other.r - r) * t,
                g: g + (other.g - g) * t,
                b: b + (other.b - b) * t,
                a: a + (other.a - a) * t)
        }
    }

    func color(for role: StagePaletteRole) -> RGBA {
        switch role {
        case .primary: primary
        case .secondary: secondary
        case .accent: accent
        case .warm: warm
        case .backgroundContrast: backgroundContrast
        }
    }
}

enum LyricStagePaletteResolver {
    static func resolve(
        strategy: StagePaletteStrategy,
        cover: PlayerArtworkPalette = .fallback
    ) -> StageResolvedPalette {
        let base = hsba(from: cover.top)
        let mid = hsba(from: cover.middle)
        switch strategy {
        case .coverAnalogous:
            return palette(
                primary: readable(base, brightness: 0.92, saturation: min(0.18, base.s)),
                accent: readable(shifted(base, hue: 0.07), brightness: 0.86, saturation: 0.42),
                warm: readable(shifted(base, hue: -0.06), brightness: 0.84, saturation: 0.48),
                contrast: mid)
        case .coverComplementary:
            return palette(
                primary: readable(base, brightness: 0.93, saturation: min(0.14, base.s)),
                accent: readable(shifted(base, hue: 0.5), brightness: 0.82, saturation: 0.46),
                warm: readable(shifted(base, hue: 0.08), brightness: 0.84, saturation: 0.5),
                contrast: mid)
        case .coverMonochrome:
            return palette(
                primary: readable(base, brightness: 0.94, saturation: min(0.08, base.s)),
                accent: readable(base, brightness: 0.78, saturation: 0.22),
                warm: readable(base, brightness: 0.86, saturation: 0.16),
                contrast: mid)
        case .warmClimax:
            let warmHue = lerpHue(base.h, toward: 0.04, amount: 0.55)
            return palette(
                primary: readable(base, brightness: 0.93, saturation: min(0.16, base.s)),
                accent: readable(HSBA(h: warmHue, s: 0.52, b: 0.88, a: 1), brightness: 0.88, saturation: 0.52),
                warm: readable(HSBA(h: 0.02, s: 0.62, b: 0.9, a: 1), brightness: 0.9, saturation: 0.58),
                contrast: mid)
        case .coolClimax:
            let coolHue = lerpHue(base.h, toward: 0.54, amount: 0.55)
            return palette(
                primary: readable(base, brightness: 0.94, saturation: min(0.14, base.s)),
                accent: readable(HSBA(h: coolHue, s: 0.46, b: 0.9, a: 1), brightness: 0.9, saturation: 0.46),
                warm: readable(shifted(base, hue: 0.08), brightness: 0.82, saturation: 0.36),
                contrast: mid)
        }
    }

    private static func palette(
        primary: StageResolvedPalette.RGBA,
        accent: StageResolvedPalette.RGBA,
        warm: StageResolvedPalette.RGBA,
        contrast: HSBA
    ) -> StageResolvedPalette {
        StageResolvedPalette(
            primary: primary,
            secondary: primary.mixed(with: .init(r: 1, g: 1, b: 1, a: 0.66), amount: 0.28).withAlpha(0.7),
            accent: accent,
            warm: warm,
            backgroundContrast: readable(contrast, brightness: 0.22, saturation: 0.18).withAlpha(0.55))
    }

    private struct HSBA {
        var h: CGFloat
        var s: CGFloat
        var b: CGFloat
        var a: CGFloat
    }

    private static func hsba(from color: UIColor) -> HSBA {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return HSBA(h: h, s: s, b: b, a: a)
    }

    private static func shifted(_ color: HSBA, hue delta: CGFloat) -> HSBA {
        var next = color
        next.h = (color.h + delta).truncatingRemainder(dividingBy: 1)
        if next.h < 0 { next.h += 1 }
        return next
    }

    private static func lerpHue(_ from: CGFloat, toward: CGFloat, amount: CGFloat) -> CGFloat {
        let delta = ((toward - from + 1.5).truncatingRemainder(dividingBy: 1)) - 0.5
        var value = from + delta * amount
        if value < 0 { value += 1 }
        if value >= 1 { value -= 1 }
        return value
    }

    private static func readable(_ color: HSBA, brightness: CGFloat, saturation: CGFloat) -> StageResolvedPalette.RGBA {
        let ui = UIColor(
            hue: color.h,
            saturation: min(max(saturation, 0), 0.72),
            brightness: min(max(brightness, 0.18), 0.96),
            alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return StageResolvedPalette.RGBA(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
    }
}

private extension StageResolvedPalette.RGBA {
    func withAlpha(_ value: Double) -> StageResolvedPalette.RGBA {
        var copy = self
        copy.a = value
        return copy
    }
}
