import CoreGraphics

enum PlayerGesturePolicy {
    static let miniOpeningDragRange: CGFloat = 190
    static let miniOpeningActivationProgress: CGFloat = 0.38
    static let miniLiveOpeningActivationProgress: CGFloat = 0.38
    static let miniPredictedOpeningMinimumProgress: CGFloat = 0.10
    static let miniOpeningPredictedActivationProgress: CGFloat = 0.44
    static let velocityProjectionTime: CGFloat = 0.22
    static let dismissGrabZoneHeight: CGFloat = 150
    static let dismissTranslationThreshold: CGFloat = 130
    static let dismissPredictedThreshold: CGFloat = 260
    static let topChromeDismissTranslationThreshold: CGFloat = 90
    static let topChromeDismissPredictedThreshold: CGFloat = 180
    private static let horizontalPageIntentRatio: CGFloat = 1.12

    enum DismissRegion {
        case centerBody
        case topChrome
        case listBody
    }

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
        return translation.height < -22 && isVertical
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
        dismissGrabZoneHeight: CGFloat = Self.dismissGrabZoneHeight,
        region: DismissRegion? = nil,
        isProgressScrubbing: Bool = false
    ) -> CGFloat? {
        guard shouldTrackDismissDrag(
            translation: translation,
            startY: startY,
            dismissGrabZoneHeight: dismissGrabZoneHeight,
            region: region,
            isProgressScrubbing: isProgressScrubbing
        ) else { return nil }
        return min(340, max(0, translation.height))
    }

    static func shouldDismissFullPlayer(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        startY: CGFloat,
        dismissGrabZoneHeight: CGFloat = Self.dismissGrabZoneHeight,
        region: DismissRegion? = nil,
        isProgressScrubbing: Bool = false
    ) -> Bool {
        guard shouldTrackDismissDrag(
            translation: translation,
            startY: startY,
            dismissGrabZoneHeight: dismissGrabZoneHeight,
            region: region,
            isProgressScrubbing: isProgressScrubbing
        ) else { return false }
        switch region {
        case nil, .centerBody:
            return translation.height > dismissTranslationThreshold ||
                predictedEndTranslation.height > dismissPredictedThreshold
        case .topChrome?:
            return translation.height > topChromeDismissTranslationThreshold ||
                predictedEndTranslation.height > topChromeDismissPredictedThreshold
        case .listBody?:
            return false
        }
    }

    static func topChromeDismissDragOffset(translation: CGSize) -> CGFloat? {
        dismissDragOffset(
            translation: translation,
            startY: 0,
            region: .topChrome,
            isProgressScrubbing: false)
    }

    static func shouldDismissFromTopChrome(
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Bool {
        shouldDismissFullPlayer(
            translation: translation,
            predictedEndTranslation: predictedEndTranslation,
            startY: 0,
            region: .topChrome,
            isProgressScrubbing: false)
    }

    static func horizontalPageSwipeIntent(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        width: CGFloat
    ) -> CGFloat? {
        let horizontalIntent = strongerIntent(
            translation.width,
            predictedEndTranslation.width)
        let verticalIntent = strongerIntent(
            translation.height,
            predictedEndTranslation.height)
        let horizontalThreshold = max(28, width * 0.07)
        guard abs(horizontalIntent) > horizontalThreshold,
              abs(horizontalIntent) > abs(verticalIntent) * horizontalPageIntentRatio
        else { return nil }
        return horizontalIntent
    }

    static func isHorizontalPageSwipe(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        width: CGFloat
    ) -> Bool {
        horizontalPageSwipeIntent(
            translation: translation,
            predictedEndTranslation: predictedEndTranslation,
            width: width) != nil
    }

    static func shouldSuppressListRowTap(
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Bool {
        let horizontalIntent = strongerIntent(
            translation.width,
            predictedEndTranslation.width)
        let verticalIntent = strongerIntent(
            translation.height,
            predictedEndTranslation.height)
        guard abs(horizontalIntent) > 10 else { return false }
        return abs(horizontalIntent) > abs(verticalIntent) * 0.95
    }

    private static func predictedTranslationY(translationY: CGFloat, velocityY: CGFloat) -> CGFloat {
        translationY + velocityY * velocityProjectionTime
    }

    private static func strongerIntent(_ translation: CGFloat, _ predicted: CGFloat) -> CGFloat {
        abs(predicted) > abs(translation) ? predicted : translation
    }

    private static func shouldTrackDismissDrag(
        translation: CGSize,
        startY: CGFloat,
        dismissGrabZoneHeight: CGFloat,
        region: DismissRegion?,
        isProgressScrubbing: Bool
    ) -> Bool {
        guard !isProgressScrubbing else { return false }
        switch region {
        case nil:
            return shouldTrackTopChromeDismissDrag(translation: translation) &&
                startY < dismissGrabZoneHeight
        case .centerBody?:
            return shouldTrackTopChromeDismissDrag(translation: translation)
        case .topChrome?:
            return shouldTrackTopChromeDismissDrag(translation: translation) &&
                startY < dismissGrabZoneHeight
        case .listBody?:
            return false
        }
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
