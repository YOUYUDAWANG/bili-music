import Foundation
import Observation
import OSLog

private let libraryLog = Logger(subsystem: "com.fubuki.BiliMusic", category: "library")

/// 本地音乐库：系统「我喜欢」+ B 站收藏夹的离线缓存。
@Observable
@MainActor
final class LibraryStore {
    static let shared = LibraryStore()
    static let schemaVersion = 1
    static let maxEntries = 800

    private(set) var collections: [LibraryCollection] = [LibraryCollection.liked()]
    private(set) var entries: [LibraryEntry] = []
    private(set) var memberships: [LibraryMembership] = []
    private(set) var isLoaded = false

    private let fileURL: URL
    private let fileWriter = VersionedAtomicFileWriter()
    private var writeRevision = 0
    private var saveTask: Task<Void, Never>?
    private var loadStartVersion = 0
    private var mutationVersion = 0
    private var loadTask: Task<LibrarySnapshot, Never>?

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("music-library.json")
    }

#if DEBUG
    init(fileURLForTesting: URL) {
        fileURL = fileURLForTesting
    }
#endif

    var likedCollection: LibraryCollection {
        collections.first(where: \.isLiked) ?? .liked()
    }

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        startLoadIfNeeded()
        guard let loadTask else { return }
        let startedAt = loadStartVersion
        let loaded = await loadTask.value
        applyLoaded(loaded, startedAt: startedAt)
    }

    func isLiked(_ track: Track) -> Bool {
        let ids = entryIDs(matching: track)
        return memberships.contains {
            $0.collectionId == LibraryCollection.likedID && ids.contains($0.entryId)
        }
    }

    func tracks(in collectionId: String) -> [Track] {
        let entryIDs = memberships
            .filter { $0.collectionId == collectionId }
            .sorted { $0.addedAt > $1.addedAt }
            .map(\.entryId)
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.track) })
        return entryIDs.compactMap { byID[$0] }
    }

    func tracks(forRemoteFolder folderId: Int) -> [Track] {
        tracks(in: LibraryCollection.remoteID(folderId))
    }

    func remoteCollections() -> [LibraryCollection] {
        collections
            .filter(\.isRemote)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func toggleLiked(_ track: Track) {
        mutate {
            if isLiked(track) {
                removeLocked(track, from: LibraryCollection.likedID)
            } else {
                upsertLocked(track, into: LibraryCollection.likedID, collectionName: "我喜欢")
            }
        }
    }

    func addLiked(_ track: Track) {
        mutate {
            upsertLocked(track, into: LibraryCollection.likedID, collectionName: "我喜欢")
        }
    }

    func upsert(_ track: Track, intoRemote folderId: Int, title: String) {
        mutate {
            upsertLocked(
                track,
                into: LibraryCollection.remoteID(folderId),
                collectionName: title,
                remoteId: folderId)
        }
    }

    func remove(_ track: Track, fromRemote folderId: Int) {
        mutate {
            removeLocked(track, from: LibraryCollection.remoteID(folderId))
            if let collection = collections.first(where: { $0.remoteId == folderId }) {
                upsertCollectionLocked(collection)
            }
        }
    }

    func replaceRemoteFolder(id folderId: Int, title: String, tracks: [Track]) {
        mutate {
            let collectionId = LibraryCollection.remoteID(folderId)
            memberships.removeAll { $0.collectionId == collectionId }
            for track in tracks {
                upsertLocked(
                    track,
                    into: collectionId,
                    collectionName: title,
                    remoteId: folderId)
            }
            let cover = tracks.first(where: { $0.coverURL != nil })?.coverURL
            upsertCollectionLocked(
                LibraryCollection.remote(
                    folderId: folderId,
                    name: title,
                    itemCount: tracks.count,
                    coverURL: cover))
        }
    }

    func rememberRemoteFolder(id folderId: Int, title: String, itemCount: Int, coverURL: URL?) {
        mutate {
            var collection = collections.first(where: { $0.remoteId == folderId })
                ?? LibraryCollection.remote(folderId: folderId, name: title, itemCount: itemCount, coverURL: coverURL)
            collection.name = title
            collection.itemCount = max(itemCount, tracks(in: collection.id).count)
            if let coverURL {
                collection.coverURL = coverURL
            }
            collection.updatedAt = Date()
            upsertCollectionLocked(collection)
        }
    }

    func flush() async {
        await loadIfNeeded()
        saveTask?.cancel()
        let revision = nextRevision()
        do {
            try await write(snapshot(), revision: revision)
        } catch {
            libraryLog.error("flush failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func mutate(_ body: () -> Void) {
        if !isLoaded {
            startLoadIfNeeded()
        }
        mutationVersion += 1
        body()
        refreshLikedCount()
        trimIfNeeded()
        scheduleSave()
    }

    private func upsertLocked(
        _ track: Track,
        into collectionId: String,
        collectionName: String,
        remoteId: Int? = nil
    ) {
        let now = Date()
        let entryID = resolvedEntryID(for: track)
        if let index = entries.firstIndex(where: { $0.id == entryID }) {
            var existing = entries.remove(at: index)
            if existing.track.cid == nil, track.cid != nil {
                existing.track = track
                existing.id = LibraryEntry.entryID(for: track)
            } else {
                existing.track = track
            }
            existing.updatedAt = now
            entries.insert(existing, at: 0)
        } else {
            entries.insert(LibraryEntry(id: entryID, track: track, updatedAt: now), at: 0)
        }
        let resolvedID = entries.first(where: { $0.track.bvid == track.bvid })?.id ?? entryID
        if !memberships.contains(where: { $0.collectionId == collectionId && $0.entryId == resolvedID }) {
            memberships.insert(LibraryMembership.make(collectionId: collectionId, entryId: resolvedID, now: now), at: 0)
        }
        if collectionId == LibraryCollection.likedID {
            upsertCollectionLocked(collections.first(where: \.isLiked) ?? .liked(now: now))
        } else if let remoteId {
            upsertCollectionLocked(
                collections.first(where: { $0.id == collectionId })
                    ?? LibraryCollection.remote(
                        folderId: remoteId,
                        name: collectionName,
                        itemCount: 0,
                        coverURL: track.coverURL,
                        now: now))
        }
    }

    private func removeLocked(_ track: Track, from collectionId: String) {
        let ids = entryIDs(matching: track)
        memberships.removeAll { $0.collectionId == collectionId && ids.contains($0.entryId) }
    }

    private func entryIDs(matching track: Track) -> Set<String> {
        var ids: Set<String> = [LibraryEntry.entryID(for: track), track.bvid]
        for entry in entries where entry.track.bvid == track.bvid {
            if entry.track.cid == nil || track.cid == nil || entry.track.cid == track.cid {
                ids.insert(entry.id)
            }
        }
        return ids
    }

    private func resolvedEntryID(for track: Track) -> String {
        if let existing = entries.first(where: { $0.track.bvid == track.bvid && ($0.track.cid == track.cid || $0.track.cid == nil || track.cid == nil) }) {
            if existing.track.cid == nil, track.cid != nil {
                return LibraryEntry.entryID(for: track)
            }
            return existing.id
        }
        return LibraryEntry.entryID(for: track)
    }

    private func upsertCollectionLocked(_ collection: LibraryCollection) {
        var next = collection
        next.itemCount = memberships.filter { $0.collectionId == collection.id }.count
        next.updatedAt = Date()
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index] = next
        } else {
            collections.append(next)
        }
        collections.sort { lhs, rhs in
            if lhs.isLiked != rhs.isLiked { return lhs.isLiked }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func refreshLikedCount() {
        upsertCollectionLocked(collections.first(where: \.isLiked) ?? .liked())
    }

    private func trimIfNeeded() {
        guard entries.count > Self.maxEntries else { return }
        let referenced = Set(memberships.map(\.entryId))
        entries.removeAll { !referenced.contains($0.id) }
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
            let kept = Set(entries.map(\.id))
            memberships.removeAll { !kept.contains($0.entryId) }
        }
    }

    private func startLoadIfNeeded() {
        guard loadTask == nil, !isLoaded else { return }
        loadStartVersion = mutationVersion
        let url = fileURL
        loadTask = Task.detached(priority: .utility) {
            Self.read(from: url)
        }
    }

    private func applyLoaded(_ loaded: LibrarySnapshot, startedAt: Int) {
        guard !isLoaded else { return }
        isLoaded = true
        loadTask = nil
        if mutationVersion == startedAt {
            collections = loaded.collections
            entries = loaded.entries
            memberships = loaded.memberships
        } else {
            merge(loaded)
        }
        if !collections.contains(where: \.isLiked) {
            collections.insert(.liked(), at: 0)
        }
        refreshLikedCount()
        if mutationVersion != startedAt {
            scheduleSave()
        }
    }

    private func merge(_ loaded: LibrarySnapshot) {
        var collectionByID = Dictionary(uniqueKeysWithValues: loaded.collections.map { ($0.id, $0) })
        for collection in collections {
            collectionByID[collection.id] = collection
        }
        collections = Array(collectionByID.values)
        var entryByID = Dictionary(uniqueKeysWithValues: loaded.entries.map { ($0.id, $0) })
        for entry in entries {
            entryByID[entry.id] = entry
        }
        entries = Array(entryByID.values)
        var membershipByID = Dictionary(uniqueKeysWithValues: loaded.memberships.map { ($0.id, $0) })
        for membership in memberships {
            membershipByID[membership.id] = membership
        }
        memberships = Array(membershipByID.values)
    }

    private func snapshot() -> LibrarySnapshot {
        LibrarySnapshot(
            version: Self.schemaVersion,
            collections: collections,
            entries: entries,
            memberships: memberships)
    }

    private func scheduleSave() {
        let payload = snapshot()
        saveTask?.cancel()
        let revision = nextRevision()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            do {
                try await self.write(payload, revision: revision)
            } catch {
                libraryLog.error("save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func write(_ snapshot: LibrarySnapshot, revision: Int) async throws {
        let url = fileURL
        let data = try await Task.detached(priority: .background) {
            try JSONEncoder().encode(snapshot)
        }.value
        try await fileWriter.write(data, revision: revision, to: url)
    }

    private func nextRevision() -> Int {
        writeRevision += 1
        return writeRevision
    }

    nonisolated private static func read(from url: URL) -> LibrarySnapshot {
        let empty = LibrarySnapshot(
            version: 1,
            collections: [.liked()],
            entries: [],
            memberships: [])
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LibrarySnapshot.self, from: data),
              decoded.version >= 1 else {
            return empty
        }
        var snapshot = decoded
        if !snapshot.collections.contains(where: \.isLiked) {
            snapshot.collections.insert(.liked(), at: 0)
        }
        return snapshot
    }
}
