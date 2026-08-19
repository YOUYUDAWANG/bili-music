import Foundation
import OSLog

private let metadataStoreLog = Logger(subsystem: "com.fubuki.BiliMusic", category: "track-metadata-store")

struct NormalizedTrackMetadata: Equatable, Sendable {
    let canonicalTitle: String
    let originalArtists: [String]
    let coverPerformers: [String]
    let uploader: String?
    let language: String
    let aliases: [String]
    let lyricSearchQueries: [String]
    let isCover: Bool
    let confidence: Double
    let needsReview: Bool
    let serviceVersion: String

    var artists: [String] { originalArtists }
    var performers: [String] { coverPerformers }
    var searchQueries: [String] { lyricSearchQueries }

    func applying(to track: Track) -> Track {
        var result = track
        let title = canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        result.title = title.isEmpty ? track.title : title
        result.artist = displayArtist(fallback: track.artist)
        return result
    }

    func displayArtist(fallback: String) -> String {
        let originals = Self.cleaned(originalArtists)
        let covers = Self.cleaned(coverPerformers)
        if isCover, !covers.isEmpty, !originals.isEmpty {
            return "\(covers.joined(separator: " / "))（翻唱） · 原唱：\(originals.joined(separator: " / "))"
        }
        if isCover, !covers.isEmpty {
            return covers.joined(separator: " / ")
        }
        if !originals.isEmpty {
            return originals.joined(separator: " / ")
        }
        if !covers.isEmpty {
            return covers.joined(separator: " / ")
        }
        let cleanedUploader = uploader?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleanedUploader.isEmpty ? fallback : cleanedUploader
    }

    func coverVersionQueries() -> [String] {
        let title = LyricsAutoMatchGate.preferredSearchTitle(
            canonicalTitle: canonicalTitle,
            aliases: aliases)
        guard !title.isEmpty else { return [] }
        let performers = Self.cleaned(coverPerformers)
        guard !performers.isEmpty else { return [] }
        return Self.dedupeQueries(performers.map { "\(title) \($0)" })
    }

    func originalVersionQueries() -> [String] {
        let title = LyricsAutoMatchGate.preferredSearchTitle(
            canonicalTitle: canonicalTitle,
            aliases: aliases)
        guard !title.isEmpty else { return [] }
        var queries: [String] = []
        for artist in Self.cleaned(originalArtists) {
            queries.append("\(title) \(artist)")
        }
        queries.append(title)
        return Self.dedupeQueries(queries)
    }

    static func lyricSearchQueries(
        canonicalTitle: String,
        originalArtists: [String],
        coverPerformers: [String],
        aliases: [String]
    ) -> [String] {
        let title = LyricsAutoMatchGate.preferredSearchTitle(
            canonicalTitle: canonicalTitle,
            aliases: aliases)
        guard !title.isEmpty else { return [] }
        var queries: [String] = []
        for artist in cleaned(originalArtists) {
            queries.append("\(title) \(artist)")
        }
        queries.append(title)
        for performer in cleaned(coverPerformers) {
            queries.append("\(title) \(performer)")
        }
        return dedupeQueries(queries)
    }

    private static func dedupeQueries(_ queries: [String]) -> [String] {
        var seen = Set<String>()
        return queries.filter { query in
            let key = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted
        }
    }

    static func manual(
        canonicalTitle: String,
        originalArtists: [String],
        coverPerformers: [String],
        uploader: String?,
        aliases: [String] = [],
        isCover: Bool,
        serviceVersion: String
    ) -> NormalizedTrackMetadata {
        NormalizedTrackMetadata(
            canonicalTitle: canonicalTitle,
            originalArtists: cleaned(originalArtists),
            coverPerformers: cleaned(coverPerformers),
            uploader: uploader,
            language: "und",
            aliases: cleaned(aliases),
            lyricSearchQueries: lyricSearchQueries(
                canonicalTitle: canonicalTitle,
                originalArtists: originalArtists,
                coverPerformers: coverPerformers,
                aliases: aliases),
            isCover: isCover || !cleaned(coverPerformers).isEmpty,
            confidence: 1,
            needsReview: false,
            serviceVersion: serviceVersion)
    }

    private static func cleaned(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

extension NormalizedTrackMetadata: Codable {
    private enum CodingKeys: String, CodingKey {
        case canonicalTitle
        case originalArtists, artists
        case coverPerformers, performers
        case uploader, language, aliases
        case lyricSearchQueries, searchQueries
        case isCover, confidence, needsReview
        case serviceVersion, version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canonicalTitle = try container.decode(String.self, forKey: .canonicalTitle)
        originalArtists = Self.decodeNames(container, .originalArtists, .artists)
        coverPerformers = Self.decodeNames(container, .coverPerformers, .performers)
        uploader = try container.decodeIfPresent(String.self, forKey: .uploader)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "und"
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        lyricSearchQueries = Self.decodeNames(container, .lyricSearchQueries, .searchQueries)
        isCover = try container.decodeIfPresent(Bool.self, forKey: .isCover)
            ?? !coverPerformers.isEmpty
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        needsReview = try container.decodeIfPresent(Bool.self, forKey: .needsReview) ?? false
        serviceVersion = try container.decodeIfPresent(String.self, forKey: .serviceVersion)
            ?? container.decodeIfPresent(String.self, forKey: .version)
            ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(canonicalTitle, forKey: .canonicalTitle)
        try container.encode(originalArtists, forKey: .originalArtists)
        try container.encode(originalArtists, forKey: .artists)
        try container.encode(coverPerformers, forKey: .coverPerformers)
        try container.encode(coverPerformers, forKey: .performers)
        try container.encodeIfPresent(uploader, forKey: .uploader)
        try container.encode(language, forKey: .language)
        try container.encode(aliases, forKey: .aliases)
        try container.encode(lyricSearchQueries, forKey: .lyricSearchQueries)
        try container.encode(lyricSearchQueries, forKey: .searchQueries)
        try container.encode(isCover, forKey: .isCover)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(needsReview, forKey: .needsReview)
        try container.encode(serviceVersion, forKey: .serviceVersion)
    }

    private static func decodeNames(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ keys: CodingKeys...
    ) -> [String] {
        for key in keys {
            if let values = try? container.decode([String].self, forKey: key) {
                return values
            }
        }
        return []
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
            entries.removeAll { $0.trackKey == sourceTrack.key }
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
    private let requiredServiceVersion: String?
    private var inFlight: [TrackKey: Task<NormalizedTrackMetadata, Error>] = [:]

    init(
        store: TrackMetadataStore = .shared,
        normalizer: any TrackMetadataNormalizing,
        requiredServiceVersion: String? = nil
    ) {
        self.store = store
        self.normalizer = normalizer
        self.requiredServiceVersion = requiredServiceVersion
    }

    func resolve(_ track: Track, forceRefresh: Bool = false) async throws -> Track {
        if !forceRefresh,
           let cached = store.entry(for: track),
           requiredServiceVersion == nil || cached.metadata.serviceVersion == requiredServiceVersion {
            return cached.metadata.applying(to: track)
        }

        let task: Task<NormalizedTrackMetadata, Error>
        let taskKey: TrackKey
        if !forceRefresh, let existing = inFlight.first(where: { $0.key.matches(track) }) {
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
            await store.save(metadata, for: sourceTrack(from: track))
            return metadata.applying(to: track)
        } catch {
            inFlight[taskKey] = nil
            throw error
        }
    }

    private func sourceTrack(from track: Track) -> Track {
        if let stored = store.entry(for: track) {
            var source = track
            source.title = stored.sourceTitle
            source.artist = stored.sourceArtist
            return source
        }
        return track
    }
}
