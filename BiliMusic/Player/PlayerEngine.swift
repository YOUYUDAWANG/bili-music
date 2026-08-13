import AVFoundation
import MediaPlayer
import Observation
import OSLog
import UIKit

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "player")

/// B 站视频可以有多个分P(cid)。播放、缓存、历史和预取不能只按 bvid 去重,
/// 否则同一个 BV 下的多首歌会互相覆盖。cid 未知时先退回 bvid,播放补全后再升级。
struct TrackKey: Hashable, Codable, CustomStringConvertible, Sendable {
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

    /// Search and recommendation results often gain their cid during first playback.
    /// That is metadata enrichment for the same track, not a user-visible track change.
    func isCIDEnrichment(to other: TrackKey) -> Bool {
        bvid == other.bvid && cid == nil && other.cid != nil
    }
}

struct Track: Identifiable, Equatable, Codable, Sendable {
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

enum TrackTitleFormatter {
    static let cleanListTitlesDefaultsKey = "cleanListTitles"
    struct DisplayMetadata: Equatable {
        let title: String
        let artist: String
    }

    struct DisplayMetadataCacheKey: Hashable {
        let trackKey: TrackKey
        let title: String
        let artist: String
        let clean: Bool
    }

    private static let displayMetadataCache = DisplayMetadataCache()

    static var shouldCleanListTitles: Bool {
        if UserDefaults.standard.object(forKey: cleanListTitlesDefaultsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: cleanListTitlesDefaultsKey)
    }

    static func displayMetadata(for track: Track, clean: Bool = shouldCleanListTitles) -> DisplayMetadata {
        let cacheKey = DisplayMetadataCacheKey(
            trackKey: track.key,
            title: track.title,
            artist: track.artist,
            clean: clean)
        if let cached = displayMetadataCache.value(for: cacheKey) {
            return cached
        }
        let metadata: DisplayMetadata
        if clean {
            let parsed = LyricsClient.parseSongForDisplay(from: track.title, fallbackArtist: track.artist)
            let parsedTitle = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedArtist = parsed.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
            metadata = DisplayMetadata(
                title: parsedTitle.isEmpty ? track.title : parsedTitle,
                artist: parsedArtist.flatMap { $0.isEmpty ? nil : $0 } ?? track.artist)
        } else {
            metadata = DisplayMetadata(title: track.title, artist: track.artist)
        }
        displayMetadataCache.insert(metadata, for: cacheKey)
        return metadata
    }

    static func listTitle(for track: Track, clean: Bool = shouldCleanListTitles) -> String {
        displayMetadata(for: track, clean: clean).title
    }

#if DEBUG
    static func resetDisplayMetadataCacheForTesting() {
        displayMetadataCache.reset()
    }

    static var displayMetadataCacheCountForTesting: Int {
        displayMetadataCache.count
    }

    static var displayMetadataCacheMissesForTesting: Int {
        displayMetadataCache.misses
    }
#endif
}

private final class DisplayMetadataCache {
    private let lock = NSLock()
    private var storage: [TrackTitleFormatter.DisplayMetadataCacheKey: TrackTitleFormatter.DisplayMetadata] = [:]
    private var order: [TrackTitleFormatter.DisplayMetadataCacheKey] = []
    private let capacity = 256
    #if DEBUG
    private(set) var misses = 0
    #endif

    func value(for key: TrackTitleFormatter.DisplayMetadataCacheKey) -> TrackTitleFormatter.DisplayMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func insert(_ value: TrackTitleFormatter.DisplayMetadata, for key: TrackTitleFormatter.DisplayMetadataCacheKey) {
        lock.lock()
        defer { lock.unlock() }
        guard storage[key] == nil else { return }
        storage[key] = value
        order.append(key)
        #if DEBUG
        misses += 1
        #endif
        if order.count > capacity, let oldest = order.first {
            order.removeFirst()
            storage.removeValue(forKey: oldest)
        }
    }

    #if DEBUG
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
        misses = 0
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }
    #endif
}

struct PlaybackSource {
    let track: Track
    let url: URL
    let candidateURLs: [URL]
    let isLocal: Bool
    let kind: PlaybackDiagnosticEvent.SourceKind
    let quality: Int?
    let bandwidth: Int?
    let mimeType: String?
    let codecs: String?
    let videoQuality: Int?

    init(
        track: Track,
        url: URL,
        candidateURLs: [URL] = [],
        isLocal: Bool,
        kind: PlaybackDiagnosticEvent.SourceKind,
        quality: Int?,
        bandwidth: Int?,
        mimeType: String? = nil,
        codecs: String? = nil,
        videoQuality: Int? = nil
    ) {
        self.track = track
        self.url = url
        self.candidateURLs = AudioCDNSelector.deduped([url] + candidateURLs)
        self.isLocal = isLocal
        self.kind = kind
        self.quality = quality
        self.bandwidth = bandwidth
        self.mimeType = mimeType
        self.codecs = codecs
        self.videoQuality = videoQuality
    }
}

enum PlaybackBufferPolicy {
    static func preferredForwardBufferDuration(for source: PlaybackSource) -> TimeInterval {
        if source.isLocal { return 0 }
        return source.kind == .mvRemote ? 6 : 30
    }

    static func allowsNetworkUseWhilePaused(for source: PlaybackSource) -> Bool {
        !source.isLocal && source.kind != .mvRemote
    }
}

enum PlaybackPreferences {
    static let autoCacheKey = "autoCache"
    static let playbackQualityKey = "playbackQuality"
    static let downloadQualityKey = "downloadQuality"
    static let preferMVOnWiFiKey = "preferMVOnWiFi"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            autoCacheKey: false,
            playbackQualityKey: 30280,
            downloadQualityKey: 0,
            preferMVOnWiFiKey: true,
        ])
    }

    static var autoCache: Bool {
        UserDefaults.standard.bool(forKey: autoCacheKey)
    }

    static var playbackQuality: Int {
        guard UserDefaults.standard.object(forKey: playbackQualityKey) != nil else {
            return 30280
        }
        return UserDefaults.standard.integer(forKey: playbackQualityKey)
    }

    static var preferMVOnWiFi: Bool {
        guard UserDefaults.standard.object(forKey: preferMVOnWiFiKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: preferMVOnWiFiKey)
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

    struct PreparedVideoAvailabilityPolicy: Equatable {
        var videoAvailable: Bool
        var playbackMode: PlaybackMode

        static func applyPreparedVideo(
            currentPlaybackMode: PlaybackMode,
            hasPreparedVideo: Bool
        ) -> PreparedVideoAvailabilityPolicy {
            PreparedVideoAvailabilityPolicy(
                videoAvailable: hasPreparedVideo,
                playbackMode: currentPlaybackMode)
        }
    }

    struct AutomaticPlaybackPolicy: Equatable {
        static func shouldSwitchToMV(
            prefersMVOnWiFi: Bool,
            isWiFi: Bool,
            hasManualModeOverride: Bool,
            currentMode: PlaybackMode,
            hasPreparedVideo: Bool,
            wantsPlayback: Bool,
            isAppActive: Bool
        ) -> Bool {
            prefersMVOnWiFi
                && isWiFi
                && !hasManualModeOverride
                && currentMode == .music
                && hasPreparedVideo
                && wantsPlayback
                && isAppActive
        }
    }

    struct PlaybackFailureRecoveryPolicy {
        static func shouldFallbackToMusic(
            sourceKind: PlaybackDiagnosticEvent.SourceKind
        ) -> Bool {
            sourceKind == .mvRemote
        }
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
        case artworkPrefetchScheduled
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
    private var scrubTrackKey: TrackKey?
    private(set) var lyrics: [LyricLine] = []
    private(set) var videoAvailable = false
    private(set) var currentAudioQuality: Int?
    private(set) var currentAudioBandwidth: Int?
    private(set) var currentVideoQuality: Int?
    /// 队列推进策略:顺序、随机、单曲循环、电台。
    private(set) var queueMode: QueueMode = .sequential
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
    private let radioTrackProvider: (@MainActor (Track, Set<TrackKey>) async -> Track?)?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?
    private var itemFailureObserver: NSObjectProtocol?
    private var bufferObserver: NSKeyValueObservation?
    /// 用户意图:是否希望在播放。用来区分「用户主动暂停」与「缓冲断流导致的暂停」——
    /// 后者不该停住,缓冲恢复后要自动续播。
    private(set) var wantsPlayback = false
    private var isAppInBackground = false
    private(set) var coverImage: UIImage?
    private var coverImageKey: TrackKey?
    private(set) var artworkPalette = PlayerArtworkPalette.fallback
    private var artworkPaletteKey: TrackKey?
    var currentCoverImage: UIImage? {
        guard let current,
              coverImageKey?.matches(current) == true else { return nil }
        return coverImage
    }
    var currentArtworkPalette: PlayerArtworkPalette {
        guard let current,
              artworkPaletteKey?.matches(current) == true else { return .fallback }
        return artworkPalette
    }
    private var playedKeys: Set<TrackKey> = []   // 电台去重
    private var prefetchTask: Task<Void, Never>?
    private var queuePrefetchTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var startupArtworkTask: Task<Void, Never>?
    private var autoMVTask: Task<Void, Never>?
    private var autoCacheTask: Task<Void, Never>?
    private var postPlaybackTask: Task<Void, Never>?
    private var remoteStartupFallbackTask: Task<Void, Never>?
    private var preparedVideoStreams: [TrackKey: PreparedVideoStream] = [:]
    private static let preparedVideoStreamTTL: TimeInterval = 90 * 60
    private static let preparedVideoStreamLimit = 16
    private var prefetchedRadio: (seed: TrackKey, track: Track)?
    private var pendingRadioAdvance: (id: UUID, automatic: Bool)?
    private var playbackGeneration = UUID()
    private var firstPlayingDiagnosticsGeneration: UUID?
    private var retriedPreparedStreamGenerations: Set<UUID> = []
    private var remoteStartupFallbackGenerations: Set<UUID> = []
    private var handlingPlaybackFailureGenerations: Set<UUID> = []
    private var activePlaybackSource: PlaybackSource?
    private var activePlaybackGeneration: UUID?
    private var manualPlaybackModeOverride: PlaybackMode?
    private var mvReloadRequestID = UUID()
    private var directPlayRequestID: UUID?
    // deinit 非 MainActor,要在其中拆除 token 就不能经过 @Observable 的访问器,
    // 用 @ObservationIgnored + nonisolated(unsafe) 保持为普通存储属性。
    // 只在 init 阶段写入、deinit 读取,无并发竞争。
    @ObservationIgnored private nonisolated(unsafe) var audioSessionObservers: [NSObjectProtocol] = []
    @ObservationIgnored private nonisolated(unsafe) var remoteCommandTargets: [(command: MPRemoteCommand, token: Any)] = []
    private var isAudioSessionInterrupted = false

    private struct PreparedVideoStream {
        let url: URL
        let cid: Int
        let quality: Int
        let fetchedAt: Date
    }

    init(
        playbackDiagnostics: PlaybackDiagnostics = PlaybackDiagnostics(),
        streamResolver: (any AudioStreamResolving)? = nil,
        startupTestHooks: PlaybackStartupTestHooks = .none,
        radioTrackProvider: (@MainActor (Track, Set<TrackKey>) async -> Track?)? = nil
    ) {
        self.playbackDiagnostics = playbackDiagnostics
        self.streamResolver = streamResolver ?? StreamResolver()
        self.startupTestHooks = startupTestHooks
        self.radioTrackProvider = radioTrackProvider
        Task(priority: .userInitiated) {
            Self.configureAudioSession()
        }
        _ = NetworkMonitor.shared
        setUpRemoteCommands()
        setUpAudioSessionNotifications()
    }

    deinit {
        // deinit 不在 MainActor 上执行;NotificationCenter.removeObserver 与
        // MPRemoteCommand.removeTarget 均线程安全,直接拆除避免 target/observer 泄漏。
        for token in audioSessionObservers {
            NotificationCenter.default.removeObserver(token)
        }
        for entry in remoteCommandTargets {
            entry.command.removeTarget(entry.token)
        }
    }

    // MARK: - 对外操作

    /// 用一组曲目替换队列并从指定位置开播(搜索页点击)
    func play(tracks: [Track], startAt index: Int, queueMode: QueueMode? = nil) async {
        guard tracks.indices.contains(index) else { return }
        pendingRadioAdvance = nil
        directPlayRequestID = nil
#if DEBUG
        if UITestFixtures.enabled && !startupTestHooks.isActive {
            installUITestFixture(tracks: tracks, startAt: index)
            return
        }
#endif
        playbackDiagnostics.begin(track: tracks[index])
        playbackDiagnostics.record(.tap, track: tracks[index])
        prefetchTask?.cancel()
        queuePrefetchTask?.cancel()
        autoMVTask?.cancel()
        remoteStartupFallbackTask?.cancel()
        queue = tracks
        queueIndex = index
        playedKeys = []
        prefetchedRadio = nil
        manualPlaybackModeOverride = nil
        if let queueMode {
            self.queueMode = queueMode
        } else if self.queueMode == .radio {
            self.queueMode = .sequential
        }
        playbackMode = preferredModeForNewTrack()
        await startCurrent()
    }

    func playRadio(seed track: Track) async {
        pendingRadioAdvance = nil
        directPlayRequestID = nil
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
        prefetchedRadio = nil
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

    /// 直接播一个 BV 号，供 AUTOPLAY_BV 真机/命令行诊断入口使用。
    func play(bvid: String) async {
        let requestID = UUID()
        directPlayRequestID = requestID
        pendingRadioAdvance = nil
        preloadTask?.cancel()
        prefetchTask?.cancel()
        queuePrefetchTask?.cancel()
        autoMVTask?.cancel()
        remoteStartupFallbackTask?.cancel()
        wantsPlayback = true
        state = .loading
        do {
            let track = try await resolve(bvid: bvid)
            guard directPlayRequestID == requestID else { return }
            await play(tracks: [track], startAt: 0)
        } catch {
            guard directPlayRequestID == requestID else { return }
            directPlayRequestID = nil
            wantsPlayback = false
            player?.pause()
            state = .failed(error.localizedDescription)
            updateNowPlayingInfo()
        }
    }

    func playNext() async {
        await advance(automatic: false)
    }

    func advance(automatic: Bool) async {
        if automatic, queueMode == .repeatOne {
            // 单曲循环自然播完:item 仍健康时直接回到开头续播,
            // 避免走完整 startCurrent 重建 AVPlayer 造成静音间隙;item 失效才完整重启。
            if wantsPlayback,
               activePlaybackGeneration == playbackGeneration,
               let player,
               let item = player.currentItem,
               item.status == .readyToPlay,
               item.error == nil {
                let generation = playbackGeneration
                currentTime = 0
                _ = await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                guard playbackGeneration == generation,
                      self.player === player,
                      wantsPlayback else { return }
                player.play()
                updateNowPlayingInfo()
                return
            }
            await startCurrent(shouldPlay: wantsPlayback)
        } else if queueMode == .radio, let seed = current {
            let expectedGeneration = playbackGeneration
            let expectedIndex = queueIndex
            let requestID = UUID()
            pendingRadioAdvance = (requestID, automatic)
            defer {
                if pendingRadioAdvance?.id == requestID {
                    pendingRadioAdvance = nil
                }
            }
            let excluded = playedKeys.union(queue.map(\.key))
            if automatic {
                state = .loading
                updateNowPlayingInfo()
            }
            let prefetched = prefetchedRadio?.seed == seed.key ? prefetchedRadio?.track : nil
            prefetchedRadio = nil
            let next: Track?
            // 预取之后用户可能手动把同一首 appendToQueue,消费前再对
            // playedKeys ∪ queue 验一次重,失效则回落到实时选歌。
            if let prefetched, !excluded.contains(where: { $0.matches(prefetched) }) {
                next = prefetched
            } else {
                next = await radioPick(after: seed, excludedKeys: excluded)
            }
            guard playbackGeneration == expectedGeneration,
                  pendingRadioAdvance?.id == requestID,
                  queueIndex == expectedIndex,
                  current.map({ seed.key.matches($0) }) ?? false else { return }
            guard queueMode == .radio else {
                if automatic, !wantsPlayback {
                    setPausedStatePreservingFailure()
                    updateNowPlayingInfo()
                    return
                }
                await advance(automatic: automatic)
                return
            }
            if let next {
                let insertIndex = min(queueIndex + 1, queue.count)
                queue.insert(next, at: insertIndex)
                queueIndex = insertIndex
                manualPlaybackModeOverride = nil
                playbackMode = preferredModeForNewTrack()
                // Radio lookup can outlive a pause tap. Preserve the latest
                // transport intent instead of reviving playback when it returns.
                await startCurrent(shouldPlay: wantsPlayback)
            } else if queueIndex + 1 < queue.count {
                queueIndex += 1
                manualPlaybackModeOverride = nil
                playbackMode = preferredModeForNewTrack()
                await startCurrent(shouldPlay: wantsPlayback)
            } else {
                if automatic {
                    finishPlaybackAtQueueEnd()
                }
            }
        } else if let nextIndex = QueueController.nextIndex(
            mode: queueMode,
            queueCount: queue.count,
            currentIndex: queueIndex,
            automatic: automatic) {
            queueIndex = nextIndex
            manualPlaybackModeOverride = nil
            playbackMode = preferredModeForNewTrack()
            await startCurrent(shouldPlay: automatic ? wantsPlayback : true)
        } else if automatic {
            finishPlaybackAtQueueEnd()
        }
    }

    func setQueueMode(_ mode: QueueMode) {
        guard queueMode != mode else { return }
        let interruptedAdvance = pendingRadioAdvance
        if mode != .radio {
            pendingRadioAdvance = nil
        }
        queueMode = mode
        prefetchedRadio = nil
        prefetchTask?.cancel()
        if mode == .radio, state == .playing {
            scheduleRadioPrefetch()
        } else if let interruptedAdvance {
            if interruptedAdvance.automatic, !wantsPlayback {
                setPausedStatePreservingFailure()
                updateNowPlayingInfo()
            } else {
                Task { [weak self] in
                    await self?.advance(automatic: interruptedAdvance.automatic)
                }
            }
        }
    }

    private func finishPlaybackAtQueueEnd() {
        wantsPlayback = false
        remoteStartupFallbackTask?.cancel()
        player?.pause()
        if duration > 0 {
            currentTime = duration
        }
        state = .paused
        updateNowPlayingInfo()
    }

    func playPrevious() async {
        let wasWaitingForRadioAdvance = pendingRadioAdvance != nil
        pendingRadioAdvance = nil
        directPlayRequestID = nil
        if wasWaitingForRadioAdvance {
            await startCurrent()
            return
        }
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
        pendingRadioAdvance = nil
        directPlayRequestID = nil
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
        wantsPlayback = true
        guard !isAudioSessionInterrupted else {
            setPausedStatePreservingFailure()
            updateNowPlayingInfo()
            return
        }
        // While radio mode resolves its next track, a remote play command should
        // update intent without restarting an ended (or deliberately paused) item.
        if pendingRadioAdvance != nil {
            state = player?.timeControlStatus == .playing ? .playing : .loading
            updateNowPlayingInfo()
            return
        }
        if case .failed = state {
            restartCurrentPlaybackAfterFailure()
            return
        }
        if activePlaybackGeneration == playbackGeneration,
           player?.currentItem?.status == .failed {
            restartCurrentPlaybackAfterFailure()
            return
        }
        guard activePlaybackGeneration == playbackGeneration,
              let player else {
            if current != nil {
                state = .loading
                updateNowPlayingInfo()
            }
            return
        }
        if duration > 0, currentTime >= duration - 0.5 {
            seek(to: 0)
        }
        player.play()
        rescheduleRemoteStartupFallbackIfNeeded()
        state = .playing
        updateNowPlayingInfo()
    }

    func pause() {
        wantsPlayback = false
        remoteStartupFallbackTask?.cancel()
        player?.pause()
        setPausedStatePreservingFailure()
        updateNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        let upperBound = duration > 0 ? duration : max(0, seconds)
        let target = min(max(0, seconds), upperBound)
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
        updateNowPlayingInfo()
    }

    private func restartCurrentPlaybackAfterFailure() {
        guard let expectedTrack = current else { return }
        let expectedGeneration = playbackGeneration
        let resumeAt = currentTime.isFinite ? currentTime : 0
        state = .loading
        updateNowPlayingInfo()
        Task { [weak self, expectedTrack, expectedGeneration] in
            guard let self,
                  self.playbackGeneration == expectedGeneration,
                  self.current?.id == expectedTrack.id,
                  self.wantsPlayback else { return }
            await self.startCurrent(resumeAt: resumeAt, shouldPlay: true)
        }
    }

    private func setPausedStatePreservingFailure() {
        if case .failed = state { return }
        state = .paused
    }


    /// 进度条交互:开始拖动时冻结时间回写,只更新显示;松手时一次性 seek。
    /// 当前在线播放音质偏好。默认30280=192K以平衡加载速度与听感;
    /// 用户可在播放器中手动切到更高音质(含Hi-Res/杜比)。
    /// 下载音质单独存 downloadQuality。
    static var playbackQuality: Int {
        PlaybackPreferences.playbackQuality
    }

    static var mvQuality: Int {
        UserDefaults.standard.integer(forKey: "mvQuality")
    }

    /// 在播放器里切换音质:写入偏好并按当前进度重取流续播。本地缓存曲目无需切换。
    func setPlaybackQuality(_ id: Int) async {
        UserDefaults.standard.set(id, forKey: PlaybackPreferences.playbackQualityKey)
        guard let track = current, CacheStore.shared.entry(for: track) == nil else { return }
        let shouldPlay = wantsPlayback
        streamResolver.invalidateAudio(for: track)
        await startCurrent(resumeAt: currentTime, shouldPlay: shouldPlay)
    }

    func setMVQuality(_ id: Int) async {
        UserDefaults.standard.set(id, forKey: "mvQuality")
        guard playbackMode == .mv else { return }
        await reloadCurrentMV(profile: .fullscreen, preferredQuality: id)
    }

    func beginScrub() {
        scrubTrackKey = current?.key
        isScrubbing = true
    }

    func endScrub(to seconds: Double) {
        let expectedTrackKey = scrubTrackKey
        scrubTrackKey = nil
        isScrubbing = false
        guard let current,
              expectedTrackKey?.matches(current) == true else { return }
        seek(to: seconds)
    }

    func setPlaybackMode(_ mode: PlaybackMode) async {
        guard mode != playbackMode else { return }
        let shouldPlay = wantsPlayback
        manualPlaybackModeOverride = mode
        playbackMode = mode
        await startCurrent(resumeAt: currentTime, shouldPlay: shouldPlay)
    }

    func upgradeMVForFullscreen() async {
        await reloadCurrentMV(profile: .fullscreen, preferredQuality: Self.mvQuality)
    }

    private func reloadCurrentMV(
        profile: BiliClient.VideoStreamProfile,
        preferredQuality: Int = 0
    ) async {
        guard playbackMode == .mv, var track = current else { return }
        let requestID = UUID()
        mvReloadRequestID = requestID
        let expectedGeneration = playbackGeneration
        do {
            if track.cid == nil {
                track = try await fillPlaybackPage(for: track)
            }
            guard let cid = track.cid else { return }
            let stream = try await client.videoStreamResult(
                bvid: track.bvid,
                cid: cid,
                profile: profile,
                preferredQuality: preferredQuality)
            guard mvReloadRequestID == requestID,
                  playbackGeneration == expectedGeneration,
                  current.map({ track.key.matches($0) }) ?? false,
                  playbackMode == .mv,
                  queue.indices.contains(queueIndex) else { return }
            queue[queueIndex] = track
            storePreparedVideoStream(PreparedVideoStream(
                url: stream.url,
                cid: cid,
                quality: stream.quality,
                fetchedAt: Date()), for: track.key)
            await startCurrent(
                resumeAt: currentTime.isFinite ? currentTime : 0,
                shouldPlay: wantsPlayback)
        } catch {
            // 全屏提质失败不影响当前 MV 播放。
        }
    }

    func handleScenePhase(isBackground: Bool) async {
        isAppInBackground = isBackground
        restoreCurrentArtworkFromImageCache()
        guard isBackground else {
            await ensureCurrentArtworkLoaded()
            return
        }
        autoMVTask?.cancel()
        guard playbackMode == .mv else { return }
        let shouldPlay = wantsPlayback
        playbackMode = .music
        await startCurrent(resumeAt: currentTime, shouldPlay: shouldPlay)
    }

    func prepareForInactiveSnapshot() {
        restoreCurrentArtworkFromImageCache()
    }

    func rememberCurrentCover(_ image: UIImage, for track: Track?) {
        guard let current,
              let track,
              track.key.matches(current) else { return }
        storeCurrentCover(image, for: current)
    }

    func restoreCurrentArtworkFromImageCache() {
        guard let current else {
#if DEBUG
            artworkDiag("restore.skip.noCurrent")
#endif
            return
        }
        guard currentCoverImageNeedsUpgrade else {
#if DEBUG
            artworkDiag("restore.skip.coverAlreadyUsable", track: current)
#endif
            return
        }
        guard let baseCoverURL = current.coverURL,
              let coverURL = BiliArtworkURL.thumbnail(
                baseCoverURL,
                width: 960,
                height: 540,
                rejectsTransparentPlaceholder: false
              ) else {
#if DEBUG
            artworkDiag("restore.skip.noCoverURL", track: current)
#endif
            return
        }
        if let cached = ImageMemoryCache.shared.bestImage(forAnyVariantOf: baseCoverURL)
            ?? ImageMemoryCache.shared.bestImage(forAnyVariantOf: coverURL) {
#if DEBUG
            artworkDiag("restore.hit.bestVariant", track: current, extra: "image=\(Self.debugImageDescription(cached))")
#endif
            storeCurrentCover(cached, for: current)
            return
        }
        let targetPixelSize = CGSize(width: 960, height: 540)
        guard let cached = ImageMemoryCache.shared.image(for: coverURL, targetPixelSize: targetPixelSize) else {
#if DEBUG
            artworkDiag("restore.miss", track: current, extra: "url=\(coverURL.absoluteString)")
#endif
            return
        }
#if DEBUG
        artworkDiag("restore.hit.exact", track: current, extra: "image=\(Self.debugImageDescription(cached))")
#endif
        storeCurrentCover(cached, for: current)
    }

    private func storeCurrentCover(_ image: UIImage, for track: Track) {
        guard current.map({ track.key.matches($0) }) ?? false else {
#if DEBUG
            artworkDiag("store.skip.staleTrack", track: track, extra: "image=\(Self.debugImageDescription(image))")
#endif
            return
        }
        let normalized = image.resized(maxDimension: 960)
        if coverImageKey?.matches(track) == true,
           let coverImage,
           Self.pixelArea(of: coverImage) >= Self.pixelArea(of: normalized) {
#if DEBUG
            artworkDiag(
                "store.skip.existingLarger",
                track: track,
                extra: "existing=\(Self.debugImageDescription(coverImage)) incoming=\(Self.debugImageDescription(normalized))")
#endif
            return
        }
        coverImage = normalized
        coverImageKey = track.key
        artworkPalette = PlayerArtworkPalette.from(normalized)
        artworkPaletteKey = track.key
#if DEBUG
        artworkDiag("store.done", track: track, extra: "image=\(Self.debugImageDescription(normalized))")
#endif
        updateNowPlayingInfo()
    }

    func ensureCurrentArtworkLoaded() async {
        guard let track = current,
              currentCoverImageNeedsUpgrade else { return }
        await loadCover(for: track, generation: playbackGeneration)
    }

    private var currentCoverImageNeedsUpgrade: Bool {
        guard let image = currentCoverImage else { return true }
        return Self.pixelArea(of: image) < CGFloat(540 * 304)
    }

    // MARK: - 播放核心

    private func startCurrent(resumeAt: Double = 0, shouldPlay: Bool = true) async {
        directPlayRequestID = nil
        pendingRadioAdvance = nil
        isMiniPlayerHidden = false
        guard var track = current else { return }
        // 先停掉旧 player:新流解析弱网可达数秒,不暂停会让上一首继续出声,
        // 且期间 seek 会作用在旧 item 上。与失败路径 catch 分支的 pause 对齐。
        player?.pause()
        preloadTask?.cancel()
        preloadTask = nil
        streamResolver.cancelPreparations(except: track)
        wantsPlayback = shouldPlay
        let generation = UUID()
        playbackGeneration = generation
        firstPlayingDiagnosticsGeneration = nil
        retriedPreparedStreamGenerations.removeAll()
        remoteStartupFallbackGenerations.removeAll()
        playbackDiagnostics.record(.currentAssigned, track: track)
        startupTestHooks.record(.currentAssigned)
        state = .loading
        isScrubbing = false
        scrubTrackKey = nil
#if DEBUG
        artworkDiag("startCurrent.assigned", track: track, extra: "resumeAt=\(String(format: "%.2f", resumeAt))")
#endif
        currentTime = resumeAt
        lyrics = []
        videoAvailable = false
        currentAudioQuality = nil
        currentAudioBandwidth = nil
        currentVideoQuality = nil
        autoMVTask?.cancel()
        autoCacheTask?.cancel()
        startupArtworkTask?.cancel()
        postPlaybackTask?.cancel()
        queuePrefetchTask?.cancel()
        remoteStartupFallbackTask?.cancel()
        scheduleStartupArtworkPrefetch(for: track, generation: generation)
        do {
            let source = try await resolvePlaybackSource(for: track)
            track = source.track
            guard playbackGeneration == generation,
                  current.map({ track.key.matches($0) }) ?? false,
                  queue.indices.contains(queueIndex) else { return }
            queue[queueIndex] = track
            if source.kind == .mvRemote {
                videoAvailable = true
                currentVideoQuality = source.videoQuality
            } else {
                currentAudioQuality = source.quality
                currentAudioBandwidth = source.bandwidth
            }
            playbackDiagnostics.record(
                .sourceResolved,
                track: track,
                sourceKind: source.kind,
                quality: currentAudioQuality,
                bandwidth: currentAudioBandwidth)
            startupTestHooks.record(.sourceResolved(source.kind))
            let latestResumeAt = currentTime.isFinite ? currentTime : resumeAt
            startPlayback(source: source, resumeAt: latestResumeAt, generation: generation)
        } catch {
            guard playbackGeneration == generation else { return }
            if playbackMode == .mv {
                videoAvailable = false
                playbackMode = .music
                await startCurrent(
                    resumeAt: currentTime.isFinite ? currentTime : resumeAt,
                    shouldPlay: wantsPlayback)
                return
            }
            wantsPlayback = false
            player?.pause()
            state = .failed(error.localizedDescription)
            updateNowPlayingInfo()
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
        pendingRadioAdvance = nil
        tearDownPlayerObservers()
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
        isScrubbing = false
        scrubTrackKey = nil
        lyrics = []
        videoAvailable = !tracks.isEmpty
        currentAudioQuality = nil
        currentAudioBandwidth = nil
        currentVideoQuality = nil
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
        return Track(
            aid: info.aid,
            ownerMid: info.owner.mid,
            bvid: info.bvid,
            cid: page.cid,
            title: info.title,
            artist: info.owner.name,
            coverURL: URL(string: info.pic),
            duration: page.duration
        )
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
            }
            guard let cid = track.cid else {
                throw BiliClient.APIError(code: -1, message: "无分P")
            }
            let url: URL
            let quality: Int
            if let prepared = preparedVideoStream(for: track), prepared.cid == cid {
                url = prepared.url
                quality = prepared.quality
            } else {
                let stream = try await client.videoStreamResult(bvid: track.bvid, cid: cid)
                url = stream.url
                quality = stream.quality
                storePreparedVideoStream(
                    PreparedVideoStream(url: url, cid: cid, quality: quality, fetchedAt: Date()),
                    for: track.key)
            }
            return PlaybackSource(
                track: track,
                url: url,
                candidateURLs: [url],
                isLocal: false,
                kind: .mvRemote,
                quality: nil,
                bandwidth: nil,
                videoQuality: quality)
        }

        if let cached = CacheStore.shared.entry(for: track) {
            track.cid = cached.cid
            track.duration = cached.duration
            return PlaybackSource(
                track: track,
                url: CacheStore.audioDir.appendingPathComponent(cached.fileName),
                candidateURLs: [],
                isLocal: true,
                kind: .localCache,
                quality: cached.quality,
                bandwidth: nil)
        }

        if let prepared = streamResolver.cachedAudio(
            for: track,
            preferredQuality: Self.playbackQuality
        ) {
            track.cid = prepared.cid
            track.duration = prepared.duration
            return PlaybackSource(
                track: track,
                url: prepared.url,
                candidateURLs: prepared.candidateURLs,
                isLocal: false,
                kind: .preparedRemote,
                quality: prepared.quality,
                bandwidth: prepared.bandwidth,
                mimeType: prepared.mimeType,
                codecs: prepared.codecs)
        }

        let prepared = try await streamResolver.prepareAudio(
            for: track,
            preferredQuality: Self.playbackQuality)
        track.cid = prepared.cid
        track.duration = prepared.duration
        return PlaybackSource(
            track: track,
            url: prepared.url,
            candidateURLs: prepared.candidateURLs,
            isLocal: false,
            kind: .freshRemote,
            quality: prepared.quality,
            bandwidth: prepared.bandwidth,
            mimeType: prepared.mimeType,
            codecs: prepared.codecs)
    }

    /// 电台选歌:用统一推荐引擎打分,避免 related 第一条把队列带偏。
    private func radioPick(after seed: Track, excludedKeys: Set<TrackKey>) async -> Track? {
        if let radioTrackProvider {
            return await radioTrackProvider(seed, excludedKeys)
        }
        if let track = await fastRelatedRadioPick(after: seed.bvid, excludedKeys: excludedKeys) {
            return track
        }
        return await RecommendationEngine().nextRadioTrack(after: seed, excludedKeys: excludedKeys)
    }

    /// 自动下一首必须先保证速度:related 接口通常最快,且返回 cid 时能少一次 pagelist 请求。
    private func fastRelatedRadioPick(after bvid: String, excludedKeys: Set<TrackKey>) async -> Track? {
        guard let items = try? await client.related(bvid: bvid) else { return nil }
        let tracks = items
            .map(Track.init(related:))
            .filter { track in !excludedKeys.contains { $0.matches(track) } }
        return tracks.first(where: MusicFilter.isStrictMusic)
            ?? tracks.first(where: MusicFilter.isMusic)
    }

    private func scheduleRadioPrefetch() {
        prefetchTask?.cancel()
        guard queueMode == .radio, let seed = current else { return }
        let seedKey = seed.key
        let expectedIndex = queueIndex
        let expectedGeneration = playbackGeneration
        let excluded = playedKeys.union(queue.map(\.key))
        startupTestHooks.record(.queuePrefetchScheduled)
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard let next = await self.radioPick(after: seed, excludedKeys: excluded) else { return }
            guard !Task.isCancelled,
                  self.playbackGeneration == expectedGeneration,
                  self.queueMode == .radio,
                  self.queueIndex == expectedIndex,
                  self.current.map({ seedKey.matches($0) }) ?? false else { return }
            self.prefetchedRadio = (seedKey, next)
            await self.prepare(track: next)
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
        prunePreparedVideoStreams()
        let key = track.key
        if let exact = preparedVideoStreams[key] {
            return exact
        }
        guard track.cid == nil else { return nil }
        return preparedVideoStreams[TrackKey(bvid: track.bvid, cid: nil)]
    }

    private func storePreparedVideoStream(_ stream: PreparedVideoStream, for key: TrackKey) {
        preparedVideoStreams[key] = stream
        prunePreparedVideoStreams()
    }

    private func prunePreparedVideoStreams(now: Date = Date()) {
        preparedVideoStreams = preparedVideoStreams.filter {
            now.timeIntervalSince($0.value.fetchedAt) < Self.preparedVideoStreamTTL
        }
        guard preparedVideoStreams.count > Self.preparedVideoStreamLimit else { return }
        let overflow = preparedVideoStreams.count - Self.preparedVideoStreamLimit
        let oldestKeys = preparedVideoStreams
            .sorted { $0.value.fetchedAt < $1.value.fetchedAt }
            .prefix(overflow)
            .map(\.key)
        for key in oldestKeys {
            preparedVideoStreams[key] = nil
        }
    }

    private func prepare(track: Track) async {
        guard CacheStore.shared.entry(for: track) == nil else { return }
        await streamResolver.warmAudioCDN(for: track, preferredQuality: Self.playbackQuality)
    }

    private func schedulePostPlaybackWork(for track: Track, generation: UUID, resumeAt: Double) {
        postPlaybackTask?.cancel()
        autoMVTask?.cancel()
        autoCacheTask?.cancel()
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
        if PlaybackPreferences.autoCache, CacheStore.shared.entry(for: track) == nil {
            startupTestHooks.record(.autoCacheScheduled)
            autoCacheTask = Task(priority: .background) { [weak self, track, generation] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled,
                      let self,
                      self.isCurrent(track, generation: generation) else { return }
                await DownloadManager.shared.download(track: track)
            }
        }
        autoMVTask = Task(priority: .utility) { [weak self, track, generation] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.startupTestHooks.record(.mvPreparationScheduled)
            await self?.prepareVideoIfUseful(for: track, generation: generation)
        }
    }

    private func scheduleStartupArtworkPrefetch(for track: Track, generation: UUID) {
#if DEBUG
        artworkDiag(
            "startupPrefetch.enter",
            track: track,
            extra: "hasCoverURL=\(track.coverURL != nil)")
#endif
        guard track.coverURL != nil else {
#if DEBUG
            artworkDiag("startupPrefetch.skip.noCoverURL", track: track)
#endif
            return
        }
        startupTestHooks.record(.artworkPrefetchScheduled)
        restoreCurrentArtworkFromImageCache()
#if DEBUG
        artworkDiag(
            "startupPrefetch.afterRestore",
            track: track,
            extra: "needsUpgrade=\(currentCoverImageNeedsUpgrade)")
#endif
        guard currentCoverImageNeedsUpgrade else {
#if DEBUG
            artworkDiag("startupPrefetch.skip.coverReady", track: track)
#endif
            return
        }

        startupArtworkTask = Task(priority: .userInitiated) { [weak self, track, generation] in
            await self?.loadCover(
                for: track,
                generation: generation,
                width: 320,
                height: 180,
                priority: .userInitiated)
        }
    }

    private func isCurrent(_ track: Track, generation: UUID) -> Bool {
        playbackGeneration == generation && (current.map { track.key.matches($0) } ?? false)
    }

    private func prefetchUpcomingTracks() {
        scheduleRadioPrefetch()
        scheduleQueuePrefetch()
    }

    /// 成对拆除挂在 player/item 上的全部观察器。丢弃或替换 player 前必须调用,
    /// 否则 timeObserver 留在被释放的 AVPlayer 上有崩溃风险。
    private func tearDownPlayerObservers() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let itemFailureObserver { NotificationCenter.default.removeObserver(itemFailureObserver) }
        statusObserver?.invalidate()
        itemStatusObserver?.invalidate()
        bufferObserver?.invalidate()
        timeObserver = nil
        endObserver = nil
        statusObserver = nil
        itemStatusObserver = nil
        itemFailureObserver = nil
        bufferObserver = nil
    }

    private func startPlayback(source: PlaybackSource, resumeAt: Double = 0, generation: UUID) {
        remoteStartupFallbackTask?.cancel()
        remoteStartupFallbackTask = nil
        tearDownPlayerObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        activePlaybackSource = source
        activePlaybackGeneration = generation
        if let startPlaybackOverride = startupTestHooks.startPlaybackOverride {
            recordPlayerItemCreated(for: source)
            startPlaybackOverride(source, resumeAt, generation)
            if wantsPlayback, !isAudioSessionInterrupted {
                recordPlayRequested(for: source)
            } else {
                state = .paused
                updateNowPlayingInfo()
            }
            if wantsPlayback,
               !isAudioSessionInterrupted,
               startupTestHooks.reportFirstPlayingImmediately {
                handleFirstObservedPlaying(source: source, generation: generation, resumeAt: resumeAt)
            }
            return
        }

        let asset: AVURLAsset
        if source.isLocal {
            asset = AVURLAsset(url: source.url)
        } else {
            var options: [String: Any] = [
                "AVURLAssetHTTPHeaderFieldsKey": BiliClient.headers
            ]
            if let userAgent = BiliClient.headers["User-Agent"] {
                options[AVURLAssetHTTPUserAgentKey] = userAgent
            }
            if source.kind != .mvRemote, let mimeType = source.mimeType, !mimeType.isEmpty {
                // Bilibili CDN 常把音频 m4s 返回为 application/octet-stream。
                // 使用 playurl 声明的实际 MIME，保留 AAC/Hi-Res/未来杜比各自的格式。
                options[AVURLAssetOverrideMIMETypeKey] = mimeType
            }
            asset = AVURLAsset(url: source.url, options: options)
        }
        let item = AVPlayerItem(asset: asset)
        // 音频保留较长缓冲抵抗弱网；高码率 MV 若同样缓冲 30 秒会显著
        // 放大内存占用，尤其是 4K 全屏流。暂停 MV 时也不要继续拉取数据。
        item.preferredForwardBufferDuration =
            PlaybackBufferPolicy.preferredForwardBufferDuration(for: source)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused =
            PlaybackBufferPolicy.allowsNetworkUseWhilePaused(for: source)
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
                guard let self,
                      self.playbackGeneration == generation,
                      self.player === player,
                      self.player?.currentItem === item,
                      !self.isScrubbing else { return }
                let seconds = time.seconds
                guard seconds.isFinite, seconds >= 0 else { return }
                self.currentTime = seconds
            }
        }
        // 让播放/暂停状态始终跟随播放器真实状态(缓冲、卡顿、自动暂停都能同步 UI)
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self,
                      self.playbackGeneration == generation,
                      self.player === player,
                      self.player?.currentItem === item else { return }
                if case .failed = self.state { return }
                switch player.timeControlStatus {
                case .playing:
                    self.handleFirstObservedPlaying(source: source, generation: generation, resumeAt: resumeAt)
                case .paused:
                    // 关键:区分「用户主动暂停」与「缓冲断流」。用户想播却变 paused = 断流,
                    // 显示 loading 而非 paused,等 bufferObserver 在缓冲恢复后续播。
                    self.state = self.isAudioSessionInterrupted
                        ? .paused
                        : (self.wantsPlayback ? .loading : .paused)
                    self.updateNowPlayingInfo()
                case .waitingToPlayAtSpecifiedRate:
                    self.state = self.wantsPlayback && !self.isAudioSessionInterrupted
                        ? .loading
                        : .paused
                    self.updateNowPlayingInfo()
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
                PlaybackFailureDiagnostics.report(
                    trigger: .itemStatus,
                    source: source,
                    error: item.error,
                    item: item)
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
                PlaybackFailureDiagnostics.report(
                    trigger: .failedToEnd,
                    source: source,
                    error: error,
                    item: item)
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
                   !self.isAudioSessionInterrupted,
                   self.pendingRadioAdvance == nil,
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
                      self.player?.currentItem === item,
                      self.pendingRadioAdvance == nil else { return }
                // 只有真正播到资源结尾才切歌。弱网时 didPlayToEnd 可能在缓冲
                // 耗尽处提前触发,若按旧逻辑(播过 5s 就切)会在线放歌时随机跳曲。
                // 以资源自身时长 item.duration 为准,缺失时退回元数据时长。
                let assetDuration = item.duration.seconds
                let reference = assetDuration.isFinite && assetDuration > 0 ? assetDuration : self.duration
                let actualTime = item.currentTime().seconds
                let reachedEnd = reference <= 0 || actualTime >= reference - 2
                guard reachedEnd else {
                    // 提前触发 = 弱网缓冲断流,不切歌,尝试续播让它自行恢复。
                    if self.wantsPlayback, !self.isAudioSessionInterrupted {
                        self.player?.play()
                    } else {
                        self.setPausedStatePreservingFailure()
                        self.updateNowPlayingInfo()
                    }
                    return
                }
                await self.advance(automatic: true)
            }
        }
        if resumeAt > 0 {
            player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
        }
        if wantsPlayback, !isAudioSessionInterrupted {
            recordPlayRequested(for: source)
            Self.activateAudioSession()
            player.playImmediately(atRate: 1)
            scheduleRemoteStartupFallback(for: source, generation: generation, resumeAt: resumeAt)
        } else {
            state = .paused
        }
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
                      self.player?.timeControlStatus != .playing,
                      self.wantsPlayback,
                      self.activePlaybackGeneration == generation,
                      self.activePlaybackSource?.url == source.url,
                      self.current.map({ source.track.key.matches($0) }) ?? false,
                      !self.remoteStartupFallbackGenerations.contains(generation) else { return }

                self.remoteStartupFallbackGenerations.insert(generation)
                Task { await AudioCDNSelector.recordPlaybackFailure(url: source.url) }
                log.debug("remote startup fallback host=\(fallbackURL.host() ?? "nil", privacy: .public)")
                let retrySource = PlaybackSource(
                    track: source.track,
                    url: fallbackURL,
                    candidateURLs: source.candidateURLs,
                    isLocal: false,
                    kind: source.kind,
                    quality: source.quality,
                    bandwidth: source.bandwidth,
                    mimeType: source.mimeType,
                    codecs: source.codecs)
                self.startPlayback(
                    source: retrySource,
                    resumeAt: self.currentTime.isFinite ? self.currentTime : resumeAt,
                    generation: generation)
            }
        }
    }

    private func rescheduleRemoteStartupFallbackIfNeeded() {
        guard pendingRadioAdvance == nil,
              let source = activePlaybackSource,
              let generation = activePlaybackGeneration,
              generation == playbackGeneration,
              firstPlayingDiagnosticsGeneration != generation else { return }
        scheduleRemoteStartupFallback(
            for: source,
            generation: generation,
            resumeAt: currentTime)
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
        guard wantsPlayback, !isAudioSessionInterrupted else {
            player?.pause()
            setPausedStatePreservingFailure()
            updateNowPlayingInfo()
            return
        }
        state = .playing
        updateNowPlayingInfo()
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
        guard isActivePlaybackSource(source, generation: generation),
              handlingPlaybackFailureGenerations.insert(generation).inserted else { return }
        defer { handlingPlaybackFailureGenerations.remove(generation) }
        remoteStartupFallbackTask?.cancel()
        remoteStartupFallbackTask = nil

        if !source.isLocal, source.kind != .mvRemote {
            Task { await AudioCDNSelector.recordPlaybackFailure(url: source.url) }
        }

        if Self.PlaybackFailureRecoveryPolicy.shouldFallbackToMusic(sourceKind: source.kind) {
            guard isActivePlaybackSource(source, generation: generation) else { return }
            let shouldPlay = wantsPlayback
            let retryAt = resumeAt.isFinite ? resumeAt : currentTime
            videoAvailable = false
            playbackMode = .music
            manualPlaybackModeOverride = .music
            await startCurrent(resumeAt: retryAt, shouldPlay: shouldPlay)
            return
        }

        if let fallbackSource = await remoteFallbackSource(for: source, generation: generation) {
            guard isActivePlaybackSource(source, generation: generation) else { return }
            PlaybackFailureDiagnostics.reportRetry(
                .candidateFallback,
                source: source,
                targetURL: fallbackSource.url)
            startPlayback(
                source: fallbackSource,
                resumeAt: resumeAt.isFinite ? resumeAt : currentTime,
                generation: generation)
            return
        }

        guard isActivePlaybackSource(source, generation: generation) else { return }
        // freshRemote 也给一次重取流机会:暂停过夜后流 URL(约 2 小时时效)会过期,
        // 复用 retriedPreparedStreamGenerations 防止无限循环。
        guard source.kind == .preparedRemote || source.kind == .localCache
                || source.kind == .freshRemote,
              !retriedPreparedStreamGenerations.contains(generation) else {
            startupTestHooks.record(.failureSurfaced)
            PlaybackFailureDiagnostics.reportRetry(.surfaceFailure, source: source)
            wantsPlayback = false
            state = .failed(errorDescription ?? "播放失败")
            updateNowPlayingInfo()
            return
        }

        retriedPreparedStreamGenerations.insert(generation)
        PlaybackFailureDiagnostics.reportRetry(.invalidatePrepared, source: source)
        if source.kind == .localCache {
            if let entry = CacheStore.shared.entry(for: source.track) {
                CacheStore.shared.remove(entry)
            }
            streamResolver.invalidateAudio(for: source.track)
        } else {
            if source.kind == .preparedRemote {
                startupTestHooks.record(.preparedStreamInvalidated)
            }
            streamResolver.invalidateAudio(for: source.track)
        }

        do {
            let prepared = try await streamResolver.prepareAudio(
                for: source.track,
                preferredQuality: Self.playbackQuality)
            var retryTrack = source.track
            retryTrack.cid = prepared.cid
            retryTrack.duration = prepared.duration
            guard isActivePlaybackSource(source, generation: generation),
                  current.map({ retryTrack.key.matches($0) }) ?? false else { return }
            queue[queueIndex] = retryTrack
            let retrySource = PlaybackSource(
                track: retryTrack,
                url: prepared.url,
                candidateURLs: prepared.candidateURLs,
                isLocal: false,
                kind: .freshRemote,
                quality: prepared.quality,
                bandwidth: prepared.bandwidth,
                mimeType: prepared.mimeType,
                codecs: prepared.codecs)
            currentAudioQuality = retrySource.quality
            currentAudioBandwidth = retrySource.bandwidth
            playbackDiagnostics.record(
                .sourceResolved,
                track: retryTrack,
                sourceKind: retrySource.kind,
                quality: retrySource.quality,
                bandwidth: retrySource.bandwidth)
            startupTestHooks.record(.sourceResolved(retrySource.kind))
            PlaybackFailureDiagnostics.reportRetry(
                .freshResolved,
                source: source,
                targetURL: retrySource.url)
            if source.kind == .preparedRemote {
                startupTestHooks.record(.preparedStreamRetryRequested)
            }
            startPlayback(source: retrySource, resumeAt: resumeAt.isFinite ? resumeAt : currentTime, generation: generation)
        } catch {
            guard isActivePlaybackSource(source, generation: generation) else { return }
            startupTestHooks.record(.failureSurfaced)
            PlaybackFailureDiagnostics.report(
                trigger: .freshResolution,
                source: source,
                error: error,
                item: nil)
            PlaybackFailureDiagnostics.reportRetry(.surfaceFailure, source: source)
            wantsPlayback = false
            state = .failed(error.localizedDescription)
            updateNowPlayingInfo()
        }
    }

    private func isActivePlaybackSource(_ source: PlaybackSource, generation: UUID) -> Bool {
        playbackGeneration == generation
            && activePlaybackGeneration == generation
            && activePlaybackSource?.url == source.url
            && (current.map { source.track.key.matches($0) } ?? false)
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
        guard isActivePlaybackSource(source, generation: generation),
              !remoteStartupFallbackGenerations.contains(generation) else { return nil }

        remoteStartupFallbackGenerations.insert(generation)
        log.debug("remote failure fallback host=\(fallbackURL.host() ?? "nil", privacy: .public)")
        return PlaybackSource(
            track: source.track,
            url: fallbackURL,
            candidateURLs: source.candidateURLs,
            isLocal: false,
            kind: source.kind,
            quality: source.quality,
            bandwidth: source.bandwidth,
            mimeType: source.mimeType,
            codecs: source.codecs)
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

    private func loadCover(
        for track: Track,
        generation: UUID,
        width: Int = 960,
        height: Int = 540,
        priority: TaskPriority = .utility
    ) async {
        let startedAt = CFAbsoluteTimeGetCurrent()
        guard let coverURL = BiliArtworkURL.thumbnail(
            track.coverURL,
            width: width,
            height: height,
            rejectsTransparentPlaceholder: false
        ) else {
#if DEBUG
            artworkDiag("loadCover.skip.noURL", track: track, extra: "target=\(width)x\(height)")
#endif
            return
        }
        guard isCurrent(track, generation: generation) else {
#if DEBUG
            artworkDiag("loadCover.skip.notCurrentBeforeLoad", track: track, extra: "target=\(width)x\(height)")
#endif
            return
        }
#if DEBUG
        artworkDiag("loadCover.start", track: track, extra: "target=\(width)x\(height) url=\(coverURL.absoluteString)")
#endif
        let targetPixelSize = CGSize(width: width, height: height)
        if let cached = ImageMemoryCache.shared.image(for: coverURL, targetPixelSize: targetPixelSize) {
            guard isCurrent(track, generation: generation) else { return }
#if DEBUG
            artworkDiag(
                "loadCover.cacheHit",
                track: track,
                extra: "target=\(width)x\(height) elapsed=\(Self.debugElapsedMS(since: startedAt)) image=\(Self.debugImageDescription(cached))")
#endif
            storeCurrentCover(cached, for: track)
            return
        }
        guard let decoded = await ImageLoadCoordinator.shared.image(
            for: coverURL,
            targetPixelSize: targetPixelSize,
            scale: 1,
            priority: priority
        ) else {
#if DEBUG
            artworkDiag(
                "loadCover.downloadNil",
                track: track,
                extra: "target=\(width)x\(height) elapsed=\(Self.debugElapsedMS(since: startedAt))")
#endif
            return
        }
        guard isCurrent(track, generation: generation) else {
#if DEBUG
            artworkDiag(
                "loadCover.skip.notCurrentAfterLoad",
                track: track,
                extra: "target=\(width)x\(height) elapsed=\(Self.debugElapsedMS(since: startedAt)) image=\(Self.debugImageDescription(decoded))")
#endif
            return
        }
        ImageMemoryCache.shared.insert(decoded, for: coverURL, targetPixelSize: targetPixelSize)
#if DEBUG
        artworkDiag(
            "loadCover.downloadDone",
            track: track,
            extra: "target=\(width)x\(height) elapsed=\(Self.debugElapsedMS(since: startedAt)) image=\(Self.debugImageDescription(decoded))")
#endif
        storeCurrentCover(decoded, for: track)
    }

    private static func pixelArea(of image: UIImage) -> CGFloat {
        image.size.width * image.scale * image.size.height * image.scale
    }

#if DEBUG
    private func artworkDiag(_ message: String, track: Track? = nil, extra: String = "") {
        guard ProcessInfo.processInfo.environment["BILIMUSIC_ARTWORK_DIAGNOSTICS"] == "1" else {
            return
        }
        let track = track ?? current
        let trackKey = track?.key.description ?? "nil"
        let currentKey = current?.key.description ?? "nil"
        let storedKey = coverImageKey?.description ?? "nil"
        let hasMatchingImage = track.map { coverImageKey?.matches($0) == true && coverImage != nil } ?? false
        let coverURLState = track?.coverURL == nil ? "nil" : "set"
        let stateText = String(describing: state)
        let suffix = extra.isEmpty ? "" : " \(extra)"
        NSLog(
            "ARTWORK_DIAG engine %@ track=%@ current=%@ coverURL=%@ storedKey=%@ hasMatchingImage=%@ state=%@%@",
            message,
            trackKey,
            currentKey,
            coverURLState,
            storedKey,
            hasMatchingImage ? "true" : "false",
            stateText,
            suffix
        )
    }

    private static func debugImageDescription(_ image: UIImage?) -> String {
        guard let image else { return "nil" }
        let width = Int((image.size.width * image.scale).rounded())
        let height = Int((image.size.height * image.scale).rounded())
        return "\(width)x\(height)@\(String(format: "%.1f", image.scale))"
    }

    private static func debugElapsedMS(since start: CFAbsoluteTime) -> String {
        String(format: "%.1fms", (CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
#endif

    private func loadLyrics(for track: Track, generation: UUID) async {
        // 只用 LRCLIB 在线歌词。不再 fallback 到 B 站字幕——音乐区"字幕"多是自动生成的 CC,
        // 把伴奏标成"♪音乐♪",当歌词用纯属错配,宁可显示"无歌词"。
        let online = try? await lyricsClient.lyrics(for: track)
        guard playbackGeneration == generation, current.map({ track.key.matches($0) }) ?? false else { return }
        lyrics = online ?? []
    }

    private func prepareVideoIfUseful(for track: Track, generation: UUID) async {
        guard !isAppInBackground, playbackMode == .music, let cid = track.cid else { return }
        // 先查 90 分钟 prepared 缓存,命中且 cid 匹配时跳过网络请求。
        let hasPreparedVideo: Bool
        if let prepared = preparedVideoStream(for: track), prepared.cid == cid {
            hasPreparedVideo = true
        } else {
            let videoStream = try? await client.videoStreamResult(bvid: track.bvid, cid: cid)
            guard playbackGeneration == generation, current.map({ track.key.matches($0) }) ?? false else { return }
            if let videoStream {
                storePreparedVideoStream(PreparedVideoStream(
                    url: videoStream.url,
                    cid: cid,
                    quality: videoStream.quality,
                    fetchedAt: Date()), for: track.key)
            }
            hasPreparedVideo = videoStream != nil
        }
        let policy = PreparedVideoAvailabilityPolicy.applyPreparedVideo(
            currentPlaybackMode: playbackMode,
            hasPreparedVideo: hasPreparedVideo)
        videoAvailable = policy.videoAvailable
        playbackMode = policy.playbackMode
        guard AutomaticPlaybackPolicy.shouldSwitchToMV(
            prefersMVOnWiFi: PlaybackPreferences.preferMVOnWiFi,
            isWiFi: NetworkMonitor.shared.isWiFi,
            hasManualModeOverride: manualPlaybackModeOverride != nil,
            currentMode: playbackMode,
            hasPreparedVideo: hasPreparedVideo,
            wantsPlayback: wantsPlayback,
            isAppActive: !isAppInBackground
        ) else { return }
        playbackMode = .mv
        await startCurrent(resumeAt: currentTime)
    }

    // MARK: - 锁屏 / 控制中心

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        var targets: [(command: MPRemoteCommand, token: Any)] = []
        targets.append((center.playCommand, center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }))
        targets.append((center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }))
        targets.append((center.nextTrackCommand, center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.playNext() }
            return .success
        }))
        targets.append((center.previousTrackCommand, center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.playPrevious() }
            return .success
        }))
        targets.append((center.changePlaybackPositionCommand, center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }))
        remoteCommandTargets = targets
    }

    private func setUpAudioSessionNotifications() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioSessionInterruption(notification)
            }
        }
        let routeChange = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioRouteChange(notification)
            }
        }
        audioSessionObservers = [interruption, routeChange]
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            isAudioSessionInterrupted = true
            player?.pause()
            setPausedStatePreservingFailure()
            updateNowPlayingInfo()
        case .ended:
            isAudioSessionInterrupted = false
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            guard wantsPlayback, options.contains(.shouldResume) else {
                wantsPlayback = false
                setPausedStatePreservingFailure()
                updateNowPlayingInfo()
                return
            }
            Self.activateAudioSession()
            if pendingRadioAdvance == nil,
               activePlaybackGeneration == playbackGeneration {
                player?.play()
                rescheduleRemoteStartupFallbackIfNeeded()
            }
            state = .loading
            updateNowPlayingInfo()
        @unknown default:
            break
        }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable else {
            return
        }
        pause()
    }

    private static func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    private static func activateAudioSession() {
        configureAudioSession()
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func updateNowPlayingInfo() {
        guard let track = current else { return }
        let metadata = TrackTitleFormatter.displayMetadata(for: track)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: metadata.title,
            MPMediaItemPropertyArtist: metadata.artist,
            MPMediaItemPropertyPlaybackDuration: Double(track.duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: queueIndex,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
        ]
        if let coverImage = currentCoverImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: coverImage.size) { _ in coverImage }
        }
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = hasNext
        center.previousTrackCommand.isEnabled = hasPrevious || currentTime > 3
        center.changePlaybackPositionCommand.isEnabled = duration > 0
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
