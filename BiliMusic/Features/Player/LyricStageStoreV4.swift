import Foundation
import OSLog

private let lyricStageV4Log = Logger(subsystem: "com.fubuki.BiliMusic", category: "lyric-stage-v4-store")

private struct StoredLyricStageV4: Codable, Equatable, Sendable {
    let schemaVersion: String
    let compilerVersion: String
    let cacheIdentity: String
    let trackKey: TrackKey
    let lyricsHash: String
    let audioScoreHash: String
    let direction: LyricStageDirectionV4
    let updatedAt: Date
}

@MainActor
final class LyricStageStoreV4 {
    static let shared = LyricStageStoreV4()

    private let fileURL: URL
    private let fileWriter = VersionedAtomicFileWriter()
    private var entries: [StoredLyricStageV4] = []
    private var isLoaded = false
    private var revision = 0

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lyric-stage-v4.json")
    }

#if DEBUG
    init(fileURLForTesting: URL) {
        fileURL = fileURLForTesting
    }
#endif

    func direction(
        for track: Track,
        lines: [PlayerEngine.LyricLine],
        audioScore: AudioStructureScoreV4
    ) async -> LyricStageDirectionV4? {
        await loadIfNeeded()
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(lines)
        let audioScoreHash = audioScore.fingerprint
        let candidates = entries.filter {
            $0.schemaVersion == LyricStagePlanV4Version.current
                && $0.compilerVersion == LyricStagePlanV4Version.compiler
                && $0.lyricsHash == lyricsHash
                && $0.audioScoreHash == audioScoreHash
                && Self.hasValidCacheIdentity($0)
                && $0.trackKey.bvid == track.bvid
        }
        guard let entry = Self.preferredEntry(in: candidates, for: track.key) else { return nil }
        return LyricStageDirectorV4.validated(
            entry.direction,
            trackID: track.key.description,
            lyricsHash: lyricsHash,
            lines: lines,
            audioScore: audioScore)
    }

    @discardableResult
    func save(
        _ direction: LyricStageDirectionV4,
        for track: Track,
        lines: [PlayerEngine.LyricLine],
        audioScore: AudioStructureScoreV4
    ) async -> Bool {
        await loadIfNeeded()
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(lines)
        guard let safe = LyricStageDirectorV4.validated(
            direction,
            trackID: track.key.description,
            lyricsHash: lyricsHash,
            lines: lines,
            audioScore: audioScore) else { return false }
        let identity = LyricStageFingerprintV4.cacheIdentity(
            trackID: track.key.description,
            lyricsHash: lyricsHash,
            audioScoreHash: audioScore.fingerprint,
            directorVersion: safe.directorVersion)
        entries.removeAll { Self.matchesForMutation($0.trackKey, requested: track.key) }
        entries.insert(
            StoredLyricStageV4(
                schemaVersion: LyricStagePlanV4Version.current,
                compilerVersion: LyricStagePlanV4Version.compiler,
                cacheIdentity: identity,
                trackKey: track.key,
                lyricsHash: lyricsHash,
                audioScoreHash: audioScore.fingerprint,
                direction: safe,
                updatedAt: Date()),
            at: 0)
        if entries.count > 100 { entries.removeLast(entries.count - 100) }
        await persist()
        return true
    }

    func clear(for track: Track) async {
        await loadIfNeeded()
        entries.removeAll { Self.matchesForMutation($0.trackKey, requested: track.key) }
        await persist()
    }

    private static func preferredEntry(
        in candidates: [StoredLyricStageV4],
        for requested: TrackKey
    ) -> StoredLyricStageV4? {
        if let exact = candidates.first(where: { $0.trackKey == requested }) { return exact }
        if requested.cid != nil {
            return candidates.first(where: { $0.trackKey.cid == nil })
        }
        let resolved = candidates.filter { $0.trackKey.cid != nil }
        let cids = Set(resolved.compactMap(\.trackKey.cid))
        guard cids.count == 1 else { return nil }
        return resolved.first
    }

    private static func matchesForMutation(_ stored: TrackKey, requested: TrackKey) -> Bool {
        guard stored.bvid == requested.bvid else { return false }
        if let cid = requested.cid { return stored.cid == nil || stored.cid == cid }
        return stored.cid == nil
    }

    private static func hasValidCacheIdentity(_ entry: StoredLyricStageV4) -> Bool {
        entry.trackKey.description == entry.direction.trackID
            && entry.cacheIdentity == LyricStageFingerprintV4.cacheIdentity(
                trackID: entry.direction.trackID,
                lyricsHash: entry.lyricsHash,
                audioScoreHash: entry.audioScoreHash,
                directorVersion: entry.direction.directorVersion)
    }

    private func loadIfNeeded() async {
        guard !isLoaded else { return }
        let url = fileURL
        let loaded = await Task.detached(priority: .utility) { () -> [StoredLyricStageV4] in
            guard let data = try? Data(contentsOf: url) else { return [] }
            return (try? JSONDecoder().decode([StoredLyricStageV4].self, from: data)) ?? []
        }.value
        entries = loaded
            .filter {
                $0.schemaVersion == LyricStagePlanV4Version.current
                    && $0.compilerVersion == LyricStagePlanV4Version.compiler
                    && Self.hasValidCacheIdentity($0)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        if entries.count > 100 { entries.removeLast(entries.count - 100) }
        isLoaded = true
    }

    private func persist() async {
        revision += 1
        let currentRevision = revision
        let snapshot = entries
        do {
            let data = try await Task.detached(priority: .background) {
                try JSONEncoder().encode(snapshot)
            }.value
            try await fileWriter.write(data, revision: currentRevision, to: fileURL)
        } catch {
            lyricStageV4Log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
