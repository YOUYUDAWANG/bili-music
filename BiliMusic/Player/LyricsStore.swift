import Foundation
import OSLog

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "lyrics-store")

struct StoredLyricsEntry: Codable, Equatable, Sendable {
    var trackKey: TrackKey
    var document: LyricsDocument
    var offsetMilliseconds: Int
    var updatedAt: Date
}

@MainActor
final class LyricsStore {
    static let shared = LyricsStore()

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
#endif

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        let url = fileURL
        entries = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([StoredLyricsEntry].self, from: data) else {
                return []
            }
            return decoded.sorted { $0.updatedAt > $1.updatedAt }
        }.value
        isLoaded = true
    }

    func entry(for track: Track) async -> StoredLyricsEntry? {
        await loadIfNeeded()
        if let exact = entries.first(where: { $0.trackKey == track.key }) {
            return exact
        }
        return entries.first(where: { $0.trackKey.matches(track) })
    }

    func save(document: LyricsDocument, offsetMilliseconds: Int, for track: Track) async {
        await loadIfNeeded()
        let entry = StoredLyricsEntry(
            trackKey: track.key,
            document: document,
            offsetMilliseconds: offsetMilliseconds,
            updatedAt: Date())
        if let index = entries.firstIndex(where: { $0.trackKey.matches(track) }) {
            entries.remove(at: index)
        }
        entries.insert(entry, at: 0)
        if entries.count > 300 {
            entries.removeLast(entries.count - 300)
        }
        let revision = nextRevision()
        do {
            try await write(entries, revision: revision)
        } catch {
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func updateOffset(_ offsetMilliseconds: Int, for track: Track) async {
        await loadIfNeeded()
        guard let index = entries.firstIndex(where: { $0.trackKey.matches(track) }) else { return }
        var entry = entries.remove(at: index)
        entry.offsetMilliseconds = offsetMilliseconds
        entry.updatedAt = Date()
        entries.insert(entry, at: 0)
        scheduleSave()
    }

    func flush() async {
        await loadIfNeeded()
        saveTask?.cancel()
        let revision = nextRevision()
        do {
            try await write(entries, revision: revision)
        } catch {
            log.error("flush failed: \(error.localizedDescription, privacy: .public)")
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
