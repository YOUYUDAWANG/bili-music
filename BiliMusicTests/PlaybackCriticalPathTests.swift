import MediaPlayer
import XCTest
@testable import BiliMusic

@MainActor
final class PlaybackCriticalPathTests: XCTestCase {
    override func tearDown() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        super.tearDown()
    }

    func testPlayAssignsCurrentBeforeAwaitedSourceResolutionCompletes() async {
        let track = Self.track()
        let resolver = CriticalPathAudioResolver(
            prepared: Self.stream(
                url: URL(string: "https://example.invalid/prepared.m4a")!,
                cid: 1001,
                duration: 211,
                quality: 30280,
                bandwidth: 192_000))
        var currentDuringResolution: Track?
        resolver.onPrepare = { (engine: PlayerEngine) in
            currentDuringResolution = engine.current
        }
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                startPlaybackOverride: { _, _, _ in },
                reportFirstPlayingImmediately: false))
        resolver.engineProvider = { return engine }

        await engine.play(tracks: [track], startAt: 0)

        XCTAssertEqual(currentDuringResolution?.bvid, track.bvid)
        XCTAssertEqual(engine.current?.bvid, track.bvid)
    }

    func testPlaybackRequestUsesOnlyOneFreshAudioResolutionBeforePlay() async {
        let track = Self.track(cid: nil)
        let resolver = CriticalPathAudioResolver(
            prepared: Self.stream(
                url: URL(string: "https://example.invalid/fresh.m4a")!,
                cid: 1001,
                duration: 211,
                quality: 30280,
                bandwidth: 192_000))
        var events: [PlayerEngine.PlaybackStartupTestEvent] = []
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                record: { events.append($0) },
                startPlaybackOverride: { _, _, _ in },
                reportFirstPlayingImmediately: false))

        await engine.play(tracks: [track], startAt: 0)

        XCTAssertEqual(resolver.prepareCount, 1)
        XCTAssertEqual(events, [
            .currentAssigned,
            .sourceResolutionStarted,
            .sourceResolved(.freshRemote),
            .playerItemCreated(.freshRemote),
            .playRequested(.freshRemote)
        ])
    }

    func testFirstObservedPlayingSchedulesOnlyAllowedPostSoundWork() async {
        let track = Self.track()
        let cached = Self.stream(
            url: URL(fileURLWithPath: "/tmp/critical-path.m4a"),
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 0)
        let resolver = CriticalPathAudioResolver(
            cached: cached,
            prepared: cached)
        var events: [PlayerEngine.PlaybackStartupTestEvent] = []
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                record: { events.append($0) },
                startPlaybackOverride: { _, _, _ in },
                reportFirstPlayingImmediately: true))

        await engine.play(tracks: [track], startAt: 0)

        XCTAssertTrue(events.contains(.historyScheduled))
        XCTAssertTrue(events.contains(.artworkScheduled))
        XCTAssertTrue(events.contains(.lyricsScheduled))
        XCTAssertFalse(events.contains(.mvPreparationScheduled))
        XCTAssertFalse(events.contains(.queuePrefetchScheduled))
        XCTAssertFalse(events.contains(.autoCacheScheduled))
    }

    func testFirstObservedPlayingSchedulesUpcomingTrackPrewarmAfterFirstPlaying() async throws {
        let current = Self.track()
        let next = Self.track(bvid: "BVPATH002", cid: 1002)
        let cached = Self.stream(
            url: URL(fileURLWithPath: "/tmp/critical-path.m4a"),
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 0)
        let resolver = CriticalPathAudioResolver(
            cached: cached,
            prepared: cached)
        var events: [PlayerEngine.PlaybackStartupTestEvent] = []
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                record: { events.append($0) },
                startPlaybackOverride: { _, _, _ in },
                reportFirstPlayingImmediately: true))

        await engine.play(tracks: [current, next], startAt: 0)

        let firstPlayingIndex = try XCTUnwrap(events.firstIndex(of: .firstPlaying(.preparedRemote)))
        let prefetchIndex = try XCTUnwrap(events.firstIndex(of: .queuePrefetchScheduled))
        XCTAssertGreaterThan(prefetchIndex, firstPlayingIndex)
    }

    func testNowPlayingInfoReportsPlayingAfterFirstObservedAudio() async throws {
        let track = Self.track(title: "【4K修复】Fixture Artist《Critical Path Song》Official MV")
        let cached = Self.stream(
            url: URL(fileURLWithPath: "/tmp/critical-path.m4a"),
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 0)
        let resolver = CriticalPathAudioResolver(
            cached: cached,
            prepared: cached)
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                startPlaybackOverride: { _, _, _ in },
                reportFirstPlayingImmediately: true))

        await engine.play(tracks: [track], startAt: 0)

        let info = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "Critical Path Song")
        XCTAssertEqual(info[MPMediaItemPropertyArtist] as? String, "Fixture Artist")
        XCTAssertEqual(info[MPMediaItemPropertyPlaybackDuration] as? Double, 211)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyDefaultPlaybackRate] as? Double, 1)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyMediaType] as? UInt, MPNowPlayingInfoMediaType.audio.rawValue)
    }

    private static func track(
        bvid: String = "BVPATH001",
        cid: Int? = 1001,
        title: String = "Critical Path Song",
        artist: String = "Fixture Artist"
    ) -> Track {
        Track(
            typeID: 3,
            bvid: bvid,
            cid: cid,
            title: title,
            artist: artist,
            coverURL: nil,
            duration: cid == nil ? 0 : 211)
    }

    private static func stream(
        url: URL,
        cid: Int,
        duration: Int,
        quality: Int,
        bandwidth: Int
    ) -> StreamResolver.PreparedAudioStream {
        .init(
            url: url,
            cid: cid,
            duration: duration,
            quality: quality,
            bandwidth: bandwidth,
            fetchedAt: Date())
    }
}

@MainActor
private final class CriticalPathAudioResolver: AudioStreamResolving {
    var onPrepare: ((PlayerEngine) -> Void)?
    var engineProvider: (() -> PlayerEngine)?
    private let cached: StreamResolver.PreparedAudioStream?
    private let prepared: StreamResolver.PreparedAudioStream
    private(set) var prepareCount = 0

    init(cached: StreamResolver.PreparedAudioStream? = nil, prepared: StreamResolver.PreparedAudioStream) {
        self.cached = cached
        self.prepared = prepared
    }

    func cachedAudio(for track: Track) -> StreamResolver.PreparedAudioStream? {
        cached
    }

    func isPreparing(_ track: Track) -> Bool {
        false
    }

    func invalidateAudio(for track: Track) {}

    func prepareAudio(for track: Track, preferredQuality: Int) async throws -> StreamResolver.PreparedAudioStream {
        prepareCount += 1
        if let engine = engineProvider?() {
            onPrepare?(engine)
        }
        return prepared
    }

    func warmAudioCDN(for track: Track, preferredQuality: Int) async {}
}
