import CryptoKit
import Foundation

enum LyricStagePlanV3Version {
    static let current = "lyric-stage-v3-choreography"
    static let compiler = "bilimusic-v53-compiler-1"
}

enum LyricStageV53Composition: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case stillness
    case leadingAnchor
    case trailingAnchor
    case dialogue
    case stack
    case arc
    case hero
    case hookCall
    case hookEcho
    case hookConverge
    case hookLock

    var isHook: Bool {
        switch self {
        case .hookCall, .hookEcho, .hookConverge, .hookLock: true
        default: false
        }
    }
}

enum LyricStageMotifPhaseV3: String, Codable, CaseIterable, Equatable, Sendable {
    case introduce
    case develop
    case transform
    case resolve
}

enum LyricStagePlanSourceV3: String, Codable, Equatable, Sendable {
    case local
    case luna
}

struct LyricStageBibleV3: Codable, Equatable, Sendable {
    let concept: String
    let motif: String
    let intensityArc: String

    func validated() -> LyricStageBibleV3? {
        let concept = concept.trimmingCharacters(in: .whitespacesAndNewlines)
        let motif = motif.trimmingCharacters(in: .whitespacesAndNewlines)
        let arc = intensityArc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !concept.isEmpty, !motif.isEmpty, !arc.isEmpty else { return nil }
        return LyricStageBibleV3(
            concept: String(concept.prefix(160)),
            motif: String(motif.prefix(120)),
            intensityArc: String(arc.prefix(200)))
    }
}

struct LyricStageSectionV3: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let lineFrom: Int
    let lineTo: Int
    let kind: StageSectionKind
    let intensity: Double
    let motifPhase: LyricStageMotifPhaseV3

    var lineRange: ClosedRange<Int> { lineFrom...max(lineFrom, lineTo) }

    func validated(lineCount: Int) -> LyricStageSectionV3? {
        let id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !id.isEmpty,
              (0..<lineCount).contains(lineFrom),
              (0..<lineCount).contains(lineTo),
              lineTo >= lineFrom else { return nil }
        return LyricStageSectionV3(
            id: id,
            lineFrom: lineFrom,
            lineTo: lineTo,
            kind: kind,
            intensity: intensity.clamped(to: 0...1),
            motifPhase: motifPhase)
    }
}

struct LyricStageSceneOverrideV3: Codable, Equatable, Sendable {
    let lineIndex: Int
    let composition: LyricStageV53Composition
    let companionLineIndices: [Int]
    let intensity: Double
    let motifRef: String?

    init(
        lineIndex: Int,
        composition: LyricStageV53Composition,
        companionLineIndices: [Int] = [],
        intensity: Double = 0.7,
        motifRef: String? = nil
    ) {
        self.lineIndex = lineIndex
        self.composition = composition
        self.companionLineIndices = companionLineIndices
        self.intensity = intensity
        self.motifRef = motifRef
    }
}

struct LyricStageDirectionV3: Codable, Equatable, Sendable {
    let version: String
    let directorVersion: String
    let trackID: String
    let lyricsHash: String
    let lineCount: Int
    let audioSummaryHash: String
    let stageBible: LyricStageBibleV3
    let sections: [LyricStageSectionV3]
    let scenes: [LyricStageSceneOverrideV3]
    let partial: Bool
    let provider: String?
    let model: String?

    init(
        version: String = LyricStagePlanV3Version.current,
        directorVersion: String,
        trackID: String,
        lyricsHash: String,
        lineCount: Int,
        audioSummaryHash: String,
        stageBible: LyricStageBibleV3,
        sections: [LyricStageSectionV3],
        scenes: [LyricStageSceneOverrideV3],
        partial: Bool = false,
        provider: String? = nil,
        model: String? = nil
    ) {
        self.version = version
        self.directorVersion = directorVersion
        self.trackID = trackID
        self.lyricsHash = lyricsHash
        self.lineCount = lineCount
        self.audioSummaryHash = audioSummaryHash
        self.stageBible = stageBible
        self.sections = sections
        self.scenes = scenes
        self.partial = partial
        self.provider = provider
        self.model = model
    }

    func validated(
        trackID: String,
        lyricsHash: String,
        lines: [PlayerEngine.LyricLine],
        audioSummaryHash: String
    ) -> LyricStageDirectionV3? {
        guard version == LyricStagePlanV3Version.current,
              self.trackID == trackID,
              self.lyricsHash == lyricsHash,
              self.audioSummaryHash == audioSummaryHash,
              lineCount == lines.count,
              lineCount > 0,
              !directorVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let bible = stageBible.validated() else { return nil }

        var sectionIDs = Set<String>()
        let safeSections = sections.compactMap { $0.validated(lineCount: lineCount) }
            .sorted { $0.lineFrom < $1.lineFrom }
        guard safeSections.count == sections.count,
              safeSections.first?.lineFrom == 0,
              safeSections.last?.lineTo == lineCount - 1,
              safeSections.allSatisfy({ sectionIDs.insert($0.id).inserted }) else { return nil }
        for index in safeSections.indices.dropFirst() {
            guard safeSections[index].lineFrom == safeSections[index - 1].lineTo + 1 else { return nil }
        }

        let basePlan = LyricStageDirectorV3.localPlan(
            trackID: trackID,
            lines: lines,
            audioSummary: .empty(duration: lines.last?.to ?? 0))
        var seenLines = Set<Int>()
        let safeScenes = scenes.compactMap { scene -> LyricStageSceneOverrideV3? in
            guard seenLines.insert(scene.lineIndex).inserted,
                  lines.indices.contains(scene.lineIndex),
                  let base = basePlan.scene(for: scene.lineIndex) else { return nil }

            var companions = [Int]()
            for companion in scene.companionLineIndices where companion != scene.lineIndex {
                guard lines.indices.contains(companion), companions.count < 2 else { continue }
                let sharesVoiceGroup = lines[scene.lineIndex].overlapGroup != nil
                    && lines[scene.lineIndex].overlapGroup == lines[companion].overlapGroup
                guard sharesVoiceGroup || abs(companion - scene.lineIndex) <= 2 else { continue }
                if !companions.contains(companion) { companions.append(companion) }
            }

            if scene.composition.isHook {
                guard let occurrence = base.repetitionIndex,
                      base.repetitionCount >= 2,
                      scene.composition == LyricStageDirectorV3.expectedHookComposition(
                        occurrence: occurrence,
                        count: base.repetitionCount) else { return nil }
            }
            switch scene.composition {
            case .dialogue, .stack:
                guard !companions.isEmpty else { return nil }
            default:
                companions = []
            }
            if scene.composition == .hero {
                let glyphCount = lines[scene.lineIndex].text.filter { !$0.isWhitespace }.count
                guard glyphCount <= 12 else { return nil }
            }
            return LyricStageSceneOverrideV3(
                lineIndex: scene.lineIndex,
                composition: scene.composition,
                companionLineIndices: companions,
                intensity: scene.intensity.clamped(to: 0.25...1.25),
                motifRef: scene.motifRef.map { String($0.prefix(40)) })
        }

        let minimumScenes = max(1, Int(ceil(Double(lineCount) * 0.10)))
        let maximumScenes = max(minimumScenes, Int(ceil(Double(lineCount) * 0.75)))
        let heroCount = safeScenes.filter { $0.composition == .hero || $0.composition == .hookLock }.count
        let heroLimit = max(1, Int(ceil(Double(lineCount) * 0.12)))
        guard safeScenes.count == scenes.count,
              (minimumScenes...maximumScenes).contains(safeScenes.count),
              heroCount <= heroLimit else { return nil }

        return LyricStageDirectionV3(
            version: version,
            directorVersion: String(directorVersion.prefix(120)),
            trackID: trackID,
            lyricsHash: lyricsHash,
            lineCount: lineCount,
            audioSummaryHash: audioSummaryHash,
            stageBible: bible,
            sections: safeSections,
            scenes: safeScenes,
            partial: partial,
            provider: provider.map { String($0.prefix(80)) },
            model: model.map { String($0.prefix(120)) })
    }
}

struct LyricStageV53Scene: Codable, Equatable, Sendable {
    let lineIndex: Int
    let sectionIndex: Int
    let composition: LyricStageV53Composition
    let companionLineIndices: [Int]
    let repetitionIndex: Int?
    let repetitionCount: Int
    let isSectionStart: Bool
    let intensity: Double
    let motifRef: String?

    init(
        lineIndex: Int,
        sectionIndex: Int,
        composition: LyricStageV53Composition,
        companionLineIndices: [Int],
        repetitionIndex: Int?,
        repetitionCount: Int,
        isSectionStart: Bool,
        intensity: Double = 0.7,
        motifRef: String? = nil
    ) {
        self.lineIndex = lineIndex
        self.sectionIndex = sectionIndex
        self.composition = composition
        self.companionLineIndices = companionLineIndices
        self.repetitionIndex = repetitionIndex
        self.repetitionCount = repetitionCount
        self.isSectionStart = isSectionStart
        self.intensity = intensity
        self.motifRef = motifRef
    }
}

struct LyricStagePlanV3: Codable, Equatable, Sendable {
    let version: String
    let compilerVersion: String
    let directorVersion: String
    let trackID: String
    let lyricsHash: String
    let audioSummaryHash: String
    let stageBible: LyricStageBibleV3
    let sections: [LyricStageSectionV3]
    let scenes: [LyricStageV53Scene]
    let source: LyricStagePlanSourceV3
    let partial: Bool

    func scene(for lineIndex: Int) -> LyricStageV53Scene? {
        scenes.first { $0.lineIndex == lineIndex }
    }

    func scene(at time: Double, lines: [PlayerEngine.LyricLine]) -> LyricStageV53Scene? {
        let active = LyricHighlightModel.activeLineIndices(lines: lines, at: time)
        if let lead = active.first(where: { lines[$0].voiceRole == .lead || lines[$0].voiceRole == .together }) {
            return scene(for: lead)
        }
        if let first = active.first { return scene(for: first) }
        if let latest = lines.indices.last(where: { lines[$0].from <= time }) {
            return scene(for: latest)
        }
        return scenes.first
    }

    var summary: LyricStagePlanV3Summary {
        LyricStagePlanV3Summary(
            concept: stageBible.concept,
            motif: stageBible.motif,
            intensityArc: stageBible.intensityArc,
            source: source,
            partial: partial,
            sections: sections.map { "\($0.kind.rawValue) \($0.lineFrom)–\($0.lineTo) · \($0.motifPhase.rawValue)" },
            compositions: Dictionary(grouping: scenes, by: \.composition)
                .map { "\($0.key.rawValue): \($0.value.count)" }
                .sorted())
    }

    static func compile(lines: [PlayerEngine.LyricLine]) -> LyricStagePlanV3 {
        LyricStageDirectorV3.localPlan(
            trackID: "local-preview",
            lines: lines,
            audioSummary: .empty(duration: lines.last?.to ?? 0))
    }
}

/// Immutable, render-ready scene index for V5.3. The initializer performs the
/// only full lyric scan; `sample(at:)` is a binary search over timestamps where
/// the selected scene can change.
struct LyricStagePreparedRuntimeV3: Sendable {
    struct Sample: Equatable, Sendable {
        let scene: LyricStageV53Scene
        let motifPhase: LyricStageMotifPhaseV3
    }

    private struct Boundary: Sendable {
        let time: Double
        let sample: Sample
    }

    private let fallback: Sample?
    private let boundaries: [Boundary]

    init(plan: LyricStagePlanV3, lines: [PlayerEngine.LyricLine]) {
        var scenesByLineIndex: [Int: LyricStageV53Scene] = [:]
        scenesByLineIndex.reserveCapacity(plan.scenes.count)
        for scene in plan.scenes where scenesByLineIndex[scene.lineIndex] == nil {
            scenesByLineIndex[scene.lineIndex] = scene
        }

        func sample(for lineIndex: Int?) -> Sample? {
            guard let lineIndex, let scene = scenesByLineIndex[lineIndex] else { return nil }
            let motifPhase: LyricStageMotifPhaseV3
            if plan.sections.indices.contains(scene.sectionIndex) {
                motifPhase = plan.sections[scene.sectionIndex].motifPhase
            } else {
                motifPhase = .develop
            }
            return Sample(scene: scene, motifPhase: motifPhase)
        }

        fallback = sample(for: plan.scenes.first?.lineIndex)

        let changeTimes = Set(lines.flatMap { [$0.from, $0.to] }.filter(\.isFinite)).sorted()
        var resolved: [Boundary] = []
        resolved.reserveCapacity(changeTimes.count)
        for time in changeTimes {
            let lineIndex = Self.selectedLineIndex(lines: lines, at: time)
            guard let next = sample(for: lineIndex) ?? fallback else { continue }
            if resolved.last?.sample == next { continue }
            resolved.append(Boundary(time: time, sample: next))
        }
        boundaries = resolved
    }

    var changeCount: Int { boundaries.count }

    func sample(at time: Double) -> Sample? {
        guard time.isFinite, !boundaries.isEmpty else { return fallback }
        guard time >= boundaries[0].time else { return fallback }

        var lower = 0
        var upper = boundaries.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if boundaries[middle].time <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return boundaries[max(0, lower - 1)].sample
    }

    private static func selectedLineIndex(
        lines: [PlayerEngine.LyricLine],
        at time: Double
    ) -> Int? {
        var firstActive: Int?
        for index in lines.indices where time >= lines[index].from && time < lines[index].to {
            if firstActive == nil { firstActive = index }
            let role = lines[index].voiceRole
            if role == .lead || role == .together { return index }
        }
        if let firstActive { return firstActive }
        return lines.indices.last(where: { lines[$0].from <= time })
    }
}

typealias LyricStageV53Plan = LyricStagePlanV3

struct LyricStagePlanV3Summary: Equatable, Sendable {
    let concept: String
    let motif: String
    let intensityArc: String
    let source: LyricStagePlanSourceV3
    let partial: Bool
    let sections: [String]
    let compositions: [String]
}

enum LyricStageFingerprintV3 {
    static func cacheIdentity(
        trackID: String,
        lyricsHash: String,
        audioSummaryHash: String,
        directorVersion: String
    ) -> String {
        digest([
            LyricStagePlanV3Version.current,
            LyricStagePlanV3Version.compiler,
            directorVersion,
            trackID,
            lyricsHash,
            audioSummaryHash,
        ])
    }

    static func digest<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "none" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
