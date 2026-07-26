import Foundation
import OSLog

private let streamLog = Logger(subsystem: "com.fubuki.BiliMusic", category: "stream")

/// 负责把 Track 解析成可播放的音频流,并维护短期 playurl 缓存。
/// URL 有时效,只做内存级预取,不持久化。
@MainActor
final class StreamResolver {
    private struct PreparedStreamKey: Hashable {
        let track: TrackKey
        let preferredQuality: Int
    }

    private struct PreparingStream {
        let id: UUID
        let task: Task<PreparedAudioStream, Error>
    }

    struct PreparedAudioStream {
        let url: URL
        let candidateURLs: [URL]
        let cid: Int
        let duration: Int
        let quality: Int
        let bandwidth: Int
        let fetchedAt: Date
        let cdnWarmedAt: Date?

        init(
            url: URL,
            candidateURLs: [URL] = [],
            cid: Int,
            duration: Int,
            quality: Int,
            bandwidth: Int,
            fetchedAt: Date,
            cdnWarmedAt: Date? = nil
        ) {
            self.url = url
            self.candidateURLs = AudioCDNSelector.deduped([url] + candidateURLs)
            self.cid = cid
            self.duration = duration
            self.quality = quality
            self.bandwidth = bandwidth
            self.fetchedAt = fetchedAt
            self.cdnWarmedAt = cdnWarmedAt
        }
    }

    private let client: BiliClient
    private var preparedStreams: [PreparedStreamKey: PreparedAudioStream] = [:]
    private var preparingStreams: [PreparedStreamKey: PreparingStream] = [:]
    private var warmingStreams: [PreparedStreamKey: UUID] = [:]
    private static let preparedStreamTTL: TimeInterval = 90 * 60
    private static let preparedStreamLimit = 40

    init(client: BiliClient = BiliClient()) {
        self.client = client
    }

    func cachedAudio(for track: Track, preferredQuality: Int) -> PreparedAudioStream? {
        prunePreparedStreams()
        let key = PreparedStreamKey(track: track.key, preferredQuality: preferredQuality)
        if let exact = preparedStreams[key] {
            return exact
        }
        guard track.cid == nil else { return nil }
        let fallbackKey = PreparedStreamKey(
            track: TrackKey(bvid: track.bvid, cid: nil),
            preferredQuality: preferredQuality)
        return preparedStreams[fallbackKey]
    }

    func invalidateAudio(for track: Track) {
        let fallbackTrackKey = TrackKey(bvid: track.bvid, cid: nil)
        let preparedKeys = preparedStreams.keys.filter { key in
            key.track == track.key || (track.cid != nil && key.track == fallbackTrackKey)
        }
        for key in preparedKeys {
            preparedStreams[key] = nil
        }
        let preparingKeys = preparingStreams.keys.filter { key in
            key.track == track.key || (track.cid != nil && key.track == fallbackTrackKey)
        }
        for key in preparingKeys {
            preparingStreams[key]?.task.cancel()
            preparingStreams[key] = nil
        }
        warmingStreams = warmingStreams.filter { key, _ in
            key.track != track.key && !(track.cid != nil && key.track == fallbackTrackKey)
        }
    }

    /// 真正开播时取消其他曲目的后台解析，避免列表预加载与首响争抢 API/CDN 连接。
    /// 当前曲目若已在预取则保留，播放请求可以直接复用同一个任务。
    func cancelPreparations(except track: Track?) {
        let retainedKey = track?.key
        let shouldRetain: (PreparedStreamKey) -> Bool = { key in
            guard let retainedKey else { return false }
            if retainedKey.cid == nil {
                return key.track.bvid == retainedKey.bvid
            }
            return key.track == retainedKey
        }

        let preparingKeys = preparingStreams.keys.filter { !shouldRetain($0) }
        for key in preparingKeys {
            preparingStreams[key]?.task.cancel()
            preparingStreams[key] = nil
        }
        warmingStreams = warmingStreams.filter { shouldRetain($0.key) }
    }

    func prepareAudio(for track: Track, preferredQuality: Int) async throws -> PreparedAudioStream {
        if let prepared = cachedAudio(for: track, preferredQuality: preferredQuality) {
            return prepared
        }
        let requestKey = PreparedStreamKey(track: track.key, preferredQuality: preferredQuality)
        if let preparing = preparingStreams[requestKey] {
            return try await preparing.task.value
        }

        let requestID = UUID()
        let task = Task<PreparedAudioStream, Error> { [client] in
            let start = CFAbsoluteTimeGetCurrent()
            let meta = try await Self.resolveCidDuration(
                client: client,
                bvid: track.bvid,
                cid: track.cid,
                duration: track.duration)
            let stream = try await client.audioStream(
                bvid: track.bvid,
                cid: meta.cid,
                preferredQuality: preferredQuality)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            streamLog.debug("prepare audio(bvid:\(track.bvid)) \(elapsed, format: .fixed(precision: 1))ms")
            return PreparedAudioStream(
                url: stream.url,
                candidateURLs: stream.candidateURLs,
                cid: meta.cid,
                duration: meta.duration,
                quality: stream.quality,
                bandwidth: stream.bandwidth,
                fetchedAt: Date())
        }

        preparingStreams[requestKey] = PreparingStream(id: requestID, task: task)
        do {
            let prepared = try await task.value
            guard preparingStreams[requestKey]?.id == requestID else {
                return prepared
            }
            let resolvedKey = PreparedStreamKey(
                track: TrackKey(bvid: track.bvid, cid: prepared.cid),
                preferredQuality: preferredQuality)
            preparedStreams[resolvedKey] = prepared
            if resolvedKey != requestKey {
                preparedStreams[requestKey] = prepared
            }
            prunePreparedStreams()
            preparingStreams[requestKey] = nil
            return prepared
        } catch {
            if preparingStreams[requestKey]?.id == requestID {
                preparingStreams[requestKey] = nil
            }
            throw error
        }
    }

    func warmAudioCDN(for track: Track, preferredQuality: Int) async {
        let key = PreparedStreamKey(track: track.key, preferredQuality: preferredQuality)
        guard warmingStreams[key] == nil else { return }
        let requestID = UUID()
        warmingStreams[key] = requestID
        defer {
            if warmingStreams[key] == requestID {
                warmingStreams[key] = nil
            }
        }

        do {
            let prepared = try await prepareAudio(for: track, preferredQuality: preferredQuality)
            guard !Task.isCancelled else { return }
            guard prepared.candidateURLs.count > 1 else { return }
            if let warmedAt = prepared.cdnWarmedAt,
               Date().timeIntervalSince(warmedAt) < 10 * 60 {
                return
            }
            guard let selected = await AudioCDNSelector.fastestReachableURL(
                from: prepared.candidateURLs,
                timeout: .milliseconds(700)) else { return }
            guard !Task.isCancelled, warmingStreams[key] == requestID else { return }
            let warmed = PreparedAudioStream(
                url: selected,
                candidateURLs: prepared.candidateURLs,
                cid: prepared.cid,
                duration: prepared.duration,
                quality: prepared.quality,
                bandwidth: prepared.bandwidth,
                fetchedAt: prepared.fetchedAt,
                cdnWarmedAt: Date())
            let resolvedKey = PreparedStreamKey(
                track: TrackKey(bvid: track.bvid, cid: prepared.cid),
                preferredQuality: preferredQuality)
            preparedStreams[resolvedKey] = warmed
            preparedStreams[key] = warmed
            prunePreparedStreams()
            streamLog.debug("warm audio cdn(bvid:\(track.bvid)) host=\(selected.host() ?? "nil", privacy: .public)")
        } catch {
            // 预热失败不影响真正播放;播放时仍会走普通取流和慢启动 fallback。
        }
    }

    private static func resolveCidDuration(client: BiliClient, bvid: String, cid: Int?, duration: Int) async throws -> (cid: Int, duration: Int) {
        if let cid, duration > 0 {
            return (cid, duration)
        }
        guard let page = try await client.pageList(bvid: bvid).first else {
            throw BiliClient.APIError(code: -1, message: "无分P")
        }
        return (cid ?? page.cid, duration > 0 ? duration : page.duration)
    }

    private func prunePreparedStreams(now: Date = Date()) {
        preparedStreams = preparedStreams.filter {
            now.timeIntervalSince($0.value.fetchedAt) < Self.preparedStreamTTL
        }
        guard preparedStreams.count > Self.preparedStreamLimit else { return }
        let overflow = preparedStreams.count - Self.preparedStreamLimit
        let oldestKeys = preparedStreams
            .sorted { $0.value.fetchedAt < $1.value.fetchedAt }
            .prefix(overflow)
            .map(\.key)
        for key in oldestKeys {
            preparedStreams[key] = nil
        }
    }
}

@MainActor
protocol AudioStreamResolving: AnyObject {
    func cachedAudio(for track: Track, preferredQuality: Int) -> StreamResolver.PreparedAudioStream?
    func invalidateAudio(for track: Track)
    func cancelPreparations(except track: Track?)
    func prepareAudio(for track: Track, preferredQuality: Int) async throws -> StreamResolver.PreparedAudioStream
    func warmAudioCDN(for track: Track, preferredQuality: Int) async
}

extension AudioStreamResolving {
    func cancelPreparations(except track: Track?) {}
}

extension StreamResolver: AudioStreamResolving {}
