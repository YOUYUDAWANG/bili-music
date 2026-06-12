import SwiftUI

enum AppTheme {
    static let accent = Color(red: 1.0, green: 0.18, blue: 0.32)
    static let background = Color(uiColor: .systemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let secondaryBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let separator = Color(uiColor: .separator)
    static let label = Color(uiColor: .label)
    static let secondaryLabel = Color(uiColor: .secondaryLabel)

    static let playerGradient = LinearGradient(
        colors: [
            accent.opacity(0.28),
            Color(uiColor: .systemBackground),
            Color(uiColor: .systemBackground),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}
