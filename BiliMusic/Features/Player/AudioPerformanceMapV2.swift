import CryptoKit
import Foundation

enum AudioPerformanceMapV2Version {
    static let current = "audio-performance-map-v2"
    static let analyzer = "bilimusic-local-audio-analysis-v2"
    static let stageSummary = "lyric-stage-audio-summary-v3"
}

enum AudioPerformanceEnvelopeKind: String, Codable, CaseIterable, Sendable {
    case energy
    case brightness
    case pitch
    case pitchConfidence
    case vocalActivity
}

struct AudioPerformanceEnvelope: Codable, Equatable, Sendable {
    let kind: AudioPerformanceEnvelopeKind
    let startTime: Double
    let sampleRateHz: Double
    let minimum: Double
    let maximum: Double
    let samples: Data

    func value(at time: Double) -> Double? {
        guard !samples.isEmpty,
              time.isFinite,
              sampleRateHz.isFinite,
              sampleRateHz > 0,
              time >= startTime else { return nil }
        let requestedPosition = (time - startTime) * sampleRateHz
        let maximumExtrapolation = max(2, sampleRateHz * 0.5)
        guard requestedPosition <= Double(samples.count - 1) + maximumExtrapolation else { return nil }
        let position = min(requestedPosition, Double(samples.count - 1))
        let lower = min(max(0, Int(position.rounded(.down))), samples.count - 1)
        let upper = min(lower + 1, samples.count - 1)
        let fraction = position - Double(lower)
        let normalized = (Double(samples[lower]) * (1 - fraction) + Double(samples[upper]) * fraction) / 255
        return minimum + normalized * (maximum - minimum)
    }

    fileprivate func validated(duration: Double) -> AudioPerformanceEnvelope? {
        guard startTime.isFinite,
              sampleRateHz.isFinite,
              minimum.isFinite,
              maximum.isFinite,
              startTime >= 0,
              startTime <= duration,
              sampleRateHz > 0,
              sampleRateHz <= 240,
              maximum >= minimum,
              !samples.isEmpty else { return nil }
        let lastSampleTime = startTime + Double(samples.count - 1) / sampleRateHz
        let tolerance = max(0.5, 2 / sampleRateHz)
        guard lastSampleTime <= duration + tolerance,
              duration - lastSampleTime <= tolerance else { return nil }
        return self
    }
}

struct AudioPerformanceTempoSegment: Codable, Equatable, Sendable {
    let from: Double
    let to: Double
    let bpm: Double
    let confidence: Double
}

struct AudioPerformanceOnset: Codable, Equatable, Sendable {
    let time: Double
    let strength: Double
}

enum AudioPerformanceRegionKind: String, Codable, CaseIterable, Sendable {
    case acousticSection
    case silence
    case lowEnergy
    case highEnergy
    case transition
}

struct AudioPerformanceRegion: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: AudioPerformanceRegionKind
    let from: Double
    let to: Double
    let confidence: Double
}

struct AudioPerformanceConfidence: Codable, Equatable, Sendable {
    let beat: Double
    let downbeat: Double
    let onset: Double
    let energy: Double
    let pitch: Double
    let regions: Double
    let overall: Double

    fileprivate var isValid: Bool {
        [beat, downbeat, onset, energy, pitch, regions, overall].allSatisfy {
            $0.isFinite && (0...1).contains($0)
        }
    }

    static let none = AudioPerformanceConfidence(
        beat: 0,
        downbeat: 0,
        onset: 0,
        energy: 0,
        pitch: 0,
        regions: 0,
        overall: 0)
}

struct AudioPerformanceMapV2: Codable, Equatable, Sendable {
    let version: String
    let analysisVersion: String
    let audioFingerprint: String
    let duration: Double
    let tempoSegments: [AudioPerformanceTempoSegment]
    let beats: [Double]
    let downbeats: [Double]
    let onsets: [AudioPerformanceOnset]
    let envelopes: [AudioPerformanceEnvelope]
    let regions: [AudioPerformanceRegion]
    let confidence: AudioPerformanceConfidence

    var fingerprint: String {
        AudioPerformanceFingerprint.map(self)
    }

    func validated(
        expectedAudioFingerprint: String? = nil,
        expectedDuration: Double? = nil,
        expectedAnalysisVersion: String? = nil
    ) -> AudioPerformanceMapV2? {
        guard version == AudioPerformanceMapV2Version.current,
              analysisVersion == AudioPerformanceMapV2Version.analyzer,
              !audioFingerprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              duration.isFinite,
              duration > 0,
              duration <= 24 * 60 * 60,
              confidence.isValid else { return nil }
        if let expectedAudioFingerprint, expectedAudioFingerprint != audioFingerprint { return nil }
        if let expectedAnalysisVersion, expectedAnalysisVersion != analysisVersion { return nil }
        if let expectedDuration {
            guard expectedDuration.isFinite,
                  abs(expectedDuration - duration) <= max(0.75, duration * 0.005) else { return nil }
        }

        guard Self.strictlyIncreasing(beats, duration: duration),
              Self.strictlyIncreasing(downbeats, duration: duration),
              Self.validOnsets(onsets, duration: duration),
              Self.validTempoSegments(tempoSegments, duration: duration),
              Self.validRegions(regions, duration: duration) else { return nil }

        var seenEnvelopeKinds = Set<AudioPerformanceEnvelopeKind>()
        let safeEnvelopes = envelopes.compactMap { envelope -> AudioPerformanceEnvelope? in
            guard seenEnvelopeKinds.insert(envelope.kind).inserted else { return nil }
            return envelope.validated(duration: duration)
        }
        guard safeEnvelopes.count == envelopes.count,
              seenEnvelopeKinds.contains(.energy) else { return nil }
        return self
    }

    func envelope(_ kind: AudioPerformanceEnvelopeKind, at time: Double) -> Double? {
        envelopes.first(where: { $0.kind == kind })?.value(at: time)
    }

    func nearestOnset(to time: Double, tolerance: Double) -> AudioPerformanceOnset? {
        guard time.isFinite, tolerance.isFinite, tolerance >= 0, !onsets.isEmpty else { return nil }
        let insertion = Self.lowerBound(onsets, time: time)
        return [insertion - 1, insertion]
            .filter { onsets.indices.contains($0) }
            .map { onsets[$0] }
            .filter { abs($0.time - time) <= tolerance }
            .min { abs($0.time - time) < abs($1.time - time) }
    }

    func summary(for lines: [PlayerEngine.LyricLine]) -> LyricStageAudioSummaryV3 {
        guard !lines.isEmpty else { return .empty(duration: duration, mapFingerprint: fingerprint) }
        let acousticSections = regions.filter { $0.kind == .acousticSection }.sorted { $0.from < $1.from }
        let silenceRegions = regions.filter { $0.kind == .silence }
        let lineSummaries = lines.enumerated().map { index, line in
            let from = min(max(0, line.from), duration)
            let to = min(max(from, line.to), duration)
            let sectionIndex = acousticSections.firstIndex { region in
                let midpoint = from + (to - from) / 2
                return midpoint >= region.from && midpoint <= region.to
            }
            let energySamples = sampledValues(.energy, from: from, to: to, count: 12)
            let pitchConfidenceSamples = sampledValues(.pitchConfidence, from: from, to: to, count: 8)
            let lineOnsets = onsets.lazy.filter { $0.time >= from && $0.time < to }
            let pitchStart = confidentPitch(at: from, confidenceValues: pitchConfidenceSamples)
            let pitchEnd = confidentPitch(at: max(from, to - 0.001), confidenceValues: pitchConfidenceSamples)
            let meanEnergy = Self.mean(energySamples)
            let peakEnergy = energySamples.max() ?? 0
            let startEnergy = envelope(.energy, at: from) ?? meanEnergy
            let endEnergy = envelope(.energy, at: max(from, to - 0.001)) ?? meanEnergy
            let nearestBeatDistance = nearestDistance(in: beats, to: from)
            return LyricStageAudioLineSummaryV3(
                lineIndex: index,
                from: from,
                to: to,
                sectionIndex: sectionIndex,
                meanEnergy: meanEnergy,
                peakEnergy: peakEnergy,
                energyDelta: endEnergy - startEnergy,
                onsetCount: lineOnsets.count,
                onsetStrength: lineOnsets.map(\.strength).max() ?? 0,
                nearestBeatDistance: nearestBeatDistance,
                pitchStart: pitchStart,
                pitchEnd: pitchEnd,
                pitchTrend: pitchStart.flatMap { start in pitchEnd.map { $0 - start } },
                pitchConfidence: pitchConfidenceSamples.isEmpty ? nil : Self.mean(pitchConfidenceSamples),
                longToneRatio: pitchConfidenceSamples.isEmpty
                    ? 0
                    : Double(pitchConfidenceSamples.filter { $0 >= 0.35 }.count)
                        / Double(pitchConfidenceSamples.count),
                silenceBefore: adjacentSilence(before: from, regions: silenceRegions),
                silenceAfter: adjacentSilence(after: to, regions: silenceRegions))
        }

        let sectionSummaries = acousticSections.enumerated().map { index, region in
            let covered = lineSummaries.filter { summary in
                summary.to >= region.from && summary.from <= region.to
            }
            let energy = sampledValues(.energy, from: region.from, to: region.to, count: 24)
            let pitch = sampledValues(.pitch, from: region.from, to: region.to, count: 12)
            return LyricStageAudioSectionSummaryV3(
                index: index,
                from: region.from,
                to: region.to,
                lineFrom: covered.map(\.lineIndex).min(),
                lineTo: covered.map(\.lineIndex).max(),
                meanEnergy: Self.mean(energy),
                energyTrend: (energy.last ?? 0) - (energy.first ?? 0),
                onsetDensity: Double(onsets.lazy.filter { $0.time >= region.from && $0.time < region.to }.count)
                    / max(0.25, region.to - region.from),
                pitchTrend: (pitch.last ?? 0) - (pitch.first ?? 0),
                confidence: region.confidence)
        }
        return LyricStageAudioSummaryV3.make(
            mapFingerprint: fingerprint,
            duration: duration,
            bpm: representativeBPM,
            confidence: confidence,
            sections: sectionSummaries,
            lines: lineSummaries)
    }

    private var representativeBPM: Double? {
        let credible = tempoSegments.filter { $0.confidence >= 0.20 }
        let weighted = credible.map { segment in
            (value: segment.bpm, weight: (segment.to - segment.from) * segment.confidence)
        }
        let totalWeight = weighted.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        return weighted.reduce(0) { $0 + $1.value * $1.weight } / totalWeight
    }

    private func sampledValues(
        _ kind: AudioPerformanceEnvelopeKind,
        from: Double,
        to: Double,
        count: Int
    ) -> [Double] {
        guard count > 0, to >= from else { return [] }
        if to - from < 0.001 { return envelope(kind, at: from).map { [$0] } ?? [] }
        return (0..<count).compactMap { index in
            let fraction = count == 1 ? 0 : Double(index) / Double(count - 1)
            return envelope(kind, at: from + (to - from) * fraction)
        }
    }

    private func confidentPitch(at time: Double, confidenceValues: [Double]) -> Double? {
        guard Self.mean(confidenceValues) >= 0.20 else { return nil }
        return envelope(.pitch, at: time)
    }

    private func nearestDistance(in values: [Double], to time: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        var lower = 0
        var upper = values.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if values[middle] < time { lower = middle + 1 } else { upper = middle }
        }
        return [lower - 1, lower]
            .filter { values.indices.contains($0) }
            .map { abs(values[$0] - time) }
            .min()
    }

    private func adjacentSilence(before time: Double, regions: [AudioPerformanceRegion]) -> Double {
        regions
            .filter { $0.to <= time + 0.08 && time - $0.to <= 0.30 }
            .map { min(8, $0.to - $0.from) }
            .max() ?? 0
    }

    private func adjacentSilence(after time: Double, regions: [AudioPerformanceRegion]) -> Double {
        regions
            .filter { $0.from >= time - 0.08 && $0.from - time <= 0.30 }
            .map { min(8, $0.to - $0.from) }
            .max() ?? 0
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func strictlyIncreasing(_ values: [Double], duration: Double) -> Bool {
        values.enumerated().allSatisfy { index, value in
            value.isFinite
                && value >= 0
                && value <= duration
                && (index == 0 || value > values[index - 1])
        }
    }

    private static func validOnsets(_ values: [AudioPerformanceOnset], duration: Double) -> Bool {
        values.enumerated().allSatisfy { index, onset in
            onset.time.isFinite
                && onset.strength.isFinite
                && onset.time >= 0
                && onset.time <= duration
                && (0...1).contains(onset.strength)
                && (index == 0 || onset.time > values[index - 1].time)
        }
    }

    private static func validTempoSegments(
        _ values: [AudioPerformanceTempoSegment],
        duration: Double
    ) -> Bool {
        guard !values.isEmpty else { return true }
        for (index, segment) in values.enumerated() {
            guard segment.from.isFinite,
                  segment.to.isFinite,
                  segment.bpm.isFinite,
                  segment.confidence.isFinite,
                  segment.from >= 0,
                  segment.to > segment.from,
                  segment.to <= duration + 0.001,
                  (20...320).contains(segment.bpm),
                  (0...1).contains(segment.confidence) else { return false }
            if index > 0, abs(segment.from - values[index - 1].to) > 0.001 { return false }
        }
        return abs((values.first?.from ?? 0)) <= 0.001
            && abs((values.last?.to ?? duration) - duration) <= 0.001
    }

    private static func validRegions(_ values: [AudioPerformanceRegion], duration: Double) -> Bool {
        var seenIDs = Set<String>()
        var previousByKind: [AudioPerformanceRegionKind: AudioPerformanceRegion] = [:]
        for region in values {
            guard !region.id.isEmpty,
                  seenIDs.insert(region.id).inserted,
                  region.from.isFinite,
                  region.to.isFinite,
                  region.confidence.isFinite,
                  region.from >= 0,
                  region.to > region.from,
                  region.to <= duration + 0.001,
                  (0...1).contains(region.confidence) else { return false }
            if let previous = previousByKind[region.kind], region.from < previous.to - 0.001 {
                return false
            }
            previousByKind[region.kind] = region
        }
        let sections = values.filter { $0.kind == .acousticSection }
        guard !sections.isEmpty else { return true }
        return abs((sections.first?.from ?? 0)) <= 0.001
            && abs((sections.last?.to ?? duration) - duration) <= 0.001
            && zip(sections, sections.dropFirst()).allSatisfy { abs($0.to - $1.from) <= 0.001 }
    }

    private static func lowerBound(_ values: [AudioPerformanceOnset], time: Double) -> Int {
        var lower = 0
        var upper = values.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if values[middle].time < time { lower = middle + 1 } else { upper = middle }
        }
        return lower
    }
}

struct LyricStageAudioLineSummaryV3: Codable, Equatable, Sendable {
    let lineIndex: Int
    let from: Double
    let to: Double
    let sectionIndex: Int?
    let meanEnergy: Double
    let peakEnergy: Double
    let energyDelta: Double
    let onsetCount: Int
    let onsetStrength: Double
    let nearestBeatDistance: Double?
    let pitchStart: Double?
    let pitchEnd: Double?
    let pitchTrend: Double?
    let pitchConfidence: Double?
    let longToneRatio: Double
    let silenceBefore: Double
    let silenceAfter: Double

    init(
        lineIndex: Int,
        from: Double,
        to: Double,
        sectionIndex: Int?,
        meanEnergy: Double,
        peakEnergy: Double,
        energyDelta: Double,
        onsetCount: Int,
        onsetStrength: Double = 0,
        nearestBeatDistance: Double?,
        pitchStart: Double?,
        pitchEnd: Double?,
        pitchTrend: Double?,
        pitchConfidence: Double?,
        longToneRatio: Double = 0,
        silenceBefore: Double,
        silenceAfter: Double
    ) {
        self.lineIndex = lineIndex
        self.from = from
        self.to = to
        self.sectionIndex = sectionIndex
        self.meanEnergy = meanEnergy
        self.peakEnergy = peakEnergy
        self.energyDelta = energyDelta
        self.onsetCount = onsetCount
        self.onsetStrength = onsetStrength
        self.nearestBeatDistance = nearestBeatDistance
        self.pitchStart = pitchStart
        self.pitchEnd = pitchEnd
        self.pitchTrend = pitchTrend
        self.pitchConfidence = pitchConfidence
        self.longToneRatio = longToneRatio
        self.silenceBefore = silenceBefore
        self.silenceAfter = silenceAfter
    }
}

struct LyricStageAudioSectionSummaryV3: Codable, Equatable, Sendable {
    let index: Int
    let from: Double
    let to: Double
    let lineFrom: Int?
    let lineTo: Int?
    let meanEnergy: Double
    let energyTrend: Double
    let onsetDensity: Double
    let pitchTrend: Double
    let confidence: Double
}

struct LyricStageAudioSummaryV3: Codable, Equatable, Sendable {
    let version: String
    let mapFingerprint: String
    let summaryHash: String
    let duration: Double
    let bpm: Double?
    let confidence: AudioPerformanceConfidence
    let sections: [LyricStageAudioSectionSummaryV3]
    let lines: [LyricStageAudioLineSummaryV3]

    init(
        version: String,
        mapFingerprint: String,
        summaryHash: String,
        duration: Double,
        bpm: Double? = nil,
        confidence: AudioPerformanceConfidence,
        sections: [LyricStageAudioSectionSummaryV3],
        lines: [LyricStageAudioLineSummaryV3]
    ) {
        self.version = version
        self.mapFingerprint = mapFingerprint
        self.summaryHash = summaryHash
        self.duration = duration
        self.bpm = bpm
        self.confidence = confidence
        self.sections = sections
        self.lines = lines
    }

    static func empty(duration: Double, mapFingerprint: String = "none") -> LyricStageAudioSummaryV3 {
        make(
            mapFingerprint: mapFingerprint,
            duration: max(0, duration.isFinite ? duration : 0),
            bpm: nil,
            confidence: .none,
            sections: [],
            lines: [])
    }

    fileprivate static func make(
        mapFingerprint: String,
        duration: Double,
        bpm: Double?,
        confidence: AudioPerformanceConfidence,
        sections: [LyricStageAudioSectionSummaryV3],
        lines: [LyricStageAudioLineSummaryV3]
    ) -> LyricStageAudioSummaryV3 {
        let payload = HashPayload(
            version: AudioPerformanceMapV2Version.stageSummary,
            mapFingerprint: mapFingerprint,
            duration: duration,
            bpm: bpm,
            confidence: confidence,
            sections: sections,
            lines: lines)
        return LyricStageAudioSummaryV3(
            version: payload.version,
            mapFingerprint: mapFingerprint,
            summaryHash: AudioPerformanceFingerprint.digest(payload),
            duration: duration,
            bpm: bpm,
            confidence: confidence,
            sections: sections,
            lines: lines)
    }

    private struct HashPayload: Codable {
        let version: String
        let mapFingerprint: String
        let duration: Double
        let bpm: Double?
        let confidence: AudioPerformanceConfidence
        let sections: [LyricStageAudioSectionSummaryV3]
        let lines: [LyricStageAudioLineSummaryV3]
    }
}

enum AudioPerformanceFingerprint {
    static func audioFile(at url: URL) throws -> String {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func map(_ map: AudioPerformanceMapV2) -> String {
        digest(map)
    }

    static func digest<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "invalid" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
