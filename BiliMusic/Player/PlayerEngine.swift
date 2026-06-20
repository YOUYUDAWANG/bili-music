import AVFoundation
import MediaPlayer
import Observation
import OSLog
import UIKit

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "player")

/// 领域模型：一首曲目。流 URL 不持久化，只存 bvid/cid，每次播放现取。
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
    var id: String { bvid }

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

    /// 由搜索结果构造。
    init(search item: BiliClient.SearchItem) {
        self.init(aid: item.aid, ownerMid: item.mid, typeID: item.typeid, bvid: item.bvid, title: item.cleanTitle, artist: item.author,
                  coverURL: item.coverURL, duration: item.durationSeconds)
    }

    /// 由相关推荐构造。
    init(related item: BiliClient.RelatedItem) {
        self.init(aid: item.aid, ownerMid: item.owner.mid, bvid: item.bvid, cid: item.cid, title: item.title, artist: item.owner.name,
                  coverURL: URL(string: item.pic), duration: item.duration)
    }

    /// 由合集条目构造。
    init(playlist item: BiliClient.UPPlaylistItem, artist: String, ownerMid: Int) {
        self.init(aid: item.aid, ownerMid: ownerMid, bvid: item.bvid, cid: item.cid,
                  title: item.title, artist: artist,
                  coverURL: item.pic.flatMap(URL.init(string:)), duration: item.duration ?? 0)
    }
}

/// 全局播放引擎：AVPlayer + 队列 + 播放状态 + 歌词 + MV/音乐模式 + 预取调度 + 锁屏控制。
@Observable
@MainActor
final class PlayerEngine {
    /// 播放状态。
    enum State: Equatable {
        case idle, loading, playing, paused
        case failed(String)
    }

    /// 音乐 / MV 模式。
    enum PlaybackMode: String, CaseIterable, Identifiable {
        case music = "音乐"
        case mv = "MV"
        var id: String { rawValue }
    }

    /// 队列推进策略：顺序 / 随机 / 单曲循环 / 电台。
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

    /// 一行歌词（起止时间 + 文本）。
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

    var current: Track? { queue.indices.contains(queueIndex) ? queue[queueIndex] : nil }
    var duration: Double { Double(current?.duration ?? 0) }
    var hasNext: Bool {
        queueIndex + 1 < queue.count || queueMode == .radio || queueMode == .repeatOne || (queueMode == .shuffle && queue.count > 1)
    }
    var hasPrevious: Bool { queueIndex > 0 }
    var avPlayer: AVPlayer? { player }

    private let client = BiliClient()
    private let lyricsClient = LyricsClient()
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var coverImage: UIImage?
    private var playedBVs: Set<String> = []   // 电台去重
    private var prefetchTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var autoMVTask: Task<Void, Never>?
    private var preparedStreams: [String: PreparedStream] = [:]
    private var preparingStreams: [String: Task<PreparedStream, Error>] = [:]
    private var schedulePreloadInflight = 0   // 限制滚动触发的预加载并发,避免一次划过几十行齐发请求被限流
    private static let maxSchedulePreloadInflight = 3
    private var preparedVideoStreams: [String: PreparedVideoStream] = [:]
    private var prefetchedRadio: (seed: String, track: Track)?
    private var playbackGeneration = UUID()
    private var manualPlaybackModeOverride: PlaybackMode?

    /// 预取好的音频流（带取流时间，用于判过期）。
    private struct PreparedStream {
        let url: URL
        let cid: Int
        let duration: Int
        let quality: Int
        let bandwidth: Int
        let fetchedAt: Date
    }

    /// 预取好的 MV 流。
    private struct PreparedVideoStream {
        let url: URL
        let cid: Int
        let fetchedAt: Date
    }

    /// 配置音频会话为后台播放，并注册锁屏/控制中心远程命令。
    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        _ = NetworkMonitor.shared
        setUpRemoteCommands()
    }

    // MARK: - 对外操作

    /// 用一组曲目替换队列并从指定位置开播(搜索页点击)
    func play(tracks: [Track], startAt index: Int, queueMode: QueueMode? = nil) async {
        prefetchTask?.cancel()
        autoMVTask?.cancel()
        queue = tracks
        queueIndex = index
        playedBVs = []
        manualPlaybackModeOverride = nil
        if let queueMode {
            self.queueMode = queueMode
        }
        playbackMode = preferredModeForNewTrack()
        await startCurrent()
    }

    /// 以某曲为种子开启电台模式。
    func playRadio(seed track: Track) async {
        prefetchTask?.cancel()
        autoMVTask?.cancel()
        queue = [track]
        queueIndex = 0
        playedBVs = []
        manualPlaybackModeOverride = nil
        queueMode = .radio
        playbackMode = preferredModeForNewTrack()
        await startCurrent()
    }

    /// 提前取 cid + playurl,减少点击歌曲后等待时间。URL 有时效,只做短期缓存。
    func preload(tracks: [Track]) {
        preloadTask?.cancel()
        let candidates = tracks.prefix(5)
        preloadTask = Task { [weak self] in
            guard let self else { return }
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
    /// prepare() 内部通过 preparingStreams 去重,play() 点击时可直接 await 同一 Task。
    func schedulePreload(_ track: Track) {
        // 已缓存/已预加载的直接跳过,不占并发名额。
        guard CacheStore.shared.entry(bvid: track.bvid) == nil,
              preparedStream(for: track.bvid) == nil,
              preparingStreams[track.bvid] == nil,
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
        autoMVTask?.cancel()
        state = .loading
        do {
            let track = try await resolve(bvid: bvid)
            await play(tracks: [track], startAt: 0)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// 手动下一首。
    func playNext() async {
        await advance(automatic: false)
    }

    /// 按队列模式推进到下一首（automatic 区分自动播完与手动切）。
    private func advance(automatic: Bool) async {
        if automatic, queueMode == .repeatOne {
            await startCurrent()
        } else if queueMode == .radio, let bvid = current?.bvid {
            state = .loading
            let prefetched = prefetchedRadio?.seed == bvid ? prefetchedRadio?.track : nil
            prefetchedRadio = nil
            let next: Track?
            if let prefetched {
                next = prefetched
            } else {
                next = await radioPick(after: bvid)
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
        } else if queueMode == .shuffle, queue.count > 1 {
            let candidates = queue.indices.filter { $0 != queueIndex }
            queueIndex = candidates.randomElement() ?? queueIndex
            manualPlaybackModeOverride = nil
            playbackMode = preferredModeForNewTrack()
            await startCurrent()
        } else if queueIndex + 1 < queue.count {
            queueIndex += 1
            manualPlaybackModeOverride = nil
            playbackMode = preferredModeForNewTrack()
            await startCurrent()
        }
    }

    /// 上一首：播放超过 3 秒则回到开头，否则切到上一首。
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

    /// 跳到队列中的指定曲目。
    func jump(to index: Int) async {
        guard queue.indices.contains(index) else { return }
        preloadTask?.cancel()
        prefetchTask?.cancel()
        autoMVTask?.cancel()
        queueIndex = index
        manualPlaybackModeOverride = nil
        playbackMode = preferredModeForNewTrack()
        await startCurrent()
    }

    /// 从队列移除某曲（移除当前曲则自动播下一首）。
    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index), queue.count > 1 else { return }
        queue.remove(at: index)
        if index < queueIndex {
            queueIndex -= 1
        } else if index == queueIndex {
            queueIndex = min(queueIndex, queue.count - 1)
            Task { await startCurrent() }
        }
    }

    /// 向队列尾追加曲目（去重并预取）。
    func appendToQueue(_ tracks: [Track]) {
        let existing = Set(queue.map(\.bvid))
        let additions = tracks.filter { !existing.contains($0.bvid) }
        queue.append(contentsOf: additions)
        preload(tracks: additions)
    }

    /// 切换播放/暂停。
    func togglePlayPause() {
        if state == .playing {
            pause()
        } else if state == .paused {
            play()
        }
    }

    /// 继续播放。
    func play() {
        guard let player else { return }
        player.play()
        state = .playing
        updateNowPlayingInfo()
    }

    /// 暂停。
    func pause() {
        guard let player else { return }
        player.pause()
        state = .paused
        updateNowPlayingInfo()
    }

    /// 跳转到指定秒数。
    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
        updateNowPlayingInfo()
    }

    /// 进度条交互:开始拖动时冻结时间回写,只更新显示;松手时一次性 seek。
    /// 当前在线播放音质偏好(0=最高)。下载音质单独存 downloadQuality。
    static var playbackQuality: Int { UserDefaults.standard.integer(forKey: "playbackQuality") }

    /// 在播放器里切换音质:写入偏好并按当前进度重取流续播。本地缓存曲目无需切换。
    func setPlaybackQuality(_ id: Int) async {
        UserDefaults.standard.set(id, forKey: "playbackQuality")
        guard let track = current, CacheStore.shared.entry(bvid: track.bvid) == nil else { return }
        preparedStreams.removeValue(forKey: track.bvid)
        await startCurrent(resumeAt: currentTime)
    }

    /// 开始拖动进度条：冻结时间回写，只更新显示。
    func beginScrub() {
        isScrubbing = true
    }

    /// 结束拖动：一次性 seek 并恢复时间回写。
    func endScrub(to seconds: Double) {
        isScrubbing = false
        seek(to: seconds)
    }

    /// 手动切换音乐/MV 模式并在当前进度续播。
    func setPlaybackMode(_ mode: PlaybackMode) async {
        guard mode != playbackMode else { return }
        manualPlaybackModeOverride = mode
        playbackMode = mode
        await startCurrent(resumeAt: currentTime)
    }

    /// 进入全屏时把 MV 升到更高画质（失败不影响当前播放）。
    func upgradeMVForFullscreen() async {
        guard playbackMode == .mv, var track = current else { return }
        let resumeAt = currentTime
        do {
            if track.cid == nil {
                track = try await fillPlaybackPage(for: track)
                if current?.bvid == track.bvid {
                    queue[queueIndex] = track
                }
            }
            guard let cid = track.cid else { return }
            let url = try await client.videoStream(bvid: track.bvid, cid: cid, profile: .fullscreen)
            guard current?.bvid == track.bvid, playbackMode == .mv else { return }
            preparedVideoStreams[track.bvid] = PreparedVideoStream(url: url, cid: cid, fetchedAt: Date())
            await startCurrent(resumeAt: resumeAt)
        } catch {
            // 全屏提质失败不影响当前 MV 播放。
        }
    }

    /// 进入后台时若在放 MV 则切回纯音乐，保住锁屏播放。
    func handleScenePhase(isBackground: Bool) async {
        guard isBackground else { return }
        autoMVTask?.cancel()
        guard playbackMode == .mv, state == .playing else { return }
        playbackMode = .music
        await startCurrent(resumeAt: currentTime)
    }

    // MARK: - 播放核心

    /// 起播当前曲目：缓存优先 → 预取流 → 现取流；起播后异步加载封面/歌词/MV 并触发预取。
    private func startCurrent(resumeAt: Double = 0) async {
        guard var track = current else { return }
        let generation = UUID()
        playbackGeneration = generation
        state = .loading
        currentTime = resumeAt
        lyrics = []
        videoAvailable = false
        currentAudioQuality = nil
        currentAudioBandwidth = nil
        autoMVTask?.cancel()
        do {
            let url: URL
            let isLocal: Bool
            if playbackMode == .mv {
                if track.cid == nil {
                    track = try await fillPlaybackPage(for: track)
                    queue[queueIndex] = track
                }
                if let prepared = preparedVideoStream(for: track.bvid), prepared.cid == track.cid {
                    url = prepared.url
                } else {
                    url = try await client.videoStream(bvid: track.bvid, cid: track.cid!)
                    preparedVideoStreams[track.bvid] = PreparedVideoStream(
                        url: url, cid: track.cid!, fetchedAt: Date())
                }
                isLocal = false
                videoAvailable = true
            } else if let cached = CacheStore.shared.entry(bvid: track.bvid) {
                // 缓存优先,顺便补全 cid,离线也能播
                track.cid = cached.cid
                track.duration = cached.duration
                queue[queueIndex] = track
                url = CacheStore.audioDir.appendingPathComponent(cached.fileName)
                isLocal = true
                currentAudioQuality = cached.quality
                currentAudioBandwidth = nil
            } else if let prepared = preparedStream(for: track.bvid) {
                track.cid = prepared.cid
                track.duration = prepared.duration
                queue[queueIndex] = track
                url = prepared.url
                isLocal = false
                currentAudioQuality = prepared.quality
                currentAudioBandwidth = prepared.bandwidth
            } else {
                let prepared = try await preparedStreamValue(for: track)
                track.cid = prepared.cid
                track.duration = prepared.duration
                queue[queueIndex] = track
                url = prepared.url
                isLocal = false
                currentAudioQuality = prepared.quality
                currentAudioBandwidth = prepared.bandwidth
            }
            guard playbackGeneration == generation, current?.bvid == track.bvid else { return }
            startPlayback(url: url, isLocal: isLocal, resumeAt: resumeAt)
            try? AVAudioSession.sharedInstance().setActive(true)
            state = .playing
            let shouldRecordHistory = resumeAt < 1 || !playedBVs.contains(track.bvid)
            playedBVs.insert(track.bvid)
            if shouldRecordHistory {
                PlaybackHistoryStore.shared.record(track)
            }
            if !isLocal, UserDefaults.standard.bool(forKey: "autoCache") {
                let toCache = track
                Task {
                    try? await Task.sleep(for: .seconds(12))
                    guard playbackGeneration == generation, current?.bvid == toCache.bvid else { return }
                    await DownloadManager.shared.download(track: toCache)
                }
            }
            Task { [track, generation] in
                try? await Task.sleep(for: .seconds(1))
                await loadCover(for: track, generation: generation)
            }
            Task { [track, generation] in
                try? await Task.sleep(for: .seconds(2))
                await loadLyrics(for: track, generation: generation)
            }
            autoMVTask = Task { [weak self, track, generation] in
                try? await Task.sleep(for: .seconds(1))
                await self?.prepareVideoIfUseful(for: track, generation: generation)
            }
            scheduleRadioPrefetch()
            scheduleQueuePrefetch()
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

    /// 由 BV 号解析出完整 Track。
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

    /// 补全曲目的 cid 与时长（取第一个分 P）。
    private func fillPlaybackPage(for track: Track) async throws -> Track {
        let info = try await client.videoInfo(bvid: track.bvid)
        guard let page = info.pages.first else {
            throw BiliClient.APIError(code: -1, message: "无分P")
        }
        return Track(aid: info.aid, ownerMid: info.owner.mid, typeID: track.typeID, bvid: track.bvid,
                     cid: page.cid, title: track.title, artist: track.artist,
                     coverURL: track.coverURL, duration: page.duration)
    }

    /// 解析音频流前先拿到 cid 和时长。已知 cid+时长就直接跳过元数据请求;
    /// 否则用轻量的 pagelist(而非完整的 view 接口,后者会带回整个合集树白白解析)。
    private static func resolveCidDuration(client: BiliClient, bvid: String, cid: Int?, duration: Int) async throws -> (cid: Int, duration: Int) {
        if let cid, duration > 0 {
            return (cid, duration)
        }
        guard let page = try await client.pageList(bvid: bvid).first else {
            throw BiliClient.APIError(code: -1, message: "无分P")
        }
        return (cid ?? page.cid, duration > 0 ? duration : page.duration)
    }

    /// 取（或等待正在进行的）音频流预取结果，按 bvid 去重避免重复请求。
    private func preparedStreamValue(for track: Track) async throws -> PreparedStream {
        if let prepared = preparedStream(for: track.bvid) {
            return prepared
        }
        if let task = preparingStreams[track.bvid] {
            return try await task.value
        }
        let task = Task<PreparedStream, Error> { [client] in
            let start = CFAbsoluteTimeGetCurrent()
            let meta = try await Self.resolveCidDuration(
                client: client, bvid: track.bvid, cid: track.cid, duration: track.duration)
            let stream = try await client.audioStream(
                bvid: track.bvid,
                cid: meta.cid,
                preferredQuality: Self.playbackQuality)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            log.debug("prepare stream(bvid:\(track.bvid)) \(elapsed, format: .fixed(precision: 1))ms")
            return PreparedStream(
                url: stream.url,
                cid: meta.cid,
                duration: meta.duration,
                quality: stream.quality,
                bandwidth: stream.bandwidth,
                fetchedAt: Date())
        }
        preparingStreams[track.bvid] = task
        do {
            let prepared = try await task.value
            preparedStreams[track.bvid] = prepared
            preparingStreams[track.bvid] = nil
            return prepared
        } catch {
            preparingStreams[track.bvid] = nil
            throw error
        }
    }

    /// 新曲目默认先用音乐模式起播（MV 作为后续切换/预取策略）。
    private func preferredModeForNewTrack() -> PlaybackMode {
        // 新点击歌曲先出声。MV 流尤其是高画质会明显慢于音频流;Wi-Fi 优先 MV
        // 只作为切换/预取策略,不阻塞新歌首播。
        .music
    }

    /// 电台选歌:用统一推荐引擎打分,避免 related 第一条把队列带偏。
    private func radioPick(after bvid: String) async -> Track? {
        if let track = await fastRelatedRadioPick(after: bvid) {
            return track
        }
        let excluded = playedBVs.union(queue.map(\.bvid))
        return await RecommendationEngine().nextRadioTrack(after: current, excludedBVIDs: excluded)
    }

    /// 自动下一首必须先保证速度:related 接口通常最快,且返回 cid 时能少一次 pagelist 请求。
    private func fastRelatedRadioPick(after bvid: String) async -> Track? {
        let excluded = playedBVs.union(queue.map(\.bvid))
        guard let items = try? await client.related(bvid: bvid) else { return nil }
        let tracks = items
            .map(Track.init(related:))
            .filter { !excluded.contains($0.bvid) }
        return tracks.first(where: MusicFilter.isStrictMusic)
            ?? tracks.first(where: MusicFilter.isMusic)
    }

    /// 当前曲起播后，提前选好并预取电台下一首。
    private func scheduleRadioPrefetch() {
        prefetchTask?.cancel()
        guard queueMode == .radio, let bvid = current?.bvid else { return }
        let expectedIndex = queueIndex
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard let next = await self.radioPick(after: bvid) else { return }
            guard !Task.isCancelled else { return }
            if self.queueIndex == expectedIndex {
                self.prefetchedRadio = (bvid, next)
                await self.prepare(track: next)
            }
        }
    }

    /// 提前预取队列里的下一首。
    private func scheduleQueuePrefetch() {
        guard queue.indices.contains(queueIndex + 1) else { return }
        let next = queue[queueIndex + 1]
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            await self?.prepare(track: next)
        }
    }

    /// 取未过期的已预取音频流（超 90 分钟视为过期并清除）。
    private func preparedStream(for bvid: String) -> PreparedStream? {
        guard let prepared = preparedStreams[bvid] else { return nil }
        if Date().timeIntervalSince(prepared.fetchedAt) < 90 * 60 {
            return prepared
        }
        preparedStreams[bvid] = nil
        preparingStreams[bvid] = nil
        return nil
    }

    /// 取未过期的已预取 MV 流。
    private func preparedVideoStream(for bvid: String) -> PreparedVideoStream? {
        guard let prepared = preparedVideoStreams[bvid] else { return nil }
        if Date().timeIntervalSince(prepared.fetchedAt) < 90 * 60 {
            return prepared
        }
        preparedVideoStreams[bvid] = nil
        return nil
    }

    /// 预取某曲音频流（已缓存或已预取则跳过）。
    private func prepare(track: Track) async {
        guard CacheStore.shared.entry(bvid: track.bvid) == nil,
              preparedStream(for: track.bvid) == nil else { return }
        do {
            _ = try await preparedStreamValue(for: track)
        } catch {
            // 预加载失败不影响手动播放,真正播放时会再取一次。
        }
    }

    /// 搭建 AVPlayer 并装监听器（时间/状态/播完）。按代际丢弃过期回调，弱网误触播完不切歌。
    private func startPlayback(url: URL, isLocal: Bool = false, resumeAt: Double = 0) {
        let generation = playbackGeneration
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        statusObserver?.invalidate()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        timeObserver = nil
        endObserver = nil
        statusObserver = nil
        let asset = isLocal
            ? AVURLAsset(url: url)
            : AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": BiliClient.headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        let player = AVPlayer(playerItem: item)
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
                    self.state = .playing
                case .paused:
                    if self.state == .playing { self.state = .paused }
                case .waitingToPlayAtSpecifiedRate:
                    self.state = .loading
                @unknown default:
                    break
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
        player.playImmediately(atRate: 1)
        updateNowPlayingInfo()
    }

    /// 异步加载封面并刷新锁屏信息。
    private func loadCover(for track: Track, generation: UUID) async {
        coverImage = nil
        guard let coverURL = artworkURL(track.coverURL) else { return }
        var req = URLRequest(url: coverURL)
        BiliClient.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if let (data, _) = try? await URLSession.shared.data(for: req) {
            guard playbackGeneration == generation, current?.bvid == track.bvid else { return }
            coverImage = UIImage(data: data)?.resized(maxDimension: 600)
            updateNowPlayingInfo()
        }
    }

    /// 给 B 站封面 URL 拼上缩放参数，减小下载体积。
    private func artworkURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        let raw = url.absoluteString
        guard raw.contains("hdslb.com"), !raw.contains("@") else { return url }
        return URL(string: raw + "@600w_600h_1c.webp")
    }

    /// 异步匹配并加载歌词（仅 LRCLIB，匹配不到则留空）。
    private func loadLyrics(for track: Track, generation: UUID) async {
        // 只用 LRCLIB 在线歌词。不再 fallback 到 B 站字幕——音乐区"字幕"多是自动生成的 CC,
        // 把伴奏标成"♪音乐♪",当歌词用纯属错配,宁可显示"无歌词"。
        let online = try? await lyricsClient.lyrics(for: track)
        guard playbackGeneration == generation, current?.bvid == track.bvid else { return }
        lyrics = online ?? []
    }

    /// 音乐模式下预取 MV 流，并在满足条件时自动切到 MV。
    private func prepareVideoIfUseful(for track: Track, generation: UUID) async {
        guard playbackMode == .music, let cid = track.cid else { return }
        let videoURL = try? await client.videoStream(bvid: track.bvid, cid: cid)
        guard playbackGeneration == generation, current?.bvid == track.bvid else { return }
        if let videoURL {
            preparedVideoStreams[track.bvid] = PreparedVideoStream(url: videoURL, cid: cid, fetchedAt: Date())
        }
        let available = videoURL != nil
        videoAvailable = available
        if available, shouldAutoSwitchToMV(generation: generation, bvid: track.bvid) {
            playbackMode = .mv
            await startCurrent(resumeAt: currentTime)
        }
    }

    /// 是否应自动切到 MV：Wi-Fi 优先 MV + 前台 + 未手动覆盖 + 仍是同一曲。
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

    /// 注册锁屏/控制中心的播放、暂停、上/下一首、拖动进度命令。
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

    /// 刷新锁屏/控制中心的标题、艺人、封面、进度信息。
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
    /// 等比缩放到最长边不超过给定值（封面降采样省内存）。
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
