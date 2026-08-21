import CoreGraphics
import XCTest
@testable import BiliMusic

final class LyricStageV4PreparedRendererTests: XCTestCase {
    func testDefaultMotionSettlesAndStaysStill() {
        XCTAssertEqual(LyricStageCalmMotion.defaultScale(0), 1, accuracy: 0.000_1)
        XCTAssertGreaterThan(LyricStageCalmMotion.defaultScale(0.12), 1)
        XCTAssertLessThanOrEqual(LyricStageCalmMotion.defaultScale(0.12), 1.015)
        XCTAssertEqual(LyricStageCalmMotion.defaultScale(0.36), 1, accuracy: 0.000_1)
        XCTAssertEqual(LyricStageCalmMotion.defaultScale(1), 1, accuracy: 0.000_1)
        XCTAssertEqual(LyricStageCalmMotion.defaultLift(1), 0, accuracy: 0.000_1)
        XCTAssertEqual(LyricStageCalmMotion.settlingRemainder(1), 0, accuracy: 0.000_1)
    }

    func testTrackingBreathIsOneShotInsteadOfPeriodic() {
        XCTAssertEqual(LyricStageCalmMotion.oneShotPulse(-1), 0, accuracy: 0.000_1)
        XCTAssertEqual(LyricStageCalmMotion.oneShotPulse(0), 0, accuracy: 0.000_1)
        XCTAssertEqual(LyricStageCalmMotion.oneShotPulse(0.5), 1, accuracy: 0.000_1)
        XCTAssertEqual(LyricStageCalmMotion.oneShotPulse(1), 0, accuracy: 0.000_1)
        XCTAssertEqual(LyricStageCalmMotion.oneShotPulse(2), 0, accuracy: 0.000_1)
    }

    func testBudgetCapsEchoLayersAndTextDraws() {
        let twoLayers = LyricStageV4RendererPreparation.budget(
            glyphCount: 32,
            requestedEchoLayers: 2)
        XCTAssertEqual(twoLayers.transformedGlyphCount, 32)
        XCTAssertEqual(twoLayers.echoLayerCount, 2)
        XCTAssertEqual(twoLayers.estimatedTextDrawCount, 96)
        XCTAssertFalse(twoLayers.usesWrappedFallback)

        let oneLayer = LyricStageV4RendererPreparation.budget(
            glyphCount: 40,
            requestedEchoLayers: 2)
        XCTAssertEqual(oneLayer.echoLayerCount, 1)
        XCTAssertEqual(oneLayer.estimatedTextDrawCount, 80)

        let fallback = LyricStageV4RendererPreparation.budget(
            glyphCount: 49,
            requestedEchoLayers: 2)
        XCTAssertEqual(fallback.echoLayerCount, 0)
        XCTAssertEqual(fallback.transformedGlyphCount, 0)
        XCTAssertLessThanOrEqual(fallback.estimatedTextDrawCount, 96)
        XCTAssertTrue(fallback.usesWrappedFallback)

        let veryLongFallback = LyricStageV4RendererPreparation.budget(
            glyphCount: 97,
            requestedEchoLayers: 2)
        XCTAssertEqual(veryLongFallback.transformedGlyphCount, 0)
        XCTAssertEqual(veryLongFallback.echoLayerCount, 0)
        XCTAssertLessThanOrEqual(veryLongFallback.estimatedTextDrawCount, 96)
        XCTAssertTrue(veryLongFallback.usesWrappedFallback)
    }

    func testContiguousTokenRangeResolvesToCompleteGlyphRange() {
        let tokens = [
            StageToken(id: 0, text: "you", glyphRange: 0..<3, kind: .word, realTiming: nil),
            StageToken(id: 1, text: "&", glyphRange: 3..<4, kind: .word, realTiming: nil),
            StageToken(id: 2, text: "合図", glyphRange: 4..<6, kind: .word, realTiming: nil),
        ]
        XCTAssertEqual(
            LyricStageV4RendererPreparation.focusGlyphRange(
                tokens: tokens,
                startTokenIndex: 1,
                endTokenIndex: 2),
            3...5)
    }

    func testInvalidTokenLandmarksDoNotGuessFocus() {
        let tokens = [
            StageToken(id: 0, text: "A", glyphRange: 0..<1, kind: .word, realTiming: nil),
            StageToken(id: 1, text: "B", glyphRange: 2..<3, kind: .word, realTiming: nil),
        ]
        XCTAssertNil(LyricStageV4RendererPreparation.focusGlyphRange(
            tokens: tokens,
            startTokenIndex: 0,
            endTokenIndex: 1))
        XCTAssertNil(LyricStageV4RendererPreparation.focusGlyphRange(
            tokens: tokens,
            startTokenIndex: 1,
            endTokenIndex: 4))
    }

    func testSemanticLensGeometryIsPreparedDeterministically() {
        let points = [
            CGPoint(x: 10, y: 20),
            CGPoint(x: 20, y: 20),
            CGPoint(x: 30, y: 20),
        ]
        let first = LyricStageV4RendererPreparation.semanticLensPoints(
            points: points,
            widths: [10, 10, 10],
            focusGlyphRange: 1...1)
        let second = LyricStageV4RendererPreparation.semanticLensPoints(
            points: points,
            widths: [10, 10, 10],
            focusGlyphRange: 1...1)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first[0].x, 9.4, accuracy: 0.001)
        XCTAssertEqual(first[1].x, 20, accuracy: 0.001)
        XCTAssertEqual(first[2].x, 30.6, accuracy: 0.001)
    }

    func testRailAndApertureGeometryArePrecomputedInsideCanvas() {
        let canvas = CGSize(width: 340, height: 260)
        let previous = CGRect(x: 190, y: 42, width: 110, height: 30)
        let current = CGRect(x: 18, y: 116, width: 240, height: 38)
        let rail = LyricStageV4RendererPreparation.rail(
            previousBounds: previous,
            currentBounds: current,
            canvasSize: canvas)
        XCTAssertEqual(rail.points.count, 4)
        XCTAssertEqual(rail.points.first, CGPoint(x: 300, y: 80))
        XCTAssertEqual(rail.points.last, CGPoint(x: 258, y: 163))

        let aperture = LyricStageV4RendererPreparation.aperture(
            textBounds: current,
            canvasSize: canvas)
        XCTAssertEqual(aperture.center.x, current.midX, accuracy: 0.001)
        XCTAssertGreaterThan(aperture.openHalfGap, aperture.closedHalfGap)
        XCTAssertLessThanOrEqual(aperture.halfLength, canvas.width * 0.36)
    }

    func testStructuralDriversUseRawAudioClockDespiteLyricOffset() {
        XCTAssertEqual(
            LyricStageV4RendererPreparation.driverClockTime(
                driver: .structuralMoment,
                lyricTime: 31.2,
                audioTime: 29.0),
            29.0)
        XCTAssertEqual(
            LyricStageV4RendererPreparation.driverClockTime(
                driver: .sectionEdge,
                lyricTime: 31.2,
                audioTime: 29.0),
            29.0)
        XCTAssertEqual(
            LyricStageV4RendererPreparation.driverClockTime(
                driver: .wordReveal,
                lyricTime: 31.2,
                audioTime: 29.0),
            31.2)
    }

    func testUnrevealedV4TextHasNoBaselineOpacity() {
        XCTAssertEqual(LyricStageV4RendererPreparation.revealedTextOpacity(-0.2), 0)
        XCTAssertEqual(LyricStageV4RendererPreparation.revealedTextOpacity(0), 0)
        XCTAssertEqual(LyricStageV4RendererPreparation.revealedTextOpacity(0.6), 0.6)
        XCTAssertEqual(LyricStageV4RendererPreparation.revealedTextOpacity(1.2), 1)
    }

    func testSilenceAperturePreludeRuntimeKeepsAudioAndLyricClocksSeparate() {
        let runtime = LyricStageV4PreparedPreludeRuntime(windows: [
            .init(lineIndex: 8, audioFrom: 22.7, lyricTo: 25.0),
            .init(lineIndex: 2, audioFrom: 5.6, lyricTo: 8.0),
        ])
        XCTAssertNil(runtime.lineIndex(lyricTime: 7.8, audioTime: 5.59))
        XCTAssertEqual(runtime.lineIndex(lyricTime: 7.8, audioTime: 5.8), 2)
        XCTAssertNil(runtime.lineIndex(lyricTime: 8.0, audioTime: 5.8))
        XCTAssertEqual(runtime.lineIndex(lyricTime: 24.9, audioTime: 22.9), 8)
        XCTAssertNil(runtime.lineIndex(lyricTime: 25.0, audioTime: 22.9))
    }
}
