import Foundation

enum LyricStageDirectorV3 {
    static func localPlan(
        trackID: String,
        lines: [PlayerEngine.LyricLine],
        audioSummary: LyricStageAudioSummaryV3
    ) -> LyricStagePlanV3 {
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(lines)
        guard !lines.isEmpty else {
            return LyricStagePlanV3(
                version: LyricStagePlanV3Version.current,
                compilerVersion: LyricStagePlanV3Version.compiler,
                directorVersion: "bilimusic-v53-local-1",
                trackID: trackID,
                lyricsHash: lyricsHash,
                audioSummaryHash: audioSummary.summaryHash,
                stageBible: localBible,
                sections: [],
                scenes: [],
                source: .local,
                partial: false)
        }

        let keys = lines.map { normalizedRepeatKey($0.text) }
        let repeatedBlocks = repeatedBlockMarks(keys: keys)
        let audioByLine = Dictionary(uniqueKeysWithValues: audioSummary.lines.map { ($0.lineIndex, $0) })
        let hasReliableAudio = audioSummary.confidence.overall >= 0.20 && !audioSummary.lines.isEmpty
        var occurrences: [String: [Int]] = [:]
        for (index, key) in keys.enumerated() where key.count >= 2 {
            occurrences[key, default: []].append(index)
        }

        var sectionIndex = 0
        var localIndex = 0
        var scenes: [LyricStageV53Scene] = []
        for index in lines.indices {
            let previous = index > 0 ? lines[index - 1] : nil
            let gap = previous.map { lines[index].from - $0.to } ?? .infinity
            let repeated = (occurrences[keys[index]]?.count ?? 0) >= 2
            let previousRepeated = index > 0 && (occurrences[keys[index - 1]]?.count ?? 0) >= 2
            let entersHook = repeated && (index == 0 || keys[index - 1] != keys[index])
            let leavesHook = !repeated && previousRepeated
            let blockMark = repeatedBlocks[index]
            let entersRepeatedBlock = blockMark?.offset == 0
            let audioLine = audioByLine[index]
            let audioSectionChanged = hasReliableAudio
                && index > 0
                && audioLine?.sectionIndex != audioByLine[index - 1]?.sectionIndex
            let sectionStart = index == 0
                || gap > 1.35
                || entersHook
                || leavesHook
                || entersRepeatedBlock
                || audioSectionChanged
            if index > 0, sectionStart {
                sectionIndex += 1
                localIndex = 0
            }

            let globalRepeatedIndices = occurrences[keys[index]] ?? []
            let localRepeatedIndices = contiguousRepeatCluster(
                containing: index,
                key: keys[index],
                keys: keys,
                lines: lines)
            let repeatedIndices = localRepeatedIndices.count >= 2
                ? localRepeatedIndices
                : globalRepeatedIndices
            let repetitionIndex = repeatedIndices.firstIndex(of: index)
            let composition: LyricStageV53Composition
            if let repetitionIndex, repeatedIndices.count >= 2 {
                composition = expectedHookComposition(occurrence: repetitionIndex, count: repeatedIndices.count)
            } else if let blockMark {
                composition = blockComposition(mark: blockMark)
            } else if lines[index].overlapGroup != nil {
                composition = .dialogue
            } else {
                let glyphCount = lines[index].text.filter { !$0.isWhitespace }.count
                if glyphCount <= 4 {
                    composition = .hero
                } else if hasReliableAudio,
                          let audioLine,
                          audioLine.silenceBefore >= 0.45 {
                    composition = .stillness
                } else if hasReliableAudio,
                          let audioLine,
                          glyphCount <= 12,
                          audioLine.peakEnergy >= 0.82,
                          audioLine.onsetCount >= 2 {
                    composition = .hero
                } else if sectionStart {
                    composition = sectionIndex.isMultiple(of: 2) ? .stack : .stillness
                } else if hasReliableAudio,
                          let audioLine,
                          (audioLine.pitchTrend ?? 0) > 12,
                          (audioLine.pitchConfidence ?? 0) >= 0.35 {
                    composition = .arc
                } else if hasReliableAudio,
                          let audioLine,
                          audioLine.energyDelta >= 0.18 {
                    composition = .leadingAnchor
                } else if hasReliableAudio,
                          let audioLine,
                          audioLine.energyDelta <= -0.18 {
                    composition = .trailingAnchor
                } else {
                    let grammar: [LyricStageV53Composition] = [
                        .leadingAnchor, .dialogue, .trailingAnchor, .arc, .stillness,
                    ]
                    composition = grammar[(localIndex + sectionIndex) % grammar.count]
                }
            }

            scenes.append(
                LyricStageV53Scene(
                    lineIndex: index,
                    sectionIndex: sectionIndex,
                    composition: composition,
                    companionLineIndices: companionIndices(
                        for: index,
                        composition: composition,
                        lines: lines),
                    repetitionIndex: repetitionIndex,
                    repetitionCount: repeatedIndices.count,
                    isSectionStart: sectionStart,
                    intensity: localIntensity(composition: composition, audio: audioLine)
                        + min(0.12, Double(blockMark?.occurrence ?? 0) * 0.04),
                    motifRef: blockMark.map { "chorus-block-\($0.groupID)" }
                        ?? (composition.isHook ? "repeat-evolution" : nil)))
            localIndex += 1
        }

        let budgetedScenes = applyGlobalBudgets(
            scenes,
            lines: lines,
            audioSummary: audioSummary)
        return LyricStagePlanV3(
            version: LyricStagePlanV3Version.current,
            compilerVersion: LyricStagePlanV3Version.compiler,
            directorVersion: "bilimusic-v53-local-1",
            trackID: trackID,
            lyricsHash: lyricsHash,
            audioSummaryHash: audioSummary.summaryHash,
            stageBible: localBible,
            sections: sections(for: budgetedScenes, audioSummary: audioSummary),
            scenes: budgetedScenes,
            source: .local,
            partial: false)
    }

    static func resolve(
        trackID: String,
        lines: [PlayerEngine.LyricLine],
        audioSummary: LyricStageAudioSummaryV3,
        direction: LyricStageDirectionV3?
    ) -> LyricStagePlanV3 {
        let local = localPlan(trackID: trackID, lines: lines, audioSummary: audioSummary)
        guard let direction,
              direction.trackID == trackID,
              direction.lyricsHash == local.lyricsHash,
              direction.audioSummaryHash == audioSummary.summaryHash,
              direction.lineCount <= lines.count else { return local }

        let directedLines = Array(lines.prefix(direction.lineCount))
        guard let safe = direction.validated(
            trackID: trackID,
            lyricsHash: local.lyricsHash,
            lines: directedLines,
            audioSummaryHash: audioSummary.summaryHash) else { return local }

        let overrides = Dictionary(uniqueKeysWithValues: safe.scenes.map { ($0.lineIndex, $0) })
        let resolvedScenes = local.scenes.map { scene -> LyricStageV53Scene in
            guard let override = overrides[scene.lineIndex] else { return scene }
            return LyricStageV53Scene(
                lineIndex: scene.lineIndex,
                sectionIndex: scene.sectionIndex,
                composition: override.composition,
                companionLineIndices: override.companionLineIndices,
                repetitionIndex: scene.repetitionIndex,
                repetitionCount: scene.repetitionCount,
                isSectionStart: scene.isSectionStart,
                intensity: override.intensity,
                motifRef: override.motifRef)
        }
        let budgetedScenes = applyGlobalBudgets(
            resolvedScenes,
            lines: lines,
            audioSummary: audioSummary)
        let resolvedSections = safe.lineCount == lines.count ? safe.sections : local.sections
        let remappedScenes = budgetedScenes.map { scene -> LyricStageV53Scene in
            guard let sectionIndex = resolvedSections.firstIndex(where: { $0.lineRange.contains(scene.lineIndex) }) else {
                return scene
            }
            return LyricStageV53Scene(
                lineIndex: scene.lineIndex,
                sectionIndex: sectionIndex,
                composition: scene.composition,
                companionLineIndices: scene.companionLineIndices,
                repetitionIndex: scene.repetitionIndex,
                repetitionCount: scene.repetitionCount,
                isSectionStart: resolvedSections[sectionIndex].lineFrom == scene.lineIndex,
                intensity: scene.intensity,
                motifRef: scene.motifRef)
        }
        return LyricStagePlanV3(
            version: LyricStagePlanV3Version.current,
            compilerVersion: LyricStagePlanV3Version.compiler,
            directorVersion: safe.directorVersion,
            trackID: trackID,
            lyricsHash: local.lyricsHash,
            audioSummaryHash: audioSummary.summaryHash,
            stageBible: safe.stageBible,
            sections: resolvedSections,
            scenes: remappedScenes,
            source: .luna,
            partial: safe.partial)
    }

    private static let localBible = LyricStageBibleV3(
        concept: "结构驱动的通用全曲舞台",
        motif: "呼应、接近与收束",
        intensityArc: "安静建立 → 逐步发展 → 少量高潮 → 明确收束")

    private static func sections(
        for scenes: [LyricStageV53Scene],
        audioSummary: LyricStageAudioSummaryV3
    ) -> [LyricStageSectionV3] {
        guard !scenes.isEmpty else { return [] }
        let groups = Dictionary(grouping: scenes, by: \.sectionIndex)
        let ordered = groups.keys.sorted()
        return ordered.enumerated().compactMap { order, key in
            guard let group = groups[key]?.sorted(by: { $0.lineIndex < $1.lineIndex }),
                  let first = group.first,
                  let last = group.last else { return nil }
            let containsHook = group.contains {
                $0.composition.isHook || $0.motifRef?.hasPrefix("chorus-block-") == true
            }
            let kind: StageSectionKind
            if order == 0 {
                kind = .intro
            } else if order == ordered.count - 1 {
                kind = .outro
            } else {
                kind = containsHook ? .chorus : .verse
            }
            let phase: LyricStageMotifPhaseV3
            let progress = Double(order) / Double(max(1, ordered.count - 1))
            if progress < 0.25 { phase = .introduce }
            else if progress < 0.55 { phase = .develop }
            else if progress < 0.82 { phase = .transform }
            else { phase = .resolve }
            let audioSection = audioSummary.sections.first { summary in
                guard let from = summary.lineFrom, let to = summary.lineTo else { return false }
                return from <= first.lineIndex && to >= last.lineIndex
            }
            let peak = max(
                group.map(\.intensity).max() ?? 0.4,
                audioSection?.meanEnergy ?? 0)
            return LyricStageSectionV3(
                id: "local-section-\(key)",
                lineFrom: first.lineIndex,
                lineTo: last.lineIndex,
                kind: kind,
                intensity: peak,
                motifPhase: phase)
        }
    }

    static func expectedHookComposition(occurrence: Int, count: Int) -> LyricStageV53Composition {
        if occurrence == 0 { return .hookCall }
        if occurrence == count - 1 { return .hookLock }
        if occurrence == 1 { return .hookEcho }
        return .hookConverge
    }

    private struct RepeatedBlockMark: Equatable {
        let groupID: Int
        let occurrence: Int
        let occurrenceCount: Int
        let offset: Int
        let length: Int
    }

    /// Detects recurring 2–8 line phrases without track metadata. Longest blocks
    /// win, and a normalized-character similarity gate tolerates punctuation or
    /// tiny wording differences while rejecting unrelated repeated short lines.
    private static func repeatedBlockMarks(keys: [String]) -> [Int: RepeatedBlockMark] {
        guard keys.count >= 4 else { return [:] }
        var marks: [Int: RepeatedBlockMark] = [:]
        var groupID = 0
        for length in stride(from: min(8, keys.count / 2), through: 2, by: -1) {
            var start = 0
            while start + length <= keys.count {
                let source = Array(keys[start..<(start + length)])
                guard source.allSatisfy({ $0.count >= 2 }),
                      !source.indices.contains(where: { marks[start + $0] != nil }) else {
                    start += 1
                    continue
                }
                var occurrences = [start]
                var candidate = start + length
                while candidate + length <= keys.count {
                    let target = Array(keys[candidate..<(candidate + length)])
                    if blocksAreSimilar(source, target),
                       !(0..<length).contains(where: { marks[candidate + $0] != nil }) {
                        occurrences.append(candidate)
                        candidate += length
                    } else {
                        candidate += 1
                    }
                }
                guard occurrences.count >= 2 else {
                    start += 1
                    continue
                }
                for (occurrence, base) in occurrences.enumerated() {
                    for offset in 0..<length {
                        marks[base + offset] = RepeatedBlockMark(
                            groupID: groupID,
                            occurrence: occurrence,
                            occurrenceCount: occurrences.count,
                            offset: offset,
                            length: length)
                    }
                }
                groupID += 1
                start += length
            }
        }
        return marks
    }

    private static func blocksAreSimilar(_ lhs: [String], _ rhs: [String]) -> Bool {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return false }
        let matching = zip(lhs, rhs).reduce(into: 0) { count, pair in
            if pair.0 == pair.1 || normalizedSimilarity(pair.0, pair.1) >= 0.84 {
                count += 1
            }
        }
        return matching >= Int(ceil(Double(lhs.count) * 0.80))
    }

    private static func normalizedSimilarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 1 }
        let left = characterBigrams(lhs)
        let right = characterBigrams(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(left.union(right).count)
    }

    private static func characterBigrams(_ value: String) -> Set<String> {
        let characters = Array(value)
        guard characters.count >= 2 else { return [] }
        return Set(zip(characters, characters.dropFirst()).map { pair in
            String(pair.0) + String(pair.1)
        })
    }

    private static func blockComposition(mark: RepeatedBlockMark) -> LyricStageV53Composition {
        let firstPass: [LyricStageV53Composition] = [
            .stillness, .leadingAnchor, .dialogue, .stack, .trailingAnchor, .arc,
        ]
        let transformed: [LyricStageV53Composition] = [
            .leadingAnchor, .arc, .stack, .trailingAnchor, .dialogue, .arc,
        ]
        let grammar = mark.occurrence == 0 ? firstPass : transformed
        if mark.occurrence == mark.occurrenceCount - 1, mark.offset == mark.length - 1 {
            return .hero
        }
        return grammar[mark.offset % grammar.count]
    }

    private static func applyGlobalBudgets(
        _ input: [LyricStageV53Scene],
        lines: [PlayerEngine.LyricLine],
        audioSummary: LyricStageAudioSummaryV3
    ) -> [LyricStageV53Scene] {
        guard !input.isEmpty else { return [] }
        let audioByLine = Dictionary(uniqueKeysWithValues: audioSummary.lines.map { ($0.lineIndex, $0) })
        var scenes = input.map { replacing($0, intensity: $0.intensity.clamped(to: 0...1)) }

        // Dense hero/arc and multi-line geometries become unreadable long before
        // the anchor renderer does. Downgrade them to the wrapping anchor path;
        // never shorten or otherwise rewrite the lyric text.
        for index in scenes.indices {
            let scene = scenes[index]
            let ownGlyphCount = glyphCount(for: scene.lineIndex, in: lines)
            let companionGlyphCounts = scene.companionLineIndices.map { glyphCount(for: $0, in: lines) }
            let exceedsCompositionBudget: Bool = switch scene.composition {
            case .hero:
                ownGlyphCount > 12
            case .arc, .hookCall, .hookEcho, .hookConverge, .hookLock:
                ownGlyphCount > 22
            case .dialogue, .stack:
                ownGlyphCount > 20 || companionGlyphCounts.contains(where: { $0 > 20 })
            case .stillness, .leadingAnchor, .trailingAnchor:
                false
            }
            guard exceedsCompositionBudget else { continue }
            let replacement: LyricStageV53Composition = scene.lineIndex.isMultiple(of: 2)
                ? .leadingAnchor
                : .stillness
            scenes[index] = replacing(
                scene,
                composition: replacement,
                companionLineIndices: [])
        }

        let heroLimit = max(1, Int(ceil(Double(scenes.count) * 0.12)))
        let heroIndices = scenes.indices
            .filter { scenes[$0].composition == .hero || scenes[$0].composition == .hookLock }
            .sorted { lhs, rhs in
                heroPriority(scenes[lhs], audio: audioByLine[scenes[lhs].lineIndex])
                    < heroPriority(scenes[rhs], audio: audioByLine[scenes[rhs].lineIndex])
            }
        if heroIndices.count > heroLimit {
            for index in heroIndices.prefix(heroIndices.count - heroLimit) {
                let scene = scenes[index]
                let replacement: LyricStageV53Composition = scene.composition == .hookLock
                    ? .hookConverge
                    : (scene.lineIndex.isMultiple(of: 2) ? .leadingAnchor : .stillness)
                scenes[index] = replacing(scene, composition: replacement)
            }
        }

        var previous: LyricStageV53Composition?
        var runLength = 0
        for index in scenes.indices {
            let scene = scenes[index]
            if scene.composition == previous {
                runLength += 1
            } else {
                previous = scene.composition
                runLength = 1
            }
            let realDuet = lines.indices.contains(scene.lineIndex)
                && lines[scene.lineIndex].overlapGroup != nil
            guard runLength >= 3, !scene.composition.isHook, !realDuet else { continue }
            let alternatives: [LyricStageV53Composition] = [.leadingAnchor, .trailingAnchor, .stillness, .arc]
            let replacement = alternatives[(scene.lineIndex + scene.sectionIndex) % alternatives.count]
            scenes[index] = replacing(scene, composition: replacement)
            previous = replacement
            runLength = 1
        }
        return scenes
    }

    private static func heroPriority(
        _ scene: LyricStageV53Scene,
        audio: LyricStageAudioLineSummaryV3?
    ) -> Double {
        let hookPriority = scene.composition == .hookLock ? 2.0 : 0
        let motifPriority = scene.motifRef?.hasPrefix("chorus-block-") == true ? 0.4 : 0
        return hookPriority + motifPriority + (audio?.peakEnergy ?? 0) + scene.intensity * 0.25
    }

    private static func replacing(
        _ scene: LyricStageV53Scene,
        composition: LyricStageV53Composition? = nil,
        companionLineIndices: [Int]? = nil,
        intensity: Double? = nil
    ) -> LyricStageV53Scene {
        LyricStageV53Scene(
            lineIndex: scene.lineIndex,
            sectionIndex: scene.sectionIndex,
            composition: composition ?? scene.composition,
            companionLineIndices: companionLineIndices ?? scene.companionLineIndices,
            repetitionIndex: scene.repetitionIndex,
            repetitionCount: scene.repetitionCount,
            isSectionStart: scene.isSectionStart,
            intensity: intensity ?? scene.intensity,
            motifRef: scene.motifRef)
    }

    private static func glyphCount(
        for lineIndex: Int,
        in lines: [PlayerEngine.LyricLine]
    ) -> Int {
        guard lines.indices.contains(lineIndex) else { return 0 }
        return lines[lineIndex].text.reduce(into: 0) { count, character in
            if !character.isWhitespace { count += 1 }
        }
    }

    private static func localIntensity(
        composition: LyricStageV53Composition,
        audio: LyricStageAudioLineSummaryV3?
    ) -> Double {
        let base: Double = switch composition {
        case .stillness: 0.30
        case .leadingAnchor, .trailingAnchor, .dialogue, .stack, .arc: 0.52
        case .hero, .hookCall, .hookEcho: 0.78
        case .hookConverge: 0.92
        case .hookLock: 1.0
        }
        guard let audio else { return base }
        let onsetLift = min(0.12, Double(audio.onsetCount) * 0.025)
        return (base * 0.68 + audio.peakEnergy * 0.32 + onsetLift).clamped(to: 0.25...1.0)
    }

    private static func companionIndices(
        for index: Int,
        composition: LyricStageV53Composition,
        lines: [PlayerEngine.LyricLine]
    ) -> [Int] {
        if let group = lines[index].overlapGroup {
            return Array(lines.indices.filter { $0 != index && lines[$0].overlapGroup == group }.prefix(2))
        }
        switch composition {
        case .dialogue:
            if index > 0 { return [index - 1] }
            return lines.indices.contains(index + 1) ? [index + 1] : []
        case .stack:
            return [index - 1, index + 1].filter { lines.indices.contains($0) }
        default:
            return []
        }
    }

    private static func contiguousRepeatCluster(
        containing index: Int,
        key: String,
        keys: [String],
        lines: [PlayerEngine.LyricLine]
    ) -> [Int] {
        guard !key.isEmpty else { return [] }
        var lower = index
        while lower > 0,
              keys[lower - 1] == key,
              lines[lower].from - lines[lower - 1].to <= 1.35 {
            lower -= 1
        }
        var upper = index
        while upper + 1 < lines.count,
              keys[upper + 1] == key,
              lines[upper + 1].from - lines[upper].to <= 1.35 {
            upper += 1
        }
        return Array(lower...upper)
    }

    private static func normalizedRepeatKey(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}
