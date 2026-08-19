import Foundation

enum LibraryCollectionSource: String, Codable, Sendable {
    case local
    case remote
}

/// 本地音乐库里的一份歌单：系统「我喜欢」或缓存下来的 B 站收藏夹。
struct LibraryCollection: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var source: LibraryCollectionSource
    var remoteId: Int?
    var itemCount: Int
    var coverURL: URL?
    var lastSyncedAt: Date?
    var updatedAt: Date

    static let likedID = "liked"

    var isLiked: Bool { id == Self.likedID }
    var isRemote: Bool { source == .remote }

    static func liked(now: Date = Date()) -> LibraryCollection {
        LibraryCollection(
            id: likedID,
            name: "我喜欢",
            source: .local,
            remoteId: nil,
            itemCount: 0,
            coverURL: nil,
            lastSyncedAt: nil,
            updatedAt: now)
    }

    static func remoteID(_ folderId: Int) -> String { "remote:\(folderId)" }

    static func remote(
        folderId: Int,
        name: String,
        itemCount: Int,
        coverURL: URL?,
        now: Date = Date()
    ) -> LibraryCollection {
        LibraryCollection(
            id: remoteID(folderId),
            name: name,
            source: .remote,
            remoteId: folderId,
            itemCount: itemCount,
            coverURL: coverURL,
            lastSyncedAt: now,
            updatedAt: now)
    }
}

struct LibraryEntry: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var track: Track
    var updatedAt: Date

    static func make(from track: Track, now: Date = Date()) -> LibraryEntry {
        LibraryEntry(id: entryID(for: track), track: track, updatedAt: now)
    }

    static func entryID(for track: Track) -> String {
        if track.cid != nil {
            return track.key.description
        }
        return track.bvid
    }
}

struct LibraryMembership: Codable, Equatable, Sendable {
    var collectionId: String
    var entryId: String
    var addedAt: Date

    var id: String { "\(collectionId)::\(entryId)" }

    static func make(collectionId: String, entryId: String, now: Date = Date()) -> LibraryMembership {
        LibraryMembership(collectionId: collectionId, entryId: entryId, addedAt: now)
    }
}

struct LibrarySnapshot: Codable, Equatable, Sendable {
    var version: Int
    var collections: [LibraryCollection]
    var entries: [LibraryEntry]
    var memberships: [LibraryMembership]
}
