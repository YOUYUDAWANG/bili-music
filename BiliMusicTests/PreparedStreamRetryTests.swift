import XCTest
@testable import BiliMusic

@MainActor
final class PreparedStreamRetryTests: XCTestCase {
    func testPreparedRemoteFailureInvalidatesOnceBeforeFreshRetry() async {
        let track = Self.track(cid: nil)
        let resolver = PreparedRetryAudioResolver(
            cached: Self.stream(
                url: URL(string: "https://example.invalid/prepared.m4a")!,
                cid: 1001,
                duration: 188,
                quality: 30280,
                bandwidth: 192_000),
            preparedResults: [
                .success(Self.stream(
                    url: URL(string: "https://example.invalid/fresh.m4a")!,
                    cid: 1001,
                    duration: 188,
                    quality: 30280,
                    bandwidth: 192_000))
            ])
        var events: [PlayerEngine.PlaybackStartupTestEvent] = []
        var playbackKinds: [PlaybackDiagnosticEvent.SourceKind] = []
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                record: { events.append($0) },
                startPlaybackOverride: { source, _, _ in playbackKinds.append(source.kind) }))

        await engine.play(tracks: [track], startAt: 0)
        await engine.simulateCurrentPlaybackItemFailureForTesting(message: "prepared expired")

        XCTAssertEqual(resolver.prepareCount, 1)
        XCTAssertEqual(resolver.invalidatedKeys, [
            TrackKey(bvid: "BVRETRY001", cid: 1001),
            TrackKey(bvid: "BVRETRY001", cid: nil)
        ])
        XCTAssertEqual(playbackKinds, [.preparedRemote, .freshRemote])
        XCTAssertEqual(events.filter { $0 == .currentAssigned }.count, 1)
        XCTAssertTrue(events.contains(.preparedStreamInvalidated))
        XCTAssertTrue(events.contains(.preparedStreamRetryRequested))
        XCTAssertEqual(engine.current?.cid, 1001)
    }

    func testFreshRetryFailureSurfacesFailureWithoutLooping() async {
        let track = Self.track(cid: nil)
        let resolver = PreparedRetryAudioResolver(
            cached: Self.stream(
                url: URL(string: "https://example.invalid/prepared.m4a")!,
                cid: 1001,
                duration: 188,
                quality: 30280,
                bandwidth: 192_000),
            preparedResults: [
                .success(Self.stream(
                    url: URL(string: "https://example.invalid/fresh.m4a")!,
                    cid: 1001,
                    duration: 188,
                    quality: 30280,
                    bandwidth: 192_000))
            ])
        var events: [PlayerEngine.PlaybackStartupTestEvent] = []
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                record: { events.append($0) },
                startPlaybackOverride: { _, _, _ in }))

        await engine.play(tracks: [track], startAt: 0)
        await engine.simulateCurrentPlaybackItemFailureForTesting(message: "prepared expired")
        await engine.simulateCurrentPlaybackItemFailureForTesting(message: "retry failed")

        XCTAssertEqual(resolver.prepareCount, 1)
        XCTAssertEqual(events.filter { $0 == .preparedStreamInvalidated }.count, 1)
        XCTAssertEqual(events.filter { $0 == .preparedStreamRetryRequested }.count, 1)
        XCTAssertEqual(events.filter { $0 == .failureSurfaced }.count, 1)
        XCTAssertEqual(engine.state, .failed("retry failed"))
    }

    func testFreshRetryResolutionFailureSurfacesFailureWithoutLooping() async {
        let track = Self.track(cid: nil)
        let resolver = PreparedRetryAudioResolver(
            cached: Self.stream(
                url: URL(string: "https://example.invalid/prepared.m4a")!,
                cid: 1001,
                duration: 188,
                quality: 30280,
                bandwidth: 192_000),
            preparedResults: [.failure(RetryFixtureError.freshStreamUnavailable)])
        var events: [PlayerEngine.PlaybackStartupTestEvent] = []
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                record: { events.append($0) },
                startPlaybackOverride: { _, _, _ in }))

        await engine.play(tracks: [track], startAt: 0)
        await engine.simulateCurrentPlaybackItemFailureForTesting(message: "prepared expired")

        XCTAssertEqual(resolver.prepareCount, 1)
        XCTAssertEqual(events.filter { $0 == .preparedStreamInvalidated }.count, 1)
        XCTAssertEqual(events.filter { $0 == .preparedStreamRetryRequested }.count, 0)
        XCTAssertEqual(events.filter { $0 == .failureSurfaced }.count, 1)
        XCTAssertEqual(engine.state, .failed("fresh stream unavailable"))
    }

    private static func track(cid: Int? = 1001) -> Track {
        Track(
            typeID: 3,
            bvid: "BVRETRY001",
            cid: cid,
            title: "Retry Song",
            artist: "Fixture Artist",
            coverURL: nil,
            duration: cid == nil ? 0 : 188)
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
private final class PreparedRetryAudioResolver: AudioStreamResolving {
    private let cached: StreamResolver.PreparedAudioStream
    private var preparedResults: [Result<StreamResolver.PreparedAudioStream, Error>]
    private var invalidated = false
    private(set) var prepareCount = 0
    private(set) var invalidatedKeys: [TrackKey] = []

    init(
        cached: StreamResolver.PreparedAudioStream,
        preparedResults: [Result<StreamResolver.PreparedAudioStream, Error>]
    ) {
        self.cached = cached
        self.preparedResults = preparedResults
    }

    func cachedAudio(for track: Track) -> StreamResolver.PreparedAudioStream? {
        invalidated ? nil : cached
    }

    func isPreparing(_ track: Track) -> Bool {
        false
    }

    func invalidateAudio(for track: Track) {
        invalidated = true
        invalidatedKeys.append(track.key)
        if track.cid != nil {
            invalidatedKeys.append(TrackKey(bvid: track.bvid, cid: nil))
        }
    }

    func prepareAudio(
        for track: Track,
        preferredQuality: Int
    ) async throws -> StreamResolver.PreparedAudioStream {
        prepareCount += 1
        guard !preparedResults.isEmpty else {
            throw RetryFixtureError.freshStreamUnavailable
        }
        return try preparedResults.removeFirst().get()
    }

    func warmAudioCDN(for track: Track, preferredQuality: Int) async {}
}

private enum RetryFixtureError: LocalizedError {
    case freshStreamUnavailable

    var errorDescription: String? {
        "fresh stream unavailable"
    }
}
