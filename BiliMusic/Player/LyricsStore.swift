import Foundation
import OSLog

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "lyrics-store")

struct StoredLyricsEntry: Codable, Equatable, Sendable {
    var trackKey: TrackKey
    var document: LyricsDocument?
    var offsetMilliseconds: Int
    var offsetIsUserSet: Bool
    var updatedAt: Date
    var missExpiresAt: Date?

    var hasLyrics: Bool { document?.hasLyrics == true }

    func isActiveMiss(at date: Date = Date()) -> Bool {
        document == nil && (missExpiresAt ?? .distantPast) > date
    }

    init(
        trackKey: TrackKey,
        document: LyricsDocument?,
        offsetMilliseconds: Int,
        offsetIsUserSet: Bool = false,
        updatedAt: Date,
        missExpiresAt: Date?
    ) {
        self.trackKey = trackKey
        self.document = document
        self.offsetMilliseconds = offsetMilliseconds
        self.offsetIsUserSet = offsetIsUserSet
        self.updatedAt = updatedAt
        self.missExpiresAt = missExpiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackKey = try container.decode(TrackKey.self, forKey: .trackKey)
        document = try container.decodeIfPresent(LyricsDocument.self, forKey: .document)
        offsetMilliseconds = try container.decode(Int.self, forKey: .offsetMilliseconds)
        offsetIsUserSet = try container.decodeIfPresent(Bool.self, forKey: .offsetIsUserSet) ?? false
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        missExpiresAt = try container.decodeIfPresent(Date.self, forKey: .missExpiresAt)
    }
}

@MainActor
final class LyricsStore {
    static let shared = LyricsStore()
    static let missCacheTTL: TimeInterval = 7 * 24 * 60 * 60

    private let fileURL: URL
    private let fileWriter = VersionedAtomicFileWriter()
    private var entries: [StoredLyricsEntry] = []
    private var isLoaded = false
    private var writeRevision = 0
    private var saveTask: Task<Void, Never>?

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lyrics-library.json")
    }

#if DEBUG
    init(fileURLForTesting: URL) {
        fileURL = fileURLForTesting
    }

    var storedEntriesForTesting: [StoredLyricsEntry] { entries }
#endif

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        let url = fileURL
        entries = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return [] }
            if let decoded = try? JSONDecoder().decode([StoredLyricsEntry].self, from: data) {
                return decoded.sorted { $0.updatedAt > $1.updatedAt }
            }
            return []
        }.value
        isLoaded = true
        if dropRetiredSources() {
            await persistNow()
        }
    }

    func entry(for track: Track) async -> StoredLyricsEntry? {
        await loadIfNeeded()
        if let exact = entries.first(where: { $0.trackKey == track.key }) {
            return exact
        }
        return entries.first(where: { $0.trackKey.matches(track) })
    }

    func save(
        document: LyricsDocument,
        offsetMilliseconds: Int,
        offsetIsUserSet: Bool = false,
        for track: Track
    ) async {
        guard !document.result.provider.isRetired else {
            await clear(for: track)
            return
        }
        await loadIfNeeded()
        replace(
            StoredLyricsEntry(
                trackKey: track.key,
                document: document,
                offsetMilliseconds: offsetMilliseconds,
                offsetIsUserSet: offsetIsUserSet,
                updatedAt: Date(),
                missExpiresAt: nil),
            for: track)
        await persistNow()
    }

    func saveMiss(for track: Track, now: Date = Date()) async {
        await loadIfNeeded()
        replace(
            StoredLyricsEntry(
                trackKey: track.key,
                document: nil,
                offsetMilliseconds: 0,
                updatedAt: now,
                missExpiresAt: now.addingTimeInterval(Self.missCacheTTL)),
            for: track)
        await persistNow()
    }

    func clear(for track: Track) async {
        await loadIfNeeded()
        entries.removeAll { $0.trackKey == track.key || $0.trackKey.matches(track) }
        await persistNow()
    }

    func updateOffset(_ offsetMilliseconds: Int, userSet: Bool = true, for track: Track) async {
        await loadIfNeeded()
        guard let index = entries.firstIndex(where: { $0.trackKey == track.key })
                ?? entries.firstIndex(where: { $0.trackKey.matches(track) }) else { return }
        var entry = entries.remove(at: index)
        entry.offsetMilliseconds = offsetMilliseconds
        entry.offsetIsUserSet = userSet
        entry.updatedAt = Date()
        entries.insert(entry, at: 0)
        scheduleSave()
    }

    func flush() async {
        await loadIfNeeded()
        saveTask?.cancel()
        await persistNow()
    }

    private func dropRetiredSources() -> Bool {
        let before = entries.count
        entries.removeAll { $0.document?.result.provider.isRetired == true }
        return entries.count != before
    }

    private func replace(_ entry: StoredLyricsEntry, for track: Track) {
        entries.removeAll { $0.trackKey == track.key }
        entries.insert(entry, at: 0)
        if entries.count > 300 {
            entries.removeLast(entries.count - 300)
        }
    }

    private func scheduleSave() {
        let snapshot = entries
        saveTask?.cancel()
        let revision = nextRevision()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            do {
                try await self.write(snapshot, revision: revision)
            } catch {
                log.error("save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func persistNow() async {
        let revision = nextRevision()
        do {
            try await write(entries, revision: revision)
        } catch {
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func write(_ snapshot: [StoredLyricsEntry], revision: Int) async throws {
        let data = try await Task.detached(priority: .background) {
            try JSONEncoder().encode(snapshot)
        }.value
        try await fileWriter.write(data, revision: revision, to: fileURL)
    }

    private func nextRevision() -> Int {
        writeRevision += 1
        return writeRevision
    }
}
