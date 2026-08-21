import Foundation

enum LyricStageDirectorV4 {
    static func localPlan(
        trackID: String,
        lines: [PlayerEngine.LyricLine],
        audioMap: AudioPerformanceMapV2?,
        audioScore: AudioStructureScoreV4
    ) -> LyricStagePlanV4 {
        resolve(
            trackID: trackID,
            lines: lines,
            audioMap: audioMap,
            audioScore: audioScore,
            direction: nil)
    }

    static func resolve(
        trackID: String,
        lines: [PlayerEngine.LyricLine],
        audioMap: AudioPerformanceMapV2?,
        audioScore: AudioStructureScoreV4,
        direction: LyricStageDirectionV4?
    ) -> LyricStagePlanV4 {
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(lines)
        let safeScore = audioScore.validated(lineCount: lines.count)
            ?? AudioStructureScoreBuilderV4.make(
                map: nil,
                lines: lines,
                availability: .analysisFailed)
        let summary = audioMap?.validated()?.summary(for: lines)
            ?? .empty(duration: max(lines.map(\.to).filter(\.isFinite).max() ?? 0, 0))
        let basePlan = LyricStageDirectorV3.localPlan(
            trackID: trackID,
            lines: lines,
            audioSummary: summary)
        let landmarks = resolvedLandmarks(score: safeScore, map: audioMap, lines: lines)
        let safeDirection = direction.flatMap {
            validated(
                $0,
                trackID: trackID,
                lyricsHash: lyricsHash,
                lines: lines,
                audioScore: safeScore)
        }
        return LyricStagePlanV4(
            version: LyricStagePlanV4Version.current,
            grammarVersion: LyricStagePlanV4Version.grammar,
            compilerVersion: LyricStagePlanV4Version.compiler,
            directorVersion: safeDirection?.directorVersion ?? "bilimusic-v54-local-fallback-1",
            trackID: trackID,
            lyricsHash: lyricsHash,
            audioScoreHash: safeScore.fingerprint,
            basePlan: basePlan,
            audioScore: safeScore,
            stageBible: safeDirection?.stageBible ?? localBible,
            recipes: safeDirection?.scenes ?? [],
            landmarkByID: landmarks,
            source: safeDirection == nil ? .local : .gemini,
            partial: safeDirection?.partial ?? false)
    }

    static func validated(
        _ direction: LyricStageDirectionV4,
        trackID: String,
        lyricsHash: String,
        lines: [PlayerEngine.LyricLine],
        audioScore: AudioStructureScoreV4
    ) -> LyricStageDirectionV4? {
        validateWire(
            LyricStageResponseWireV4(direction),
            trackID: trackID,
            lyricsHash: lyricsHash,
            lines: lines,
            audioScore: audioScore)
    }

    static func validateWire(
        _ wire: LyricStageResponseWireV4,
        trackID: String,
        lyricsHash: String,
        lines: [PlayerEngine.LyricLine],
        audioScore: AudioStructureScoreV4
    ) -> LyricStageDirectionV4? {
        guard wire.version == LyricStagePlanV4Version.current,
              wire.grammarVersion == LyricStagePlanV4Version.grammar,
              wire.degraded != true,
              wire.trackID == trackID,
              wire.lyricsHash == lyricsHash,
              wire.lineCount == lines.count,
              wire.audioScoreHash == audioScore.fingerprint,
              !lines.isEmpty,
              let directorVersion = clean(wire.directorVersion, limit: 120),
              let bible = canonicalBible(wire.stageBible),
              audioScore.validated(lineCount: lines.count) != nil else { return nil }

        let momentsByID = Dictionary(uniqueKeysWithValues: audioScore.moments.map { ($0.id, $0) })
        let factsByLine = Dictionary(uniqueKeysWithValues: audioScore.lineFacts.map { ($0.lineIndex, $0) })
        let repeatGroups = repeatedLineIndices(lines)
        var seenLines = Set<Int>()
        var recipes = wire.scenes.compactMap { raw -> LyricStageSceneRecipeV4? in
            guard let lineIndex = raw.lineIndex,
                  !seenLines.contains(lineIndex),
                  lines.indices.contains(lineIndex),
                  let familyRaw = raw.family,
                  let family = LyricStageSceneFamilyV4(rawValue: familyRaw) else { return nil }
            guard let recipe = canonicalRecipe(
                raw,
                lineIndex: lineIndex,
                family: family,
                lines: lines,
                momentsByID: momentsByID,
                factsByLine: factsByLine,
                repeatedIndices: repeatGroups[lineIndex] ?? []) else { return nil }
            seenLines.insert(lineIndex)
            return recipe
        }
        recipes = enforceGlobalBudgets(recipes, lineCount: lines.count)
        let minimumScenes = max(1, Int(ceil(Double(lines.count) * 0.10)))
        guard recipes.count >= minimumScenes else { return nil }
        return LyricStageDirectionV4(
            directorVersion: directorVersion,
            trackID: trackID,
            lyricsHash: lyricsHash,
            lineCount: lines.count,
            audioScoreHash: audioScore.fingerprint,
            stageBible: bible,
            scenes: recipes,
            partial: wire.partial ?? false,
            provider: wire.provider.flatMap { clean($0, limit: 80) },
            model: wire.model.flatMap { clean($0, limit: 120) })
    }

    private static let localBible = LyricStageBibleV4(
        concept: "结构清晰、时间诚实的全曲动态文字",
        intensityArc: "克制建立 → 有界发展 → 稀疏高潮 → 清晰收束",
        primaryMotif: LyricStageMotifV4(signature: .rail, axis: .horizontal, cadence: .phrase),
        secondaryMotif: nil)

    private static func canonicalBible(_ raw: LyricStageBibleWireV4?) -> LyricStageBibleV4? {
        guard let raw,
              let concept = clean(raw.concept, limit: 160),
              let intensityArc = clean(raw.intensityArc, limit: 200),
              let primary = canonicalMotif(raw.primaryMotif) else { return nil }
        return LyricStageBibleV4(
            concept: concept,
            intensityArc: intensityArc,
            primaryMotif: primary,
            secondaryMotif: canonicalMotif(raw.secondaryMotif))
    }

    private static func canonicalMotif(_ raw: LyricStageMotifWireV4?) -> LyricStageMotifV4? {
        guard let raw,
              let signatureRaw = raw.signature,
              let axisRaw = raw.axis,
              let cadenceRaw = raw.cadence,
              let signature = LyricStageMotifSignatureV4(rawValue: signatureRaw),
              let axis = LyricStageMotifAxisV4(rawValue: axisRaw),
              let cadence = LyricStageMotifCadenceV4(rawValue: cadenceRaw) else { return nil }
        return LyricStageMotifV4(signature: signature, axis: axis, cadence: cadence)
    }

    private static func canonicalRecipe(
        _ raw: LyricStageSceneRecipeWireV4,
        lineIndex: Int,
        family: LyricStageSceneFamilyV4,
        lines: [PlayerEngine.LyricLine],
        momentsByID: [String: AudioStructureMomentV4],
        factsByLine: [Int: AudioStructureLineFactV4],
        repeatedIndices: [Int]
    ) -> LyricStageSceneRecipeV4? {
        let line = lines[lineIndex]
        let tokens = LyricStageTokenizer.tokens(for: line)
        let tokenCount = tokens.count
        let requestedRange = raw.tokenRange.flatMap { range -> LyricStageTokenRangeV4? in
            guard range.startTokenIndex >= 0,
                  range.endTokenIndex >= range.startTokenIndex,
                  range.endTokenIndex - range.startTokenIndex < 12,
                  range.endTokenIndex < tokenCount else { return nil }
            return LyricStageTokenRangeV4(
                startTokenIndex: range.startTokenIndex,
                endTokenIndex: range.endTokenIndex)
        }
        let validLandmarks = (raw.landmarkIDs ?? [])
            .compactMap { clean($0, limit: 48) }
            .filter { id in
                guard let moment = momentsByID[id] else { return false }
                if moment.lineIndex == lineIndex { return true }
                guard let momentLine = moment.lineIndex else { return false }
                return factsByLine[momentLine]?.sectionIndex != nil
                    && factsByLine[momentLine]?.sectionIndex == factsByLine[lineIndex]?.sectionIndex
            }
            .reduce(into: [String]()) { result, value in
                if result.count < 3, !result.contains(value) { result.append(value) }
            }
        let companions = sanitizedCompanions(
            raw.companionLineIndices ?? [],
            lineIndex: lineIndex,
            lines: lines)
        let motifPhase = raw.motifPhase.flatMap(LyricStageMotifPhaseV4.init(rawValue:)) ?? .develop
        let intensity = min(1, max(0.25, raw.intensity?.isFinite == true ? raw.intensity! : 0.6))

        switch family {
        case .railHandoff:
            return LyricStageSceneRecipeV4(
                lineIndex: lineIndex,
                family: family,
                topology: allowed(raw.topology, [.relay, .anchor], fallback: .relay),
                entrance: allowed(raw.entrance, [.slide, .gather, .settle], fallback: .slide),
                focus: .wholeLine,
                tokenRange: nil,
                sustain: allowed(raw.sustain, [.railTravel, .trackingBreath, .none], fallback: .railTravel),
                continuity: allowed(raw.continuity, [.handoff, .residue], fallback: .handoff),
                driver: repairedStructuralDriver(
                    raw.driver,
                    allowed: [.lyricReveal, .sectionEdge, .structuralMoment],
                    landmarks: validLandmarks),
                landmarkIDs: validLandmarks,
                companionLineIndices: Array(companions.prefix(1)),
                motifPhase: motifPhase,
                intensity: intensity)

        case .semanticLens:
            guard raw.focus == LyricStageFocusV4.tokenRange.rawValue,
                  let requestedRange else { return nil }
            let focusedTokens = tokens.filter {
                ($0.id >= requestedRange.startTokenIndex && $0.id <= requestedRange.endTokenIndex)
                    && $0.kind != .whitespace
            }
            let focusedRangeHasRealTiming = !focusedTokens.isEmpty
                && focusedTokens.allSatisfy { $0.realTiming != nil }
            let driver: LyricStageDriverV4 = focusedRangeHasRealTiming
                ? allowed(raw.driver, [.wordReveal, .lyricReveal], fallback: .lyricReveal)
                : .lyricReveal
            return LyricStageSceneRecipeV4(
                lineIndex: lineIndex,
                family: family,
                topology: allowed(raw.topology, [.anchor, .lockup], fallback: .anchor),
                entrance: allowed(raw.entrance, [.settle, .gather], fallback: .settle),
                focus: .tokenRange,
                tokenRange: requestedRange,
                sustain: allowed(raw.sustain, [.weightBloom, .sweep, .trackingBreath], fallback: .weightBloom),
                continuity: allowed(raw.continuity, [.clear, .residue], fallback: .clear),
                driver: driver,
                landmarkIDs: validLandmarks,
                companionLineIndices: [],
                motifPhase: motifPhase,
                intensity: intensity)

        case .chorusMemory:
            guard repeatedIndices.count >= 2 else { return nil }
            let repeatedCompanions = companions.filter { repeatedIndices.contains($0) }
            let fallbackCompanion = repeatedIndices.first { $0 != lineIndex }
            return LyricStageSceneRecipeV4(
                lineIndex: lineIndex,
                family: family,
                topology: allowed(raw.topology, [.stack, .relay, .lockup], fallback: .stack),
                entrance: allowed(raw.entrance, [.gather, .interleave, .settle], fallback: .gather),
                focus: .wholeLine,
                tokenRange: nil,
                sustain: .echo,
                continuity: allowed(raw.continuity, [.residue, .accumulate], fallback: .residue),
                driver: repairedStructuralDriver(
                    raw.driver,
                    allowed: [.lyricReveal, .structuralMoment, .sectionEdge],
                    landmarks: validLandmarks),
                landmarkIDs: validLandmarks,
                companionLineIndices: Array((repeatedCompanions.isEmpty ? fallbackCompanion.map { [$0] } ?? [] : repeatedCompanions).prefix(2)),
                motifPhase: motifPhase,
                intensity: intensity)

        case .silenceAperture:
            let structuralLandmarks = validLandmarks.filter {
                guard let moment = momentsByID[$0] else { return false }
                return moment.lineIndex == lineIndex
                    && (moment.kind == .sectionStart || moment.kind == .silenceExit)
            }
            guard !structuralLandmarks.isEmpty else { return nil }
            return LyricStageSceneRecipeV4(
                lineIndex: lineIndex,
                family: family,
                topology: allowed(raw.topology, [.anchor, .split], fallback: .anchor),
                entrance: .aperture,
                focus: .wholeLine,
                tokenRange: nil,
                sustain: allowed(raw.sustain, [.none, .weightBloom], fallback: .none),
                continuity: .clear,
                driver: allowed(raw.driver, [.structuralMoment, .sectionEdge], fallback: .structuralMoment),
                landmarkIDs: structuralLandmarks,
                companionLineIndices: [],
                motifPhase: motifPhase,
                intensity: intensity)
        }
    }

    private static func enforceGlobalBudgets(
        _ input: [LyricStageSceneRecipeV4],
        lineCount: Int
    ) -> [LyricStageSceneRecipeV4] {
        let maximumScenes = max(1, Int(floor(Double(lineCount) * 0.45)))
        let sorted = input.sorted { $0.lineIndex < $1.lineIndex }
        var accepted: [LyricStageSceneRecipeV4] = []
        var highMotionRun = 0
        var totalHighMotion = 0
        let maximumHighMotion = max(1, Int(floor(Double(lineCount) * 0.30)))
        var previousLine = -2
        for recipe in sorted {
            let consecutive = recipe.lineIndex == previousLine + 1
            let highMotion = isHighMotion(recipe)
            highMotionRun = consecutive && highMotion ? highMotionRun + 1 : (highMotion ? 1 : 0)
            previousLine = recipe.lineIndex
            if highMotion && (highMotionRun > 2 || totalHighMotion >= maximumHighMotion) {
                accepted.append(stableRepair(recipe))
                highMotionRun = 0
            } else {
                accepted.append(recipe)
                if highMotion { totalHighMotion += 1 }
            }
            if accepted.count >= maximumScenes { break }
        }
        return accepted
    }

    private static func isHighMotion(_ recipe: LyricStageSceneRecipeV4) -> Bool {
        recipe.family == .chorusMemory
            || recipe.family == .silenceAperture
            || recipe.entrance == .gather
            || recipe.entrance == .interleave
            || recipe.entrance == .aperture
    }

    private static func stableRepair(_ recipe: LyricStageSceneRecipeV4) -> LyricStageSceneRecipeV4 {
        LyricStageSceneRecipeV4(
            lineIndex: recipe.lineIndex,
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
            motifPhase: recipe.motifPhase,
            intensity: min(0.58, recipe.intensity))
    }

    private static func sanitizedCompanions(
        _ values: [Int],
        lineIndex: Int,
        lines: [PlayerEngine.LyricLine]
    ) -> [Int] {
        var result: [Int] = []
        for candidate in values where candidate != lineIndex && lines.indices.contains(candidate) {
            let sameOverlap = lines[lineIndex].overlapGroup != nil
                && lines[lineIndex].overlapGroup == lines[candidate].overlapGroup
            guard sameOverlap || abs(candidate - lineIndex) <= 2 else { continue }
            if !result.contains(candidate) { result.append(candidate) }
            if result.count == 2 { break }
        }
        return result
    }

    private static func repeatedLineIndices(_ lines: [PlayerEngine.LyricLine]) -> [Int: [Int]] {
        let grouped = Dictionary(grouping: lines.indices, by: { normalized(lines[$0].text) })
        var result: [Int: [Int]] = [:]
        for (key, indices) in grouped where key.count >= 2 && indices.count >= 2 {
            for index in indices { result[index] = indices }
        }
        return result
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().unicodeScalars
            .filter { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func allowed<T: RawRepresentable & Equatable>(
        _ raw: String?,
        _ allowedValues: [T],
        fallback: T
    ) -> T where T.RawValue == String {
        guard let raw, let value = T(rawValue: raw), allowedValues.contains(value) else { return fallback }
        return value
    }

    private static func repairedStructuralDriver(
        _ raw: String?,
        allowed allowedValues: [LyricStageDriverV4],
        landmarks: [String]
    ) -> LyricStageDriverV4 {
        let driver: LyricStageDriverV4 = allowed(raw, allowedValues, fallback: .lyricReveal)
        return driver == .structuralMoment && landmarks.isEmpty ? .lyricReveal : driver
    }

    private static func resolvedLandmarks(
        score: AudioStructureScoreV4,
        map: AudioPerformanceMapV2?,
        lines: [PlayerEngine.LyricLine]
    ) -> [String: LyricStageResolvedLandmarkV4] {
        Dictionary(uniqueKeysWithValues: score.moments.map { moment in
            let quantizedFrom = Double(moment.fromMilliseconds) / 1_000
            let quantizedTo = Double(moment.toMilliseconds) / 1_000
            let exact: (Double, Double) = guardResolvedTime(moment, map: map, lines: lines)
                ?? (quantizedFrom, quantizedTo)
            return (
                moment.id,
                LyricStageResolvedLandmarkV4(
                    id: moment.id,
                    kind: moment.kind,
                    from: exact.0,
                    to: max(exact.0, exact.1),
                    strength: Double(moment.strengthQ) / 255,
                    confidence: Double(moment.confidenceQ) / 255))
        })
    }

    private static func guardResolvedTime(
        _ moment: AudioStructureMomentV4,
        map: AudioPerformanceMapV2?,
        lines: [PlayerEngine.LyricLine]
    ) -> (Double, Double)? {
        let target = Double(moment.fromMilliseconds) / 1_000
        switch moment.kind {
        case .sectionStart:
            guard let region = map?.regions.filter({ $0.kind == .acousticSection })
                .min(by: { abs($0.from - target) < abs($1.from - target) }) else { return nil }
            return (region.from, min(region.to, region.from + 0.7))
        case .silenceExit:
            guard let region = map?.regions.filter({ $0.kind == .silence })
                .min(by: { abs($0.to - target) < abs($1.to - target) }) else { return nil }
            return (region.to, region.to)
        case .strongDownbeat:
            guard let time = map?.downbeats.min(by: { abs($0 - target) < abs($1 - target) }) else { return nil }
            return (time, time)
        case .energyPeak:
            guard let map else { return nil }
            let candidates = (-10...10).map { target + Double($0) * 0.025 }
                .filter { $0 >= 0 && $0 <= map.duration }
            guard let time = candidates.max(by: {
                (map.envelope(.energy, at: $0) ?? 0) < (map.envelope(.energy, at: $1) ?? 0)
            }) else { return nil }
            return (time, time)
        case .cadence:
            guard let lineIndex = moment.lineIndex, lines.indices.contains(lineIndex) else { return nil }
            return (lines[lineIndex].to, lines[lineIndex].to)
        }
    }

    private static func clean(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(limit))
    }
}

struct LyricStageResponseWireV4: Decodable {
    let version: String?
    let grammarVersion: String?
    let directorVersion: String?
    let trackID: String?
    let lyricsHash: String?
    let lineCount: Int?
    let audioScoreHash: String?
    let stageBible: LyricStageBibleWireV4?
    let scenes: [LyricStageSceneRecipeWireV4]
    let degraded: Bool?
    let degradedReason: String?
    let partial: Bool?
    let provider: String?
    let model: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try? container.decode(String.self, forKey: .version)
        grammarVersion = try? container.decode(String.self, forKey: .grammarVersion)
        directorVersion = try? container.decode(String.self, forKey: .directorVersion)
        trackID = try? container.decode(String.self, forKey: .trackID)
        lyricsHash = try? container.decode(String.self, forKey: .lyricsHash)
        lineCount = try? container.decode(Int.self, forKey: .lineCount)
        audioScoreHash = try? container.decode(String.self, forKey: .audioScoreHash)
        stageBible = try? container.decode(LyricStageBibleWireV4.self, forKey: .stageBible)
        scenes = (try? container.decode(LossySceneArrayV4.self, forKey: .scenes).values) ?? []
        degraded = try? container.decode(Bool.self, forKey: .degraded)
        degradedReason = try? container.decode(String.self, forKey: .degradedReason)
        partial = try? container.decode(Bool.self, forKey: .partial)
        provider = try? container.decode(String.self, forKey: .provider)
        model = try? container.decode(String.self, forKey: .model)
    }

    init(_ direction: LyricStageDirectionV4) {
        version = direction.version
        grammarVersion = direction.grammarVersion
        directorVersion = direction.directorVersion
        trackID = direction.trackID
        lyricsHash = direction.lyricsHash
        lineCount = direction.lineCount
        audioScoreHash = direction.audioScoreHash
        stageBible = LyricStageBibleWireV4(direction.stageBible)
        scenes = direction.scenes.map(LyricStageSceneRecipeWireV4.init)
        degraded = false
        degradedReason = nil
        partial = direction.partial
        provider = direction.provider
        model = direction.model
    }

    private enum CodingKeys: String, CodingKey {
        case version, grammarVersion, directorVersion, trackID, lyricsHash, lineCount, audioScoreHash
        case stageBible, scenes, degraded, degradedReason, partial, provider, model
    }
}

struct LyricStageBibleWireV4: Codable {
    let concept: String?
    let intensityArc: String?
    let primaryMotif: LyricStageMotifWireV4?
    let secondaryMotif: LyricStageMotifWireV4?

    init(_ bible: LyricStageBibleV4) {
        concept = bible.concept
        intensityArc = bible.intensityArc
        primaryMotif = LyricStageMotifWireV4(bible.primaryMotif)
        secondaryMotif = bible.secondaryMotif.map(LyricStageMotifWireV4.init)
    }
}

struct LyricStageMotifWireV4: Codable {
    let signature: String?
    let axis: String?
    let cadence: String?

    init(_ motif: LyricStageMotifV4) {
        signature = motif.signature.rawValue
        axis = motif.axis.rawValue
        cadence = motif.cadence.rawValue
    }
}

struct LyricStageTokenRangeWireV4: Codable {
    let startTokenIndex: Int
    let endTokenIndex: Int

    init(_ range: LyricStageTokenRangeV4) {
        startTokenIndex = range.startTokenIndex
        endTokenIndex = range.endTokenIndex
    }
}

struct LyricStageSceneRecipeWireV4: Decodable {
    let lineIndex: Int?
    let family: String?
    let topology: String?
    let entrance: String?
    let focus: String?
    let tokenRange: LyricStageTokenRangeWireV4?
    let sustain: String?
    let continuity: String?
    let driver: String?
    let landmarkIDs: [String]?
    let companionLineIndices: [Int]?
    let motifPhase: String?
    let intensity: Double?

    init(_ recipe: LyricStageSceneRecipeV4) {
        lineIndex = recipe.lineIndex
        family = recipe.family.rawValue
        topology = recipe.topology.rawValue
        entrance = recipe.entrance.rawValue
        focus = recipe.focus.rawValue
        tokenRange = recipe.tokenRange.map(LyricStageTokenRangeWireV4.init)
        sustain = recipe.sustain.rawValue
        continuity = recipe.continuity.rawValue
        driver = recipe.driver.rawValue
        landmarkIDs = recipe.landmarkIDs
        companionLineIndices = recipe.companionLineIndices
        motifPhase = recipe.motifPhase.rawValue
        intensity = recipe.intensity
    }
}

private struct LossySceneArrayV4: Decodable {
    let values: [LyricStageSceneRecipeWireV4]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [LyricStageSceneRecipeWireV4] = []
        while !container.isAtEnd {
            let previousIndex = container.currentIndex
            do {
                values.append(try container.decode(LyricStageSceneRecipeWireV4.self))
            } catch {
                _ = try? container.decode(DiscardedJSONValueV4.self)
                if container.currentIndex == previousIndex { break }
            }
        }
        self.values = values
    }
}

private struct DiscardedJSONValueV4: Decodable {
    init(from decoder: Decoder) throws {
        if var values = try? decoder.unkeyedContainer() {
            while !values.isAtEnd { _ = try values.decode(DiscardedJSONValueV4.self) }
            return
        }
        if let values = try? decoder.container(keyedBy: AnyJSONCodingKeyV4.self) {
            for key in values.allKeys { _ = try values.decode(DiscardedJSONValueV4.self, forKey: key) }
            return
        }
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { return }
        if (try? value.decode(Bool.self)) != nil { return }
        if (try? value.decode(Double.self)) != nil { return }
        if (try? value.decode(String.self)) != nil { return }
        throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unsupported JSON value")
    }
}

private struct AnyJSONCodingKeyV4: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
