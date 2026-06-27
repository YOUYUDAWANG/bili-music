import SwiftUI
import UIKit

/// 全局主题。结构参考 Apple Music 的克制层级，品牌强调色使用 B 站粉。
enum AppTheme {
    static let biliPink = Color(red: 0.984, green: 0.447, blue: 0.600)
    static let biliPinkDeep = Color(red: 0.914, green: 0.208, blue: 0.408)
    static let biliPinkSoft = Color(red: 1.000, green: 0.918, blue: 0.944)
    static let accent = biliPink
    static let background = Color(uiColor: .systemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let secondaryBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevatedBackground = Color(uiColor: .tertiarySystemGroupedBackground)
    static let separator = Color(uiColor: .separator)
    static let label = Color(uiColor: .label)
    static let secondaryLabel = Color(uiColor: .secondaryLabel)

    /// 语义颜色
    static let error = Color.red
    static let success = Color.green

    /// 通用圆角半径
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 12
    static let coverRadius: CGFloat = 6
    static let playerCoverRadius: CGFloat = 14

    /// 封面缩略图尺寸
    static let listCoverSize: CGFloat = 56
    static let miniCoverWidth: CGFloat = 52
    static let miniCoverHeight: CGFloat = 30

    /// 没有封面时的中性兜底背景,带很轻的 B 站粉品牌感。
    static let playerGradient = LinearGradient(
        colors: [
            biliPink.opacity(0.20),
            Color(uiColor: .secondarySystemBackground),
            Color(uiColor: .systemBackground)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

struct PlayerArtworkPalette: Equatable {
    let top: UIColor
    let middle: UIColor
    let bottom: UIColor

    static let fallback = PlayerArtworkPalette(
        top: UIColor(red: 0.19, green: 0.20, blue: 0.23, alpha: 1),
        middle: UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1),
        bottom: UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1)
    )

    static func == (lhs: PlayerArtworkPalette, rhs: PlayerArtworkPalette) -> Bool {
        lhs.top.isEqual(rhs.top)
            && lhs.middle.isEqual(rhs.middle)
            && lhs.bottom.isEqual(rhs.bottom)
    }

    static func from(_ image: UIImage?) -> PlayerArtworkPalette {
        guard let base = image?.averageColor else { return .fallback }
        let readable = base
            .boostedSaturation(1.22)
            .limitedBrightness(maximum: 0.44)
        return PlayerArtworkPalette(
            top: readable.mixed(with: .white, amount: 0.10),
            middle: readable.mixed(with: .black, amount: 0.18),
            bottom: readable.mixed(with: .black, amount: 0.76)
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

    func limitedBrightness(maximum: CGFloat) -> UIColor {
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
            brightness: min(maximum, max(0.18, brightness)),
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
