import XCTest
@testable import BiliMusic

@MainActor
final class CacheStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bili-music-cache-store-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        super.tearDown()
    }

    func testLegacyIndexWithoutAccessedAtStillDecodes() throws {
        let original = makeEntry(index: 1)
        let encoded = try JSONEncoder().encode([original])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        object[0].removeValue(forKey: "accessedAt")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode([CachedEntry].self, from: stripped)
        XCTAssertEqual(decoded.first?.bvid, "BVCACHE001")
        XCTAssertNil(decoded.first?.accessedAt)
        XCTAssertEqual(decoded.first?.lastAccessedAt, decoded.first?.downloadedAt)
    }

    func testAddPersistingEvictsOldestBeyondLimit() async throws {
        let audioDir = tempDir.appendingPathComponent("audio", isDirectory: true)
        let cache = CacheStore(
            indexURLForTesting: tempDir.appendingPathComponent("cache_index.json"),
            audioDirForTesting: audioDir)
        await cache.loadIfNeeded()

        for index in 1...CacheStore.maxEntryCount {
            let entry = makeEntry(index: index)
            try writeAudioFile(named: entry.fileName, in: audioDir)
            try await cache.addPersisting(entry)
        }
        XCTAssertEqual(cache.entries.count, CacheStore.maxEntryCount)
        XCTAssertEqual(cache.entries.last?.bvid, "BVCACHE001")

        let overflow = makeEntry(index: CacheStore.maxEntryCount + 1)
        try writeAudioFile(named: overflow.fileName, in: audioDir)
        try await cache.addPersisting(overflow)

        XCTAssertEqual(cache.entries.count, CacheStore.maxEntryCount)
        XCTAssertEqual(cache.entries.first?.bvid, overflow.bvid)
        XCTAssertNil(cache.entry(for: Track(bvid: "BVCACHE001", cid: 1, title: "1", artist: "A", coverURL: nil, duration: 180)))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("BVCACHE001_1.m4a").path))
        XCTAssertNotNil(cache.entry(for: overflow.track))
    }

    func testRetentionSkipsProtectedPlaybackKey() async throws {
        let audioDir = tempDir.appendingPathComponent("audio", isDirectory: true)
        let cache = CacheStore(
            indexURLForTesting: tempDir.appendingPathComponent("cache_index.json"),
            audioDirForTesting: audioDir)
        await cache.loadIfNeeded()

        for index in 1...CacheStore.maxEntryCount {
            let entry = makeEntry(index: index)
            try writeAudioFile(named: entry.fileName, in: audioDir)
            try await cache.addPersisting(entry)
        }
        let oldest = cache.entries.last!
        cache.setPlaybackProtectedKey(oldest.key)

        let overflow = makeEntry(index: CacheStore.maxEntryCount + 1)
        try writeAudioFile(named: overflow.fileName, in: audioDir)
        try await cache.addPersisting(overflow)

        XCTAssertEqual(cache.entries.count, CacheStore.maxEntryCount)
        XCTAssertNotNil(cache.entry(for: oldest.track))
        XCTAssertNil(cache.entry(for: Track(
            bvid: "BVCACHE002",
            cid: 2,
            title: "2",
            artist: "A",
            coverURL: nil,
            duration: 180)))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: audioDir.appendingPathComponent(oldest.fileName).path))
    }
}

private func makeEntry(index: Int) -> CachedEntry {
    let bvid = String(format: "BVCACHE%03d", index)
    return CachedEntry(
        bvid: bvid,
        cid: index,
        title: "\(index)",
        artist: "A",
        coverURL: nil,
        duration: 180,
        fileName: "\(bvid)_\(index).m4a",
        fileSize: 1024,
        downloadedAt: Date(timeIntervalSince1970: TimeInterval(index)),
        quality: 30280)
}

private func writeAudioFile(named fileName: String, in directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("audio".utf8).write(to: directory.appendingPathComponent(fileName))
}
