import Foundation
import OSLog

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "download")
import Observation

/// 整曲下载到本地缓存,带进度。用 URLSessionDownloadTask(逐字节 AsyncBytes 读流吞吐太低)。
@Observable
@MainActor
final class DownloadManager {
    static let shared = DownloadManager()

    /// TrackKey → 0...1 下载进度;不在字典里 = 没在下载
    private(set) var progress: [TrackKey: Double] = [:]
    private(set) var lastError: String?

    private let client = BiliClient()

    private init() {}

    /// 该 bvid 是否正在下载。
    func isDownloading(_ bvid: String) -> Bool {
        progress.keys.contains { $0.bvid == bvid }
    }

    func isDownloading(_ track: Track) -> Bool {
        progress[track.key] != nil || (track.cid == nil && progress.keys.contains { $0.bvid == track.bvid })
    }

    func progress(for track: Track) -> Double? {
        progress[track.key] ?? progress.first { $0.key.matches(track) }?.value
    }

    /// 下载整曲到本地缓存：补全 cid → 取流 → 边下边报进度 → 落盘并写索引。已在下载或已缓存则跳过。
    func download(track: Track) async {
        guard !isDownloading(track),
              CacheStore.shared.entry(for: track) == nil else { return }
        let initialKey = track.key
        progress[initialKey] = 0
        var activeKey = initialKey
        defer { progress[activeKey] = nil }
        do {
            var track = track
            if track.cid == nil {
                let info = try await client.videoInfo(bvid: track.bvid)
                guard let page = info.pages.first else {
                    throw BiliClient.APIError(code: -1, message: "无分P")
                }
                track.cid = page.cid
                track.duration = page.duration
            }
            let cid = track.cid!
            activeKey = track.key
            if activeKey != initialKey {
                progress[activeKey] = progress.removeValue(forKey: initialKey) ?? 0
            }
            let stream = try await client.audioStream(
                bvid: track.bvid, cid: cid,
                preferredQuality: UserDefaults.standard.integer(forKey: "downloadQuality"))

            var req = URLRequest(url: stream.url)
            BiliClient.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
            let key = track.key
            let watcher = ProgressWatcher { [weak self] fraction in
                Task { @MainActor in self?.progress[key] = fraction }
            }
            let (tempURL, _) = try await URLSession.shared.download(for: req, delegate: watcher)

            let fileName = "\(track.key.fileStem).m4a"
            let finalURL = CacheStore.audioDir.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: finalURL)
            try FileManager.default.moveItem(at: tempURL, to: finalURL)
            let size = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int64) ?? 0

            CacheStore.shared.add(CachedEntry(
                bvid: track.bvid, cid: cid, title: track.title, artist: track.artist,
                coverURL: track.coverURL?.absoluteString, duration: track.duration,
                fileName: fileName, fileSize: size, downloadedAt: Date(),
                quality: stream.quality))
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// URLSessionDownloadTask 的进度回调适配器，把字节进度换算成 0...1 回调出去。
private final class ProgressWatcher: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    // async download(for:) 自己处理完成回调,这里只需要进度;但协议要求实现该方法
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
