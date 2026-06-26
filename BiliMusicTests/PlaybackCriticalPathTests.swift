import XCTest
@testable import BiliMusic

@MainActor
final class PlaybackCriticalPathTests: XCTestCase {
    func testPlayAssignsCurrentBeforeAwaitedSourceResolutionCompletes() async {
        let track = Self.track()
        let resolver = CriticalPathAudioResolver(
            prepared: .init(
                url: URL(string: "https://example.invalid/prepared.m4a")!,
                cid: 1001,
                duration: 211,
                quality: 30280,
                bandwidth: 192_000))
        var currentDuringResolution: Track?
        resolver.onPrepare = { engine in
            currentDuringResolution = engine.current
        }
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                startPlaybackOverride: { _, _, _ in },
                reportFirstPlayingImmediately: false))
        resolver.engineProvider = { engine }

        await engine.play(tracks: [track], startAt: 0)

        XCTAssertEqual(currentDuringResolution?.bvid, track.bvid)
        XCTAssertEqual(engine.current?.bvid, track.bvid)
    }

    func testPlaybackRequestUsesOnlyOneFreshAudioResolutionBeforePlay() async {
        let track = Self.track(cid: nil)
        let resolver = CriticalPathAudioResolver(
            prepared: .init(
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
        let resolver = CriticalPathAudioResolver(
            cached: .init(
                url: URL(fileURLWithPath: "/tmp/critical-path.m4a"),
                cid: 1001,
                duration: 211,
                quality: 30280,
                bandwidth: 0))
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

    private static func track(cid: Int? = 1001) -> Track {
        Track(
            typeID: 3,
            bvid: "BVPATH001",
            cid: cid,
            title: "Critical Path Song",
            artist: "Fixture Artist",
            coverURL: nil,
            duration: cid == nil ? 0 : 211)
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
}
