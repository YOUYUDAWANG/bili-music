import CoreGraphics

enum PlayerGesturePolicy {
    static let miniOpeningDragRange: CGFloat = 190
    static let miniOpeningActivationProgress: CGFloat = 0.10
    static let miniLiveOpeningActivationProgress: CGFloat = 0.07
    static let miniPredictedOpeningMinimumProgress: CGFloat = 0.10
    static let miniOpeningPredictedActivationProgress: CGFloat = 0.38
    static let velocityProjectionTime: CGFloat = 0.22
    static let dismissGrabZoneHeight: CGFloat = 150
    static let dismissTranslationThreshold: CGFloat = 130
    static let dismissPredictedThreshold: CGFloat = 260
    static let topChromeDismissTranslationThreshold: CGFloat = 90
    static let topChromeDismissPredictedThreshold: CGFloat = 180

    static func miniOpenProgress(for translationY: CGFloat) -> CGFloat {
        clamp(-translationY / miniOpeningDragRange)
    }

    static func renderedMiniOpenProgress(
        rawProgress: CGFloat,
        isMiniOpening: Bool,
        isFullPlayerPresented: Bool
    ) -> CGFloat {
        let clamped = clamp(rawProgress)
        if isMiniOpening && !isFullPlayerPresented {
            return 1 - CGFloat(pow(Double(1 - clamped), 1.08))
        }
        return clamped
    }

    static func shouldBeginMiniOpenDrag(translation: CGSize) -> Bool {
        let isVertical = abs(translation.height) > abs(translation.width) * 1.2
        return translation.height < -18 && isVertical
    }

    static func shouldOpenMiniPlayerLive(translationY: CGFloat, velocityY: CGFloat) -> Bool {
        let progress = miniOpenProgress(for: translationY)
        let predictedProgress = miniOpenProgress(for: predictedTranslationY(
            translationY: translationY,
            velocityY: velocityY))

        return progress >= miniLiveOpeningActivationProgress ||
            (progress >= miniPredictedOpeningMinimumProgress &&
             predictedProgress >= miniOpeningPredictedActivationProgress)
    }

    static func shouldFinishMiniOpenDrag(translationY: CGFloat, velocityY: CGFloat) -> Bool {
        let progress = miniOpenProgress(for: translationY)
        let predictedProgress = miniOpenProgress(for: predictedTranslationY(
            translationY: translationY,
            velocityY: velocityY))

        return progress > miniOpeningActivationProgress ||
            (progress > miniPredictedOpeningMinimumProgress &&
             predictedProgress > miniOpeningPredictedActivationProgress)
    }

    static func initialMiniOpenProgress(for translationY: CGFloat) -> CGFloat {
        max(miniOpenProgress(for: translationY), miniOpeningActivationProgress)
    }

    static func dismissDragOffset(
        translation: CGSize,
        startY: CGFloat,
        dismissGrabZoneHeight: CGFloat = Self.dismissGrabZoneHeight
    ) -> CGFloat? {
        guard shouldTrackDismissDrag(
            translation: translation,
            startY: startY,
            dismissGrabZoneHeight: dismissGrabZoneHeight
        ) else { return nil }
        return min(340, max(0, translation.height))
    }

    static func shouldDismissFullPlayer(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        startY: CGFloat,
        dismissGrabZoneHeight: CGFloat = Self.dismissGrabZoneHeight
    ) -> Bool {
        guard shouldTrackDismissDrag(
            translation: translation,
            startY: startY,
            dismissGrabZoneHeight: dismissGrabZoneHeight
        ) else { return false }
        return translation.height > dismissTranslationThreshold ||
            predictedEndTranslation.height > dismissPredictedThreshold
    }

    static func topChromeDismissDragOffset(translation: CGSize) -> CGFloat? {
        guard shouldTrackTopChromeDismissDrag(translation: translation) else { return nil }
        return min(340, max(0, translation.height))
    }

    static func shouldDismissFromTopChrome(
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Bool {
        guard shouldTrackTopChromeDismissDrag(translation: translation) else { return false }
        return translation.height > topChromeDismissTranslationThreshold ||
            predictedEndTranslation.height > topChromeDismissPredictedThreshold
    }

    private static func predictedTranslationY(translationY: CGFloat, velocityY: CGFloat) -> CGFloat {
        translationY + velocityY * velocityProjectionTime
    }

    private static func shouldTrackDismissDrag(
        translation: CGSize,
        startY: CGFloat,
        dismissGrabZoneHeight: CGFloat
    ) -> Bool {
        shouldTrackTopChromeDismissDrag(translation: translation) &&
            startY < dismissGrabZoneHeight
    }

    private static func shouldTrackTopChromeDismissDrag(translation: CGSize) -> Bool {
        let isDownward = translation.height > 0
        let isVertical = abs(translation.height) > abs(translation.width) * 1.08
        return isDownward && isVertical
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value))
    }
}
