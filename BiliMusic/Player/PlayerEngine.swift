import AVFoundation
import MediaPlayer
import Observation
import UIKit

struct Track: Identifiable, Equatable {
    let bvid: String
    var cid: Int?          // 搜索结果没有 cid,首次播放时补全
    let title: String
    let artist: String
    let coverURL: URL?
    var duration: Int
    var id: String { bvid }

    init(bvid: String, cid: Int? = nil, title: String, artist: String, coverURL: URL?, duration: Int) {
        self.bvid = bvid
        self.cid = cid
        self.title = title
        self.artist = artist
        self.coverURL = coverURL
        self.duration = duration
    }

    init(search item: BiliClient.SearchItem) {
        self.init(bvid: item.bvid, title: item.cleanTitle, artist: item.author,
                  coverURL: item.coverURL, duration: item.durationSeconds)
    }

    init(related item: BiliClient.RelatedItem) {
        self.init(bvid: item.bvid, cid: item.cid, title: item.title, artist: item.owner.name,
                  coverURL: URL(string: item.pic), duration: item.duration)
    }
}

@Observable
@MainActor
final class PlayerEngine {
    enum State: Equatable {
        case idle, loading, playing, paused
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var queue: [Track] = []
    private(set) var queueIndex = 0
    private(set) var currentTime: Double = 0
    /// 电台模式:队列播到末尾时用相关推荐自动续歌
    var radioMode = true

    var current: Track? { queue.indices.contains(queueIndex) ? queue[queueIndex] : nil }
    var duration: Double { Double(current?.duration ?? 0) }
    var hasNext: Bool { queueIndex + 1 < queue.count || radioMode }
    var hasPrevious: Bool { queueIndex > 0 }

    private let client = BiliClient()
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var coverImage: UIImage?
    private var playedBVs: Set<String> = []   // 电台去重

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
        await startCurrent()
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
            await startCurrent()
        } else if radioMode, let bvid = current?.bvid {
            state = .loading
            if let next = await radioPick(after: bvid) {
                queue.append(next)
                queueIndex = queue.count - 1
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
        await startCurrent()
    }

    func jump(to index: Int) async {
        guard queue.indices.contains(index) else { return }
        queueIndex = index
        await startCurrent()
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
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        updateNowPlayingInfo()
    }

    // MARK: - 播放核心

    private func startCurrent() async {
        guard var track = current else { return }
        state = .loading
        currentTime = 0
        do {
            let url: URL
            let isLocal: Bool
            if let cached = CacheStore.shared.entry(bvid: track.bvid) {
                // 缓存优先,顺便补全 cid,离线也能播
                track.cid = cached.cid
                track.duration = cached.duration
                queue[queueIndex] = track
                url = CacheStore.audioDir.appendingPathComponent(cached.fileName)
                isLocal = true
            } else {
                if track.cid == nil {
                    let info = try await client.videoInfo(bvid: track.bvid)
                    guard let page = info.pages.first else {
                        throw BiliClient.APIError(code: -1, message: "无分P")
                    }
                    track.cid = page.cid
                    track.duration = page.duration
                    queue[queueIndex] = track
                }
                url = try await client.audioStream(bvid: track.bvid, cid: track.cid!).url
                isLocal = false
            }
            startPlayback(url: url, isLocal: isLocal)
            try? AVAudioSession.sharedInstance().setActive(true)
            state = .playing
            playedBVs.insert(track.bvid)
            if !isLocal, UserDefaults.standard.bool(forKey: "autoCache") {
                let toCache = track
                Task { await DownloadManager.shared.download(track: toCache) }
            }
            await loadCover()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func resolve(bvid: String) async throws -> Track {
        let info = try await client.videoInfo(bvid: bvid)
        guard let page = info.pages.first else {
            throw BiliClient.APIError(code: -1, message: "无分P")
        }
        return Track(bvid: info.bvid, cid: page.cid, title: info.title,
                     artist: info.owner.name, coverURL: URL(string: info.pic),
                     duration: page.duration)
    }

    /// 电台选歌:相关推荐里挑 1~11 分钟、没播过的第一条
    private func radioPick(after bvid: String) async -> Track? {
        guard let items = try? await client.related(bvid: bvid) else { return nil }
        return items.first {
            (60...660).contains($0.duration) && !playedBVs.contains($0.bvid)
        }.map(Track.init(related:))
    }

    private func startPlayback(url: URL, isLocal: Bool = false) {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
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
                self?.currentTime = time.seconds
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.playNext()
            }
        }
        player.play()
        updateNowPlayingInfo()
    }

    private func loadCover() async {
        coverImage = nil
        guard let coverURL = current?.coverURL else { return }
        var req = URLRequest(url: coverURL)
        BiliClient.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if let (data, _) = try? await URLSession.shared.data(for: req) {
            coverImage = UIImage(data: data)
            updateNowPlayingInfo()
        }
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
