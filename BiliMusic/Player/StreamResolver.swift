import Foundation
import OSLog

private let streamLog = Logger(subsystem: "com.fubuki.BiliMusic", category: "stream")

/// 负责把 Track 解析成可播放的音频流,并维护短期 playurl 缓存。
/// URL 有时效,只做内存级预取,不持久化。
@MainActor
final class StreamResolver {
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
    private var preparedStreams: [TrackKey: PreparedAudioStream] = [:]
    private var preparingStreams: [TrackKey: Task<PreparedAudioStream, Error>] = [:]
    private var warmingStreams = Set<TrackKey>()

    init(client: BiliClient = BiliClient()) {
        self.client = client
    }

    func cachedAudio(for track: Track) -> PreparedAudioStream? {
        let key = track.key
        let fallbackKey = TrackKey(bvid: track.bvid, cid: nil)
        guard let prepared = preparedStreams[key] ?? preparedStreams[fallbackKey] else { return nil }
        if Date().timeIntervalSince(prepared.fetchedAt) < 90 * 60 {
            return prepared
        }
        preparedStreams[key] = nil
        preparedStreams[fallbackKey] = nil
        preparingStreams[key] = nil
        preparingStreams[fallbackKey] = nil
        return nil
    }

    func isPreparing(_ track: Track) -> Bool {
        preparingStreams[track.key] != nil || warmingStreams.contains(track.key)
    }

    func invalidateAudio(for track: Track) {
        preparedStreams[track.key] = nil
        preparingStreams[track.key] = nil
        if track.cid != nil {
            let fallbackKey = TrackKey(bvid: track.bvid, cid: nil)
            preparedStreams[fallbackKey] = nil
            preparingStreams[fallbackKey] = nil
        }
    }

    func prepareAudio(for track: Track, preferredQuality: Int) async throws -> PreparedAudioStream {
        if let prepared = cachedAudio(for: track) {
            return prepared
        }
        if let task = preparingStreams[track.key] {
            return try await task.value
        }

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

        preparingStreams[track.key] = task
        do {
            let prepared = try await task.value
            let resolvedKey = TrackKey(bvid: track.bvid, cid: prepared.cid)
            preparedStreams[resolvedKey] = prepared
            if resolvedKey != track.key {
                preparedStreams[track.key] = prepared
            }
            preparingStreams[track.key] = nil
            return prepared
        } catch {
            preparingStreams[track.key] = nil
            throw error
        }
    }

    func warmAudioCDN(for track: Track, preferredQuality: Int) async {
        let key = track.key
        guard !warmingStreams.contains(key) else { return }
        warmingStreams.insert(key)
        defer { warmingStreams.remove(key) }

        do {
            let prepared = try await prepareAudio(for: track, preferredQuality: preferredQuality)
            guard prepared.candidateURLs.count > 1 else { return }
            if let warmedAt = prepared.cdnWarmedAt,
               Date().timeIntervalSince(warmedAt) < 10 * 60 {
                return
            }
            guard let selected = await AudioCDNSelector.fastestReachableURL(
                from: prepared.candidateURLs,
                timeout: .milliseconds(700)) else { return }
            let warmed = PreparedAudioStream(
                url: selected,
                candidateURLs: prepared.candidateURLs,
                cid: prepared.cid,
                duration: prepared.duration,
                quality: prepared.quality,
                bandwidth: prepared.bandwidth,
                fetchedAt: prepared.fetchedAt,
                cdnWarmedAt: Date())
            let resolvedKey = TrackKey(bvid: track.bvid, cid: prepared.cid)
            preparedStreams[resolvedKey] = warmed
            preparedStreams[key] = warmed
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
}

@MainActor
protocol AudioStreamResolving: AnyObject {
    func cachedAudio(for track: Track) -> StreamResolver.PreparedAudioStream?
    func isPreparing(_ track: Track) -> Bool
    func invalidateAudio(for track: Track)
    func prepareAudio(for track: Track, preferredQuality: Int) async throws -> StreamResolver.PreparedAudioStream
    func warmAudioCDN(for track: Track, preferredQuality: Int) async
}

extension StreamResolver: AudioStreamResolving {}
