import XCTest
@testable import BiliMusic

@MainActor
final class LibraryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testLikedToggleAndRemoteCachePersist() async throws {
        let url = directory.appendingPathComponent("music-library.json")
        let store = LibraryStore(fileURLForTesting: url)
        let track = Track(
            bvid: "BVLIKE001",
            cid: 11,
            title: "晴天",
            artist: "周杰伦",
            coverURL: URL(string: "https://example.com/a.jpg"),
            duration: 269)

        store.toggleLiked(track)
        XCTAssertTrue(store.isLiked(track))
        XCTAssertEqual(store.tracks(in: LibraryCollection.likedID).map(\.bvid), ["BVLIKE001"])

        store.replaceRemoteFolder(id: 88, title: "音乐", tracks: [track])
        XCTAssertEqual(store.tracks(forRemoteFolder: 88).map(\.bvid), ["BVLIKE001"])
        XCTAssertEqual(store.remoteCollections().first?.name, "音乐")

        await store.flush()

        let reloaded = LibraryStore(fileURLForTesting: url)
        await reloaded.loadIfNeeded()
        XCTAssertTrue(reloaded.isLiked(track))
        XCTAssertEqual(reloaded.tracks(forRemoteFolder: 88).first?.title, "晴天")
        XCTAssertTrue(reloaded.collections.contains(where: \.isLiked))
    }

    func testRemovingLikedKeepsRemoteMembership() async {
        let url = directory.appendingPathComponent("music-library.json")
        let store = LibraryStore(fileURLForTesting: url)
        let track = Track(bvid: "BVKEEP", cid: 2, title: "Stay", artist: "A", coverURL: nil, duration: 180)

        store.addLiked(track)
        store.upsert(track, intoRemote: 3, title: "默认收藏夹")
        store.toggleLiked(track)

        XCTAssertFalse(store.isLiked(track))
        XCTAssertEqual(store.tracks(forRemoteFolder: 3).map(\.bvid), ["BVKEEP"])
    }
}
