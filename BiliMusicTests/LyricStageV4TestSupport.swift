import Foundation
@testable import BiliMusic

func makeV4FixtureLines(count: Int, longText: Bool = false) -> [PlayerEngine.LyricLine] {
    (0..<count).map { index in
        let from = Double(index) * 4.1
        let text = longText
            ? "\(index)-" + String(repeating: "長い歌詞の完全な一行", count: 8)
            : (index.isMultiple(of: 5) ? "repeat signal" : "fixture line \(index)")
        return PlayerEngine.LyricLine(
            from: from,
            to: from + 3.6,
            text: text,
            words: index.isMultiple(of: 3)
                ? [.init(from: from, to: from + 3.6, text: text)]
                : [])
    }
}

func makeV4FixtureMap(duration: Double = 760) -> AudioPerformanceMapV2 {
    let sampleCount = Int(duration) + 1
    func envelope(
        _ kind: AudioPerformanceEnvelopeKind,
        values: [UInt8],
        minimum: Double = 0,
        maximum: Double = 1
    ) -> AudioPerformanceEnvelope {
        AudioPerformanceEnvelope(
            kind: kind,
            startTime: 0,
            sampleRateHz: 1,
            minimum: minimum,
            maximum: maximum,
            samples: Data(values))
    }
    let energy = (0..<sampleCount).map { UInt8(35 + ($0 * 37) % 210) }
    let brightness = (0..<sampleCount).map { UInt8(25 + ($0 * 19) % 220) }
    let pitch = (0..<sampleCount).map { UInt8(70 + ($0 * 7) % 150) }
    let pitchConfidence = (0..<sampleCount).map { UInt8(90 + ($0 * 11) % 150) }
    let vocal = (0..<sampleCount).map { UInt8(45 + ($0 * 23) % 200) }
    let beats = stride(from: 0.25, to: duration, by: 0.5).map { $0 }
    let downbeats = stride(from: 0.25, to: duration, by: 2.0).map { $0 }
    var onsets: [AudioPerformanceOnset] = []
    for (index, time) in stride(from: 0.4, to: duration, by: 1.7).enumerated() {
        onsets.append(AudioPerformanceOnset(
            time: time,
            strength: 0.55 + Double(index % 5) * 0.09))
    }
    let sectionLength = duration / 12
    var sections: [AudioPerformanceRegion] = []
    for index in 0..<12 {
        sections.append(AudioPerformanceRegion(
            id: "section-\(index)",
            kind: .acousticSection,
            from: Double(index) * sectionLength,
            to: index == 11 ? duration : Double(index + 1) * sectionLength,
            confidence: 0.72 + Double(index % 3) * 0.08))
    }
    var silence: [AudioPerformanceRegion] = []
    for index in 1..<12 {
        let to = Double(index) * sectionLength
        silence.append(AudioPerformanceRegion(
            id: "silence-\(index)",
            kind: .silence,
            from: to - 0.72,
            to: to,
            confidence: 0.82))
    }
    var highEnergy: [AudioPerformanceRegion] = []
    for index in 0..<8 {
        let from = 8 + Double(index) * 72
        highEnergy.append(AudioPerformanceRegion(
            id: "high-\(index)",
            kind: .highEnergy,
            from: from,
            to: min(duration, from + 1.2),
            confidence: 0.8))
    }
    let map = AudioPerformanceMapV2(
        version: AudioPerformanceMapV2Version.current,
        analysisVersion: AudioPerformanceMapV2Version.analyzer,
        audioFingerprint: "v4-fixture-audio",
        duration: duration,
        tempoSegments: [
            AudioPerformanceTempoSegment(from: 0, to: duration, bpm: 120, confidence: 0.86),
        ],
        beats: beats,
        downbeats: downbeats,
        onsets: onsets,
        envelopes: [
            envelope(.energy, values: energy),
            envelope(.brightness, values: brightness),
            envelope(.pitch, values: pitch, minimum: 36, maximum: 96),
            envelope(.pitchConfidence, values: pitchConfidence),
            envelope(.vocalActivity, values: vocal),
        ],
        regions: sections + silence + highEnergy,
        confidence: AudioPerformanceConfidence(
            beat: 0.86,
            downbeat: 0.74,
            onset: 0.88,
            energy: 0.92,
            pitch: 0.71,
            regions: 0.83,
            overall: 0.82))
    return map.validated()!
}

func makeV4FixtureScore(lines: [PlayerEngine.LyricLine]) -> AudioStructureScoreV4 {
    AudioStructureScoreBuilderV4.make(map: makeV4FixtureMap(), lines: lines)
}

func makeV4FixtureBible() -> LyricStageBibleV4 {
    LyricStageBibleV4(
        concept: "fixture concept",
        intensityArc: "quiet build resolve",
        primaryMotif: LyricStageMotifV4(signature: .rail, axis: .horizontal, cadence: .phrase),
        secondaryMotif: nil)
}

func makeV4RailRecipe(lineIndex: Int, intensity: Double = 0.6) -> LyricStageSceneRecipeV4 {
    LyricStageSceneRecipeV4(
        lineIndex: lineIndex,
        family: .railHandoff,
        topology: .relay,
        entrance: .settle,
        focus: .wholeLine,
        tokenRange: nil,
        sustain: .none,
        continuity: .handoff,
        driver: .lyricReveal,
        landmarkIDs: [],
        companionLineIndices: [],
        motifPhase: .develop,
        intensity: intensity)
}

func makeV4Direction(
    track: Track,
    lines: [PlayerEngine.LyricLine],
    score: AudioStructureScoreV4,
    scenes: [LyricStageSceneRecipeV4]
) -> LyricStageDirectionV4 {
    LyricStageDirectionV4(
        directorVersion: "fixture-v4",
        trackID: track.key.description,
        lyricsHash: LyricPerformanceFingerprint.lyricsHash(lines),
        lineCount: lines.count,
        audioScoreHash: score.fingerprint,
        stageBible: makeV4FixtureBible(),
        scenes: scenes)
}
