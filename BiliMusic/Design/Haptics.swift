import SwiftUI

// MARK: - 统一震动语义

/// 震动意图枚举。各 View 层只发 intent，由本模块统一映射到具体 SensoryFeedback 参数。
/// 方便全局调整强度、统一风格、未来可加开关/档位控制。
enum HapticIntent: Equatable {
    case selection
    case lightImpact
    case primaryImpact
    case success
    case warning
    case error
    case start
    case stop
    case transportImpact
}

extension SensoryFeedback {
    static func intent(_ intent: HapticIntent) -> SensoryFeedback {
        switch intent {
        case .selection:     return .selection
        case .lightImpact:   return .impact(flexibility: .soft, intensity: 0.3)
        case .primaryImpact: return .impact(flexibility: .solid, intensity: 0.5)
        case .success:       return .success
        case .warning:       return .warning
        case .error:         return .error
        case .start:         return .start
        case .stop:          return .stop
        case .transportImpact: return .impact(weight: .medium)
        }
    }
}
