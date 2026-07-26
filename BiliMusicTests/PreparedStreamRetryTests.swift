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

    func testDuplicateFailureCallbacksShareOneRecoveryAttempt() async {
        let track = Self.track(cid: nil)
        let cached = Self.stream(
            url: URL(string: "https://example.invalid/prepared-duplicate.m4a")!,
            cid: 1001,
            duration: 188,
            quality: 30280,
            bandwidth: 192_000)
        let fresh = Self.stream(
            url: URL(string: "https://example.invalid/fresh-duplicate.m4a")!,
            cid: 1001,
            duration: 188,
            quality: 30280,
            bandwidth: 192_000)
        let resolver = SuspendedPreparedRetryAudioResolver(cached: cached)
        var events: [PlayerEngine.PlaybackStartupTestEvent] = []
        var playbackKinds: [PlaybackDiagnosticEvent.SourceKind] = []
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                record: { events.append($0) },
                startPlaybackOverride: { source, _, _ in playbackKinds.append(source.kind) }))

        await engine.play(tracks: [track], startAt: 0)
        let firstFailure = Task {
            await engine.simulateCurrentPlaybackItemFailureForTesting(message: "status failed")
        }
        await resolver.waitUntilRetryRequested()
        let duplicateFailure = Task {
            await engine.simulateCurrentPlaybackItemFailureForTesting(message: "end notification failed")
        }
        await Task.yield()

        XCTAssertEqual(resolver.prepareCount, 1)
        XCTAssertFalse(events.contains(.failureSurfaced))

        resolver.resolve(fresh)
        await firstFailure.value
        await duplicateFailure.value

        XCTAssertEqual(resolver.prepareCount, 1)
        XCTAssertEqual(playbackKinds, [.preparedRemote, .freshRemote])
        XCTAssertEqual(events.filter { $0 == .preparedStreamInvalidated }.count, 1)
        XCTAssertFalse(events.contains(.failureSurfaced))
    }

    func testPauseDoesNotHideAPlaybackFailure() async {
        let track = Self.track(cid: nil)
        let resolver = PreparedRetryAudioResolver(
            cached: Self.stream(
                url: URL(string: "https://example.invalid/prepared-pause.m4a")!,
                cid: 1001,
                duration: 188,
                quality: 30280,
                bandwidth: 192_000),
            preparedResults: [.failure(RetryFixtureError.freshStreamUnavailable)])
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(startPlaybackOverride: { _, _, _ in }))

        await engine.play(tracks: [track], startAt: 0)
        await engine.simulateCurrentPlaybackItemFailureForTesting(message: "prepared expired")
        engine.pause()

        XCTAssertEqual(engine.state, .failed("fresh stream unavailable"))
        XCTAssertFalse(engine.wantsPlayback)
    }

    func testBrokenLocalCacheFallsBackToFreshRemoteStream() async throws {
        // PlayerEngine 内部硬引用 CacheStore.shared,此测试无法迁到注入实例;
        // 用「先快照磁盘索引、teardown 恢复 + 清理测试产物」保证宿主真实数据完好。
        let track = Self.track()
        let cache = CacheStore.shared
        // 必须先完成 load:loadIfNeeded 现在会删除 audioDir 中不在磁盘索引里的
        // 孤儿文件,测试音频要在 load 之后写入才不会被当孤儿清掉。
        await cache.loadIfNeeded()
        let indexURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cache_index.json")
        let indexSnapshot = try? Data(contentsOf: indexURL)
        let fileName = "broken-local-\(UUID().uuidString).m4a"
        let fileURL = CacheStore.audioDir.appendingPathComponent(fileName)
        try FileManager.default.createDirectory(
            at: CacheStore.audioDir,
            withIntermediateDirectories: true)
        try Data([0]).write(to: fileURL)
        cache.addForTesting(CachedEntry(
            bvid: track.bvid,
            cid: track.cid!,
            title: track.title,
            artist: track.artist,
            coverURL: nil,
            duration: track.duration,
            fileName: fileName,
            fileSize: 1,
            downloadedAt: Date(),
            quality: 30280))
        addTeardownBlock { @MainActor in
            if let entry = cache.entry(for: track) {
                cache.remove(entry)
            }
            // remove() 现走 1s 防抖写盘;先 flush 落定内存态,再恢复索引快照,
            // 避免防抖写在快照恢复之后才落盘。
            try? await cache.flush()
            try? FileManager.default.removeItem(at: fileURL)
            if let indexSnapshot {
                try? indexSnapshot.write(to: indexURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: indexURL)
            }
        }

        let fresh = Self.stream(
            url: URL(string: "https://example.invalid/fresh-from-cache.m4a")!,
            cid: track.cid!,
            duration: track.duration,
            quality: 30280,
            bandwidth: 192_000)
        let resolver = PreparedRetryAudioResolver(
            cached: fresh,
            preparedResults: [.success(fresh)])
        var playbackKinds: [PlaybackDiagnosticEvent.SourceKind] = []
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                startPlaybackOverride: { source, _, _ in playbackKinds.append(source.kind) }))

        await engine.play(tracks: [track], startAt: 0)
        await engine.simulateCurrentPlaybackItemFailureForTesting(message: "local file unreadable")

        XCTAssertEqual(playbackKinds, [.localCache, .freshRemote])
        XCTAssertEqual(resolver.prepareCount, 1)
        XCTAssertTrue(resolver.invalidatedKeys.contains(track.key))
        XCTAssertNil(cache.entry(for: track))
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

    func cachedAudio(for track: Track, preferredQuality: Int) -> StreamResolver.PreparedAudioStream? {
        invalidated ? nil : cached
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

@MainActor
private final class SuspendedPreparedRetryAudioResolver: AudioStreamResolving {
    private let cached: StreamResolver.PreparedAudioStream
    private var invalidated = false
    private var retryContinuation: CheckedContinuation<StreamResolver.PreparedAudioStream, Error>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var prepareCount = 0

    init(cached: StreamResolver.PreparedAudioStream) {
        self.cached = cached
    }

    func cachedAudio(
        for track: Track,
        preferredQuality: Int
    ) -> StreamResolver.PreparedAudioStream? {
        invalidated ? nil : cached
    }

    func invalidateAudio(for track: Track) {
        invalidated = true
    }

    func prepareAudio(
        for track: Track,
        preferredQuality: Int
    ) async throws -> StreamResolver.PreparedAudioStream {
        prepareCount += 1
        requestWaiters.forEach { $0.resume() }
        requestWaiters = []
        return try await withCheckedThrowingContinuation { continuation in
            retryContinuation = continuation
        }
    }

    func warmAudioCDN(for track: Track, preferredQuality: Int) async {}

    func waitUntilRetryRequested() async {
        guard prepareCount == 0 else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func resolve(_ stream: StreamResolver.PreparedAudioStream) {
        retryContinuation?.resume(returning: stream)
        retryContinuation = nil
    }
}

private enum RetryFixtureError: LocalizedError {
    case freshStreamUnavailable

    var errorDescription: String? {
        "fresh stream unavailable"
    }
}
