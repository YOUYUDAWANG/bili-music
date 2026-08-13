import MediaPlayer
import UIKit
import XCTest
@testable import BiliMusic

@MainActor
final class PlaybackCriticalPathTests: XCTestCase {
    func testManualNextBypassesRepeatOneWhileAutomaticAdvanceRepeats() {
        XCTAssertEqual(
            QueueController.nextIndex(
                mode: .repeatOne,
                queueCount: 3,
                currentIndex: 1,
                automatic: true),
            1)
        XCTAssertEqual(
            QueueController.nextIndex(
                mode: .repeatOne,
                queueCount: 3,
                currentIndex: 1,
                automatic: false),
            2)
    }

    override func tearDown() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        ImageMemoryCache.shared.releaseReloadableImages()
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

    func testInvalidQueueSelectionDoesNotDiscardCurrentPlayback() async {
        let track = Self.track()
        let stream = Self.stream(
            url: URL(fileURLWithPath: "/tmp/current.m4a"),
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 0)
        let engine = PlayerEngine(
            streamResolver: CriticalPathAudioResolver(cached: stream, prepared: stream),
            startupTestHooks: .init(startPlaybackOverride: { _, _, _ in }))

        await engine.play(tracks: [track], startAt: 0)
        await engine.play(tracks: [], startAt: 0)

        XCTAssertEqual(engine.current?.bvid, track.bvid)
        XCTAssertEqual(engine.queue.count, 1)
    }

    func testPlayBindsCachedArtworkBeforeAwaitedSourceResolutionCompletes() async {
        let coverURL = URL(string: "https://example.invalid/cover.jpg")!
        ImageMemoryCache.shared.insert(
            Self.image(),
            for: coverURL,
            targetPixelSize: CGSize(width: 960, height: 540))
        let track = Self.track(coverURL: coverURL)
        let resolver = CriticalPathAudioResolver(
            prepared: Self.stream(
                url: URL(string: "https://example.invalid/prepared.m4a")!,
                cid: 1001,
                duration: 211,
                quality: 30280,
                bandwidth: 192_000))
        var artworkDuringResolution: UIImage?
        var events: [PlayerEngine.PlaybackStartupTestEvent] = []
        resolver.onPrepare = { (engine: PlayerEngine) in
            artworkDuringResolution = engine.currentCoverImage
        }
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                record: { events.append($0) },
                startPlaybackOverride: { _, _, _ in },
                reportFirstPlayingImmediately: false))
        resolver.engineProvider = { return engine }

        await engine.play(tracks: [track], startAt: 0)

        XCTAssertNotNil(artworkDuringResolution)
        XCTAssertEqual(Array(events.prefix(3)), [
            .currentAssigned,
            .artworkPrefetchScheduled,
            .sourceResolutionStarted
        ])
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
        XCTAssertEqual(resolver.retainedPreparationKeys, [track.key])
    }

    func testRemotePlaybackSourcePreservesMIMETypeAndCodec() async {
        let track = Self.track()
        let resolver = CriticalPathAudioResolver(
            prepared: Self.stream(
                url: URL(string: "https://example.invalid/audio.m4s")!,
                cid: 1001,
                duration: 211,
                quality: 30280,
                bandwidth: 192_000,
                mimeType: "audio/mp4",
                codecs: "mp4a.40.2"))
        var capturedSource: PlaybackSource?
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                startPlaybackOverride: { source, _, _ in capturedSource = source },
                reportFirstPlayingImmediately: false))

        await engine.play(tracks: [track], startAt: 0)

        XCTAssertEqual(capturedSource?.mimeType, "audio/mp4")
        XCTAssertEqual(capturedSource?.codecs, "mp4a.40.2")
    }

    func testFirstObservedPlayingSchedulesOnlyAllowedPostSoundWork() async {
        let defaults = UserDefaults.standard
        let previousAutoCache = defaults.object(forKey: PlaybackPreferences.autoCacheKey)
        defaults.set(false, forKey: PlaybackPreferences.autoCacheKey)
        defer {
            if let previousAutoCache {
                defaults.set(previousAutoCache, forKey: PlaybackPreferences.autoCacheKey)
            } else {
                defaults.removeObject(forKey: PlaybackPreferences.autoCacheKey)
            }
        }
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

        let firstPlayingIndex = events.firstIndex(of: .firstPlaying(.localCache)) ?? events.firstIndex(of: .firstPlaying(.preparedRemote))
        let historyIndex = events.firstIndex(of: .historyScheduled)
        let artworkIndex = events.firstIndex(of: .artworkScheduled)
        let lyricsIndex = events.firstIndex(of: .lyricsScheduled)

        XCTAssertNotNil(firstPlayingIndex)
        XCTAssertNotNil(historyIndex)
        XCTAssertNotNil(artworkIndex)
        XCTAssertNotNil(lyricsIndex)
        XCTAssertLessThan(firstPlayingIndex!, historyIndex!)
        XCTAssertLessThan(firstPlayingIndex!, artworkIndex!)
        XCTAssertLessThan(firstPlayingIndex!, lyricsIndex!)
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

    func testPreparedVideoAvailabilityPreservesMusicMode() {
        let policy = PlayerEngine.PreparedVideoAvailabilityPolicy.applyPreparedVideo(
            currentPlaybackMode: .music,
            hasPreparedVideo: true)

        XCTAssertTrue(policy.videoAvailable)
        XCTAssertEqual(policy.playbackMode, .music)
    }

    func testPreparedVideoAvailabilityDoesNotImplyPlaybackDecision() {
        let available = PlayerEngine.PreparedVideoAvailabilityPolicy.applyPreparedVideo(
            currentPlaybackMode: .music,
            hasPreparedVideo: true)
        let unavailable = PlayerEngine.PreparedVideoAvailabilityPolicy.applyPreparedVideo(
            currentPlaybackMode: .music,
            hasPreparedVideo: false)

        XCTAssertEqual(available.playbackMode, .music)
        XCTAssertEqual(unavailable.playbackMode, .music)
        XCTAssertNotEqual(available.videoAvailable, unavailable.videoAvailable)
    }

    func testPlaybackBufferPolicyKeepsVideoMemoryBounded() {
        let track = Self.track(bvid: "BVBUFFER001")
        let remoteAudio = PlaybackSource(
            track: track,
            url: URL(string: "https://example.invalid/audio.m4a")!,
            isLocal: false,
            kind: .freshRemote,
            quality: 30280,
            bandwidth: 192_000)
        let remoteVideo = PlaybackSource(
            track: track,
            url: URL(string: "https://example.invalid/video.mp4")!,
            isLocal: false,
            kind: .mvRemote,
            quality: nil,
            bandwidth: nil)
        let localAudio = PlaybackSource(
            track: track,
            url: URL(fileURLWithPath: "/tmp/audio.m4a"),
            isLocal: true,
            kind: .localCache,
            quality: 30280,
            bandwidth: 192_000)

        XCTAssertEqual(
            PlaybackBufferPolicy.preferredForwardBufferDuration(for: remoteAudio),
            30)
        XCTAssertTrue(PlaybackBufferPolicy.allowsNetworkUseWhilePaused(for: remoteAudio))
        XCTAssertEqual(
            PlaybackBufferPolicy.preferredForwardBufferDuration(for: remoteVideo),
            6)
        XCTAssertFalse(PlaybackBufferPolicy.allowsNetworkUseWhilePaused(for: remoteVideo))
        XCTAssertEqual(
            PlaybackBufferPolicy.preferredForwardBufferDuration(for: localAudio),
            0)
        XCTAssertFalse(PlaybackBufferPolicy.allowsNetworkUseWhilePaused(for: localAudio))
    }

    func testAutomaticMVPolicyRequiresEverySafetyCondition() {
        let baseline = (
            prefersMVOnWiFi: true,
            isWiFi: true,
            hasManualModeOverride: false,
            currentMode: PlayerEngine.PlaybackMode.music,
            hasPreparedVideo: true,
            wantsPlayback: true,
            isAppActive: true
        )

        XCTAssertTrue(PlayerEngine.AutomaticPlaybackPolicy.shouldSwitchToMV(
            prefersMVOnWiFi: baseline.prefersMVOnWiFi,
            isWiFi: baseline.isWiFi,
            hasManualModeOverride: baseline.hasManualModeOverride,
            currentMode: baseline.currentMode,
            hasPreparedVideo: baseline.hasPreparedVideo,
            wantsPlayback: baseline.wantsPlayback,
            isAppActive: baseline.isAppActive))
        XCTAssertFalse(PlayerEngine.AutomaticPlaybackPolicy.shouldSwitchToMV(
            prefersMVOnWiFi: false,
            isWiFi: true,
            hasManualModeOverride: false,
            currentMode: .music,
            hasPreparedVideo: true,
            wantsPlayback: true,
            isAppActive: true))
        XCTAssertFalse(PlayerEngine.AutomaticPlaybackPolicy.shouldSwitchToMV(
            prefersMVOnWiFi: true,
            isWiFi: false,
            hasManualModeOverride: false,
            currentMode: .music,
            hasPreparedVideo: true,
            wantsPlayback: true,
            isAppActive: true))
        XCTAssertFalse(PlayerEngine.AutomaticPlaybackPolicy.shouldSwitchToMV(
            prefersMVOnWiFi: true,
            isWiFi: true,
            hasManualModeOverride: true,
            currentMode: .music,
            hasPreparedVideo: true,
            wantsPlayback: true,
            isAppActive: true))
        XCTAssertFalse(PlayerEngine.AutomaticPlaybackPolicy.shouldSwitchToMV(
            prefersMVOnWiFi: true,
            isWiFi: true,
            hasManualModeOverride: false,
            currentMode: .music,
            hasPreparedVideo: false,
            wantsPlayback: true,
            isAppActive: true))
        XCTAssertFalse(PlayerEngine.AutomaticPlaybackPolicy.shouldSwitchToMV(
            prefersMVOnWiFi: true,
            isWiFi: true,
            hasManualModeOverride: false,
            currentMode: .music,
            hasPreparedVideo: true,
            wantsPlayback: true,
            isAppActive: false))
    }

    func testMVPlaybackFailureFallsBackToMusicInsteadOfFailingTheTrack() {
        XCTAssertTrue(
            PlayerEngine.PlaybackFailureRecoveryPolicy.shouldFallbackToMusic(
                sourceKind: .mvRemote))
        XCTAssertFalse(
            PlayerEngine.PlaybackFailureRecoveryPolicy.shouldFallbackToMusic(
                sourceKind: .freshRemote))
        XCTAssertFalse(
            PlayerEngine.PlaybackFailureRecoveryPolicy.shouldFallbackToMusic(
                sourceKind: .localCache))
    }

    func testExplicitAutomaticPlaybackQualityIsNotReplacedByDefaultQuality() {
        let defaults = UserDefaults.standard
        let key = PlaybackPreferences.playbackQualityKey
        let previousValue = defaults.object(forKey: key)
        defaults.set(0, forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        XCTAssertEqual(PlaybackPreferences.playbackQuality, 0)
    }

    func testPauseDuringSourceResolutionPreventsLateAutoplay() async {
        let track = Self.track()
        let stream = Self.stream(
            url: URL(string: "https://example.invalid/delayed.m4a")!,
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 192_000)
        let resolver = SuspendedAudioResolver()
        var events: [PlayerEngine.PlaybackStartupTestEvent] = []
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                record: { events.append($0) },
                startPlaybackOverride: { _, _, _ in }))

        let playTask = Task { await engine.play(tracks: [track], startAt: 0) }
        await resolver.waitUntilRequested()
        engine.pause()
        resolver.resolve(stream)
        await playTask.value

        XCTAssertFalse(engine.wantsPlayback)
        XCTAssertEqual(engine.state, .paused)
        XCTAssertFalse(events.contains { event in
            if case .playRequested = event { return true }
            return false
        })
    }

    func testSeekDuringSourceResolutionIsAppliedWhenPlaybackStarts() async {
        let track = Self.track()
        let stream = Self.stream(
            url: URL(string: "https://example.invalid/delayed-seek.m4a")!,
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 192_000)
        let resolver = SuspendedAudioResolver()
        var playbackResumeAt: Double?
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                startPlaybackOverride: { _, resumeAt, _ in
                    playbackResumeAt = resumeAt
                }))

        let playTask = Task { await engine.play(tracks: [track], startAt: 0) }
        await resolver.waitUntilRequested()
        engine.seek(to: 47)
        resolver.resolve(stream)
        await playTask.value

        XCTAssertEqual(try XCTUnwrap(playbackResumeAt), 47, accuracy: 0.001)
        XCTAssertEqual(engine.currentTime, 47, accuracy: 0.001)
    }

    func testStaleSourceResolutionCannotOverwriteANewerQueueSelection() async {
        let staleTrack = Self.track(bvid: "BVSTALE001", cid: nil)
        let selectedTrack = Self.track(bvid: "BVSELECTED001", cid: 2001)
        let staleStream = Self.stream(
            url: URL(string: "https://example.invalid/stale.m4a")!,
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 192_000)
        let selectedStream = Self.stream(
            url: URL(string: "https://example.invalid/selected.m4a")!,
            cid: 2001,
            duration: 211,
            quality: 30280,
            bandwidth: 192_000)
        let resolver = StaleResolutionAudioResolver(
            suspendedBVID: staleTrack.bvid,
            immediateBVID: selectedTrack.bvid,
            immediateStream: selectedStream)
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(startPlaybackOverride: { _, _, _ in }))

        let stalePlay = Task {
            await engine.play(tracks: [staleTrack], startAt: 0)
        }
        await resolver.waitUntilSuspended()
        await engine.play(tracks: [selectedTrack], startAt: 0)

        resolver.resolveSuspended(with: staleStream)
        await stalePlay.value

        XCTAssertEqual(engine.current?.bvid, selectedTrack.bvid)
        XCTAssertEqual(engine.current?.cid, selectedTrack.cid)
        XCTAssertEqual(engine.queue.map(\.bvid), [selectedTrack.bvid])
    }

    func testStaleRadioAdvanceCannotReplaceNewUserSelection() async {
        let seed = Self.track(bvid: "BVRADIO001")
        let selected = Self.track(bvid: "BVSELECTED", cid: 2001)
        let staleRecommendation = Self.track(bvid: "BVSTALE001", cid: 3001)
        let stream = Self.stream(
            url: URL(string: "https://example.invalid/radio.m4a")!,
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 192_000)
        let resolver = CriticalPathAudioResolver(cached: stream, prepared: stream)
        let provider = ControlledRadioTrackProvider()
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(startPlaybackOverride: { _, _, _ in }),
            radioTrackProvider: { seed, excluded in
                await provider.request(seed: seed, excluded: excluded)
            })

        await engine.playRadio(seed: seed)
        let advanceTask = Task { await engine.advance(automatic: false) }
        await provider.waitUntilRequested()

        await engine.play(tracks: [selected], startAt: 0)
        provider.resolve(staleRecommendation)
        await advanceTask.value

        XCTAssertEqual(engine.current?.bvid, selected.bvid)
        XCTAssertEqual(engine.queue.map(\.bvid), [selected.bvid])
        XCTAssertEqual(engine.queueMode, .sequential)
    }

    func testChangingModeDuringAutomaticRadioLookupDoesNotLeavePlayerLoading() async {
        let seed = Self.track(bvid: "BVRADIOMODE")
        let stream = Self.stream(
            url: URL(string: "https://example.invalid/radio-mode.m4a")!,
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 192_000)
        let resolver = CriticalPathAudioResolver(cached: stream, prepared: stream)
        let provider = ControlledRadioTrackProvider()
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(startPlaybackOverride: { _, _, _ in }),
            radioTrackProvider: { seed, excluded in
                await provider.request(seed: seed, excluded: excluded)
            })

        await engine.playRadio(seed: seed)
        let advanceTask = Task { await engine.advance(automatic: true) }
        await provider.waitUntilRequested()
        engine.setQueueMode(.sequential)

        for _ in 0..<20 where engine.state == .loading {
            await Task.yield()
        }
        XCTAssertEqual(engine.state, .paused)
        XCTAssertFalse(engine.wantsPlayback)

        provider.resolve(nil)
        await advanceTask.value

        XCTAssertEqual(engine.queueMode, .sequential)
    }

    @MainActor
    func testPauseDuringRadioLookupPreventsReturnedTrackFromResumingPlayback() async {
        let seed = Self.track(bvid: "BVRADIOPAUSE")
        let recommendation = Self.track(bvid: "BVRADIONEXT", cid: 3001)
        let stream = Self.stream(
            url: URL(string: "https://example.invalid/radio-pause.m4a")!,
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 192_000)
        let resolver = CriticalPathAudioResolver(cached: stream, prepared: stream)
        let provider = ControlledRadioTrackProvider()
        var events: [PlayerEngine.PlaybackStartupTestEvent] = []
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                record: { events.append($0) },
                startPlaybackOverride: { _, _, _ in }),
            radioTrackProvider: { seed, excluded in
                await provider.request(seed: seed, excluded: excluded)
            })

        await engine.playRadio(seed: seed)
        let advanceTask = Task { await engine.advance(automatic: true) }
        await provider.waitUntilRequested()

        engine.pause()
        provider.resolve(recommendation)
        await advanceTask.value

        XCTAssertEqual(engine.current?.bvid, recommendation.bvid)
        XCTAssertEqual(engine.state, .paused)
        XCTAssertEqual(
            events.filter {
                if case .playRequested = $0 { return true }
                return false
            }.count,
            1)
    }

    func testPlayDuringRadioLookupWaitsForResolvedTrackInsteadOfRestartingSeed() async {
        let seed = Self.track(bvid: "BVRADIORESUME")
        let recommendation = Self.track(bvid: "BVRADIORESUMENEXT", cid: 3001)
        let stream = Self.stream(
            url: URL(string: "https://example.invalid/radio-resume.m4a")!,
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 192_000)
        let provider = ControlledRadioTrackProvider()
        var events: [PlayerEngine.PlaybackStartupTestEvent] = []
        let engine = PlayerEngine(
            streamResolver: CriticalPathAudioResolver(cached: stream, prepared: stream),
            startupTestHooks: .init(
                record: { events.append($0) },
                startPlaybackOverride: { _, _, _ in },
                reportFirstPlayingImmediately: true),
            radioTrackProvider: { seed, excluded in
                await provider.request(seed: seed, excluded: excluded)
            })

        await engine.playRadio(seed: seed)
        let advanceTask = Task { await engine.advance(automatic: true) }
        await provider.waitUntilRequested()

        engine.pause()
        engine.play()

        XCTAssertTrue(engine.wantsPlayback)
        XCTAssertEqual(engine.state, .loading)
        XCTAssertEqual(engine.current?.bvid, seed.bvid)

        provider.resolve(recommendation)
        await advanceTask.value

        XCTAssertEqual(engine.current?.bvid, recommendation.bvid)
        XCTAssertEqual(engine.state, .playing)
        XCTAssertEqual(
            events.filter {
                if case .playRequested = $0 { return true }
                return false
            }.count,
            2)
    }

    func testPreviousDuringRadioLookupRestartsSeedAndRejectsLateRecommendation() async {
        let seed = Self.track(bvid: "BVRADIOPREVIOUS")
        let staleRecommendation = Self.track(bvid: "BVRADIOSTALE", cid: 3001)
        let stream = Self.stream(
            url: URL(string: "https://example.invalid/radio-previous.m4a")!,
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 192_000)
        let provider = ControlledRadioTrackProvider()
        var events: [PlayerEngine.PlaybackStartupTestEvent] = []
        let engine = PlayerEngine(
            streamResolver: CriticalPathAudioResolver(cached: stream, prepared: stream),
            startupTestHooks: .init(
                record: { events.append($0) },
                startPlaybackOverride: { _, _, _ in },
                reportFirstPlayingImmediately: true),
            radioTrackProvider: { seed, excluded in
                await provider.request(seed: seed, excluded: excluded)
            })

        await engine.playRadio(seed: seed)
        let advanceTask = Task { await engine.advance(automatic: true) }
        await provider.waitUntilRequested()

        await engine.playPrevious()
        provider.resolve(staleRecommendation)
        await advanceTask.value

        XCTAssertEqual(engine.current?.bvid, seed.bvid)
        XCTAssertEqual(engine.queue.map(\.bvid), [seed.bvid])
        XCTAssertEqual(engine.state, .playing)
        XCTAssertEqual(
            events.filter {
                if case .playRequested = $0 { return true }
                return false
            }.count,
            2)
    }

    func testAutomaticEndOfSequentialQueueClearsPlaybackIntent() async {
        let track = Self.track()
        let stream = Self.stream(
            url: URL(fileURLWithPath: "/tmp/end-of-queue.m4a"),
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 0)
        let resolver = CriticalPathAudioResolver(cached: stream, prepared: stream)
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                startPlaybackOverride: { _, _, _ in },
                reportFirstPlayingImmediately: true))

        await engine.play(tracks: [track], startAt: 0)
        XCTAssertTrue(engine.wantsPlayback)

        await engine.advance(automatic: true)

        XCTAssertFalse(engine.wantsPlayback)
        XCTAssertEqual(engine.state, .paused)
        XCTAssertEqual(engine.currentTime, 211)
        XCTAssertEqual(
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double,
            0)
    }

    func testLateAutomaticAdvanceAfterPauseMovesQueueWithoutRestartingPlayback() async {
        let first = Self.track(bvid: "BVAUTOPAUSEFIRST")
        let second = Self.track(bvid: "BVAUTOPAUSESECOND")
        let stream = Self.stream(
            url: URL(fileURLWithPath: "/tmp/automatic-advance-paused.m4a"),
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 0)
        var events: [PlayerEngine.PlaybackStartupTestEvent] = []
        let engine = PlayerEngine(
            streamResolver: CriticalPathAudioResolver(cached: stream, prepared: stream),
            startupTestHooks: .init(
                record: { events.append($0) },
                startPlaybackOverride: { _, _, _ in }))

        await engine.play(tracks: [first, second], startAt: 0)
        engine.pause()
        await engine.advance(automatic: true)

        XCTAssertEqual(engine.current?.bvid, second.bvid)
        XCTAssertEqual(engine.state, .paused)
        XCTAssertFalse(engine.wantsPlayback)
        XCTAssertEqual(
            events.filter {
                if case .playRequested = $0 { return true }
                return false
            }.count,
            1)
    }

    func testSeekRejectsNonFiniteValuesAndClampsToTrackBounds() async {
        let track = Self.track()
        let stream = Self.stream(
            url: URL(fileURLWithPath: "/tmp/seek-bounds.m4a"),
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 0)
        let engine = PlayerEngine(
            streamResolver: CriticalPathAudioResolver(cached: stream, prepared: stream),
            startupTestHooks: .init(startPlaybackOverride: { _, _, _ in }))
        await engine.play(tracks: [track], startAt: 0)

        engine.seek(to: -20)
        XCTAssertEqual(engine.currentTime, 0)

        engine.seek(to: 999)
        XCTAssertEqual(engine.currentTime, 211)

        engine.seek(to: .nan)
        XCTAssertEqual(engine.currentTime, 211)
    }

    func testScrubEndingAfterTrackChangeCannotSeekTheNewTrack() async {
        let first = Self.track(bvid: "BVSCRUBFIRST")
        let second = Self.track(bvid: "BVSCRUBSECOND")
        let stream = Self.stream(
            url: URL(fileURLWithPath: "/tmp/stale-scrub.m4a"),
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 0)
        let engine = PlayerEngine(
            streamResolver: CriticalPathAudioResolver(cached: stream, prepared: stream),
            startupTestHooks: .init(startPlaybackOverride: { _, _, _ in }))

        await engine.play(tracks: [first], startAt: 0)
        engine.beginScrub()
        await engine.play(tracks: [second], startAt: 0)
        engine.endScrub(to: 90)

        XCTAssertEqual(engine.current?.bvid, second.bvid)
        XCTAssertEqual(engine.currentTime, 0)
        XCTAssertFalse(engine.isScrubbing)
    }

    func testVersionedAtomicWriterRejectsAnOlderSnapshot() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bili-music-writer-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = VersionedAtomicFileWriter()

        try await writer.write(Data("new".utf8), revision: 2, to: url)
        try await writer.write(Data("old".utf8), revision: 1, to: url)

        XCTAssertEqual(try Data(contentsOf: url), Data("new".utf8))
    }

    func testHistoryRecordBeforeInitialLoadMergesWithPersistedEntries() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bili-music-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let persistedTrack = Self.track(bvid: "BVHISTORY001", cid: 3001)
        let newTrack = Self.track(bvid: "BVHISTORY002", cid: 3002)
        let persisted = PlaybackHistoryEntry(
            track: persistedTrack,
            playCount: 4,
            lastPlayedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try JSONEncoder().encode([persisted]).write(to: url, options: .atomic)
        let store = PlaybackHistoryStore(fileURLForTesting: url)

        store.record(newTrack)
        await store.loadIfNeeded()
        await store.flush()

        XCTAssertEqual(Set(store.entries.map(\.bvid)), [persistedTrack.bvid, newTrack.bvid])
        XCTAssertEqual(store.entries.first(where: { $0.bvid == persistedTrack.bvid })?.playCount, 4)
        XCTAssertEqual(store.entries.first(where: { $0.bvid == newTrack.bvid })?.playCount, 1)
        let saved = try JSONDecoder().decode(
            [PlaybackHistoryEntry].self,
            from: Data(contentsOf: url))
        XCTAssertEqual(Set(saved.map(\.bvid)), [persistedTrack.bvid, newTrack.bvid])
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

    private static func track(
        bvid: String = "BVPATH001",
        cid: Int? = 1001,
        title: String = "Critical Path Song",
        artist: String = "Fixture Artist",
        coverURL: URL?
    ) -> Track {
        Track(
            typeID: 3,
            bvid: bvid,
            cid: cid,
            title: title,
            artist: artist,
            coverURL: coverURL,
            duration: cid == nil ? 0 : 211)
    }

    private static func stream(
        url: URL,
        cid: Int,
        duration: Int,
        quality: Int,
        bandwidth: Int,
        mimeType: String? = nil,
        codecs: String? = nil
    ) -> StreamResolver.PreparedAudioStream {
        .init(
            url: url,
            cid: cid,
            duration: duration,
            quality: quality,
            bandwidth: bandwidth,
            mimeType: mimeType,
            codecs: codecs,
            fetchedAt: Date())
    }

    private static func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 960, height: 540)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 960, height: 540))
        }
    }
}

@MainActor
private final class SuspendedAudioResolver: AudioStreamResolving {
    private var continuation: CheckedContinuation<StreamResolver.PreparedAudioStream, Error>?

    func cachedAudio(
        for track: Track,
        preferredQuality: Int
    ) -> StreamResolver.PreparedAudioStream? {
        nil
    }

    func invalidateAudio(for track: Track) {}

    func prepareAudio(
        for track: Track,
        preferredQuality: Int
    ) async throws -> StreamResolver.PreparedAudioStream {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func warmAudioCDN(for track: Track, preferredQuality: Int) async {}

    func waitUntilRequested() async {
        await waitBounded(
            description: "SuspendedAudioResolver.prepareAudio was never requested"
        ) { self.continuation != nil }
    }

    func resolve(_ stream: StreamResolver.PreparedAudioStream) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: stream)
    }
}

@MainActor
private final class StaleResolutionAudioResolver: AudioStreamResolving {
    private let suspendedBVID: String
    private let immediateBVID: String
    private let immediateStream: StreamResolver.PreparedAudioStream
    private var continuation: CheckedContinuation<StreamResolver.PreparedAudioStream, Error>?

    init(
        suspendedBVID: String,
        immediateBVID: String,
        immediateStream: StreamResolver.PreparedAudioStream
    ) {
        self.suspendedBVID = suspendedBVID
        self.immediateBVID = immediateBVID
        self.immediateStream = immediateStream
    }

    func cachedAudio(
        for track: Track,
        preferredQuality: Int
    ) -> StreamResolver.PreparedAudioStream? {
        track.bvid == immediateBVID ? immediateStream : nil
    }

    func invalidateAudio(for track: Track) {}

    func prepareAudio(
        for track: Track,
        preferredQuality: Int
    ) async throws -> StreamResolver.PreparedAudioStream {
        if track.bvid == immediateBVID {
            return immediateStream
        }
        guard track.bvid == suspendedBVID else {
            throw URLError(.badURL)
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func warmAudioCDN(for track: Track, preferredQuality: Int) async {}

    func waitUntilSuspended() async {
        await waitBounded(
            description: "StaleResolutionAudioResolver.prepareAudio never suspended"
        ) { self.continuation != nil }
    }

    func resolveSuspended(with stream: StreamResolver.PreparedAudioStream) {
        continuation?.resume(returning: stream)
        continuation = nil
    }
}

@MainActor
private final class ControlledRadioTrackProvider {
    private var continuation: CheckedContinuation<Track?, Never>?

    func request(seed: Track, excluded: Set<TrackKey>) async -> Track? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilRequested() async {
        await waitBounded(
            description: "ControlledRadioTrackProvider.request was never called"
        ) { self.continuation != nil }
    }

    func resolve(_ track: Track?) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: track)
    }
}

/// 有界等待:行为回归时明确 XCTFail 而不是让 `while … { await Task.yield() }` 挂死整个测试进程。
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

@MainActor
private final class CriticalPathAudioResolver: AudioStreamResolving {
    var onPrepare: ((PlayerEngine) -> Void)?
    var engineProvider: (() -> PlayerEngine)?
    private let cached: StreamResolver.PreparedAudioStream?
    private let prepared: StreamResolver.PreparedAudioStream
    private(set) var prepareCount = 0
    private(set) var retainedPreparationKeys: [TrackKey] = []

    init(cached: StreamResolver.PreparedAudioStream? = nil, prepared: StreamResolver.PreparedAudioStream) {
        self.cached = cached
        self.prepared = prepared
    }

    func cachedAudio(for track: Track, preferredQuality: Int) -> StreamResolver.PreparedAudioStream? {
        cached.map { stream($0, matching: track) }
    }

    func invalidateAudio(for track: Track) {}

    func cancelPreparations(except track: Track?) {
        if let track {
            retainedPreparationKeys.append(track.key)
        }
    }

    func prepareAudio(for track: Track, preferredQuality: Int) async throws -> StreamResolver.PreparedAudioStream {
        prepareCount += 1
        if let engine = engineProvider?() {
            onPrepare?(engine)
        }
        return stream(prepared, matching: track)
    }

    func warmAudioCDN(for track: Track, preferredQuality: Int) async {}

    /// 生产 resolver 返回的流总是对应请求曲目的 cid。fixture 若固定回一个 cid,
    /// PlayerEngine 的分P身份守卫会把不同 cid 的曲目当成换了分P而拒绝该流。
    private func stream(
        _ base: StreamResolver.PreparedAudioStream,
        matching track: Track
    ) -> StreamResolver.PreparedAudioStream {
        guard let cid = track.cid, cid != base.cid else { return base }
        return .init(
            url: base.url,
            candidateURLs: base.candidateURLs,
            cid: cid,
            duration: base.duration,
            quality: base.quality,
            bandwidth: base.bandwidth,
            fetchedAt: base.fetchedAt)
    }
}
