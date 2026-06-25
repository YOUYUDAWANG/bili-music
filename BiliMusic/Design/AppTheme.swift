import SwiftUI

/// 全局主题。Apple Music 风格的克制配色，统一用系统语义色，不强加品牌色。
enum AppTheme {
    /// 单色控件语言:不强加品牌色,tint/高亮用自适应的 primary(黑/白),
    /// 唯一的色彩来自正在播放页的专辑封面虚化背景。更接近 Apple Music 的克制感。
    static let accent = Color(uiColor: .systemRed)
    static let background = Color(uiColor: .systemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let secondaryBackground = Color(uiColor: .secondarySystemGroupedBackground)
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

    /// 没有封面时的中性兜底背景(不含红色)。
    static let playerGradient = LinearGradient(
        colors: [
            Color(uiColor: .secondarySystemBackground),
            Color(uiColor: .systemBackground),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}
