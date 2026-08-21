import Foundation
import OSLog

private let lyricStageV3Log = Logger(subsystem: "com.fubuki.BiliMusic", category: "lyric-stage-v3-store")

struct StoredLyricStageV3: Codable, Equatable, Sendable {
    let schemaVersion: String
    let cacheIdentity: String
    let trackKey: TrackKey
    let lyricsHash: String
    let audioSummaryHash: String
    let direction: LyricStageDirectionV3
    let updatedAt: Date
}

@MainActor
final class LyricStageStoreV3 {
    static let shared = LyricStageStoreV3()

    private let fileURL: URL
    private let fileWriter = VersionedAtomicFileWriter()
    private var entries: [StoredLyricStageV3] = []
    private var isLoaded = false
    private var revision = 0

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lyric-stage-v3.json")
    }

#if DEBUG
    init(fileURLForTesting: URL) {
        fileURL = fileURLForTesting
    }
#endif

    func direction(
        for track: Track,
        lines: [PlayerEngine.LyricLine],
        audioSummary: LyricStageAudioSummaryV3
    ) async -> LyricStageDirectionV3? {
        await loadIfNeeded()
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(lines)
        let candidates = entries.filter {
            $0.schemaVersion == LyricStagePlanV3Version.current
                && $0.lyricsHash == lyricsHash
                && $0.audioSummaryHash == audioSummary.summaryHash
                && Self.hasValidCacheIdentity($0)
                && $0.trackKey.bvid == track.bvid
        }
        guard let entry = Self.preferredEntry(in: candidates, for: track.key) else { return nil }
        return entry.direction.validated(
            trackID: track.key.description,
            lyricsHash: lyricsHash,
            lines: Array(lines.prefix(180)),
            audioSummaryHash: audioSummary.summaryHash)
    }

    @discardableResult
    func save(
        _ direction: LyricStageDirectionV3,
        for track: Track,
        lines: [PlayerEngine.LyricLine],
        audioSummary: LyricStageAudioSummaryV3
    ) async -> Bool {
        await loadIfNeeded()
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(lines)
        let directedLines = Array(lines.prefix(180))
        guard let safe = direction.validated(
            trackID: track.key.description,
            lyricsHash: lyricsHash,
            lines: directedLines,
            audioSummaryHash: audioSummary.summaryHash) else { return false }
        let identity = LyricStageFingerprintV3.cacheIdentity(
            trackID: track.key.description,
            lyricsHash: lyricsHash,
            audioSummaryHash: audioSummary.summaryHash,
            directorVersion: safe.directorVersion)
        entries.removeAll { Self.matchesForMutation($0.trackKey, requested: track.key) }
        entries.insert(
            StoredLyricStageV3(
                schemaVersion: LyricStagePlanV3Version.current,
                cacheIdentity: identity,
                trackKey: track.key,
                lyricsHash: lyricsHash,
                audioSummaryHash: audioSummary.summaryHash,
                direction: safe,
                updatedAt: Date()),
            at: 0)
        if entries.count > 100 {
            entries.removeLast(entries.count - 100)
        }
        await persist()
        return true
    }

    func clear(for track: Track) async {
        await loadIfNeeded()
        entries.removeAll { Self.matchesForMutation($0.trackKey, requested: track.key) }
        await persist()
    }

    private static func preferredEntry(
        in candidates: [StoredLyricStageV3],
        for requested: TrackKey
    ) -> StoredLyricStageV3? {
        if let exact = candidates.first(where: { $0.trackKey == requested }) {
            return exact
        }
        if requested.cid != nil {
            return candidates.first(where: { $0.trackKey.cid == nil })
        }
        let resolved = candidates.filter { $0.trackKey.cid != nil }
        let resolvedCIDs = Set(resolved.compactMap(\.trackKey.cid))
        guard resolvedCIDs.count == 1 else { return nil }
        return resolved.first
    }

    /// A resolved part may replace its own legacy BV-only entry, but must never
    /// evict another part. A BV-only operation is deliberately BV-only.
    private static func matchesForMutation(_ stored: TrackKey, requested: TrackKey) -> Bool {
        guard stored.bvid == requested.bvid else { return false }
        if let cid = requested.cid {
            return stored.cid == nil || stored.cid == cid
        }
        return stored.cid == nil
    }

    private static func hasValidCacheIdentity(_ entry: StoredLyricStageV3) -> Bool {
        entry.trackKey.description == entry.direction.trackID
            && entry.cacheIdentity == LyricStageFingerprintV3.cacheIdentity(
                trackID: entry.direction.trackID,
                lyricsHash: entry.lyricsHash,
                audioSummaryHash: entry.audioSummaryHash,
                directorVersion: entry.direction.directorVersion)
    }

    private func loadIfNeeded() async {
        guard !isLoaded else { return }
        let url = fileURL
        let loaded = await Task.detached(priority: .utility) { () -> [StoredLyricStageV3] in
            guard let data = try? Data(contentsOf: url) else { return [] }
            return (try? JSONDecoder().decode([StoredLyricStageV3].self, from: data)) ?? []
        }.value
        entries = loaded
            .filter { $0.schemaVersion == LyricStagePlanV3Version.current }
            .sorted { $0.updatedAt > $1.updatedAt }
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
            lyricStageV3Log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
