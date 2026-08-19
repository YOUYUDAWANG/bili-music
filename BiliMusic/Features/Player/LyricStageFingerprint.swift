import CryptoKit
import Foundation
import UIKit

enum LyricStageFingerprint {
    static func score(_ score: LyricStageScoreV2?) -> String {
        guard let score else { return "none" }
        return digest(score)
    }

    static func performance(_ score: LyricPerformanceScore?) -> String {
        guard let score else { return "none" }
        return digest(score)
    }

    static func palette(_ palette: PlayerArtworkPalette) -> String {
        [
            rgba(palette.top),
            rgba(palette.middle),
            rgba(palette.bottom),
        ].joined(separator: "|")
    }

    static func cacheKey(
        trackID: String,
        lyricsHash: String,
        score: LyricStageScoreV2?,
        performanceScore: LyricPerformanceScore?,
        palette: PlayerArtworkPalette,
        canvasSize: CGSize,
        dynamicTypeScale: CGFloat,
        reduceMotion: Bool
    ) -> String {
        [
            trackID,
            lyricsHash,
            Self.score(score),
            performance(performanceScore),
            Self.palette(palette),
            String(format: "%.1fx%.1f", canvasSize.width, canvasSize.height),
            String(format: "%.3f", dynamicTypeScale),
            reduceMotion ? "1" : "0",
        ].joined(separator: "/")
    }

    private static func digest<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "none" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func rgba(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.4f,%.4f,%.4f,%.4f", r, g, b, a)
    }
}

enum StageChoreography {
    static func allows(_ verb: StageVerb, in phase: StageEventPhase) -> Bool {
        allowedVerbs(in: phase).contains(verb)
    }

    static func allowedVerbs(in phase: StageEventPhase) -> Set<StageVerb> {
        switch phase {
        case .entrance: [.appear, .assemble, .drift, .drop]
        case .performance: [.pulse, .stretch, .echo, .drift]
        case .hold: [.pulse, .echo, .appear]
        case .exit: [.dissolve, .scatter, .drift]
        }
    }
}
