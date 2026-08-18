import XCTest
@testable import BiliMusic

@MainActor
final class PlaybackPersistenceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bili-music-playback-persistence-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        super.tearDown()
    }

    func testQueueWindowKeepsCurrentTrackWhenCapping() {
        let queue = (0..<250).map { index in
            Track(bvid: String(format: "BVCAP%03d", index), cid: index, title: "Song \(index)",
                  artist: "Artist", coverURL: nil, duration: 180)
        }
        let window = PlaybackQueueWindow.capped(queue: queue, index: 180, limit: 200)
        XCTAssertEqual(window.queue.count, 200)
        XCTAssertEqual(window.queue[window.index].bvid, "BVCAP180")
        XCTAssertTrue(window.queue.contains { $0.bvid == "BVCAP180" })
        XCTAssertTrue(window.queue.contains { $0.bvid == "BVCAP249" } || window.queue.contains { $0.bvid == "BVCAP130" })
    }

    func testRestorePausedQueueAndResumePosition() async {
        let url = tempDir.appendingPathComponent("playback-queue.json")
        let store = PlaybackQueueStore(fileURLForTesting: url)
        let tracks = [
            Track(bvid: "BVQUEUE001", cid: 11, title: "First", artist: "A", coverURL: nil, duration: 200),
            Track(bvid: "BVQUEUE002", cid: 22, title: "Second", artist: "A", coverURL: nil, duration: 210)
        ]
        store.replace(
            PersistedPlaybackQueue(
                version: 1,
                queue: tracks,
                queueIndex: 1,
                queueMode: .shuffle,
                resumePosition: 42,
                savedAt: Date()))
        await store.flush()

        var capturedResume: Double?
        let engine = PlayerEngine(
            streamResolver: PersistenceAudioResolver(),
            startupTestHooks: .init(startPlaybackOverride: { _, resumeAt, _ in
                capturedResume = resumeAt
            }),
            queueStore: store)

        await engine.restorePersistedQueueIfNeeded()

        XCTAssertEqual(engine.current?.bvid, "BVQUEUE002")
        XCTAssertEqual(engine.queue.count, 2)
        XCTAssertEqual(engine.queueMode, .shuffle)
        XCTAssertEqual(engine.currentTime, 42)
        XCTAssertFalse(engine.wantsPlayback)
        if case .paused = engine.state {
            // expected
        } else {
            XCTFail("restored queue should stay paused, got \(engine.state)")
        }

        engine.play()
        await waitBounded(description: "play() should start restored item") {
            capturedResume != nil
        }
        XCTAssertEqual(capturedResume, 42)
        XCTAssertTrue(engine.wantsPlayback)
    }

    func testPersistingRadioQueueRestoresAsSequential() async {
        let url = tempDir.appendingPathComponent("playback-queue.json")
        let store = PlaybackQueueStore(fileURLForTesting: url)
        let track = Track(bvid: "BVRADIO001", cid: 33, title: "Radio", artist: "A", coverURL: nil, duration: 180)
        let engine = PlayerEngine(
            streamResolver: PersistenceAudioResolver(cid: 33),
            startupTestHooks: .init(startPlaybackOverride: { _, _, _ in }),
            queueStore: store)

        await engine.playRadio(seed: track)
        await engine.flushPlaybackQueue()

        let saved = try? JSONDecoder().decode(PersistedPlaybackQueue.self, from: Data(contentsOf: url))
        XCTAssertEqual(saved?.queueMode, .sequential)
        XCTAssertEqual(saved?.queue.first?.bvid, "BVRADIO001")

        let restored = PlayerEngine(
            streamResolver: PersistenceAudioResolver(cid: 33),
            startupTestHooks: .init(startPlaybackOverride: { _, _, _ in }),
            queueStore: store)
        await restored.restorePersistedQueueIfNeeded()
        XCTAssertEqual(restored.queueMode, .sequential)
        XCTAssertEqual(restored.current?.bvid, "BVRADIO001")
    }

    func testFavItemDecodesFirstCID() throws {
        let json = """
        {
          "bvid": "BVFAV001",
          "title": "收藏歌曲",
          "cover": "https://example.invalid/cover.jpg",
          "duration": 188,
          "upper": { "name": "UP主" },
          "attr": 0,
          "ugc": { "first_cid": 778899 }
        }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(BiliClient.FavItem.self, from: json)
        XCTAssertEqual(item.resolvedCID, 778899)
        let track = Track(fav: item)
        XCTAssertEqual(track.cid, 778899)
        XCTAssertEqual(track.bvid, "BVFAV001")
    }

    func testUniquedTracksPreferResolvedCID() {
        let withoutCID = Track(
            bvid: "BVDUP001",
            title: "封面",
            artist: "A",
            coverURL: URL(string: "https://example.invalid/a.jpg"),
            duration: 180)
        let withCID = Track(
            bvid: "BVDUP001",
            cid: 1001,
            title: "封面",
            artist: "A",
            coverURL: URL(string: "https://example.invalid/a.jpg"),
            duration: 180)
        let other = Track(
            bvid: "BVDUP002",
            cid: 2002,
            title: "另一首",
            artist: "B",
            coverURL: URL(string: "https://example.invalid/b.jpg"),
            duration: 120)
        let uniqued = Track.uniquedByBVIDPreferringCID([withoutCID, other, withCID])
        XCTAssertEqual(uniqued.map(\.bvid), ["BVDUP001", "BVDUP002"])
        XCTAssertEqual(uniqued.first?.cid, 1001)
    }

    func testCoverLibrarySnapshotEnrichesCID() async throws {
        let url = tempDir.appendingPathComponent("cover-library.json")
        let store = CoverLibrarySnapshotStore(fileURLForTesting: url)
        let track = Track(
            bvid: "BVCOVER001",
            title: "封面歌",
            artist: "A",
            coverURL: URL(string: "https://example.invalid/cover.jpg"),
            duration: 180)
        await store.save(folderID: 9, tracks: [track])
        await store.enrichCID(445566, for: "BVCOVER001")
        let loaded = await store.load(preferredFolderID: 9)
        XCTAssertEqual(loaded?.tracks.first?.cid, 445566)
    }
}

@MainActor
private final class PersistenceAudioResolver: AudioStreamResolving {
    private let cid: Int

    init(cid: Int = 22) {
        self.cid = cid
    }

    func cachedAudio(for track: Track, preferredQuality: Int) -> StreamResolver.PreparedAudioStream? {
        stream(matching: track)
    }

    func invalidateAudio(for track: Track) {}

    func prepareAudio(for track: Track, preferredQuality: Int) async throws -> StreamResolver.PreparedAudioStream {
        stream(matching: track)
    }

    func warmAudioCDN(for track: Track, preferredQuality: Int) async {}

    private func stream(matching track: Track) -> StreamResolver.PreparedAudioStream {
        .init(
            url: URL(fileURLWithPath: "/tmp/persistence.m4a"),
            cid: track.cid ?? cid,
            duration: track.duration,
            quality: 30280,
            bandwidth: 192_000,
            fetchedAt: Date())
    }
}

@MainActor
private func waitBounded(
    description: String,
    timeout: TimeInterval = 5,
    until condition: @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    var yields = 0
    while !condition() {
        yields += 1
        if yields > 20_000 || Date() > deadline {
            XCTFail("timed out: \(description)")
            return
        }
        await Task.yield()
    }
}
