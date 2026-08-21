import Foundation

enum AudioStructureAvailabilityV4: String, Codable, CaseIterable, Equatable, Sendable {
    case ready
    case missingCache
    case analysisFailed
    case stale
}

enum AudioStructureMomentKindV4: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case sectionStart
    case silenceExit
    case energyPeak
    case strongDownbeat
    case cadence
}

enum AudioStructureAccentKindV4: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case beat
    case downbeat
    case onset
}

struct AudioStructureFeatureSemanticsV4: Codable, Equatable, Sendable {
    let energy: String
    let brightness: String
    let pitch: String
    let vocalActivity: String
    let downbeat: String
    let quantization: String

    static let localAnalyzer = AudioStructureFeatureSemanticsV4(
        energy: "trackRelativePercentile",
        brightness: "zeroCrossingRateProxy",
        pitch: "dominantMixMIDIAutocorrelation",
        vocalActivity: "energyPitchConfidenceProxy",
        downbeat: "heuristicFourBeatBar",
        quantization: "q8Milliseconds")
}

struct AudioStructureDomainConfidenceV4: Codable, Equatable, Sendable {
    let beat: UInt8
    let downbeat: UInt8
    let onset: UInt8
    let energy: UInt8
    let pitch: UInt8
    let sections: UInt8
    let overall: UInt8
}

struct AudioStructureTempoSegmentV4: Codable, Equatable, Sendable {
    let fromMilliseconds: Int
    let toMilliseconds: Int
    let bpmTenths: Int
    let confidenceQ: UInt8

    init(fromMilliseconds: Int, toMilliseconds: Int, bpmTenths: Int, confidenceQ: UInt8) {
        self.fromMilliseconds = fromMilliseconds
        self.toMilliseconds = toMilliseconds
        self.bpmTenths = bpmTenths
        self.confidenceQ = confidenceQ
    }

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        fromMilliseconds = try values.decode(Int.self)
        toMilliseconds = try values.decode(Int.self)
        bpmTenths = try values.decode(Int.self)
        confidenceQ = try values.decode(UInt8.self)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(fromMilliseconds)
        try values.encode(toMilliseconds)
        try values.encode(bpmTenths)
        try values.encode(confidenceQ)
    }
}

struct AudioStructureSectionV4: Codable, Equatable, Sendable {
    let index: Int
    let fromMilliseconds: Int
    let toMilliseconds: Int
    let lineFrom: Int?
    let lineTo: Int?
    let boundaryStrengthQ: UInt8
    let meanEnergyQ: UInt8
    let peakEnergyQ: UInt8
    let energySlopeQ: Int
    let dynamicRangeQ: UInt8
    let onsetDensityQ: UInt8
    let brightnessMeanQ: UInt8
    let brightnessSlopeQ: Int
    let voicednessMeanQ: UInt8
    let pitchRangeTenths: Int
    let pitchConfidenceQ: UInt8
    let silenceHeadMilliseconds: Int
    let silenceTailMilliseconds: Int

    init(
        index: Int,
        fromMilliseconds: Int,
        toMilliseconds: Int,
        lineFrom: Int?,
        lineTo: Int?,
        boundaryStrengthQ: UInt8,
        meanEnergyQ: UInt8,
        peakEnergyQ: UInt8,
        energySlopeQ: Int,
        dynamicRangeQ: UInt8,
        onsetDensityQ: UInt8,
        brightnessMeanQ: UInt8,
        brightnessSlopeQ: Int,
        voicednessMeanQ: UInt8,
        pitchRangeTenths: Int,
        pitchConfidenceQ: UInt8,
        silenceHeadMilliseconds: Int,
        silenceTailMilliseconds: Int
    ) {
        self.index = index
        self.fromMilliseconds = fromMilliseconds
        self.toMilliseconds = toMilliseconds
        self.lineFrom = lineFrom
        self.lineTo = lineTo
        self.boundaryStrengthQ = boundaryStrengthQ
        self.meanEnergyQ = meanEnergyQ
        self.peakEnergyQ = peakEnergyQ
        self.energySlopeQ = energySlopeQ
        self.dynamicRangeQ = dynamicRangeQ
        self.onsetDensityQ = onsetDensityQ
        self.brightnessMeanQ = brightnessMeanQ
        self.brightnessSlopeQ = brightnessSlopeQ
        self.voicednessMeanQ = voicednessMeanQ
        self.pitchRangeTenths = pitchRangeTenths
        self.pitchConfidenceQ = pitchConfidenceQ
        self.silenceHeadMilliseconds = silenceHeadMilliseconds
        self.silenceTailMilliseconds = silenceTailMilliseconds
    }

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        index = try values.decode(Int.self)
        fromMilliseconds = try values.decode(Int.self)
        toMilliseconds = try values.decode(Int.self)
        lineFrom = try values.decodeOptionalInt()
        lineTo = try values.decodeOptionalInt()
        boundaryStrengthQ = try values.decode(UInt8.self)
        meanEnergyQ = try values.decode(UInt8.self)
        peakEnergyQ = try values.decode(UInt8.self)
        energySlopeQ = try values.decode(Int.self)
        dynamicRangeQ = try values.decode(UInt8.self)
        onsetDensityQ = try values.decode(UInt8.self)
        brightnessMeanQ = try values.decode(UInt8.self)
        brightnessSlopeQ = try values.decode(Int.self)
        voicednessMeanQ = try values.decode(UInt8.self)
        pitchRangeTenths = try values.decode(Int.self)
        pitchConfidenceQ = try values.decode(UInt8.self)
        silenceHeadMilliseconds = try values.decode(Int.self)
        silenceTailMilliseconds = try values.decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(index)
        try values.encode(fromMilliseconds)
        try values.encode(toMilliseconds)
        try values.encodeOptional(lineFrom)
        try values.encodeOptional(lineTo)
        try values.encode(boundaryStrengthQ)
        try values.encode(meanEnergyQ)
        try values.encode(peakEnergyQ)
        try values.encode(energySlopeQ)
        try values.encode(dynamicRangeQ)
        try values.encode(onsetDensityQ)
        try values.encode(brightnessMeanQ)
        try values.encode(brightnessSlopeQ)
        try values.encode(voicednessMeanQ)
        try values.encode(pitchRangeTenths)
        try values.encode(pitchConfidenceQ)
        try values.encode(silenceHeadMilliseconds)
        try values.encode(silenceTailMilliseconds)
    }
}

struct AudioStructureLineFactV4: Codable, Equatable, Sendable {
    let lineIndex: Int
    let sectionIndex: Int?
    let entryBeatPhaseQ: UInt8?
    let signedNearestBeatMilliseconds: Int?
    let signedNearestDownbeatMilliseconds: Int?
    let beatsSpannedTenths: Int?
    let meanEnergyQ: UInt8?
    let peakEnergyQ: UInt8?
    let energySlopeQ: Int?
    let onsetCount: Int
    let onsetPeakQ: UInt8?
    let silenceBeforeMilliseconds: Int
    let silenceAfterMilliseconds: Int

    init(
        lineIndex: Int,
        sectionIndex: Int?,
        entryBeatPhaseQ: UInt8?,
        signedNearestBeatMilliseconds: Int?,
        signedNearestDownbeatMilliseconds: Int?,
        beatsSpannedTenths: Int?,
        meanEnergyQ: UInt8?,
        peakEnergyQ: UInt8?,
        energySlopeQ: Int?,
        onsetCount: Int,
        onsetPeakQ: UInt8?,
        silenceBeforeMilliseconds: Int,
        silenceAfterMilliseconds: Int
    ) {
        self.lineIndex = lineIndex
        self.sectionIndex = sectionIndex
        self.entryBeatPhaseQ = entryBeatPhaseQ
        self.signedNearestBeatMilliseconds = signedNearestBeatMilliseconds
        self.signedNearestDownbeatMilliseconds = signedNearestDownbeatMilliseconds
        self.beatsSpannedTenths = beatsSpannedTenths
        self.meanEnergyQ = meanEnergyQ
        self.peakEnergyQ = peakEnergyQ
        self.energySlopeQ = energySlopeQ
        self.onsetCount = onsetCount
        self.onsetPeakQ = onsetPeakQ
        self.silenceBeforeMilliseconds = silenceBeforeMilliseconds
        self.silenceAfterMilliseconds = silenceAfterMilliseconds
    }

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        lineIndex = try values.decode(Int.self)
        sectionIndex = try values.decodeOptionalInt()
        entryBeatPhaseQ = try values.decodeOptionalUInt8()
        signedNearestBeatMilliseconds = try values.decodeOptionalInt()
        signedNearestDownbeatMilliseconds = try values.decodeOptionalInt()
        beatsSpannedTenths = try values.decodeOptionalInt()
        meanEnergyQ = try values.decodeOptionalUInt8()
        peakEnergyQ = try values.decodeOptionalUInt8()
        energySlopeQ = try values.decodeOptionalInt()
        onsetCount = try values.decode(Int.self)
        onsetPeakQ = try values.decodeOptionalUInt8()
        silenceBeforeMilliseconds = try values.decode(Int.self)
        silenceAfterMilliseconds = try values.decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(lineIndex)
        try values.encodeOptional(sectionIndex)
        try values.encodeOptional(entryBeatPhaseQ)
        try values.encodeOptional(signedNearestBeatMilliseconds)
        try values.encodeOptional(signedNearestDownbeatMilliseconds)
        try values.encodeOptional(beatsSpannedTenths)
        try values.encodeOptional(meanEnergyQ)
        try values.encodeOptional(peakEnergyQ)
        try values.encodeOptional(energySlopeQ)
        try values.encode(onsetCount)
        try values.encodeOptional(onsetPeakQ)
        try values.encode(silenceBeforeMilliseconds)
        try values.encode(silenceAfterMilliseconds)
    }
}

struct AudioStructureAccentEventV4: Codable, Equatable, Sendable {
    let kind: AudioStructureAccentKindV4
    let offsetMilliseconds: Int
    let strengthQ: UInt8

    init(kind: AudioStructureAccentKindV4, offsetMilliseconds: Int, strengthQ: UInt8) {
        self.kind = kind
        self.offsetMilliseconds = offsetMilliseconds
        self.strengthQ = strengthQ
    }

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        kind = try values.decode(AudioStructureAccentKindV4.self)
        offsetMilliseconds = try values.decode(Int.self)
        strengthQ = try values.decode(UInt8.self)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(kind)
        try values.encode(offsetMilliseconds)
        try values.encode(strengthQ)
    }
}

struct AudioStructureLineDetailV4: Codable, Equatable, Sendable {
    let lineIndex: Int
    let energyContourQ: [UInt8]
    let pitchContourTenths: [Int?]
    let pitchConfidenceQ: UInt8
    let voicednessQ: UInt8
    let accentEvents: [AudioStructureAccentEventV4]

    init(
        lineIndex: Int,
        energyContourQ: [UInt8],
        pitchContourTenths: [Int?],
        pitchConfidenceQ: UInt8,
        voicednessQ: UInt8,
        accentEvents: [AudioStructureAccentEventV4]
    ) {
        self.lineIndex = lineIndex
        self.energyContourQ = energyContourQ
        self.pitchContourTenths = pitchContourTenths
        self.pitchConfidenceQ = pitchConfidenceQ
        self.voicednessQ = voicednessQ
        self.accentEvents = accentEvents
    }

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        lineIndex = try values.decode(Int.self)
        energyContourQ = try values.decode([UInt8].self)
        pitchContourTenths = try values.decode([Int?].self)
        pitchConfidenceQ = try values.decode(UInt8.self)
        voicednessQ = try values.decode(UInt8.self)
        accentEvents = try values.decode([AudioStructureAccentEventV4].self)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(lineIndex)
        try values.encode(energyContourQ)
        try values.encode(pitchContourTenths)
        try values.encode(pitchConfidenceQ)
        try values.encode(voicednessQ)
        try values.encode(accentEvents)
    }
}

struct AudioStructureMomentV4: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: AudioStructureMomentKindV4
    let fromMilliseconds: Int
    let toMilliseconds: Int
    let strengthQ: UInt8
    let confidenceQ: UInt8
    let lineIndex: Int?

    init(
        id: String,
        kind: AudioStructureMomentKindV4,
        fromMilliseconds: Int,
        toMilliseconds: Int,
        strengthQ: UInt8,
        confidenceQ: UInt8,
        lineIndex: Int?
    ) {
        self.id = id
        self.kind = kind
        self.fromMilliseconds = fromMilliseconds
        self.toMilliseconds = toMilliseconds
        self.strengthQ = strengthQ
        self.confidenceQ = confidenceQ
        self.lineIndex = lineIndex
    }

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        id = try values.decode(String.self)
        kind = try values.decode(AudioStructureMomentKindV4.self)
        fromMilliseconds = try values.decode(Int.self)
        toMilliseconds = try values.decode(Int.self)
        strengthQ = try values.decode(UInt8.self)
        confidenceQ = try values.decode(UInt8.self)
        lineIndex = try values.decodeOptionalInt()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(id)
        try values.encode(kind)
        try values.encode(fromMilliseconds)
        try values.encode(toMilliseconds)
        try values.encode(strengthQ)
        try values.encode(confidenceQ)
        try values.encodeOptional(lineIndex)
    }
}

struct AudioStructureScoreV4: Codable, Equatable, Sendable {
    let version: String
    let availability: AudioStructureAvailabilityV4
    let semantics: AudioStructureFeatureSemanticsV4
    let confidence: AudioStructureDomainConfidenceV4
    let durationMilliseconds: Int
    let tempoSegments: [AudioStructureTempoSegmentV4]
    let sections: [AudioStructureSectionV4]
    let lineFacts: [AudioStructureLineFactV4]
    let lineDetails: [AudioStructureLineDetailV4]
    let moments: [AudioStructureMomentV4]

    var fingerprint: String { LyricStageFingerprintV3.digest(self) }

    func validated(lineCount: Int) -> AudioStructureScoreV4? {
        guard version == LyricStagePlanV4Version.audioScore,
              semantics == .localAnalyzer,
              durationMilliseconds >= 0,
              durationMilliseconds <= 86_400_000,
              tempoSegments.count <= 8,
              sections.count <= 24,
              lineDetails.count <= 64,
              moments.count <= 32,
              lineFacts.count == lineCount,
              lineFacts.enumerated().allSatisfy({ $0.offset == $0.element.lineIndex }) else {
            return nil
        }
        if availability == .ready, durationMilliseconds == 0 { return nil }

        guard tempoSegments.allSatisfy({ segment in
            segment.fromMilliseconds >= 0
                && segment.toMilliseconds > segment.fromMilliseconds
                && segment.toMilliseconds <= durationMilliseconds + 1_000
                && (200...3_200).contains(segment.bpmTenths)
        }) else { return nil }

        var sectionIndices = Set<Int>()
        guard sections.allSatisfy({ section in
            sectionIndices.insert(section.index).inserted
                && section.fromMilliseconds >= 0
                && section.toMilliseconds > section.fromMilliseconds
                && section.toMilliseconds <= durationMilliseconds + 1_000
                && section.lineFrom.map { (0..<lineCount).contains($0) } ?? true
                && section.lineTo.map { (0..<lineCount).contains($0) } ?? true
                && !(section.lineFrom != nil && section.lineTo == nil)
                && !(section.lineFrom == nil && section.lineTo != nil)
                && ((section.lineFrom ?? 0) <= (section.lineTo ?? 0))
                && (-255...255).contains(section.energySlopeQ)
                && (-255...255).contains(section.brightnessSlopeQ)
                && section.silenceHeadMilliseconds >= 0
                && section.silenceTailMilliseconds >= 0
        }) else { return nil }

        guard lineFacts.allSatisfy({ fact in
            fact.sectionIndex.map { sectionIndices.contains($0) } ?? true
                && fact.signedNearestBeatMilliseconds.map { (-2_000...2_000).contains($0) } ?? true
                && fact.signedNearestDownbeatMilliseconds.map { (-8_000...8_000).contains($0) } ?? true
                && fact.energySlopeQ.map { (-255...255).contains($0) } ?? true
                && fact.onsetCount >= 0
                && fact.silenceBeforeMilliseconds >= 0
                && fact.silenceAfterMilliseconds >= 0
        }) else { return nil }

        var detailedLines = Set<Int>()
        guard lineDetails.allSatisfy({ detail in
            detailedLines.insert(detail.lineIndex).inserted
                && (0..<lineCount).contains(detail.lineIndex)
                && (detail.energyContourQ.isEmpty || detail.energyContourQ.count == 4)
                && (detail.pitchContourTenths.isEmpty || detail.pitchContourTenths.count == 3)
                && detail.accentEvents.count <= 3
                && detail.accentEvents.allSatisfy { $0.offsetMilliseconds >= 0 }
        }) else { return nil }

        var momentIDs = Set<String>()
        guard moments.allSatisfy({ moment in
            !moment.id.isEmpty
                && moment.id.count <= 48
                && momentIDs.insert(moment.id).inserted
                && moment.fromMilliseconds >= 0
                && moment.toMilliseconds >= moment.fromMilliseconds
                && moment.toMilliseconds <= durationMilliseconds + 1_000
                && moment.lineIndex.map { (0..<lineCount).contains($0) } ?? true
        }) else { return nil }
        return self
    }

    func deterministicallyLimited(
        lineDetailCount: Int,
        momentCount: Int,
        includeContours: Bool
    ) -> AudioStructureScoreV4 {
        let factsByLine = lineFacts.reduce(into: [Int: AudioStructureLineFactV4]()) { result, fact in
            if result[fact.lineIndex] == nil { result[fact.lineIndex] = fact }
        }
        let selectedDetails = lineDetails
            .sorted { lhs, rhs in
                let lhsScore = Self.detailPriority(lhs, fact: factsByLine[lhs.lineIndex])
                let rhsScore = Self.detailPriority(rhs, fact: factsByLine[rhs.lineIndex])
                return lhsScore == rhsScore ? lhs.lineIndex < rhs.lineIndex : lhsScore > rhsScore
            }
            .prefix(max(0, lineDetailCount))
            .map { detail in
                guard !includeContours else { return detail }
                return AudioStructureLineDetailV4(
                    lineIndex: detail.lineIndex,
                    energyContourQ: [],
                    pitchContourTenths: [],
                    pitchConfidenceQ: detail.pitchConfidenceQ,
                    voicednessQ: detail.voicednessQ,
                    accentEvents: detail.accentEvents)
            }
            .sorted { $0.lineIndex < $1.lineIndex }
        let selectedMoments = moments
            .sorted { lhs, rhs in
                let lhsScore = Self.momentPriority(lhs)
                let rhsScore = Self.momentPriority(rhs)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                if lhs.fromMilliseconds != rhs.fromMilliseconds { return lhs.fromMilliseconds < rhs.fromMilliseconds }
                return lhs.id < rhs.id
            }
            .prefix(max(0, momentCount))
            .sorted { lhs, rhs in
                lhs.fromMilliseconds == rhs.fromMilliseconds ? lhs.id < rhs.id : lhs.fromMilliseconds < rhs.fromMilliseconds
            }
        return AudioStructureScoreV4(
            version: version,
            availability: availability,
            semantics: semantics,
            confidence: confidence,
            durationMilliseconds: durationMilliseconds,
            tempoSegments: tempoSegments,
            sections: sections,
            lineFacts: lineFacts,
            lineDetails: selectedDetails,
            moments: selectedMoments)
    }

    private static func detailPriority(
        _ detail: AudioStructureLineDetailV4,
        fact: AudioStructureLineFactV4?
    ) -> Int {
        let accent = Int(detail.accentEvents.map(\.strengthQ).max() ?? 0)
        let contour = Int(detail.energyContourQ.max() ?? 0) - Int(detail.energyContourQ.min() ?? 0)
        let onset = min(255, (fact?.onsetCount ?? 0) * 32)
        let silence = min(255, ((fact?.silenceBeforeMilliseconds ?? 0) + (fact?.silenceAfterMilliseconds ?? 0)) / 8)
        return accent * 4 + contour * 2 + onset + silence
    }

    private static func momentPriority(_ moment: AudioStructureMomentV4) -> Int {
        let kind: Int = switch moment.kind {
        case .sectionStart: 5
        case .silenceExit: 4
        case .energyPeak: 3
        case .strongDownbeat: 2
        case .cadence: 1
        }
        return kind * 1_000 + Int(moment.strengthQ) * 2 + Int(moment.confidenceQ)
    }
}

enum AudioStructureScoreBuilderV4 {
    static func make(
        map: AudioPerformanceMapV2?,
        lines: [PlayerEngine.LyricLine],
        availability requestedAvailability: AudioStructureAvailabilityV4? = nil
    ) -> AudioStructureScoreV4 {
        let safeMap = map?.validated()
        let availability: AudioStructureAvailabilityV4 = {
            if let requestedAvailability {
                if requestedAvailability == .ready, safeMap == nil { return .analysisFailed }
                return requestedAvailability
            }
            if safeMap != nil { return .ready }
            return map == nil ? .missingCache : .analysisFailed
        }()
        let duration = safeMap?.duration ?? lines.map(\.to).filter(\.isFinite).max() ?? 0
        let durationMilliseconds = milliseconds(max(0, duration))
        let confidence = safeMap.map(domainConfidence) ?? AudioStructureDomainConfidenceV4(
            beat: 0,
            downbeat: 0,
            onset: 0,
            energy: 0,
            pitch: 0,
            sections: 0,
            overall: 0)
        let tempos = safeMap?.tempoSegments
            .sorted { $0.from < $1.from }
            .prefix(8)
            .map {
                AudioStructureTempoSegmentV4(
                    fromMilliseconds: milliseconds($0.from),
                    toMilliseconds: milliseconds($0.to),
                    bpmTenths: Int(($0.bpm * 10).rounded()),
                    confidenceQ: q8($0.confidence))
            } ?? []
        let sections = safeMap.map { makeSections(map: $0, lines: lines) } ?? []
        let facts = makeLineFacts(map: safeMap, lines: lines, sections: sections)
        let details = safeMap.map { makeLineDetails(map: $0, lines: lines, facts: facts) } ?? []
        let moments = safeMap.map { makeMoments(map: $0, lines: lines, facts: facts) } ?? []
        let score = AudioStructureScoreV4(
            version: LyricStagePlanV4Version.audioScore,
            availability: availability,
            semantics: .localAnalyzer,
            confidence: confidence,
            durationMilliseconds: durationMilliseconds,
            tempoSegments: tempos,
            sections: sections,
            lineFacts: facts,
            lineDetails: details,
            moments: moments)
        return score.deterministicallyLimited(lineDetailCount: 64, momentCount: 32, includeContours: true)
    }

    private static func makeSections(
        map: AudioPerformanceMapV2,
        lines: [PlayerEngine.LyricLine]
    ) -> [AudioStructureSectionV4] {
        let silence = map.regions.filter { $0.kind == .silence }
        return map.regions
            .filter { $0.kind == .acousticSection }
            .sorted { $0.from < $1.from }
            .prefix(24)
            .enumerated()
            .map { order, region in
                let covered = lines.enumerated().filter { _, line in
                    let midpoint = line.from + max(0, line.to - line.from) / 2
                    return midpoint >= region.from && midpoint <= region.to
                }.map(\.offset)
                let energy = samples(map: map, kind: .energy, from: region.from, to: region.to, count: 8)
                let brightness = samples(map: map, kind: .brightness, from: region.from, to: region.to, count: 8)
                let voicedness = samples(map: map, kind: .vocalActivity, from: region.from, to: region.to, count: 8)
                let pitch = confidentPitchSamples(map: map, from: region.from, to: region.to, count: 8)
                let pitchValues = pitch.compactMap { $0 }
                let pitchConfidence = samples(map: map, kind: .pitchConfidence, from: region.from, to: region.to, count: 8)
                let onsetDensity = Double(map.onsets.lazy.filter {
                    $0.time >= region.from && $0.time < region.to
                }.count) / max(0.25, region.to - region.from)
                return AudioStructureSectionV4(
                    index: order,
                    fromMilliseconds: milliseconds(region.from),
                    toMilliseconds: milliseconds(region.to),
                    lineFrom: covered.min(),
                    lineTo: covered.max(),
                    boundaryStrengthQ: q8(region.confidence),
                    meanEnergyQ: q8(mean(energy)),
                    peakEnergyQ: q8(energy.max() ?? 0),
                    energySlopeQ: signedQ((energy.last ?? 0) - (energy.first ?? 0)),
                    dynamicRangeQ: q8((energy.max() ?? 0) - (energy.min() ?? 0)),
                    onsetDensityQ: UInt8(clamping: Int((min(8, onsetDensity) / 8 * 255).rounded())),
                    brightnessMeanQ: q8(mean(brightness)),
                    brightnessSlopeQ: signedQ((brightness.last ?? 0) - (brightness.first ?? 0)),
                    voicednessMeanQ: q8(mean(voicedness)),
                    pitchRangeTenths: Int((((pitchValues.max() ?? 0) - (pitchValues.min() ?? 0)) * 10).rounded()),
                    pitchConfidenceQ: q8(mean(pitchConfidence)),
                    silenceHeadMilliseconds: milliseconds(adjacentSilence(at: region.from, before: true, regions: silence)),
                    silenceTailMilliseconds: milliseconds(adjacentSilence(at: region.to, before: false, regions: silence)))
            }
    }

    private static func makeLineFacts(
        map: AudioPerformanceMapV2?,
        lines: [PlayerEngine.LyricLine],
        sections: [AudioStructureSectionV4]
    ) -> [AudioStructureLineFactV4] {
        lines.enumerated().map { index, line in
            guard let map else {
                return AudioStructureLineFactV4(
                    lineIndex: index,
                    sectionIndex: nil,
                    entryBeatPhaseQ: nil,
                    signedNearestBeatMilliseconds: nil,
                    signedNearestDownbeatMilliseconds: nil,
                    beatsSpannedTenths: nil,
                    meanEnergyQ: nil,
                    peakEnergyQ: nil,
                    energySlopeQ: nil,
                    onsetCount: 0,
                    onsetPeakQ: nil,
                    silenceBeforeMilliseconds: 0,
                    silenceAfterMilliseconds: 0)
            }
            let from = min(max(0, line.from), map.duration)
            let to = min(max(from, line.to), map.duration)
            let midpointMs = milliseconds(from + (to - from) / 2)
            let sectionIndex = sections.first { midpointMs >= $0.fromMilliseconds && midpointMs <= $0.toMilliseconds }?.index
            let energy = samples(map: map, kind: .energy, from: from, to: to, count: 6)
            let onsets = map.onsets.filter { $0.time >= from && $0.time < to }
            let silence = map.regions.filter { $0.kind == .silence }
            return AudioStructureLineFactV4(
                lineIndex: index,
                sectionIndex: sectionIndex,
                entryBeatPhaseQ: beatPhase(events: map.beats, at: from).map(q8),
                signedNearestBeatMilliseconds: nearestSignedMilliseconds(events: map.beats, to: from, cap: 2_000),
                signedNearestDownbeatMilliseconds: nearestSignedMilliseconds(events: map.downbeats, to: from, cap: 8_000),
                beatsSpannedTenths: beatSpanTenths(events: map.beats, from: from, to: to),
                meanEnergyQ: energy.isEmpty ? nil : q8(mean(energy)),
                peakEnergyQ: energy.max().map(q8),
                energySlopeQ: energy.isEmpty ? nil : signedQ((energy.last ?? 0) - (energy.first ?? 0)),
                onsetCount: onsets.count,
                onsetPeakQ: onsets.map(\.strength).max().map(q8),
                silenceBeforeMilliseconds: milliseconds(adjacentSilence(at: from, before: true, regions: silence)),
                silenceAfterMilliseconds: milliseconds(adjacentSilence(at: to, before: false, regions: silence)))
        }
    }

    private static func makeLineDetails(
        map: AudioPerformanceMapV2,
        lines: [PlayerEngine.LyricLine],
        facts: [AudioStructureLineFactV4]
    ) -> [AudioStructureLineDetailV4] {
        let details = lines.enumerated().map { index, line in
            let from = min(max(0, line.from), map.duration)
            let to = min(max(from, line.to), map.duration)
            let pitchConfidence = samples(map: map, kind: .pitchConfidence, from: from, to: to, count: 3)
            let pitch = (0..<3).map { position -> Int? in
                let time = interpolatedTime(from: from, to: to, position: position, count: 3)
                guard (map.envelope(.pitchConfidence, at: time) ?? 0) >= 0.20,
                      let value = map.envelope(.pitch, at: time) else { return nil }
                return Int((value * 10).rounded())
            }
            var accents = map.onsets
                .filter { $0.time >= from && $0.time < to }
                .map {
                    AudioStructureAccentEventV4(
                        kind: .onset,
                        offsetMilliseconds: milliseconds($0.time - from),
                        strengthQ: q8($0.strength))
                }
            accents += map.beats.filter { $0 >= from && $0 < to }.map {
                AudioStructureAccentEventV4(
                    kind: .beat,
                    offsetMilliseconds: milliseconds($0 - from),
                    strengthQ: q8((map.envelope(.energy, at: $0) ?? 0) * map.confidence.beat))
            }
            accents += map.downbeats.filter { $0 >= from && $0 < to }.map {
                AudioStructureAccentEventV4(
                    kind: .downbeat,
                    offsetMilliseconds: milliseconds($0 - from),
                    strengthQ: q8(max(0.55, map.envelope(.energy, at: $0) ?? 0) * map.confidence.downbeat))
            }
            accents = accents
                .sorted { lhs, rhs in
                    if lhs.strengthQ != rhs.strengthQ { return lhs.strengthQ > rhs.strengthQ }
                    if lhs.offsetMilliseconds != rhs.offsetMilliseconds { return lhs.offsetMilliseconds < rhs.offsetMilliseconds }
                    return lhs.kind.rawValue < rhs.kind.rawValue
                }
                .prefix(3)
                .sorted { $0.offsetMilliseconds < $1.offsetMilliseconds }
            return AudioStructureLineDetailV4(
                lineIndex: index,
                energyContourQ: samples(map: map, kind: .energy, from: from, to: to, count: 4).map(q8),
                pitchContourTenths: pitch,
                pitchConfidenceQ: q8(mean(pitchConfidence)),
                voicednessQ: q8(mean(samples(map: map, kind: .vocalActivity, from: from, to: to, count: 4))),
                accentEvents: accents)
        }
        let score = AudioStructureScoreV4(
            version: LyricStagePlanV4Version.audioScore,
            availability: .ready,
            semantics: .localAnalyzer,
            confidence: domainConfidence(map),
            durationMilliseconds: milliseconds(map.duration),
            tempoSegments: [],
            sections: [],
            lineFacts: facts,
            lineDetails: details,
            moments: [])
        return score.deterministicallyLimited(lineDetailCount: 64, momentCount: 0, includeContours: true).lineDetails
    }

    private static func makeMoments(
        map: AudioPerformanceMapV2,
        lines: [PlayerEngine.LyricLine],
        facts: [AudioStructureLineFactV4]
    ) -> [AudioStructureMomentV4] {
        var candidates: [AudioStructureMomentV4] = []
        for region in map.regions where region.kind == .acousticSection {
            candidates.append(moment(
                kind: .sectionStart,
                from: region.from,
                to: min(region.to, region.from + 0.7),
                strength: region.confidence,
                confidence: map.confidence.regions,
                lines: lines))
        }
        for region in map.regions where region.kind == .silence {
            candidates.append(moment(
                kind: .silenceExit,
                from: region.to,
                to: region.to,
                strength: min(1, (region.to - region.from) / 2),
                confidence: region.confidence,
                lines: lines))
        }
        for region in map.regions where region.kind == .highEnergy {
            let sampled = (0..<12).map { position -> (Double, Double) in
                let time = interpolatedTime(from: region.from, to: region.to, position: position, count: 12)
                return (time, map.envelope(.energy, at: time) ?? 0)
            }
            let peak = sampled.max { $0.1 < $1.1 } ?? (region.from, 0)
            candidates.append(moment(
                kind: .energyPeak,
                from: peak.0,
                to: peak.0,
                strength: peak.1,
                confidence: map.confidence.energy,
                lines: lines))
        }
        for time in map.downbeats where (map.envelope(.energy, at: time) ?? 0) >= 0.48 {
            candidates.append(moment(
                kind: .strongDownbeat,
                from: time,
                to: time,
                strength: map.envelope(.energy, at: time) ?? 0,
                confidence: map.confidence.downbeat,
                lines: lines))
        }
        for fact in facts where fact.silenceAfterMilliseconds >= 250 || fact.lineIndex == lines.count - 1 {
            guard lines.indices.contains(fact.lineIndex) else { continue }
            let time = lines[fact.lineIndex].to
            candidates.append(moment(
                kind: .cadence,
                from: time,
                to: time,
                strength: min(1, Double(fact.silenceAfterMilliseconds) / 1_500 + 0.25),
                confidence: max(map.confidence.regions, map.confidence.pitch),
                lines: lines))
        }
        var byID: [String: AudioStructureMomentV4] = [:]
        for candidate in candidates {
            if let existing = byID[candidate.id], existing.strengthQ >= candidate.strengthQ { continue }
            byID[candidate.id] = candidate
        }
        let score = AudioStructureScoreV4(
            version: LyricStagePlanV4Version.audioScore,
            availability: .ready,
            semantics: .localAnalyzer,
            confidence: domainConfidence(map),
            durationMilliseconds: milliseconds(map.duration),
            tempoSegments: [],
            sections: [],
            lineFacts: facts,
            lineDetails: [],
            moments: Array(byID.values))
        return score.deterministicallyLimited(lineDetailCount: 0, momentCount: 32, includeContours: true).moments
    }

    private static func moment(
        kind: AudioStructureMomentKindV4,
        from: Double,
        to: Double,
        strength: Double,
        confidence: Double,
        lines: [PlayerEngine.LyricLine]
    ) -> AudioStructureMomentV4 {
        let fromMilliseconds = milliseconds(from)
        return AudioStructureMomentV4(
            id: "\(kind.rawValue)-\(fromMilliseconds)",
            kind: kind,
            fromMilliseconds: fromMilliseconds,
            toMilliseconds: milliseconds(max(from, to)),
            strengthQ: q8(strength),
            confidenceQ: q8(confidence),
            lineIndex: nearestLineIndex(lines: lines, at: from))
    }

    private static func domainConfidence(_ map: AudioPerformanceMapV2) -> AudioStructureDomainConfidenceV4 {
        AudioStructureDomainConfidenceV4(
            beat: q8(map.confidence.beat),
            downbeat: q8(map.confidence.downbeat),
            onset: q8(map.confidence.onset),
            energy: q8(map.confidence.energy),
            pitch: q8(map.confidence.pitch),
            sections: q8(map.confidence.regions),
            overall: q8(map.confidence.overall))
    }

    private static func samples(
        map: AudioPerformanceMapV2,
        kind: AudioPerformanceEnvelopeKind,
        from: Double,
        to: Double,
        count: Int
    ) -> [Double] {
        guard count > 0 else { return [] }
        return (0..<count).compactMap { position in
            map.envelope(kind, at: interpolatedTime(from: from, to: to, position: position, count: count))
        }
    }

    private static func confidentPitchSamples(
        map: AudioPerformanceMapV2,
        from: Double,
        to: Double,
        count: Int
    ) -> [Double?] {
        (0..<count).map { position in
            let time = interpolatedTime(from: from, to: to, position: position, count: count)
            guard (map.envelope(.pitchConfidence, at: time) ?? 0) >= 0.20 else { return nil }
            return map.envelope(.pitch, at: time)
        }
    }

    private static func interpolatedTime(from: Double, to: Double, position: Int, count: Int) -> Double {
        guard count > 1, to > from else { return from }
        return from + (to - from) * Double(position) / Double(count - 1)
    }

    private static func adjacentSilence(
        at time: Double,
        before: Bool,
        regions: [AudioPerformanceRegion]
    ) -> Double {
        regions.compactMap { region -> Double? in
            if before {
                guard region.to <= time + 0.08, time - region.to <= 0.30 else { return nil }
            } else {
                guard region.from >= time - 0.08, region.from - time <= 0.30 else { return nil }
            }
            return min(8, region.to - region.from)
        }.max() ?? 0
    }

    private static func nearestSignedMilliseconds(events: [Double], to time: Double, cap: Int) -> Int? {
        guard !events.isEmpty else { return nil }
        let nearest = events.min { abs($0 - time) < abs($1 - time) }
        guard let nearest else { return nil }
        return min(cap, max(-cap, Int(((nearest - time) * 1_000).rounded())))
    }

    private static func beatPhase(events: [Double], at time: Double) -> Double? {
        guard let previous = events.last(where: { $0 <= time }),
              let next = events.first(where: { $0 > time }),
              next > previous else { return nil }
        return min(1, max(0, (time - previous) / (next - previous)))
    }

    private static func beatSpanTenths(events: [Double], from: Double, to: Double) -> Int? {
        guard events.count >= 2 else { return nil }
        let intervals = zip(events, events.dropFirst()).map { $1 - $0 }.filter { $0 > 0 }
        guard !intervals.isEmpty else { return nil }
        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]
        return Int((max(0, to - from) / median * 10).rounded())
    }

    private static func nearestLineIndex(lines: [PlayerEngine.LyricLine], at time: Double) -> Int? {
        if let active = lines.indices.first(where: { time >= lines[$0].from && time <= lines[$0].to }) {
            return active
        }
        if let upcoming = lines.indices.first(where: { lines[$0].from >= time }) { return upcoming }
        return lines.indices.last
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func milliseconds(_ seconds: Double) -> Int {
        guard seconds.isFinite else { return 0 }
        return max(0, Int((seconds * 1_000).rounded()))
    }

    private static func q8(_ value: Double) -> UInt8 {
        UInt8(clamping: Int((min(1, max(0, value)) * 255).rounded()))
    }

    private static func signedQ(_ value: Double) -> Int {
        min(255, max(-255, Int((value * 255).rounded())))
    }
}

private extension UnkeyedDecodingContainer {
    mutating func decodeOptionalInt() throws -> Int? {
        try decodeNil() ? nil : decode(Int.self)
    }

    mutating func decodeOptionalUInt8() throws -> UInt8? {
        try decodeNil() ? nil : decode(UInt8.self)
    }
}

private extension UnkeyedEncodingContainer {
    mutating func encodeOptional<T: Encodable>(_ value: T?) throws {
        if let value { try encode(value) } else { try encodeNil() }
    }
}
