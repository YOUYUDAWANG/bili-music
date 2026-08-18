import Foundation
import OSLog

private let metadataStoreLog = Logger(subsystem: "com.fubuki.BiliMusic", category: "track-metadata-store")

struct NormalizedTrackMetadata: Codable, Equatable, Sendable {
    let canonicalTitle: String
    let artists: [String]
    let performers: [String]
    let uploader: String?
    let language: String
    let aliases: [String]
    let searchQueries: [String]
    let confidence: Double
    let needsReview: Bool
    let serviceVersion: String

    func applying(to track: Track) -> Track {
        var result = track
        let title = canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        result.title = title.isEmpty ? track.title : title
        result.artist = displayArtist(fallback: track.artist)
        return result
    }

    func displayArtist(fallback: String) -> String {
        let candidate = artists.first ?? performers.first ?? uploader
        let cleaned = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? fallback : cleaned
    }
}

struct StoredTrackMetadataEntry: Codable, Equatable, Sendable {
    var trackKey: TrackKey
    let sourceTitle: String
    let sourceArtist: String
    let metadata: NormalizedTrackMetadata
    let updatedAt: Date
}

final class TrackMetadataStore: @unchecked Sendable {
    static let shared = TrackMetadataStore()

    private let fileURL: URL
    private let fileWriter = VersionedAtomicFileWriter()
    private let lock = NSLock()
    private var entries: [StoredTrackMetadataEntry]
    private var writeRevision = 0

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("track-metadata.json")
        entries = Self.read(from: fileURL)
    }

#if DEBUG
    init(fileURLForTesting: URL) {
        fileURL = fileURLForTesting
        entries = Self.read(from: fileURLForTesting)
    }
#endif

    func entry(for track: Track) -> StoredTrackMetadataEntry? {
        lock.withLock {
            entries.first(where: { $0.trackKey == track.key })
                ?? entries.first(where: { $0.trackKey.matches(track) })
        }
    }

    func applyingCachedMetadata(to track: Track) -> Track {
        entry(for: track)?.metadata.applying(to: track) ?? track
    }

    func save(_ metadata: NormalizedTrackMetadata, for sourceTrack: Track) async {
        let update = lock.withLock { () -> (entries: [StoredTrackMetadataEntry], revision: Int) in
            entries.removeAll { $0.trackKey.matches(sourceTrack) }
            entries.insert(
                StoredTrackMetadataEntry(
                    trackKey: sourceTrack.key,
                    sourceTitle: sourceTrack.title,
                    sourceArtist: sourceTrack.artist,
                    metadata: metadata,
                    updatedAt: Date()),
                at: 0)
            if entries.count > 500 {
                entries.removeLast(entries.count - 500)
            }
            writeRevision += 1
            return (entries, writeRevision)
        }

        do {
            let data = try await Task.detached(priority: .background) {
                try JSONEncoder().encode(update.entries)
            }.value
            try await fileWriter.write(data, revision: update.revision, to: fileURL)
            await MainActor.run {
                NotificationCenter.default.post(name: .trackMetadataDidChange, object: sourceTrack.key)
            }
        } catch {
            metadataStoreLog.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func read(from url: URL) -> [StoredTrackMetadataEntry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([StoredTrackMetadataEntry].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.updatedAt > $1.updatedAt }
    }
}

extension Notification.Name {
    static let trackMetadataDidChange = Notification.Name("BiliMusic.trackMetadataDidChange")
}

protocol TrackMetadataNormalizing: Sendable {
    func normalize(_ track: Track) async throws -> NormalizedTrackMetadata
}

actor TrackMetadataResolver {
    private let store: TrackMetadataStore
    private let normalizer: any TrackMetadataNormalizing
    private var inFlight: [TrackKey: Task<NormalizedTrackMetadata, Error>] = [:]

    init(store: TrackMetadataStore = .shared, normalizer: any TrackMetadataNormalizing) {
        self.store = store
        self.normalizer = normalizer
    }

    func resolve(_ track: Track) async throws -> Track {
        if let cached = store.entry(for: track) {
            return cached.metadata.applying(to: track)
        }

        let task: Task<NormalizedTrackMetadata, Error>
        let taskKey: TrackKey
        if let existing = inFlight.first(where: { $0.key.matches(track) }) {
            taskKey = existing.key
            task = existing.value
        } else {
            taskKey = track.key
            task = Task { try await normalizer.normalize(track) }
            inFlight[taskKey] = task
        }

        do {
            let metadata = try await task.value
            inFlight[taskKey] = nil
            await store.save(metadata, for: track)
            return metadata.applying(to: track)
        } catch {
            inFlight[taskKey] = nil
            throw error
        }
    }
}
