import CryptoKit
import Foundation

struct LyricTextComposition: Codable, Equatable, Sendable {
    let lineIndex: Int
    let textLineIndices: [Int]

    func validated(lineCount: Int) -> LyricTextComposition? {
        guard (0..<lineCount).contains(lineIndex) else { return nil }
        var seen = Set<Int>()
        let safeIndices = textLineIndices.filter { index in
            guard (0..<lineCount).contains(index),
                  abs(index - lineIndex) <= 2,
                  seen.insert(index).inserted else { return false }
            return true
        }
        guard safeIndices.count <= 3, safeIndices.contains(lineIndex) else { return nil }
        return LyricTextComposition(lineIndex: lineIndex, textLineIndices: safeIndices)
    }
}

struct LyricPerformanceScene: Codable, Equatable, Sendable {
    let lineIndex: Int
    let effect: LyricMotionEffect
    let alignment: LyricMotionAlignment?
    let direction: Int
    let intensity: Double
    let fontScale: Double
    let trackingScale: Double

    func validated(lineCount: Int) -> LyricPerformanceScene? {
        guard (0..<lineCount).contains(lineIndex) else { return nil }
        return LyricPerformanceScene(
            lineIndex: lineIndex,
            effect: effect,
            alignment: alignment,
            direction: direction < 0 ? -1 : 1,
            intensity: intensity.clamped(to: 0.35...1.25),
            fontScale: fontScale.clamped(to: 0.90...1.18),
            trackingScale: trackingScale.clamped(to: 0.50...1.80)
        )
    }
}

enum LyricWordEffect: String, Codable, Equatable, Sendable {
    case sweep
    case impact
    case stretch
    case echoTrail
}

struct LyricWordCue: Codable, Equatable, Sendable {
    let lineIndex: Int
    let startWordIndex: Int
    let endWordIndex: Int
    let effect: LyricWordEffect
    let intensity: Double
    let direction: Int

    func validated(lineCount: Int, wordCounts: [Int: Int]) -> LyricWordCue? {
        guard (0..<lineCount).contains(lineIndex),
              let wordCount = wordCounts[lineIndex],
              wordCount > 0,
              (0..<wordCount).contains(startWordIndex),
              (0..<wordCount).contains(endWordIndex),
              startWordIndex <= endWordIndex,
              endWordIndex - startWordIndex < 12 else { return nil }
        return LyricWordCue(
            lineIndex: lineIndex,
            startWordIndex: startWordIndex,
            endWordIndex: endWordIndex,
            effect: effect,
            intensity: intensity.clamped(to: 0.35...1.25),
            direction: direction < 0 ? -1 : 1)
    }

    func contains(wordIndex: Int) -> Bool {
        startWordIndex...endWordIndex ~= wordIndex
    }
}

struct LyricPerformanceScore: Codable, Equatable, Sendable {
    static let currentVersion = "lyric-performance-v4"

    let version: String
    let directorVersion: String
    let trackID: String
    let lyricsHash: String
    let lineCount: Int
    let mood: String
    let compositions: [LyricTextComposition]
    let scenes: [LyricPerformanceScene]
    let wordCues: [LyricWordCue]
    let stageBible: LyricStageBible?
    let stageDirectives: [LyricStageDirective]

    init(
        version: String,
        directorVersion: String,
        trackID: String,
        lyricsHash: String,
        lineCount: Int,
        mood: String,
        compositions: [LyricTextComposition],
        scenes: [LyricPerformanceScene],
        wordCues: [LyricWordCue] = [],
        stageBible: LyricStageBible? = nil,
        stageDirectives: [LyricStageDirective] = []
    ) {
        self.version = version
        self.directorVersion = directorVersion
        self.trackID = trackID
        self.lyricsHash = lyricsHash
        self.lineCount = lineCount
        self.mood = mood
        self.compositions = compositions
        self.scenes = scenes
        self.wordCues = wordCues
        self.stageBible = stageBible
        self.stageDirectives = stageDirectives
    }

    private enum CodingKeys: String, CodingKey {
        case version, directorVersion, trackID, lyricsHash, lineCount, mood, compositions, scenes, wordCues
        case stageBible, stageDirectives
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        directorVersion = try container.decode(String.self, forKey: .directorVersion)
        trackID = try container.decode(String.self, forKey: .trackID)
        lyricsHash = try container.decode(String.self, forKey: .lyricsHash)
        lineCount = try container.decode(Int.self, forKey: .lineCount)
        mood = try container.decode(String.self, forKey: .mood)
        compositions = try container.decode([LyricTextComposition].self, forKey: .compositions)
        scenes = try container.decode([LyricPerformanceScene].self, forKey: .scenes)
        wordCues = try container.decodeIfPresent([LyricWordCue].self, forKey: .wordCues) ?? []
        stageBible = try container.decodeIfPresent(LyricStageBible.self, forKey: .stageBible)
        stageDirectives = try container.decodeIfPresent([LyricStageDirective].self, forKey: .stageDirectives) ?? []
    }

    func validated(
        trackID: String,
        lyricsHash: String,
        lineCount availableLineCount: Int,
        wordCounts: [Int: Int] = [:]
    ) -> LyricPerformanceScore? {
        let expectedLineCount = min(availableLineCount, 180)
        guard version == Self.currentVersion,
              self.trackID == trackID,
              self.lyricsHash == lyricsHash,
              lineCount == expectedLineCount,
              !directorVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              expectedLineCount > 0 else { return nil }

        var seenCompositions = Set<Int>()
        let safeCompositions = compositions.compactMap { composition -> LyricTextComposition? in
            guard let composition = composition.validated(lineCount: expectedLineCount),
                  seenCompositions.insert(composition.lineIndex).inserted else { return nil }
            return composition
        }
        guard safeCompositions.count == expectedLineCount else { return nil }
        let compositionSizes = Dictionary(uniqueKeysWithValues: safeCompositions.map {
            ($0.lineIndex, $0.textLineIndices.count)
        })

        var seen = Set<Int>()
        let safeScenes = scenes.compactMap { scene -> LyricPerformanceScene? in
            guard let scene = scene.validated(lineCount: expectedLineCount), seen.insert(scene.lineIndex).inserted else {
                return nil
            }
            guard scene.effect != .cascade || (compositionSizes[scene.lineIndex] ?? 0) >= 2 else {
                return nil
            }
            return scene
        }
        var seenWordCueLines = Set<Int>()
        let safeWordCues = wordCues.compactMap { cue -> LyricWordCue? in
            guard let cue = cue.validated(lineCount: expectedLineCount, wordCounts: wordCounts),
                  seenWordCueLines.insert(cue.lineIndex).inserted else { return nil }
            return cue
        }
        let safeBible = stageBible?.validated()
        var seenStageLines = Set<Int>()
        let safeStageDirectives = stageDirectives.compactMap { directive -> LyricStageDirective? in
            guard let directive = directive.validated(lineCount: expectedLineCount),
                  seenStageLines.insert(directive.lineIndex).inserted else { return nil }
            return directive
        }
        guard !safeScenes.isEmpty || !safeWordCues.isEmpty || !safeStageDirectives.isEmpty else { return nil }
        return LyricPerformanceScore(
            version: version,
            directorVersion: directorVersion,
            trackID: trackID,
            lyricsHash: lyricsHash,
            lineCount: expectedLineCount,
            mood: String(mood.prefix(80)),
            compositions: safeCompositions.sorted { $0.lineIndex < $1.lineIndex },
            scenes: safeScenes.sorted { $0.lineIndex < $1.lineIndex },
            wordCues: safeWordCues.sorted { $0.lineIndex < $1.lineIndex },
            stageBible: safeBible,
            stageDirectives: safeStageDirectives.sorted { $0.lineIndex < $1.lineIndex }
        )
    }

    func textLineIndices(for lineIndex: Int) -> [Int]? {
        compositions.first(where: { $0.lineIndex == lineIndex })?.textLineIndices
    }

    func cue(for lineIndex: Int, fallback: LyricMotionCue) -> LyricMotionCue {
        guard let scene = scenes.first(where: { $0.lineIndex == lineIndex }) else { return fallback }
        let directed = LyricMotionDirector.cue(
            effect: scene.effect,
            direction: Double(scene.direction),
            lineDuration: fallback.duration,
            reduceMotion: fallback.reduceMotion
        )
        return LyricMotionCue(
            effect: directed.effect,
            alignment: scene.alignment ?? directed.alignment,
            direction: directed.direction,
            fontSize: (directed.fontSize * scene.fontScale).clamped(to: 22...36),
            weight: directed.weight,
            tracking: (directed.tracking * scene.trackingScale).clamped(to: -1...2.4),
            duration: directed.duration,
            intensity: scene.intensity,
            reduceMotion: directed.reduceMotion
        )
    }

    func scene(for lineIndex: Int) -> LyricPerformanceScene? {
        scenes.first(where: { $0.lineIndex == lineIndex })
    }

    func wordCue(for lineIndex: Int) -> LyricWordCue? {
        wordCues.first(where: { $0.lineIndex == lineIndex })
    }

    func stageDirective(for lineIndex: Int) -> LyricStageDirective? {
        stageDirectives.first(where: { $0.lineIndex == lineIndex })
    }
}

enum LyricPerformanceFingerprint {
    static func wordCounts(_ lines: [PlayerEngine.LyricLine]) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: lines.enumerated().map { ($0.offset, $0.element.words.count) })
    }

    static func lyricsHash(_ lines: [PlayerEngine.LyricLine]) -> String {
        let canonical = lines.enumerated().map { index, line in
            let from = Int((line.from * 1000).rounded())
            let to = Int((line.to * 1000).rounded())
            let words = line.words.map { word in
                "\(Int((word.from * 1000).rounded())):\(Int((word.to * 1000).rounded())):\(word.text)"
            }.joined(separator: ",")
            return "\(index)|\(from)|\(to)|\(line.voiceRole.rawValue)|\(line.layerID)|\(line.overlapGroup ?? "-")|\(line.text)|\(words)"
        }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
