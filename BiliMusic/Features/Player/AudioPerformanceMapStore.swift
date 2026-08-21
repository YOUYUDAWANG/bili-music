import Foundation
import OSLog

private let audioPerformanceStoreLog = Logger(
    subsystem: "com.fubuki.BiliMusic",
    category: "audio-performance-map-store")

private struct StoredAudioPerformanceMap: Codable, Equatable, Sendable {
    let trackKey: TrackKey
    let audioFingerprint: String
    let map: AudioPerformanceMapV2
    let updatedAt: Date
}

actor AudioPerformanceMapStore {
    static let shared = AudioPerformanceMapStore()

    private static let maximumEntryCount = 120

    private let fileURL: URL
    private let fileWriter = VersionedAtomicFileWriter()
    private var entries: [StoredAudioPerformanceMap] = []
    private var isLoaded = false
    private var revision = 0

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio-performance-maps-v2.json")
    }

#if DEBUG
    init(fileURLForTesting: URL) {
        fileURL = fileURLForTesting
    }
#endif

    func map(
        for trackKey: TrackKey,
        audioFingerprint: String,
        analysisVersion: String = AudioPerformanceMapV2Version.analyzer
    ) async -> AudioPerformanceMapV2? {
        await loadIfNeeded()
        guard let entry = entry(for: trackKey),
              entry.audioFingerprint == audioFingerprint else { return nil }
        return entry.map.validated(
            expectedAudioFingerprint: audioFingerprint,
            expectedAnalysisVersion: analysisVersion)
    }

    /// A compact fact map remains useful after the much larger cached audio is
    /// evicted. Callers with a live local file must still prefer fingerprinted
    /// lookup so a replacement recording cannot reuse stale facts.
    func latestMap(
        for trackKey: TrackKey,
        analysisVersion: String = AudioPerformanceMapV2Version.analyzer
    ) async -> AudioPerformanceMapV2? {
        await loadIfNeeded()
        guard let entry = entry(for: trackKey) else { return nil }
        return entry.map.validated(
            expectedAudioFingerprint: entry.audioFingerprint,
            expectedAnalysisVersion: analysisVersion)
    }

    func save(_ map: AudioPerformanceMapV2, for trackKey: TrackKey) async throws {
        await loadIfNeeded()
        guard let safe = map.validated(expectedAudioFingerprint: map.audioFingerprint) else {
            throw AudioPerformanceAnalysisError.invalidMap
        }
        entries.removeAll { entry in
            entry.trackKey == trackKey
                || (trackKey.cid != nil
                    && entry.trackKey.bvid == trackKey.bvid
                    && entry.trackKey.cid == nil)
        }
        entries.insert(
            StoredAudioPerformanceMap(
                trackKey: trackKey,
                audioFingerprint: safe.audioFingerprint,
                map: safe,
                updatedAt: Date()),
            at: 0)
        if entries.count > Self.maximumEntryCount {
            entries.removeLast(entries.count - Self.maximumEntryCount)
        }
        try await persist()
    }

    func remove(for trackKey: TrackKey) async throws {
        await loadIfNeeded()
        let previousCount = entries.count
        entries.removeAll { $0.trackKey == trackKey }
        guard entries.count != previousCount else { return }
        try await persist()
    }

    private func loadIfNeeded() async {
        guard !isLoaded else { return }
        let url = fileURL
        let loaded = await Task.detached(priority: .utility) { () -> [StoredAudioPerformanceMap] in
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([StoredAudioPerformanceMap].self, from: data) else {
                return []
            }
            return decoded.filter { entry in
                entry.audioFingerprint == entry.map.audioFingerprint
                    && entry.map.validated(expectedAudioFingerprint: entry.audioFingerprint) != nil
            }
        }.value
        entries = loaded.sorted { $0.updatedAt > $1.updatedAt }
        if entries.count > Self.maximumEntryCount {
            entries.removeLast(entries.count - Self.maximumEntryCount)
        }
        isLoaded = true
    }

    private func persist() async throws {
        revision += 1
        let currentRevision = revision
        let snapshot = entries
        do {
            let data = try await Task.detached(priority: .background) {
                try JSONEncoder().encode(snapshot)
            }.value
            try await fileWriter.write(data, revision: currentRevision, to: fileURL)
        } catch {
            audioPerformanceStoreLog.error("save failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func entry(for trackKey: TrackKey) -> StoredAudioPerformanceMap? {
        if trackKey.cid != nil {
            if let exact = entries.first(where: { $0.trackKey == trackKey }) {
                return exact
            }
            let unresolved = entries.filter {
                $0.trackKey.bvid == trackKey.bvid && $0.trackKey.cid == nil
            }
            guard unresolved.count == 1 else { return nil }
            return unresolved[0]
        }
        let candidates = entries.filter { $0.trackKey.bvid == trackKey.bvid }
        guard candidates.count == 1 else { return nil }
        return candidates[0]
    }
}

@MainActor
final class AudioPerformanceAnalysisService {
    typealias LocalAudioURLProvider = @MainActor @Sendable (Track) -> URL?

    static let shared = AudioPerformanceAnalysisService()

    private let store: AudioPerformanceMapStore
    private let analyzer: any AudioPerformanceAnalyzing
    private let localAudioURLProvider: LocalAudioURLProvider
    private var inFlight: [AnalysisRequestKey: Task<AudioPerformanceMapV2, Error>] = [:]

    private struct AnalysisRequestKey: Hashable {
        let trackKey: TrackKey
        let audioFingerprint: String
    }

    init(
        store: AudioPerformanceMapStore = .shared,
        analyzer: any AudioPerformanceAnalyzing = LocalAudioPerformanceAnalyzer(),
        localAudioURLProvider: @escaping LocalAudioURLProvider = { track in
            CacheStore.shared.localAudioURL(for: track)
        }
    ) {
        self.store = store
        self.analyzer = analyzer
        self.localAudioURLProvider = localAudioURLProvider
    }

    func cachedMap(for track: Track) async throws -> AudioPerformanceMapV2? {
        if let localURL = localAudioURL(for: track) {
            let fingerprint = try await fingerprint(for: localURL)
            return await store.map(for: track.key, audioFingerprint: fingerprint)
        }
        return await store.latestMap(for: track.key)
    }

    func analyzeCachedAudio(for track: Track) async throws -> AudioPerformanceMapV2 {
        let localURL = try requireLocalAudioURL(for: track)
        let fingerprint = try await fingerprint(for: localURL)
        if let existing = await store.map(for: track.key, audioFingerprint: fingerprint) {
            return existing
        }
        let requestKey = AnalysisRequestKey(trackKey: track.key, audioFingerprint: fingerprint)
        if let existingTask = inFlight[requestKey] {
            return try await existingTask.value
        }

        let analyzer = self.analyzer
        let store = self.store
        let key = track.key
        let task = Task<AudioPerformanceMapV2, Error> {
            let result = try await analyzer.analyzeCachedAudio(
                at: localURL,
                audioFingerprint: fingerprint)
            guard let safe = result.validated(expectedAudioFingerprint: fingerprint) else {
                throw AudioPerformanceAnalysisError.invalidMap
            }
            try await store.save(safe, for: key)
            return safe
        }
        inFlight[requestKey] = task
        defer { inFlight[requestKey] = nil }
        return try await task.value
    }

    private func requireLocalAudioURL(for track: Track) throws -> URL {
        guard let url = localAudioURL(for: track) else {
            throw AudioPerformanceAnalysisError.localAudioUnavailable
        }
        return url
    }

    private func localAudioURL(for track: Track) -> URL? {
        guard let url = localAudioURLProvider(track),
              url.isFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func fingerprint(for url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            try AudioPerformanceFingerprint.audioFile(at: url)
        }.value
    }
}
