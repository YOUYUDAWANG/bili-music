import Foundation

struct CoverLibrarySnapshot: Codable {
    var folderID: Int
    var savedAt: Date
    var tracks: [Track]
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

    func save(folderID: Int, tracks: [Track]) {
        let snapshot = CoverLibrarySnapshot(
            folderID: folderID,
            savedAt: Date(),
            tracks: Array(Track.uniquedByBVIDPreferringCID(tracks).prefix(480)))
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
        snapshot.tracks = snapshot.tracks.map { track in
            guard track.bvid == bvid, track.cid == nil else { return track }
            var updated = track
            updated.cid = cid
            changed = true
            return updated
        }
        guard changed, let encoded = try? JSONEncoder().encode(snapshot) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }
}
