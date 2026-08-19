import Foundation

enum LyricMotionEffect: String, CaseIterable, Codable, Equatable, Sendable {
    case rise
    case impact
    case drift
    case breathe
    case echo
    case focus
    case drop
    case stretch
    case cascade
}

enum LyricMotionAlignment: String, Codable, Equatable, Sendable {
    case leading
    case center
    case trailing
}

enum LyricMotionWeight: String, Codable, Equatable, Sendable {
    case semibold
    case bold
    case black
}

struct LyricMotionCue: Equatable, Sendable {
    let effect: LyricMotionEffect
    let alignment: LyricMotionAlignment
    let direction: Double
    let fontSize: Double
    let weight: LyricMotionWeight
    let tracking: Double
    let duration: Double
    let intensity: Double
    let reduceMotion: Bool
}

enum LyricMotionDirector {
    static func cue(
        text: String,
        lineDuration: Double,
        trackID: String,
        lineIndex: Int,
        reduceMotion: Bool
    ) -> LyricMotionCue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleCount = trimmed.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) &&
                !CharacterSet.punctuationCharacters.contains($0)
        }.count
        let duration = lineDuration.isFinite ? min(max(lineDuration, 1.2), 6) : 2.8
        let seed = stableHash("\(trackID)|\(lineIndex)|\(trimmed)")
        let direction = seed.isMultiple(of: 2) ? -1.0 : 1.0

        let effect: LyricMotionEffect
        if hasEchoPattern(trimmed) {
            effect = .echo
        } else if containsQuestion(trimmed) {
            effect = .drift
        } else if containsImpactPunctuation(trimmed) {
            effect = .impact
        } else if containsLingeringPunctuation(trimmed) || lineDuration >= 4.6 {
            effect = .breathe
        } else if visibleCount <= 8 || lineDuration <= 1.8 {
            effect = .impact
        } else {
            let neutralEffects: [LyricMotionEffect] = [
                .rise, .rise, .drift, .breathe, .focus, .stretch, .drop,
            ]
            effect = neutralEffects[Int(seed % UInt64(neutralEffects.count))]
        }

        let typography = typography(for: effect, direction: direction)
        return cue(
            effect: effect,
            direction: direction,
            lineDuration: duration,
            reduceMotion: reduceMotion,
            typography: typography
        )
    }

    static func cue(
        effect: LyricMotionEffect,
        direction: Double,
        lineDuration: Double,
        reduceMotion: Bool
    ) -> LyricMotionCue {
        cue(
            effect: effect,
            direction: direction,
            lineDuration: lineDuration,
            reduceMotion: reduceMotion,
            typography: typography(for: effect, direction: direction)
        )
    }

    private static func cue(
        effect: LyricMotionEffect,
        direction: Double,
        lineDuration: Double,
        reduceMotion: Bool,
        typography: (alignment: LyricMotionAlignment, fontSize: Double, weight: LyricMotionWeight, tracking: Double)
    ) -> LyricMotionCue {
        return LyricMotionCue(
            effect: effect,
            alignment: typography.alignment,
            direction: direction,
            fontSize: typography.fontSize,
            weight: typography.weight,
            tracking: typography.tracking,
            duration: min(max(lineDuration, 1.2), 6),
            intensity: 1,
            reduceMotion: reduceMotion
        )
    }

    private static func typography(
        for effect: LyricMotionEffect,
        direction: Double
    ) -> (alignment: LyricMotionAlignment, fontSize: Double, weight: LyricMotionWeight, tracking: Double) {
        switch effect {
        case .rise:
            return (.center, 25, .bold, 0.2)
        case .impact:
            return (.center, 32, .black, -0.4)
        case .drift:
            return (direction < 0 ? .leading : .trailing, 25, .bold, 0.25)
        case .breathe:
            return (.center, 24, .semibold, 1.2)
        case .echo:
            return (.center, 28, .bold, 0.8)
        case .focus:
            return (.center, 27, .bold, 1.6)
        case .drop:
            return (.center, 29, .bold, -0.15)
        case .stretch:
            return (.center, 26, .black, 0.9)
        case .cascade:
            return (direction < 0 ? .leading : .trailing, 26, .bold, 0.15)
        }
    }

    private static func containsQuestion(_ text: String) -> Bool {
        text.contains("?") || text.contains("？")
    }

    private static func containsImpactPunctuation(_ text: String) -> Bool {
        text.contains("!") || text.contains("！")
    }

    private static func containsLingeringPunctuation(_ text: String) -> Bool {
        text.contains("…") || text.contains("...") || text.contains("——") || text.contains("〜") || text.contains("～")
    }

    private static func hasEchoPattern(_ text: String) -> Bool {
        let tokens = text
            .lowercased()
            .split { $0.isWhitespace || $0.isPunctuation }
        if tokens.count >= 2, tokens[tokens.count - 1] == tokens[tokens.count - 2] {
            return true
        }

        let compact = Array(text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) &&
                !CharacterSet.punctuationCharacters.contains($0)
        })
        guard compact.count >= 4, compact.count.isMultiple(of: 2) else { return false }
        let midpoint = compact.count / 2
        return Array(compact[..<midpoint]) == Array(compact[midpoint...])
    }

    /// Swift's Hasher is intentionally randomized between launches; motion direction must not be.
    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(14_695_981_039_346_656_037) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}
