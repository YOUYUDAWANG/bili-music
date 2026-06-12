import AVFoundation
import MediaPlayer
import Observation
import UIKit

struct Track: Identifiable, Equatable {
    let aid: Int?
    let ownerMid: Int?
    let bvid: String
    var cid: Int?          // 搜索结果没有 cid,首次播放时补全
    let title: String
    let artist: String
    let coverURL: URL?
    var duration: Int
    var id: String { bvid }

    init(aid: Int? = nil, ownerMid: Int? = nil, bvid: String, cid: Int? = nil, title: String, artist: String, coverURL: URL?, duration: Int) {
        self.aid = aid
        self.ownerMid = ownerMid
        self.bvid = bvid
        self.cid = cid
        self.title = title
        self.artist = artist
        self.coverURL = coverURL
        self.duration = duration
    }

    init(search item: BiliClient.SearchItem) {
        self.init(aid: item.aid, ownerMid: item.mid, bvid: item.bvid, title: item.cleanTitle, artist: item.author,
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
    /// 电台模式:队列播到末尾时用相关推荐自动续歌
    var radioMode = true
    private(set) var playbackMode: PlaybackMode = .music

    var current: Track? { queue.indices.contains(queueIndex) ? queue[queueIndex] : nil }
    var duration: Double { Double(current?.duration ?? 0) }
    var hasNext: Bool { queueIndex + 1 < queue.count || radioMode }
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
    private var preparedStreams: [String: PreparedStream] = [:]
    private var playbackGeneration = UUID()

    private struct PreparedStream {
        let url: URL
        let cid: Int
        let duration: Int
        let fetchedAt: Date
    }

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        setUpRemoteCommands()
    }

    // MARK: - 对外操作

    /// 用一组曲目替换队列并从指定位置开播(搜索页点击)
    func play(tracks: [Track], startAt index: Int) async {
        queue = tracks
        queueIndex = index
        playedBVs = []
        playbackMode = preferredModeForNewTrack()
        await startCurrent()
    }

    /// 提前取 cid + playurl,减少点击歌曲后等待时间。URL 有时效,只做短期缓存。
    func preload(tracks: [Track]) {
        preloadTask?.cancel()
        let candidates = tracks.prefix(5)
        preloadTask = Task { [weak self] in
            for track in candidates {
                guard !Task.isCancelled else { return }
                await self?.prepare(track: track)
            }
        }
    }

    /// 直接播一个 BV 号(粘贴链接/调试)
    func play(bvid: String) async {
        state = .loading
        do {
            let track = try await resolve(bvid: bvid)
            await play(tracks: [track], startAt: 0)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func playNext() async {
        if queueIndex + 1 < queue.count {
            queueIndex += 1
            playbackMode = preferredModeForNewTrack()
            await startCurrent()
        } else if radioMode, let bvid = current?.bvid {
            state = .loading
            if let next = await radioPick(after: bvid) {
                queue.append(next)
                queueIndex = queue.count - 1
                playbackMode = preferredModeForNewTrack()
                await startCurrent()
            } else {
                state = .paused
            }
        }
    }

    func playPrevious() async {
        // 已播 3 秒以上则回到开头,否则真的回上一首
        if currentTime > 3 || !hasPrevious {
            seek(to: 0)
            return
        }
        queueIndex -= 1
        playbackMode = preferredModeForNewTrack()
        await startCurrent()
    }

    func jump(to index: Int) async {
        guard queue.indices.contains(index) else { return }
        queueIndex = index
        playbackMode = preferredModeForNewTrack()
        await startCurrent()
    }

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

    func appendToQueue(_ tracks: [Track]) {
        let existing = Set(queue.map(\.bvid))
        let additions = tracks.filter { !existing.contains($0.bvid) }
        queue.append(contentsOf: additions)
        preload(tracks: additions)
    }

    func togglePlayPause() {
        guard let player else { return }
        if state == .playing {
            player.pause()
            state = .paused
        } else if state == .paused {
            player.play()
            state = .playing
        }
        updateNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
        updateNowPlayingInfo()
    }

    /// 进度条交互:开始拖动时冻结时间回写,只更新显示;松手时一次性 seek。
    func beginScrub() {
        isScrubbing = true
    }

    func endScrub(to seconds: Double) {
        isScrubbing = false
        seek(to: seconds)
    }

    func setPlaybackMode(_ mode: PlaybackMode) async {
        guard mode != playbackMode else { return }
        playbackMode = mode
        await startCurrent(resumeAt: currentTime)
    }

    func handleScenePhase(isBackground: Bool) async {
        guard isBackground, playbackMode == .mv, state == .playing else { return }
        playbackMode = .music
        await startCurrent(resumeAt: currentTime)
    }

    // MARK: - 播放核心

    private func startCurrent(resumeAt: Double = 0) async {
        guard var track = current else { return }
        let generation = UUID()
        playbackGeneration = generation
        state = .loading
        currentTime = resumeAt
        lyrics = []
        do {
            let url: URL
            let isLocal: Bool
            if playbackMode == .mv {
                if track.cid == nil {
                    let info = try await client.videoInfo(bvid: track.bvid)
                    guard let page = info.pages.first else {
                        throw BiliClient.APIError(code: -1, message: "无分P")
                    }
                    track = Track(aid: info.aid, ownerMid: info.owner.mid, bvid: track.bvid,
                                  cid: page.cid, title: track.title, artist: track.artist,
                                  coverURL: track.coverURL, duration: page.duration)
                    queue[queueIndex] = track
                }
                url = try await client.videoStream(bvid: track.bvid, cid: track.cid!)
                isLocal = false
                videoAvailable = true
            } else if let cached = CacheStore.shared.entry(bvid: track.bvid) {
                // 缓存优先,顺便补全 cid,离线也能播
                track.cid = cached.cid
                track.duration = cached.duration
                queue[queueIndex] = track
                url = CacheStore.audioDir.appendingPathComponent(cached.fileName)
                isLocal = true
            } else if let prepared = preparedStream(for: track.bvid) {
                track.cid = prepared.cid
                track.duration = prepared.duration
                queue[queueIndex] = track
                url = prepared.url
                isLocal = false
            } else {
                if track.cid == nil {
                    let info = try await client.videoInfo(bvid: track.bvid)
                    guard let page = info.pages.first else {
                        throw BiliClient.APIError(code: -1, message: "无分P")
                    }
                    track = Track(aid: info.aid, ownerMid: info.owner.mid, bvid: track.bvid,
                                  cid: page.cid, title: track.title, artist: track.artist,
                                  coverURL: track.coverURL, duration: page.duration)
                    queue[queueIndex] = track
                }
                url = try await client.audioStream(bvid: track.bvid, cid: track.cid!).url
                isLocal = false
            }
            guard playbackGeneration == generation, current?.bvid == track.bvid else { return }
            startPlayback(url: url, isLocal: isLocal, resumeAt: resumeAt)
            try? AVAudioSession.sharedInstance().setActive(true)
            state = .playing
            playedBVs.insert(track.bvid)
            if !isLocal, UserDefaults.standard.bool(forKey: "autoCache") {
                let toCache = track
                Task { await DownloadManager.shared.download(track: toCache) }
            }
            await loadCover(for: track, generation: generation)
            await loadLyrics(for: track, generation: generation)
            await checkVideoAvailability(for: track, generation: generation)
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

    private func resolve(bvid: String) async throws -> Track {
        let info = try await client.videoInfo(bvid: bvid)
        guard let page = info.pages.first else {
            throw BiliClient.APIError(code: -1, message: "无分P")
        }
        return Track(aid: info.aid, ownerMid: info.owner.mid, bvid: info.bvid, cid: page.cid, title: info.title,
                     artist: info.owner.name, coverURL: URL(string: info.pic),
                     duration: page.duration)
    }

    private func preferredModeForNewTrack() -> PlaybackMode {
        UserDefaults.standard.bool(forKey: "preferMVOnWiFi") && NetworkMonitor.shared.isWiFi ? .mv : .music
    }

    /// 电台选歌:相关推荐里挑 1~11 分钟、没播过的第一条
    private func radioPick(after bvid: String) async -> Track? {
        guard let items = try? await client.related(bvid: bvid) else { return nil }
        return items.first {
            !playedBVs.contains($0.bvid) && MusicFilter.isMusic(title: $0.title, artist: $0.owner.name, duration: $0.duration)
        }.map(Track.init(related:))
    }

    private func scheduleRadioPrefetch() {
        prefetchTask?.cancel()
        guard radioMode, queueIndex == queue.count - 1, let bvid = current?.bvid else { return }
        let expectedIndex = queueIndex
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            guard let next = await self.radioPick(after: bvid) else { return }
            guard !Task.isCancelled else { return }
            if self.queueIndex == expectedIndex,
               self.queue.count == expectedIndex + 1,
               !self.queue.contains(where: { $0.bvid == next.bvid }) {
                self.queue.append(next)
            }
        }
    }

    private func scheduleQueuePrefetch() {
        guard queue.indices.contains(queueIndex + 1) else { return }
        let next = queue[queueIndex + 1]
        Task { [weak self] in
            await self?.prepare(track: next)
        }
    }

    private func preparedStream(for bvid: String) -> PreparedStream? {
        guard let prepared = preparedStreams[bvid] else { return nil }
        if Date().timeIntervalSince(prepared.fetchedAt) < 90 * 60 {
            return prepared
        }
        preparedStreams[bvid] = nil
        return nil
    }

    private func prepare(track: Track) async {
        guard CacheStore.shared.entry(bvid: track.bvid) == nil,
              preparedStream(for: track.bvid) == nil else { return }
        do {
            var track = track
            if track.cid == nil {
                let info = try await client.videoInfo(bvid: track.bvid)
                guard let page = info.pages.first else { return }
                track.cid = page.cid
                track.duration = page.duration
            }
            guard let cid = track.cid else { return }
            let stream = try await client.audioStream(bvid: track.bvid, cid: cid)
            preparedStreams[track.bvid] = PreparedStream(
                url: stream.url, cid: cid, duration: track.duration, fetchedAt: Date())
        } catch {
            // 预加载失败不影响手动播放,真正播放时会再取一次。
        }
    }

    private func startPlayback(url: URL, isLocal: Bool = false, resumeAt: Double = 0) {
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
        let player = AVPlayer(playerItem: item)
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
                    break
                @unknown default:
                    break
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.playNext()
            }
        }
        if resumeAt > 0 {
            player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
        }
        player.play()
        updateNowPlayingInfo()
    }

    private func loadCover(for track: Track, generation: UUID) async {
        coverImage = nil
        guard let coverURL = track.coverURL else { return }
        var req = URLRequest(url: coverURL)
        BiliClient.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if let (data, _) = try? await URLSession.shared.data(for: req) {
            guard playbackGeneration == generation, current?.bvid == track.bvid else { return }
            coverImage = UIImage(data: data)
            updateNowPlayingInfo()
        }
    }

    private func loadLyrics(for track: Track, generation: UUID) async {
        // 只用 LRCLIB 在线歌词。不再 fallback 到 B 站字幕——音乐区"字幕"多是自动生成的 CC,
        // 把伴奏标成"♪音乐♪",当歌词用纯属错配,宁可显示"无歌词"。
        let online = try? await lyricsClient.lyrics(for: track)
        guard playbackGeneration == generation, current?.bvid == track.bvid else { return }
        lyrics = online ?? []
    }

    private func checkVideoAvailability(for track: Track, generation: UUID) async {
        guard playbackMode == .music, let cid = track.cid else { return }
        let available = (try? await client.videoStream(bvid: track.bvid, cid: cid)) != nil
        guard playbackGeneration == generation, current?.bvid == track.bvid else { return }
        videoAvailable = available
    }

    // MARK: - 锁屏 / 控制中心

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
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
