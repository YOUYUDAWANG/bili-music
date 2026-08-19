import Foundation

enum LyricStageScoreV2Version {
    static let current = "lyric-stage-v2-events"
}

enum StagePaletteStrategy: String, Codable, CaseIterable, Sendable {
    case coverAnalogous
    case coverComplementary
    case coverMonochrome
    case warmClimax
    case coolClimax
}

enum StageTypeRole: String, Codable, CaseIterable, Sendable {
    case whisper
    case supporting
    case normal
    case emphasis
    case hero
}

enum StagePaletteRole: String, Codable, CaseIterable, Sendable {
    case primary
    case secondary
    case accent
    case warm
    case backgroundContrast
}

enum StageSectionKind: String, Codable, CaseIterable, Sendable {
    case intro
    case verse
    case preChorus
    case chorus
    case bridge
    case breakdown
    case outro
    case unknown
}

enum StageComposition: String, Codable, CaseIterable, Sendable {
    case singleAnchor
    case stacked
    case splitVoices
    case heroBackdrop
}

enum StageActorRole: String, Codable, CaseIterable, Sendable {
    case base
    case supporting
    case protagonist
    case backdrop
    case vocalA
    case vocalB
}

enum StageAnchor: String, Codable, CaseIterable, Sendable {
    case center
    case leading
    case trailing
    case upperLeading
    case upperTrailing
    case lowerLeading
    case lowerTrailing
    case offstageLeft
    case offstageRight
    case aboveStage
    case belowStage
}

enum StageEventPhase: String, Codable, CaseIterable, Sendable {
    case entrance
    case performance
    case hold
    case exit
}

enum StageVerb: String, Codable, CaseIterable, Sendable {
    case appear
    case assemble
    case drift
    case drop
    case pulse
    case stretch
    case echo
    case scatter
    case dissolve
}

enum StageEventReason: String, Codable, CaseIterable, Sendable {
    case actionWord
    case emotionalPeak
    case hookRepeat
    case sustainedPhrase
    case callAndResponse
    case structuralTransition
    case vocalOverlap
}

enum StageDirection: String, Codable, CaseIterable, Sendable {
    case leading
    case trailing
    case up
    case down
}

enum StageTokenKind: String, Codable, CaseIterable, Sendable {
    case word
    case particle
    case punctuation
    case whitespace
    case emoji
    case unknown
}

enum StageActorTarget: Equatable, Sendable {
    case line(lineIndex: Int)
    case tokens(lineIndex: Int, tokenIndices: [Int])
    case glyphs(lineIndex: Int, glyphFrom: Int, glyphTo: Int)
}

extension StageActorTarget: Codable {
    private enum Kind: String, Codable { case line, tokens, glyphs }
    private enum CodingKeys: String, CodingKey {
        case kind, lineIndex, tokenIndices, glyphFrom, glyphTo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let lineIndex = try container.decode(Int.self, forKey: .lineIndex)
        switch kind {
        case .line:
            self = .line(lineIndex: lineIndex)
        case .tokens:
            self = .tokens(
                lineIndex: lineIndex,
                tokenIndices: try container.decodeIfPresent([Int].self, forKey: .tokenIndices) ?? [])
        case .glyphs:
            let from = try container.decode(Int.self, forKey: .glyphFrom)
            let to = try container.decode(Int.self, forKey: .glyphTo)
            self = .glyphs(lineIndex: lineIndex, glyphFrom: from, glyphTo: to)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .line(let lineIndex):
            try container.encode(Kind.line, forKey: .kind)
            try container.encode(lineIndex, forKey: .lineIndex)
        case .tokens(let lineIndex, let tokenIndices):
            try container.encode(Kind.tokens, forKey: .kind)
            try container.encode(lineIndex, forKey: .lineIndex)
            try container.encode(tokenIndices, forKey: .tokenIndices)
        case .glyphs(let lineIndex, let glyphFrom, let glyphTo):
            try container.encode(Kind.glyphs, forKey: .kind)
            try container.encode(lineIndex, forKey: .lineIndex)
            try container.encode(glyphFrom, forKey: .glyphFrom)
            try container.encode(glyphTo, forKey: .glyphTo)
        }
    }

    var lineIndex: Int {
        switch self {
        case .line(let lineIndex), .tokens(let lineIndex, _), .glyphs(let lineIndex, _, _):
            return lineIndex
        }
    }
}

enum StageRelation: Equatable, Sendable {
    case pushNeighbors
    case attractTo(actorID: String)
    case mirrorWith(actorID: String)
}

extension StageRelation: Codable {
    private enum Kind: String, Codable { case pushNeighbors, attractTo, mirrorWith }
    private enum CodingKeys: String, CodingKey { case kind, actorID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .pushNeighbors:
            self = .pushNeighbors
        case .attractTo:
            self = .attractTo(actorID: try container.decode(String.self, forKey: .actorID))
        case .mirrorWith:
            self = .mirrorWith(actorID: try container.decode(String.self, forKey: .actorID))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pushNeighbors:
            try container.encode(Kind.pushNeighbors, forKey: .kind)
        case .attractTo(let actorID):
            try container.encode(Kind.attractTo, forKey: .kind)
            try container.encode(actorID, forKey: .actorID)
        case .mirrorWith(let actorID):
            try container.encode(Kind.mirrorWith, forKey: .kind)
            try container.encode(actorID, forKey: .actorID)
        }
    }
}

enum StageHandoff: Equatable, Sendable {
    case cut
    case dissolve
    case push(direction: StageDirection)
    case residue(actorID: String)
}

extension StageHandoff: Codable {
    private enum Kind: String, Codable { case cut, dissolve, push, residue }
    private enum CodingKeys: String, CodingKey { case kind, direction, actorID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .cut:
            self = .cut
        case .dissolve:
            self = .dissolve
        case .push:
            self = .push(direction: try container.decodeIfPresent(StageDirection.self, forKey: .direction) ?? .trailing)
        case .residue:
            self = .residue(actorID: try container.decode(String.self, forKey: .actorID))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cut:
            try container.encode(Kind.cut, forKey: .kind)
        case .dissolve:
            try container.encode(Kind.dissolve, forKey: .kind)
        case .push(let direction):
            try container.encode(Kind.push, forKey: .kind)
            try container.encode(direction, forKey: .direction)
        case .residue(let actorID):
            try container.encode(Kind.residue, forKey: .kind)
            try container.encode(actorID, forKey: .actorID)
        }
    }
}

struct StageTypeSystem: Codable, Equatable, Sendable {
    var whisper: Double
    var supporting: Double
    var normal: Double
    var emphasis: Double
    var hero: Double

    static let iPhone17Pro = StageTypeSystem(
        whisper: 19,
        supporting: 22,
        normal: 29,
        emphasis: 38,
        hero: 56)

    func size(for role: StageTypeRole) -> Double {
        switch role {
        case .whisper: whisper.clamped(to: 18...20)
        case .supporting: supporting.clamped(to: 20...24)
        case .normal: normal.clamped(to: 26...32)
        case .emphasis: emphasis.clamped(to: 34...42)
        case .hero: hero.clamped(to: 48...72)
        }
    }

    func validated() -> StageTypeSystem {
        StageTypeSystem(
            whisper: whisper.clamped(to: 18...20),
            supporting: supporting.clamped(to: 20...24),
            normal: normal.clamped(to: 26...32),
            emphasis: emphasis.clamped(to: 34...42),
            hero: hero.clamped(to: 48...72))
    }
}

struct StageMotif: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let verb: StageVerb
    let note: String
}

struct StageStyleSheet: Codable, Equatable, Sendable {
    let concept: String
    let paletteStrategy: StagePaletteStrategy
    let typeSystem: StageTypeSystem
    let motifs: [StageMotif]
}

struct StageSection: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let lineFrom: Int
    let lineTo: Int
    let kind: StageSectionKind
    let density: Double
    let heroBudget: Int
    let accentBudget: Double
    let preferredMotifs: [String]

    var lineRange: ClosedRange<Int> { lineFrom...max(lineFrom, lineTo) }
}

struct StageActor: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let target: StageActorTarget
    let role: StageActorRole
    let anchor: StageAnchor
    let typeRole: StageTypeRole
    let paletteRole: StagePaletteRole
}

struct StageEvent: Codable, Equatable, Sendable {
    let actorID: String
    let phase: StageEventPhase
    let verb: StageVerb
    let start: Double
    let duration: Double
    let intensity: Double
    let motifRef: String?
    let reason: StageEventReason
    let relation: StageRelation?
    let priority: Int

    init(
        actorID: String,
        phase: StageEventPhase,
        verb: StageVerb,
        start: Double,
        duration: Double,
        intensity: Double,
        motifRef: String? = nil,
        reason: StageEventReason,
        relation: StageRelation? = nil,
        priority: Int = 0
    ) {
        self.actorID = actorID
        self.phase = phase
        self.verb = verb
        self.start = start
        self.duration = duration
        self.intensity = intensity
        self.motifRef = motifRef
        self.reason = reason
        self.relation = relation
        self.priority = priority
    }
}

struct StageScene: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let lineIndices: [Int]
    let composition: StageComposition
    let actors: [StageActor]
    let events: [StageEvent]
    let handoffOut: StageHandoff?
}

struct LyricStageScoreV2: Codable, Equatable, Sendable {
    let version: String
    let trackID: String
    let lyricsHash: String
    let styleSheet: StageStyleSheet
    let sections: [StageSection]
    let scenes: [StageScene]
    let droppedEvents: [DroppedStageEvent]

    init(
        version: String = LyricStageScoreV2Version.current,
        trackID: String,
        lyricsHash: String,
        styleSheet: StageStyleSheet,
        sections: [StageSection],
        scenes: [StageScene],
        droppedEvents: [DroppedStageEvent] = []
    ) {
        self.version = version
        self.trackID = trackID
        self.lyricsHash = lyricsHash
        self.styleSheet = styleSheet
        self.sections = sections
        self.scenes = scenes
        self.droppedEvents = droppedEvents
    }

    func validated(
        trackID: String,
        lyricsHash: String,
        lineCount: Int,
        tokenCounts: [Int: Int],
        glyphCounts: [Int: Int]
    ) -> LyricStageScoreV2? {
        guard version == LyricStageScoreV2Version.current,
              self.trackID == trackID,
              self.lyricsHash == lyricsHash,
              lineCount > 0 else { return nil }

        let safeStyle = StageStyleSheet(
            concept: String(styleSheet.concept.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)),
            paletteStrategy: styleSheet.paletteStrategy,
            typeSystem: styleSheet.typeSystem.validated(),
            motifs: styleSheet.motifs.prefix(12).map {
                StageMotif(
                    id: String($0.id.prefix(40)),
                    verb: $0.verb,
                    note: String($0.note.prefix(120)))
            }.filter { !$0.id.isEmpty })
        guard !safeStyle.concept.isEmpty else { return nil }

        var seenSectionIDs = Set<String>()
        let safeSections = sections.compactMap { section -> StageSection? in
            let id = String(section.id.prefix(40))
            guard !id.isEmpty,
                  seenSectionIDs.insert(id).inserted,
                  (0..<lineCount).contains(section.lineFrom),
                  (0..<lineCount).contains(section.lineTo),
                  section.lineTo >= section.lineFrom else { return nil }
            return StageSection(
                id: id,
                lineFrom: section.lineFrom,
                lineTo: section.lineTo,
                kind: section.kind,
                density: section.density.clamped(to: 0...1),
                heroBudget: min(max(section.heroBudget, 0), 4),
                accentBudget: section.accentBudget.clamped(to: 0...0.4),
                preferredMotifs: Array(section.preferredMotifs.prefix(6)))
        }

        var seenSceneIDs = Set<String>()
        let safeScenes = scenes.compactMap { scene -> StageScene? in
            scene.validated(
                lineCount: lineCount,
                tokenCounts: tokenCounts,
                glyphCounts: glyphCounts,
                seenIDs: &seenSceneIDs)
        }

        return LyricStageScoreV2(
            version: version,
            trackID: trackID,
            lyricsHash: lyricsHash,
            styleSheet: safeStyle,
            sections: safeSections,
            scenes: safeScenes,
            droppedEvents: droppedEvents)
    }
}

struct DroppedStageEvent: Codable, Equatable, Sendable {
    let sceneID: String
    let actorID: String
    let verb: StageVerb
    let reason: String
}

struct StageToken: Equatable, Sendable, Identifiable {
    let id: Int
    let text: String
    let glyphRange: Range<Int>
    let kind: StageTokenKind
    let realTiming: ClosedRange<Double>?
}

struct StageTokenPayload: Codable, Equatable, Sendable {
    let lineIndex: Int
    let id: Int
    let text: String
    let glyphFrom: Int
    let glyphTo: Int
    let kind: StageTokenKind
}

struct LyricStagePerformanceSummary: Equatable, Sendable {
    let concept: String
    let paletteStrategy: StagePaletteStrategy
    let sections: [String]
    let motifs: [String]
    let heroScenes: [String]
    let handoffs: [String]
    let droppedEvents: [DroppedStageEvent]
    let events: [String]
}

private extension StageScene {
    func validated(
        lineCount: Int,
        tokenCounts: [Int: Int],
        glyphCounts: [Int: Int],
        seenIDs: inout Set<String>
    ) -> StageScene? {
        let id = String(id.prefix(48))
        guard !id.isEmpty, seenIDs.insert(id).inserted else { return nil }
        var seenLines = Set<Int>()
        let lines = lineIndices.filter { index in
            (0..<lineCount).contains(index) && seenLines.insert(index).inserted
        }.prefix(3)
        guard !lines.isEmpty else { return nil }

        var seenActors = Set<String>()
        let safeActors = actors.compactMap { actor -> StageActor? in
            let actorID = String(actor.id.prefix(40))
            guard !actorID.isEmpty,
                  seenActors.insert(actorID).inserted,
                  actor.target.isValid(
                    allowedLines: seenLines,
                    tokenCounts: tokenCounts,
                    glyphCounts: glyphCounts) else { return nil }
            return StageActor(
                id: actorID,
                target: actor.target.sanitized(tokenCounts: tokenCounts, glyphCounts: glyphCounts),
                role: actor.role,
                anchor: actor.anchor,
                typeRole: actor.typeRole,
                paletteRole: actor.paletteRole)
        }
        guard !safeActors.isEmpty else { return nil }
        let actorIDs = Set(safeActors.map(\.id))
        let safeEvents = events.compactMap { event -> StageEvent? in
            guard actorIDs.contains(event.actorID),
                  StageChoreography.allows(event.verb, in: event.phase) else { return nil }
            let start = event.start.clamped(to: 0...1)
            let duration = event.duration.clamped(to: 0.04...1)
            guard start < 1 else { return nil }
            return StageEvent(
                actorID: event.actorID,
                phase: event.phase,
                verb: event.verb,
                start: start,
                duration: min(duration, 1 - start),
                intensity: event.intensity.clamped(to: 0.2...1.25),
                motifRef: event.motifRef.map { String($0.prefix(40)) },
                reason: event.reason,
                relation: event.relation?.validated(actorIDs: actorIDs),
                priority: event.priority)
        }
        return StageScene(
            id: id,
            lineIndices: Array(lines),
            composition: composition,
            actors: safeActors,
            events: safeEvents,
            handoffOut: handoffOut)
    }
}

private extension StageActorTarget {
    func isValid(allowedLines: Set<Int>, tokenCounts: [Int: Int], glyphCounts: [Int: Int]) -> Bool {
        guard allowedLines.contains(lineIndex) else { return false }
        switch self {
        case .line:
            return true
        case .tokens(_, let tokenIndices):
            let count = tokenCounts[lineIndex] ?? 0
            return !tokenIndices.isEmpty && tokenIndices.allSatisfy { (0..<count).contains($0) }
        case .glyphs(_, let from, let to):
            let count = glyphCounts[lineIndex] ?? 0
            return from >= 0 && to >= from && to < count
        }
    }

    func sanitized(tokenCounts: [Int: Int], glyphCounts: [Int: Int]) -> StageActorTarget {
        switch self {
        case .line:
            return self
        case .tokens(let lineIndex, let tokenIndices):
            let count = tokenCounts[lineIndex] ?? 0
            var seen = Set<Int>()
            return .tokens(
                lineIndex: lineIndex,
                tokenIndices: tokenIndices.filter { (0..<count).contains($0) && seen.insert($0).inserted })
        case .glyphs(let lineIndex, let from, let to):
            let count = max(0, (glyphCounts[lineIndex] ?? 0) - 1)
            return .glyphs(lineIndex: lineIndex, glyphFrom: max(0, from), glyphTo: min(to, count))
        }
    }
}

private extension StageRelation {
    func validated(actorIDs: Set<String>) -> StageRelation? {
        switch self {
        case .pushNeighbors:
            return self
        case .attractTo(let actorID), .mirrorWith(let actorID):
            return actorIDs.contains(actorID) ? self : nil
        }
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
