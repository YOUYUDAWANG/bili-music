import Foundation

enum LyricStagePlanV4Version {
    static let current = "lyric-stage-v4-scene-recipe"
    static let grammar = "scene-recipe-grammar-v1"
    static let compiler = "bilimusic-v54-scene-recipe-compiler-1"
    static let audioScore = "lyric-stage-audio-structure-score-v4"
}

enum LyricStageSceneFamilyV4: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case railHandoff
    case semanticLens
    case chorusMemory
    case silenceAperture
}

enum LyricStageTopologyV4: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case anchor
    case relay
    case split
    case stack
    case contour
    case lockup
}

enum LyricStageEntranceV4: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case settle
    case slide
    case gather
    case aperture
    case interleave
}

enum LyricStageFocusV4: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case wholeLine
    case tokenRange
}

enum LyricStageSustainV4: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case none
    case sweep
    case weightBloom
    case trackingBreath
    case echo
    case railTravel
}

enum LyricStageContinuityV4: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case clear
    case residue
    case handoff
    case accumulate
}

enum LyricStageDriverV4: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case lyricReveal
    case wordReveal
    case structuralMoment
    case sectionEdge
}

enum LyricStageMotifSignatureV4: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case rail
    case echo
    case aperture
    case counterline
}

enum LyricStageMotifAxisV4: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case horizontal
    case diagonal
    case centered
}

enum LyricStageMotifCadenceV4: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case phrase
    case downbeat
    case free
}

enum LyricStageMotifPhaseV4: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case introduce
    case develop
    case transform
    case resolve
}

enum LyricStagePlanSourceV4: String, Codable, Equatable, Sendable {
    case local
    case gemini
}

struct LyricStageTokenRangeV4: Codable, Equatable, Sendable {
    let startTokenIndex: Int
    let endTokenIndex: Int
}

struct LyricStageMotifV4: Codable, Equatable, Sendable {
    let signature: LyricStageMotifSignatureV4
    let axis: LyricStageMotifAxisV4
    let cadence: LyricStageMotifCadenceV4
}

struct LyricStageBibleV4: Codable, Equatable, Sendable {
    let concept: String
    let intensityArc: String
    let primaryMotif: LyricStageMotifV4
    let secondaryMotif: LyricStageMotifV4?
}

struct LyricStageSceneRecipeV4: Codable, Equatable, Sendable {
    let lineIndex: Int
    let family: LyricStageSceneFamilyV4
    let topology: LyricStageTopologyV4
    let entrance: LyricStageEntranceV4
    let focus: LyricStageFocusV4
    let tokenRange: LyricStageTokenRangeV4?
    let sustain: LyricStageSustainV4
    let continuity: LyricStageContinuityV4
    let driver: LyricStageDriverV4
    let landmarkIDs: [String]
    let companionLineIndices: [Int]
    let motifPhase: LyricStageMotifPhaseV4
    let intensity: Double
}

struct LyricStageDirectionV4: Codable, Equatable, Sendable {
    let version: String
    let grammarVersion: String
    let directorVersion: String
    let trackID: String
    let lyricsHash: String
    let lineCount: Int
    let audioScoreHash: String
    let stageBible: LyricStageBibleV4
    let scenes: [LyricStageSceneRecipeV4]
    let partial: Bool
    let provider: String?
    let model: String?

    init(
        version: String = LyricStagePlanV4Version.current,
        grammarVersion: String = LyricStagePlanV4Version.grammar,
        directorVersion: String,
        trackID: String,
        lyricsHash: String,
        lineCount: Int,
        audioScoreHash: String,
        stageBible: LyricStageBibleV4,
        scenes: [LyricStageSceneRecipeV4],
        partial: Bool = false,
        provider: String? = nil,
        model: String? = nil
    ) {
        self.version = version
        self.grammarVersion = grammarVersion
        self.directorVersion = directorVersion
        self.trackID = trackID
        self.lyricsHash = lyricsHash
        self.lineCount = lineCount
        self.audioScoreHash = audioScoreHash
        self.stageBible = stageBible
        self.scenes = scenes
        self.partial = partial
        self.provider = provider
        self.model = model
    }
}

struct LyricStageResolvedLandmarkV4: Codable, Equatable, Sendable {
    let id: String
    let kind: AudioStructureMomentKindV4
    let from: Double
    let to: Double
    let strength: Double
    let confidence: Double
}

struct LyricStagePlanV4: Equatable, Sendable {
    let version: String
    let grammarVersion: String
    let compilerVersion: String
    let directorVersion: String
    let trackID: String
    let lyricsHash: String
    let audioScoreHash: String
    let basePlan: LyricStagePlanV3
    let audioScore: AudioStructureScoreV4
    let stageBible: LyricStageBibleV4
    let recipes: [LyricStageSceneRecipeV4]
    let landmarkByID: [String: LyricStageResolvedLandmarkV4]
    let source: LyricStagePlanSourceV4
    let partial: Bool

    var recipeByLineIndex: [Int: LyricStageSceneRecipeV4] {
        recipes.reduce(into: [:]) { result, recipe in
            if result[recipe.lineIndex] == nil { result[recipe.lineIndex] = recipe }
        }
    }

    func recipe(for lineIndex: Int) -> LyricStageSceneRecipeV4? {
        recipes.first { $0.lineIndex == lineIndex }
    }
}

enum LyricStageFingerprintV4 {
    static func cacheIdentity(
        trackID: String,
        lyricsHash: String,
        audioScoreHash: String,
        directorVersion: String
    ) -> String {
        LyricStageFingerprintV3.digest([
            LyricStagePlanV4Version.current,
            LyricStagePlanV4Version.grammar,
            LyricStagePlanV4Version.compiler,
            directorVersion,
            trackID,
            lyricsHash,
            audioScoreHash,
        ])
    }
}
