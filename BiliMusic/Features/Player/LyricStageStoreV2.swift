import Foundation
import OSLog

private let lyricStageV2Log = Logger(subsystem: "com.fubuki.BiliMusic", category: "lyric-stage-v2-store")

struct StoredLyricStageV2: Codable, Equatable, Sendable {
    let trackKey: TrackKey
    let lyricsHash: String
    let score: LyricStageScoreV2
    let updatedAt: Date
}

@MainActor
final class LyricStageStoreV2 {
    static let shared = LyricStageStoreV2()

    private let fileURL: URL
    private let fileWriter = VersionedAtomicFileWriter()
    private var entries: [StoredLyricStageV2] = []
    private var isLoaded = false
    private var revision = 0

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lyric-stage-v2.json")
    }

#if DEBUG
    init(fileURLForTesting: URL) {
        fileURL = fileURLForTesting
    }
#endif

    func score(for track: Track, lines: [PlayerEngine.LyricLine]) async -> LyricStageScoreV2? {
        await loadIfNeeded()
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        guard let entry = entries.first(where: {
            $0.lyricsHash == hash && ($0.trackKey == track.key || $0.trackKey.matches(track))
        }) else { return nil }
        return entry.score.validated(
            trackID: track.key.description,
            lyricsHash: hash,
            lineCount: lines.count,
            tokenCounts: LyricStageTokenizer.tokenCounts(for: lines),
            glyphCounts: LyricStageTokenizer.glyphCounts(for: lines))
    }

    @discardableResult
    func save(
        _ score: LyricStageScoreV2,
        for track: Track,
        lines: [PlayerEngine.LyricLine]
    ) async -> Bool {
        await loadIfNeeded()
        let hash = LyricPerformanceFingerprint.lyricsHash(lines)
        guard let safe = score.validated(
            trackID: track.key.description,
            lyricsHash: hash,
            lineCount: lines.count,
            tokenCounts: LyricStageTokenizer.tokenCounts(for: lines),
            glyphCounts: LyricStageTokenizer.glyphCounts(for: lines)
        ) else { return false }
        entries.removeAll { $0.trackKey == track.key || $0.trackKey.matches(track) }
        entries.insert(
            StoredLyricStageV2(trackKey: track.key, lyricsHash: hash, score: safe, updatedAt: Date()),
            at: 0)
        if entries.count > 100 {
            entries.removeLast(entries.count - 100)
        }
        await persist()
        return true
    }

    func clear(for track: Track) async {
        await loadIfNeeded()
        entries.removeAll { $0.trackKey == track.key || $0.trackKey.matches(track) }
        await persist()
    }

    private func loadIfNeeded() async {
        guard !isLoaded else { return }
        let url = fileURL
        let loaded = await Task.detached(priority: .utility) { () -> [StoredLyricStageV2] in
            guard let data = try? Data(contentsOf: url) else { return [] }
            return (try? JSONDecoder().decode([StoredLyricStageV2].self, from: data)) ?? []
        }.value
        entries = loaded.sorted { $0.updatedAt > $1.updatedAt }
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
            lyricStageV2Log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
