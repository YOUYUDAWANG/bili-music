import Foundation

enum LyricWordState: Equatable {
    case sung
    case current(progress: Double)
    case unsung
}

enum LyricHighlightModel {
    static func activeLineIndices(lines: [PlayerEngine.LyricLine], at t: Double) -> [Int] {
        lines.indices.filter { index in
            t >= lines[index].from && t < lines[index].to
        }
    }

    static func activeLineIndex(lines: [PlayerEngine.LyricLine], at t: Double) -> Int? {
        guard !lines.isEmpty else { return nil }
        let active = activeLineIndices(lines: lines, at: t)
        if !active.isEmpty {
            return active.min { lhs, rhs in
                rolePriority(lines[lhs].voiceRole) < rolePriority(lines[rhs].voiceRole)
            }
        }
        return lines.lastIndex { line in t >= line.from }
    }

    /// Full-page lyrics scroll with `activeLineIndex`, so its visual highlight must
    /// use the same fallback during gaps between source timestamps.
    static func highlightedLineIndices(lines: [PlayerEngine.LyricLine], at t: Double) -> [Int] {
        let active = activeLineIndices(lines: lines, at: t)
        if !active.isEmpty { return active }
        return activeLineIndex(lines: lines, at: t).map { [$0] } ?? []
    }

    private static func rolePriority(_ role: LyricVoiceRole) -> Int {
        switch role {
        case .lead, .together: return 0
        case .duetA, .duetB: return 1
        case .backing: return 2
        }
    }

    static func wordStates(of line: PlayerEngine.LyricLine, at t: Double) -> [LyricWordState] {
        let words = line.words.sorted { lhs, rhs in
            if lhs.from == rhs.from {
                return lhs.to < rhs.to
            }
            return lhs.from < rhs.from
        }
        return words.map { word in
            if t >= word.to {
                return .sung
            }
            if t >= word.from {
                let duration = max(word.to - word.from, 0.0001)
                let progress = min(max((t - word.from) / duration, 0), 1)
                return .current(progress: progress)
            }
            return .unsung
        }
    }

    static func fillProgress(for state: LyricWordState) -> Double {
        switch state {
        case .sung:
            return 1
        case let .current(progress):
            return min(max(progress, 0), 1)
        case .unsung:
            return 0
        }
    }
}
