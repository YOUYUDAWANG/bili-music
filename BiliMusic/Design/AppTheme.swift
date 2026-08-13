import SwiftUI
import UIKit

/// 全局主题。结构参考 Apple Music 的克制层级，品牌强调色使用更耐看的 B 站蓝青。
enum AppTheme {
    static let brand = Color(red: 0.000, green: 0.631, blue: 0.839)
    /// 品牌色的柔和背景（正在播放行高亮等）。动态色：
    /// 浅色模式用近白的浅青，深色模式用低亮度品牌色调，保证 `.secondary` 文字可读。
    static let brandSoft = Color(uiColor: UIColor { trait in
        if trait.userInterfaceStyle == .dark {
            return UIColor(red: 0.055, green: 0.145, blue: 0.180, alpha: 1)
        }
        return UIColor(red: 0.906, green: 0.973, blue: 1.000, alpha: 1)
    })
    static let accent = brand
    static let background = Color(uiColor: .systemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let secondaryBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let separator = Color(uiColor: .separator)
    static let label = Color(uiColor: .label)

    /// 语义颜色
    static let error = Color.red
    static let success = Color.green

    static let playerCoverRadius: CGFloat = 14
}

struct PlayerArtworkPalette: Equatable {
    let top: UIColor
    let middle: UIColor
    let bottom: UIColor

    static let fallback = PlayerArtworkPalette(
        top: UIColor(red: 0.42, green: 0.53, blue: 0.60, alpha: 1),
        middle: UIColor(red: 0.24, green: 0.32, blue: 0.39, alpha: 1),
        bottom: UIColor(red: 0.13, green: 0.17, blue: 0.22, alpha: 1)
    )

    static func == (lhs: PlayerArtworkPalette, rhs: PlayerArtworkPalette) -> Bool {
        lhs.top.isEqual(rhs.top)
            && lhs.middle.isEqual(rhs.middle)
            && lhs.bottom.isEqual(rhs.bottom)
    }

    static func from(_ image: UIImage?) -> PlayerArtworkPalette {
        guard let base = image?.averageColor else { return .fallback }
        let ambient = base
            .boostedSaturation(1.16)
            .limitedSaturation(minimum: 0.18, maximum: 0.72)
            .limitedBrightness(minimum: 0.34, maximum: 0.68)
        return PlayerArtworkPalette(
            top: ambient.mixed(with: .white, amount: 0.24),
            middle: ambient.mixed(with: UIColor(red: 0.28, green: 0.30, blue: 0.34, alpha: 1), amount: 0.18),
            bottom: ambient.mixed(with: .black, amount: 0.46)
        )
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(uiColor: top),
                Color(uiColor: middle),
                Color(uiColor: bottom)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var glow: RadialGradient {
        RadialGradient(
            colors: [
                Color(uiColor: top).opacity(0.92),
                Color(uiColor: middle).opacity(0.50),
                Color.clear
            ],
            center: .topLeading,
            startRadius: 24,
            endRadius: 520
        )
    }
}

private extension UIImage {
    var averageColor: UIColor? {
        guard let cgImage else { return nil }
        let width = 12
        let height = 12
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return nil }

        var red = 0
        var green = 0
        var blue = 0
        var count = 0
        for index in stride(from: 0, to: data.count, by: 4) {
            let alpha = Int(data[index + 3])
            guard alpha > 12 else { continue }
            red += Int(data[index])
            green += Int(data[index + 1])
            blue += Int(data[index + 2])
            count += 1
        }
        guard count > 0 else { return nil }
        return UIColor(
            red: CGFloat(red) / CGFloat(count) / 255,
            green: CGFloat(green) / CGFloat(count) / 255,
            blue: CGFloat(blue) / CGFloat(count) / 255,
            alpha: 1
        )
    }
}

private extension UIColor {
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        let amount = min(1, max(0, amount))
        let lhs = rgba
        let rhs = other.rgba
        return UIColor(
            red: lhs.r + (rhs.r - lhs.r) * amount,
            green: lhs.g + (rhs.g - lhs.g) * amount,
            blue: lhs.b + (rhs.b - lhs.b) * amount,
            alpha: lhs.a + (rhs.a - lhs.a) * amount
        )
    }

    func boostedSaturation(_ multiplier: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return UIColor(
            hue: hue,
            saturation: min(1, saturation * multiplier),
            brightness: brightness,
            alpha: alpha
        )
    }

    func limitedSaturation(minimum: CGFloat = 0.16, maximum: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return UIColor(
            hue: hue,
            saturation: min(maximum, max(minimum, saturation)),
            brightness: brightness,
            alpha: alpha
        )
    }

    func limitedBrightness(minimum: CGFloat = 0.18, maximum: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return UIColor(
            hue: hue,
            saturation: saturation,
            brightness: min(maximum, max(minimum, brightness)),
            alpha: alpha
        )
    }

    var rgba: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }
}
