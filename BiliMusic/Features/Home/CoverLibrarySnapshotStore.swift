import Foundation

struct CoverLibrarySnapshot: Codable {
    var folderID: Int
    var savedAt: Date
    var tracks: [Track]
    var discoveryTracks: [Track]

    enum CodingKeys: String, CodingKey {
        case folderID, savedAt, tracks, discoveryTracks
    }

    init(folderID: Int, savedAt: Date, tracks: [Track], discoveryTracks: [Track] = []) {
        self.folderID = folderID
        self.savedAt = savedAt
        self.tracks = tracks
        self.discoveryTracks = discoveryTracks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folderID = try container.decode(Int.self, forKey: .folderID)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        tracks = try container.decode([Track].self, forKey: .tracks)
        discoveryTracks = try container.decodeIfPresent([Track].self, forKey: .discoveryTracks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(folderID, forKey: .folderID)
        try container.encode(savedAt, forKey: .savedAt)
        try container.encode(tracks, forKey: .tracks)
        try container.encode(discoveryTracks, forKey: .discoveryTracks)
    }
}

actor CoverLibrarySnapshotStore {
    static let shared = CoverLibrarySnapshotStore()

    private let fileURL: URL

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cover-library.json")
    }

#if DEBUG
    init(fileURLForTesting: URL) {
        fileURL = fileURLForTesting
    }
#endif

    func load(preferredFolderID: Int) -> CoverLibrarySnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(CoverLibrarySnapshot.self, from: data),
              preferredFolderID == 0 || preferredFolderID == snapshot.folderID else {
            return nil
        }
        return snapshot
    }

    func save(folderID: Int, tracks: [Track], discoveryTracks: [Track] = []) {
        let snapshot = CoverLibrarySnapshot(
            folderID: folderID,
            savedAt: Date(),
            tracks: Array(Track.uniquedByBVIDPreferringCID(tracks).prefix(480)),
            discoveryTracks: Array(Track.uniquedByBVIDPreferringCID(discoveryTracks).prefix(48)))
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func enrichCID(_ cid: Int, for bvid: String) {
        guard cid > 0,
              let data = try? Data(contentsOf: fileURL),
              var snapshot = try? JSONDecoder().decode(CoverLibrarySnapshot.self, from: data) else {
            return
        }
        var changed = false
        func enrich(_ track: Track) -> Track {
            guard track.bvid == bvid, track.cid == nil else { return track }
            var updated = track
            updated.cid = cid
            changed = true
            return updated
        }
        snapshot.tracks = snapshot.tracks.map(enrich)
        snapshot.discoveryTracks = snapshot.discoveryTracks.map(enrich)
        guard changed, let encoded = try? JSONEncoder().encode(snapshot) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }
}
