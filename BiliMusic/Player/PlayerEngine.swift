import AVFoundation
import MediaPlayer
import Observation
import OSLog
import UIKit

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "player")

/// B 站视频可以有多个分P(cid)。播放、缓存、历史和预取不能只按 bvid 去重,
/// 否则同一个 BV 下的多首歌会互相覆盖。cid 未知时先退回 bvid,播放补全后再升级。
struct TrackKey: Hashable, Codable, CustomStringConvertible {
    let bvid: String
    let cid: Int?

    var description: String {
        if let cid { "\(bvid)#\(cid)" } else { bvid }
    }

    var fileStem: String {
        if let cid { "\(bvid)_\(cid)" } else { bvid }
    }

    func matches(_ track: Track) -> Bool {
        bvid == track.bvid && (cid == nil || track.cid == nil || cid == track.cid)
    }
}

struct Track: Identifiable, Equatable, Codable {
    let aid: Int?
    let ownerMid: Int?
    let typeID: Int?
    let bvid: String
    var cid: Int?          // 搜索结果没有 cid,首次播放时补全
    let title: String
    let artist: String
    let coverURL: URL?
    var duration: Int
    var key: TrackKey { TrackKey(bvid: bvid, cid: cid) }
    var id: String { key.description }

    init(aid: Int? = nil, ownerMid: Int? = nil, typeID: Int? = nil, bvid: String, cid: Int? = nil, title: String, artist: String, coverURL: URL?, duration: Int) {
        self.aid = aid
        self.ownerMid = ownerMid
        self.typeID = typeID
        self.bvid = bvid
        self.cid = cid
        self.title = title
        self.artist = artist
        self.coverURL = coverURL
        self.duration = duration
    }

    init(search item: BiliClient.SearchItem) {
        self.init(aid: item.aid, ownerMid: item.mid, typeID: item.typeid, bvid: item.bvid, title: item.cleanTitle, artist: item.author,
                  coverURL: item.coverURL, duration: item.durationSeconds)
    }

    init(related item: BiliClient.RelatedItem) {
        self.init(aid: item.aid, ownerMid: item.owner.mid, bvid: item.bvid, cid: item.cid, title: item.title, artist: item.owner.name,
                  coverURL: URL(string: item.pic), duration: item.duration)
    }

    init(playlist item: BiliClient.UPPlaylistItem, artist: String, ownerMid: Int) {
        self.init(aid: item.aid, ownerMid: ownerMid, bvid: item.bvid, cid: item.cid,
                  title: item.title, artist: artist,
                  coverURL: item.pic.flatMap(URL.init(string:)), duration: item.duration ?? 0)
    }
}

struct PlaybackSource {
    let track: Track
    let url: URL
    let candidateURLs: [URL]
    let isLocal: Bool
    let kind: PlaybackDiagnosticEvent.SourceKind
    let quality: Int?
    let bandwidth: Int?

    init(
        track: Track,
        url: URL,
        candidateURLs: [URL] = [],
        isLocal: Bool,
        kind: PlaybackDiagnosticEvent.SourceKind,
        quality: Int?,
        bandwidth: Int?
    ) {
        self.track = track
        self.url = url
        self.candidateURLs = AudioCDNSelector.deduped([url] + candidateURLs)
        self.isLocal = isLocal
        self.kind = kind
        self.quality = quality
        self.bandwidth = bandwidth
    }
}

@Observable
@MainActor
final class PlayerEngine {
    enum State: Equatable {
        case idle, loading, playing, paused
        case failed(String)
    }

    enum PlaybackMode: String, CaseIterable, Identifiable {
        case music = "音乐"
        case mv = "MV"
        var id: String { rawValue }
    }

    enum QueueMode: String, CaseIterable, Identifiable {
        case sequential = "顺序"
        case shuffle = "随机"
        case repeatOne = "单曲循环"
        case radio = "电台"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .sequential: "text.line.first.and.arrowtriangle.forward"
            case .shuffle: "shuffle"
            case .repeatOne: "repeat.1"
            case .radio: "dot.radiowaves.left.and.right"
            }
        }
    }

    enum PlaybackStartupTestEvent: Equatable {
        case currentAssigned
        case sourceResolutionStarted
        case sourceResolved(PlaybackDiagnosticEvent.SourceKind)
        case playerItemCreated(PlaybackDiagnosticEvent.SourceKind)
        case playRequested(PlaybackDiagnosticEvent.SourceKind)
        case firstPlaying(PlaybackDiagnosticEvent.SourceKind)
        case historyScheduled
        case artworkScheduled
        case lyricsScheduled
        case mvPreparationScheduled
        case queuePrefetchScheduled
        case autoCacheScheduled
        case preparedStreamInvalidated
        case preparedStreamRetryRequested
        case failureSurfaced
    }

    struct PlaybackStartupTestHooks {
        private var recorder: (@MainActor (PlaybackStartupTestEvent) -> Void)?
        var startPlaybackOverride: (@MainActor (PlaybackSource, Double, UUID) -> Void)?
        var reportFirstPlayingImmediately: Bool

        init(
            record: (@MainActor (PlaybackStartupTestEvent) -> Void)? = nil,
            startPlaybackOverride: (@MainActor (PlaybackSource, Double, UUID) -> Void)? = nil,
            reportFirstPlayingImmediately: Bool = false
        ) {
            self.recorder = record
            self.startPlaybackOverride = startPlaybackOverride
            self.reportFirstPlayingImmediately = reportFirstPlayingImmediately
        }

        static let none = PlaybackStartupTestHooks()
        var isActive: Bool {
            recorder != nil || startPlaybackOverride != nil || reportFirstPlayingImmediately
        }

        @MainActor
        func record(_ event: PlaybackStartupTestEvent) {
            recorder?(event)
        }
    }

    struct LyricLine: Identifiable, Equatable {
        let id = UUID()
        let from: Double
        let to: Double
        let text: String
    }

    private(set) var state: State = .idle
    private(set) var queue: [Track] = []
    private(set) var queueIndex = 0
    private(set) var currentTime: Double = 0
    /// 用户正在拖动进度条:期间不让时间观察器回写 currentTime,避免与手指打架
    private(set) var isScrubbing = false
    private(set) var lyrics: [LyricLine] = []
    private(set) var videoAvailable = false
    private(set) var currentAudioQuality: Int?
    private(set) var currentAudioBandwidth: Int?
    /// 队列推进策略:顺序、随机、单曲循环、电台。
    var queueMode: QueueMode = .sequential
    private(set) var playbackMode: PlaybackMode = .music
    /// 是否在页面滚动或被手动滑动时临时隐藏迷你播放器
    var isMiniPlayerHidden = false

    var current: Track? { queue.indices.contains(queueIndex) ? queue[queueIndex] : nil }
    var duration: Double { Double(current?.duration ?? 0) }
    var hasNext: Bool {
        queueIndex + 1 < queue.count || queueMode == .radio || queueMode == .repeatOne || (queueMode == .shuffle && queue.count > 1)
    }
    var hasPrevious: Bool { queueIndex > 0 }
    var avPlayer: AVPlayer? { player }

    private let client = BiliClient()
    private let lyricsClient = LyricsClient()
    private let streamResolver: any AudioStreamResolving
    private let playbackDiagnostics: PlaybackDiagnostics
    private let startupTestHooks: PlaybackStartupTestHooks
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?
    private var itemFailureObserver: NSObjectProtocol?
    private var bufferObserver: NSKeyValueObservation?
    /// 用户意图:是否希望在播放。用来区分「用户主动暂停」与「缓冲断流导致的暂停」——
    /// 后者不该停住,缓冲恢复后要自动续播。
    private var wantsPlayback = false
    private var coverImage: UIImage?
    private var playedKeys: Set<TrackKey> = []   // 电台去重
    private var prefetchTask: Task<Void, Never>?
    private var queuePrefetchTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var autoMVTask: Task<Void, Never>?
    private var postPlaybackTask: Task<Void, Never>?
    private var remoteStartupFallbackTask: Task<Void, Never>?
    private var schedulePreloadInflight = 0   // 限制滚动触发的预加载并发,避免一次划过几十行齐发请求被限流
    private static let maxSchedulePreloadInflight = 3
    private var preparedVideoStreams: [TrackKey: PreparedVideoStream] = [:]
    private var prefetchedRadio: (seed: TrackKey, track: Track)?
    private var playbackGeneration = UUID()
    private var firstPlayingDiagnosticsGeneration: UUID?
    private var retriedPreparedStreamGenerations: Set<UUID> = []
    private var remoteStartupFallbackGenerations: Set<UUID> = []
    private var activePlaybackSource: PlaybackSource?
    private var activePlaybackGeneration: UUID?
    private var manualPlaybackModeOverride: PlaybackMode?

    private struct PreparedVideoStream {
        let url: URL
        let cid: Int
        let fetchedAt: Date
    }

    init(
        playbackDiagnostics: PlaybackDiagnostics = PlaybackDiagnostics(),
        streamResolver: (any AudioStreamResolving)? = nil,
        startupTestHooks: PlaybackStartupTestHooks = .none
    ) {
        self.playbackDiagnostics = playbackDiagnostics
        self.streamResolver = streamResolver ?? StreamResolver()
        self.startupTestHooks = startupTestHooks
        Task(priority: .userInitiated) {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        }
        _ = NetworkMonitor.shared
        setUpRemoteCommands()
    }

    // MARK: - 对外操作

    /// 用一组曲目替换队列并从指定位置开播(搜索页点击)
    func play(tracks: [Track], startAt index: Int, queueMode: QueueMode? = nil) async {
#if DEBUG
        if UITestFixtures.enabled && !startupTestHooks.isActive {
            installUITestFixture(tracks: tracks, startAt: index)
            return
        }
#endif
        if tracks.indices.contains(index) {
            playbackDiagnostics.begin(track: tracks[index])
            playbackDiagnostics.record(.tap, track: tracks[index])
        }
        prefetchTask?.cancel()
        queuePrefetchTask?.cancel()
        autoMVTask?.cancel()
        remoteStartupFallbackTask?.cancel()
        queue = tracks
        queueIndex = index
        playedKeys = []
        manualPlaybackModeOverride = nil
        if let queueMode {
            self.queueMode = queueMode
        }
        playbackMode = preferredModeForNewTrack()
        await startCurrent()
    }

    func playRadio(seed track: Track) async {
#if DEBUG
        if UITestFixtures.enabled && !startupTestHooks.isActive {
            installUITestFixture(tracks: [track], startAt: 0)
            queueMode = .radio
            return
        }
#endif
        prefetchTask?.cancel()
        queuePrefetchTask?.cancel()
        autoMVTask?.cancel()
        remoteStartupFallbackTask?.cancel()
        queue = [track]
        queueIndex = 0
        playedKeys = []
        manualPlaybackModeOverride = nil
        queueMode = .radio
        playbackMode = preferredModeForNewTrack()
        await startCurrent()
    }

    /// 提前取 cid + playurl,减少点击歌曲后等待时间。URL 有时效,只做短期缓存。
    func preload(tracks: [Track]) {
        preload(tracks: tracks, limit: 5, delay: .zero)
    }

    func preload(tracks: [Track], limit: Int, delay: Duration) {
        preloadTask?.cancel()
        let candidates = Array(tracks.prefix(limit))
        guard !candidates.isEmpty else { return }
        preloadTask = Task { [weak self] in
            guard let self else { return }
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            await withTaskGroup(of: Void.self) { group in
                for track in candidates {
                    group.addTask { [weak self] in
                        guard !Task.isCancelled else { return }
                        await self?.prepare(track: track)
                    }
                }
            }
        }
    }

    /// 单曲预加载:列表行滚入视野时调用。不影响 preloadTask,多次调用安全。
    /// StreamResolver 内部会去重,play() 点击时可直接 await 同一 Task。
    func schedulePreload(_ track: Track) {
        // 已缓存的直接跳过;已准备的远程流仍可继续做一次 CDN 预热。
        guard CacheStore.shared.entry(for: track) == nil,
              !streamResolver.isPreparing(track),
              schedulePreloadInflight < Self.maxSchedulePreloadInflight else { return }
        schedulePreloadInflight += 1
        Task { [weak self] in
            await self?.prepare(track: track)
            self?.schedulePreloadInflight -= 1
        }
    }

    /// 直接播一个 BV 号(粘贴链接/调试)
    func play(bvid: String) async {
        preloadTask?.cancel()
        prefetchTask?.cancel()
        queuePrefetchTask?.cancel()
        autoMVTask?.cancel()
        remoteStartupFallbackTask?.cancel()
        state = .loading
        do {
            let track = try await resolve(bvid: bvid)
            await play(tracks: [track], startAt: 0)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func playNext() async {
        await advance(automatic: false)
    }

    private func advance(automatic: Bool) async {
        if automatic, queueMode == .repeatOne {
            await startCurrent()
        } else if queueMode == .radio, let current {
            state = .loading
            let prefetched = prefetchedRadio?.seed == current.key ? prefetchedRadio?.track : nil
            prefetchedRadio = nil
            let next: Track?
            if let prefetched {
                next = prefetched
            } else {
                next = await radioPick(after: current.bvid)
            }
            if let next {
                let insertIndex = min(queueIndex + 1, queue.count)
                queue.insert(next, at: insertIndex)
                queueIndex = insertIndex
                manualPlaybackModeOverride = nil
                playbackMode = preferredModeForNewTrack()
                await startCurrent()
            } else if queueIndex + 1 < queue.count {
                queueIndex += 1
                manualPlaybackModeOverride = nil
                playbackMode = preferredModeForNewTrack()
                await startCurrent()
            } else {
                state = .paused
            }
        } else if let nextIndex = QueueController.nextIndex(
            mode: queueMode,
            queueCount: queue.count,
            currentIndex: queueIndex) {
            queueIndex = nextIndex
            manualPlaybackModeOverride = nil
            playbackMode = preferredModeForNewTrack()
            await startCurrent()
        }
    }

    func playPrevious() async {
        // 已播 3 秒以上则回到开头,否则真的回上一首
        if currentTime > 3 || !hasPrevious {
            seek(to: 0)
            return
        }
        queueIndex -= 1
        manualPlaybackModeOverride = nil
        playbackMode = preferredModeForNewTrack()
        await startCurrent()
    }

    func jump(to index: Int) async {
        guard queue.indices.contains(index) else { return }
#if DEBUG
        if UITestFixtures.enabled && !startupTestHooks.isActive {
            installUITestFixture(tracks: queue, startAt: index)
            return
        }
#endif
        preloadTask?.cancel()
        prefetchTask?.cancel()
        queuePrefetchTask?.cancel()
        autoMVTask?.cancel()
        remoteStartupFallbackTask?.cancel()
        queueIndex = index
        manualPlaybackModeOverride = nil
        playbackMode = preferredModeForNewTrack()
        await startCurrent()
    }

    func removeFromQueue(at index: Int) {
        if QueueController.remove(at: index, from: &queue, currentIndex: &queueIndex) {
            Task { await startCurrent() }
        }
    }

    func appendToQueue(_ tracks: [Track]) {
        let additions = QueueController.appendUnique(tracks, to: &queue)
        preload(tracks: additions)
    }

    func togglePlayPause() {
        // 用意图判断,而非 state——缓冲断流时 state 会是 .loading,此时点按应能暂停。
        if wantsPlayback {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard let player else { return }
        wantsPlayback = true
        player.play()
        state = .playing
        updateNowPlayingInfo()
    }

    func pause() {
        guard let player else { return }
        wantsPlayback = false
        remoteStartupFallbackTask?.cancel()
        player.pause()
        state = .paused
        updateNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
        updateNowPlayingInfo()
    }


    /// 进度条交互:开始拖动时冻结时间回写,只更新显示;松手时一次性 seek。
    /// 当前在线播放音质偏好。默认30280=192K以平衡加载速度与听感;
    /// 用户可在播放器中手动切到更高音质(含Hi-Res/杜比)。
    /// 下载音质单独存 downloadQuality。
    static var playbackQuality: Int {
        let raw = UserDefaults.standard.integer(forKey: "playbackQuality")
        return raw > 0 ? raw : 30280
    }

    /// 在播放器里切换音质:写入偏好并按当前进度重取流续播。本地缓存曲目无需切换。
    func setPlaybackQuality(_ id: Int) async {
        UserDefaults.standard.set(id, forKey: "playbackQuality")
        guard let track = current, CacheStore.shared.entry(for: track) == nil else { return }
        streamResolver.invalidateAudio(for: track)
        await startCurrent(resumeAt: currentTime)
    }

    func beginScrub() {
        isScrubbing = true
    }

    func endScrub(to seconds: Double) {
        isScrubbing = false
        seek(to: seconds)
    }

    func setPlaybackMode(_ mode: PlaybackMode) async {
        guard mode != playbackMode else { return }
        manualPlaybackModeOverride = mode
        playbackMode = mode
        await startCurrent(resumeAt: currentTime)
    }

    func upgradeMVForFullscreen() async {
        guard playbackMode == .mv, var track = current else { return }
        let resumeAt = currentTime
        do {
            if track.cid == nil {
                track = try await fillPlaybackPage(for: track)
                if current.map({ track.key.matches($0) }) ?? false {
                    queue[queueIndex] = track
                }
            }
            guard let cid = track.cid else { return }
            let url = try await client.videoStream(bvid: track.bvid, cid: cid, profile: .fullscreen)
            guard current.map({ track.key.matches($0) }) ?? false, playbackMode == .mv else { return }
            preparedVideoStreams[track.key] = PreparedVideoStream(url: url, cid: cid, fetchedAt: Date())
            await startCurrent(resumeAt: resumeAt)
        } catch {
            // 全屏提质失败不影响当前 MV 播放。
        }
    }

    func handleScenePhase(isBackground: Bool) async {
        guard isBackground else { return }
        autoMVTask?.cancel()
        guard playbackMode == .mv, state == .playing else { return }
        playbackMode = .music
        await startCurrent(resumeAt: currentTime)
    }

    // MARK: - 播放核心

    private func startCurrent(resumeAt: Double = 0) async {
        isMiniPlayerHidden = false
        guard var track = current else { return }
        let generation = UUID()
        playbackGeneration = generation
        firstPlayingDiagnosticsGeneration = nil
        retriedPreparedStreamGenerations.removeAll()
        remoteStartupFallbackGenerations.removeAll()
        playbackDiagnostics.record(.currentAssigned, track: track)
        startupTestHooks.record(.currentAssigned)
        state = .loading
        currentTime = resumeAt
        lyrics = []
        videoAvailable = false
        currentAudioQuality = nil
        currentAudioBandwidth = nil
        autoMVTask?.cancel()
        postPlaybackTask?.cancel()
        queuePrefetchTask?.cancel()
        remoteStartupFallbackTask?.cancel()
        do {
            let source = try await resolvePlaybackSource(for: track)
            track = source.track
            guard playbackGeneration == generation, current.map({ track.key.matches($0) }) ?? false else { return }
            currentAudioQuality = source.quality
            currentAudioBandwidth = source.bandwidth
            playbackDiagnostics.record(
                .sourceResolved,
                track: track,
                sourceKind: source.kind,
                quality: currentAudioQuality,
                bandwidth: currentAudioBandwidth)
            startupTestHooks.record(.sourceResolved(source.kind))
            startPlayback(source: source, resumeAt: resumeAt, generation: generation)
            try? AVAudioSession.sharedInstance().setActive(true)
        } catch {
            guard playbackGeneration == generation else { return }
            if playbackMode == .mv {
                videoAvailable = false
                playbackMode = .music
                await startCurrent(resumeAt: resumeAt)
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

#if DEBUG
    func installUITestFixture(tracks: [Track], startAt index: Int = 0) {
        preloadTask?.cancel()
        prefetchTask?.cancel()
        queuePrefetchTask?.cancel()
        autoMVTask?.cancel()
        postPlaybackTask?.cancel()
        remoteStartupFallbackTask?.cancel()
        itemStatusObserver?.invalidate()
        if let itemFailureObserver { NotificationCenter.default.removeObserver(itemFailureObserver) }
        player?.pause()
        player = nil
        queue = tracks
        queueIndex = min(max(index, 0), max(tracks.count - 1, 0))
        playedKeys = []
        manualPlaybackModeOverride = nil
        playbackMode = .music
        queueMode = .sequential
        state = tracks.isEmpty ? .idle : .paused
        currentTime = 0
        lyrics = []
        videoAvailable = !tracks.isEmpty
        currentAudioQuality = nil
        currentAudioBandwidth = nil
        activePlaybackSource = nil
        activePlaybackGeneration = nil
        isMiniPlayerHidden = false
    }
#endif

    private func resolve(bvid: String) async throws -> Track {
        let start = CFAbsoluteTimeGetCurrent()
        let info = try await client.videoInfo(bvid: bvid)
        guard let page = info.pages.first else {
            throw BiliClient.APIError(code: -1, message: "无分P")
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        log.debug("resolve(bvid:\(bvid)) \(elapsed, format: .fixed(precision: 1))ms")
        return Track(aid: info.aid, ownerMid: info.owner.mid, bvid: info.bvid, cid: page.cid, title: info.title,
                     artist: info.owner.name, coverURL: URL(string: info.pic),
                     duration: page.duration)
    }

    private func fillPlaybackPage(for track: Track) async throws -> Track {
        let info = try await client.videoInfo(bvid: track.bvid)
        guard let page = info.pages.first else {
            throw BiliClient.APIError(code: -1, message: "无分P")
        }
        return Track(aid: info.aid, ownerMid: info.owner.mid, typeID: track.typeID, bvid: track.bvid,
                     cid: page.cid, title: track.title, artist: track.artist,
                     coverURL: track.coverURL, duration: page.duration)
    }

    private func preferredModeForNewTrack() -> PlaybackMode {
        // 新点击歌曲先出声。MV 流尤其是高画质会明显慢于音频流;Wi-Fi 优先 MV
        // 只作为切换/预取策略,不阻塞新歌首播。
        .music
    }

    private func resolvePlaybackSource(for initialTrack: Track) async throws -> PlaybackSource {
        startupTestHooks.record(.sourceResolutionStarted)
        var track = initialTrack
        if playbackMode == .mv {
            if track.cid == nil {
                track = try await fillPlaybackPage(for: track)
                queue[queueIndex] = track
            }
            let url: URL
            if let prepared = preparedVideoStream(for: track), prepared.cid == track.cid {
                url = prepared.url
            } else {
                url = try await client.videoStream(bvid: track.bvid, cid: track.cid!)
                preparedVideoStreams[track.key] = PreparedVideoStream(
                    url: url, cid: track.cid!, fetchedAt: Date())
            }
            videoAvailable = true
            return PlaybackSource(
                track: track,
                url: url,
                candidateURLs: [url],
                isLocal: false,
                kind: .mvRemote,
                quality: nil,
                bandwidth: nil)
        }

        if let cached = CacheStore.shared.entry(for: track) {
            track.cid = cached.cid
            track.duration = cached.duration
            queue[queueIndex] = track
            return PlaybackSource(
                track: track,
                url: CacheStore.audioDir.appendingPathComponent(cached.fileName),
                candidateURLs: [],
                isLocal: true,
                kind: .localCache,
                quality: cached.quality,
                bandwidth: nil)
        }

        if let prepared = streamResolver.cachedAudio(for: track) {
            track.cid = prepared.cid
            track.duration = prepared.duration
            queue[queueIndex] = track
            return PlaybackSource(
                track: track,
                url: prepared.url,
                candidateURLs: prepared.candidateURLs,
                isLocal: false,
                kind: .preparedRemote,
                quality: prepared.quality,
                bandwidth: prepared.bandwidth)
        }

        let prepared = try await streamResolver.prepareAudio(
            for: track,
            preferredQuality: Self.playbackQuality)
        track.cid = prepared.cid
        track.duration = prepared.duration
        queue[queueIndex] = track
        return PlaybackSource(
            track: track,
            url: prepared.url,
            candidateURLs: prepared.candidateURLs,
            isLocal: false,
            kind: .freshRemote,
            quality: prepared.quality,
            bandwidth: prepared.bandwidth)
    }

    /// 电台选歌:用统一推荐引擎打分,避免 related 第一条把队列带偏。
    private func radioPick(after bvid: String) async -> Track? {
        if let track = await fastRelatedRadioPick(after: bvid) {
            return track
        }
        let excluded = playedKeys.union(queue.map(\.key))
        return await RecommendationEngine().nextRadioTrack(after: current, excludedKeys: excluded)
    }

    /// 自动下一首必须先保证速度:related 接口通常最快,且返回 cid 时能少一次 pagelist 请求。
    private func fastRelatedRadioPick(after bvid: String) async -> Track? {
        let excluded = playedKeys.union(queue.map(\.key))
        guard let items = try? await client.related(bvid: bvid) else { return nil }
        let tracks = items
            .map(Track.init(related:))
            .filter { track in !excluded.contains { $0.matches(track) } }
        return tracks.first(where: MusicFilter.isStrictMusic)
            ?? tracks.first(where: MusicFilter.isMusic)
    }

    private func scheduleRadioPrefetch() {
        prefetchTask?.cancel()
        guard queueMode == .radio, let current else { return }
        let seedKey = current.key
        let bvid = current.bvid
        let expectedIndex = queueIndex
        startupTestHooks.record(.queuePrefetchScheduled)
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard let next = await self.radioPick(after: bvid) else { return }
            guard !Task.isCancelled else { return }
            if self.queueIndex == expectedIndex {
                self.prefetchedRadio = (seedKey, next)
                await self.prepare(track: next)
            }
        }
    }

    private func scheduleQueuePrefetch() {
        queuePrefetchTask?.cancel()
        guard queue.indices.contains(queueIndex + 1) else { return }
        let next = queue[queueIndex + 1]
        let expectedIndex = queueIndex
        startupTestHooks.record(.queuePrefetchScheduled)
        queuePrefetchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled,
                  self?.queueIndex == expectedIndex else { return }
            await self?.prepare(track: next)
        }
    }

    private func preparedVideoStream(for track: Track) -> PreparedVideoStream? {
        let key = track.key
        let fallbackKey = TrackKey(bvid: track.bvid, cid: nil)
        guard let prepared = preparedVideoStreams[key] ?? preparedVideoStreams[fallbackKey] else { return nil }
        if Date().timeIntervalSince(prepared.fetchedAt) < 90 * 60 {
            return prepared
        }
        preparedVideoStreams[key] = nil
        preparedVideoStreams[fallbackKey] = nil
        return nil
    }

    private func prepare(track: Track) async {
        guard CacheStore.shared.entry(for: track) == nil else { return }
        await streamResolver.warmAudioCDN(for: track, preferredQuality: Self.playbackQuality)
    }

    private func schedulePostPlaybackWork(for track: Track, generation: UUID, resumeAt: Double) {
        postPlaybackTask?.cancel()
        let shouldRecordHistory = resumeAt < 1 || !playedKeys.contains(track.key)
        playedKeys.insert(track.key)
        if shouldRecordHistory {
            startupTestHooks.record(.historyScheduled)
        }
        startupTestHooks.record(.artworkScheduled)
        startupTestHooks.record(.lyricsScheduled)
        postPlaybackTask = Task(priority: .utility) { [weak self, track, generation, shouldRecordHistory] in
            guard let self else { return }

            if shouldRecordHistory {
                PlaybackHistoryStore.shared.record(track)
            }

            try? await Task.sleep(for: .milliseconds(900))
            guard self.isCurrent(track, generation: generation) else { return }
            await self.loadCover(for: track, generation: generation)

            try? await Task.sleep(for: .milliseconds(900))
            guard self.isCurrent(track, generation: generation) else { return }
            await self.loadLyrics(for: track, generation: generation)
        }
    }

    private func isCurrent(_ track: Track, generation: UUID) -> Bool {
        playbackGeneration == generation && (current.map { track.key.matches($0) } ?? false)
    }

    private func prefetchUpcomingTracks() {
        scheduleRadioPrefetch()
        scheduleQueuePrefetch()
    }

    private func startPlayback(source: PlaybackSource, resumeAt: Double = 0, generation: UUID) {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let itemFailureObserver { NotificationCenter.default.removeObserver(itemFailureObserver) }
        statusObserver?.invalidate()
        itemStatusObserver?.invalidate()
        bufferObserver?.invalidate()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        timeObserver = nil
        endObserver = nil
        statusObserver = nil
        itemStatusObserver = nil
        itemFailureObserver = nil
        bufferObserver = nil
        activePlaybackSource = source
        activePlaybackGeneration = generation
        wantsPlayback = true   // startPlayback 一定是「要播」的语境

        if let startPlaybackOverride = startupTestHooks.startPlaybackOverride {
            recordPlayerItemCreated(for: source)
            startPlaybackOverride(source, resumeAt, generation)
            recordPlayRequested(for: source)
            if startupTestHooks.reportFirstPlayingImmediately {
                handleFirstObservedPlaying(source: source, generation: generation, resumeAt: resumeAt)
            }
            return
        }

        let asset = source.isLocal
            ? AVURLAsset(url: source.url)
            : AVURLAsset(url: source.url, options: ["AVURLAssetHTTPHeaderFieldsKey": BiliClient.headers])
        let item = AVPlayerItem(asset: asset)
        // 本地文件不需要前向缓冲;在线流缓冲 30s,降低弱网下播一半停住的概率。
        item.preferredForwardBufferDuration = source.isLocal ? 0 : 30
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        recordPlayerItemCreated(for: source)
        let player = AVPlayer(playerItem: item)
        // false = 数据一到就播,起播快;代价是断流后不会自己恢复,
        // 所以下面用 bufferObserver 手动续播,兼顾「快起播」和「不中途卡死」。
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isScrubbing else { return }
                self.currentTime = time.seconds
            }
        }
        // 让播放/暂停状态始终跟随播放器真实状态(缓冲、卡顿、自动暂停都能同步 UI)
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.handleFirstObservedPlaying(source: source, generation: generation, resumeAt: resumeAt)
                case .paused:
                    // 关键:区分「用户主动暂停」与「缓冲断流」。用户想播却变 paused = 断流,
                    // 显示 loading 而非 paused,等 bufferObserver 在缓冲恢复后续播。
                    self.state = self.wantsPlayback ? .loading : .paused
                case .waitingToPlayAtSpecifiedRate:
                    self.state = .loading
                @unknown default:
                    break
                }
            }
        }
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self,
                      self.playbackGeneration == generation,
                      self.player?.currentItem === item,
                      item.status == .failed else { return }
                await self.handlePlaybackItemFailure(
                    source: source,
                    generation: generation,
                    resumeAt: item.currentTime().seconds,
                    errorDescription: item.error?.localizedDescription)
            }
        }
        itemFailureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self,
                      self.playbackGeneration == generation,
                      self.player?.currentItem === item else { return }
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                await self.handlePlaybackItemFailure(
                    source: source,
                    generation: generation,
                    resumeAt: item.currentTime().seconds,
                    errorDescription: error?.localizedDescription)
            }
        }
        // 缓冲恢复后自动续播。automaticallyWaitsToMinimizeStalling=false 时 AVPlayer
        // 断流后不会自己重启,这里在「可以流畅播放」时手动 play(),前提是用户仍想播。
        bufferObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self,
                      self.playbackGeneration == generation,
                      self.player?.currentItem === item else { return }
                if item.isPlaybackLikelyToKeepUp,
                   self.wantsPlayback,
                   self.player?.timeControlStatus != .playing {
                    self.player?.play()
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      self.playbackGeneration == generation,
                      self.player?.currentItem === item else { return }
                // 只有真正播到资源结尾才切歌。弱网时 didPlayToEnd 可能在缓冲
                // 耗尽处提前触发,若按旧逻辑(播过 5s 就切)会在线放歌时随机跳曲。
                // 以资源自身时长 item.duration 为准,缺失时退回元数据时长。
                let assetDuration = item.duration.seconds
                let reference = assetDuration.isFinite && assetDuration > 0 ? assetDuration : self.duration
                let actualTime = item.currentTime().seconds
                let reachedEnd = reference <= 0 || actualTime >= reference - 2
                guard reachedEnd else {
                    // 提前触发 = 弱网缓冲断流,不切歌,尝试续播让它自行恢复。
                    self.player?.play()
                    return
                }
                await self.advance(automatic: true)
            }
        }
        if resumeAt > 0 {
            player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
        }
        recordPlayRequested(for: source)
        player.playImmediately(atRate: 1)
        scheduleRemoteStartupFallback(for: source, generation: generation, resumeAt: resumeAt)
        updateNowPlayingInfo()
    }

    private func scheduleRemoteStartupFallback(for source: PlaybackSource, generation: UUID, resumeAt: Double) {
        let candidates = AudioCDNSelector.fallbackCandidates(from: source.candidateURLs, excluding: source.url)
        guard !source.isLocal,
              source.kind != .mvRemote,
              !candidates.isEmpty,
              !remoteStartupFallbackGenerations.contains(generation) else { return }

        remoteStartupFallbackTask?.cancel()
        remoteStartupFallbackTask = Task { [weak self, source, generation, candidates, resumeAt] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            let fallbackURL = await AudioCDNSelector.fastestReachableURL(from: candidates)
            guard !Task.isCancelled, let fallbackURL else { return }

            await MainActor.run {
                guard let self,
                      self.playbackGeneration == generation,
                      self.firstPlayingDiagnosticsGeneration != generation,
                      self.wantsPlayback,
                      self.current.map({ source.track.key.matches($0) }) ?? false,
                      !self.remoteStartupFallbackGenerations.contains(generation) else { return }

                self.remoteStartupFallbackGenerations.insert(generation)
                Task { await AudioCDNSelector.recordPlaybackFailure(url: source.url) }
                log.debug("remote startup fallback host=\(fallbackURL.host() ?? "nil", privacy: .public)")
                let retrySource = PlaybackSource(
                    track: source.track,
                    url: fallbackURL,
                    candidateURLs: [fallbackURL],
                    isLocal: false,
                    kind: source.kind,
                    quality: source.quality,
                    bandwidth: source.bandwidth)
                self.startPlayback(
                    source: retrySource,
                    resumeAt: self.currentTime.isFinite ? self.currentTime : resumeAt,
                    generation: generation)
            }
        }
    }

    private func recordPlayerItemCreated(for source: PlaybackSource) {
        playbackDiagnostics.record(
            .playerItemCreated,
            track: source.track,
            sourceKind: source.kind,
            quality: source.quality,
            bandwidth: source.bandwidth)
        startupTestHooks.record(.playerItemCreated(source.kind))
    }

    private func recordPlayRequested(for source: PlaybackSource) {
        playbackDiagnostics.record(
            .playRequested,
            track: source.track,
            sourceKind: source.kind,
            quality: source.quality,
            bandwidth: source.bandwidth)
        startupTestHooks.record(.playRequested(source.kind))
    }

    private func handleFirstObservedPlaying(source: PlaybackSource, generation: UUID, resumeAt: Double) {
        guard playbackGeneration == generation,
              current.map({ source.track.key.matches($0) }) ?? false else { return }
        state = .playing
        remoteStartupFallbackTask?.cancel()
        guard firstPlayingDiagnosticsGeneration != generation else { return }
        firstPlayingDiagnosticsGeneration = generation
        playbackDiagnostics.record(
            .firstPlaying,
            track: source.track,
            sourceKind: source.kind,
            quality: source.quality,
            bandwidth: source.bandwidth)
        startupTestHooks.record(.firstPlaying(source.kind))
        schedulePostPlaybackWork(for: source.track, generation: generation, resumeAt: resumeAt)
        if !source.isLocal, source.kind != .mvRemote {
            Task { await AudioCDNSelector.recordPlaybackSuccess(url: source.url) }
        }
        prefetchUpcomingTracks()
    }

    private func handlePlaybackItemFailure(
        source: PlaybackSource,
        generation: UUID,
        resumeAt: Double,
        errorDescription: String?
    ) async {
        guard playbackGeneration == generation,
              current.map({ source.track.key.matches($0) }) ?? false else { return }

        if !source.isLocal, source.kind != .mvRemote {
            Task { await AudioCDNSelector.recordPlaybackFailure(url: source.url) }
        }

        if let fallbackSource = await remoteFallbackSource(for: source, generation: generation) {
            startPlayback(
                source: fallbackSource,
                resumeAt: resumeAt.isFinite ? resumeAt : currentTime,
                generation: generation)
            return
        }

        guard source.kind == .preparedRemote,
              !retriedPreparedStreamGenerations.contains(generation) else {
            startupTestHooks.record(.failureSurfaced)
            state = .failed(errorDescription ?? "播放失败")
            return
        }

        retriedPreparedStreamGenerations.insert(generation)
        startupTestHooks.record(.preparedStreamInvalidated)
        streamResolver.invalidateAudio(for: source.track)

        do {
            let prepared = try await streamResolver.prepareAudio(
                for: source.track,
                preferredQuality: Self.playbackQuality)
            var retryTrack = source.track
            retryTrack.cid = prepared.cid
            retryTrack.duration = prepared.duration
            guard playbackGeneration == generation,
                  current.map({ retryTrack.key.matches($0) }) ?? false else { return }
            queue[queueIndex] = retryTrack
            let retrySource = PlaybackSource(
                track: retryTrack,
                url: prepared.url,
                candidateURLs: prepared.candidateURLs,
                isLocal: false,
                kind: .freshRemote,
                quality: prepared.quality,
                bandwidth: prepared.bandwidth)
            currentAudioQuality = retrySource.quality
            currentAudioBandwidth = retrySource.bandwidth
            playbackDiagnostics.record(
                .sourceResolved,
                track: retryTrack,
                sourceKind: retrySource.kind,
                quality: retrySource.quality,
                bandwidth: retrySource.bandwidth)
            startupTestHooks.record(.sourceResolved(retrySource.kind))
            startupTestHooks.record(.preparedStreamRetryRequested)
            startPlayback(source: retrySource, resumeAt: resumeAt.isFinite ? resumeAt : currentTime, generation: generation)
            try? AVAudioSession.sharedInstance().setActive(true)
        } catch {
            guard playbackGeneration == generation else { return }
            startupTestHooks.record(.failureSurfaced)
            state = .failed(error.localizedDescription)
        }
    }

    private func remoteFallbackSource(for source: PlaybackSource, generation: UUID) async -> PlaybackSource? {
        let candidates = AudioCDNSelector.fallbackCandidates(from: source.candidateURLs, excluding: source.url)
        guard !source.isLocal,
              source.kind != .mvRemote,
              !candidates.isEmpty,
              !remoteStartupFallbackGenerations.contains(generation) else { return nil }
        guard let fallbackURL = await AudioCDNSelector.fastestReachableURL(
            from: candidates,
            timeout: .milliseconds(700)) else { return nil }
        guard playbackGeneration == generation,
              current.map({ source.track.key.matches($0) }) ?? false else { return nil }

        remoteStartupFallbackGenerations.insert(generation)
        log.debug("remote failure fallback host=\(fallbackURL.host() ?? "nil", privacy: .public)")
        return PlaybackSource(
            track: source.track,
            url: fallbackURL,
            candidateURLs: [fallbackURL],
            isLocal: false,
            kind: source.kind,
            quality: source.quality,
            bandwidth: source.bandwidth)
    }

    func simulateCurrentPlaybackItemFailureForTesting(message: String = "播放失败") async {
        guard let source = activePlaybackSource,
              let generation = activePlaybackGeneration else { return }
        await handlePlaybackItemFailure(
            source: source,
            generation: generation,
            resumeAt: currentTime,
            errorDescription: message)
    }

    private func loadCover(for track: Track, generation: UUID) async {
        coverImage = nil
        guard let coverURL = artworkURL(track.coverURL) else { return }
        let targetPixelSize = CGSize(width: 600, height: 600)
        if let cached = ImageMemoryCache.shared.image(for: coverURL, targetPixelSize: targetPixelSize) {
            coverImage = cached.resized(maxDimension: 600)
            updateNowPlayingInfo()
            return
        }
        guard let decoded = await ImageLoadCoordinator.shared.image(
            for: coverURL,
            targetPixelSize: targetPixelSize,
            scale: 1
        ) else { return }
        guard playbackGeneration == generation, current.map({ track.key.matches($0) }) ?? false else { return }
        ImageMemoryCache.shared.insert(decoded, for: coverURL, targetPixelSize: targetPixelSize)
        coverImage = decoded.resized(maxDimension: 600)
        updateNowPlayingInfo()
    }

    private func artworkURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        let raw = url.absoluteString
        guard raw.contains("hdslb.com"), !raw.contains("@") else { return url }
        return URL(string: raw + "@600w_600h_1c.webp")
    }

    private func loadLyrics(for track: Track, generation: UUID) async {
        // 只用 LRCLIB 在线歌词。不再 fallback 到 B 站字幕——音乐区"字幕"多是自动生成的 CC,
        // 把伴奏标成"♪音乐♪",当歌词用纯属错配,宁可显示"无歌词"。
        let online = try? await lyricsClient.lyrics(for: track)
        guard playbackGeneration == generation, current.map({ track.key.matches($0) }) ?? false else { return }
        lyrics = online ?? []
    }

    private func prepareVideoIfUseful(for track: Track, generation: UUID) async {
        guard playbackMode == .music, let cid = track.cid else { return }
        let videoURL = try? await client.videoStream(bvid: track.bvid, cid: cid)
        guard playbackGeneration == generation, current.map({ track.key.matches($0) }) ?? false else { return }
        if let videoURL {
            preparedVideoStreams[track.key] = PreparedVideoStream(url: videoURL, cid: cid, fetchedAt: Date())
        }
        let available = videoURL != nil
        videoAvailable = available
        if available, shouldAutoSwitchToMV(generation: generation, bvid: track.bvid) {
            playbackMode = .mv
            await startCurrent(resumeAt: currentTime)
        }
    }

    private func shouldAutoSwitchToMV(generation: UUID, bvid: String) -> Bool {
        UserDefaults.standard.bool(forKey: "preferMVOnWiFi")
            && NetworkMonitor.shared.isWiFi
            && manualPlaybackModeOverride == nil
            && playbackMode == .music
            && state == .playing
            && UIApplication.shared.applicationState == .active
            && playbackGeneration == generation
            && current?.bvid == bvid
    }

    // MARK: - 锁屏 / 控制中心

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.playPrevious() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: Double(track.duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
        ]
        if let coverImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: coverImage.size) { _ in coverImage }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let scale = maxDimension / longest
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
