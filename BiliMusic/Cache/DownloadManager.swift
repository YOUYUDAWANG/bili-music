import Foundation
import Observation

/// 整曲下载到本地缓存,带进度。用 URLSessionDownloadTask(逐字节 AsyncBytes 读流吞吐太低)。
@Observable
@MainActor
final class DownloadManager {
    static let shared = DownloadManager()

    /// bvid → 0...1 下载进度;不在字典里 = 没在下载
    private(set) var progress: [String: Double] = [:]
    private(set) var lastError: String?

    private let client = BiliClient()

    private init() {}

    func isDownloading(_ bvid: String) -> Bool {
        progress[bvid] != nil
    }

    func download(track: Track) async {
        guard progress[track.bvid] == nil,
              CacheStore.shared.entry(bvid: track.bvid) == nil else { return }
        progress[track.bvid] = 0
        defer { progress[track.bvid] = nil }
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
            let stream = try await client.audioStream(bvid: track.bvid, cid: cid)

            var req = URLRequest(url: stream.url)
            BiliClient.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
            let bvid = track.bvid
            let watcher = ProgressWatcher { [weak self] fraction in
                Task { @MainActor in self?.progress[bvid] = fraction }
            }
            let (tempURL, _) = try await URLSession.shared.download(for: req, delegate: watcher)

            let fileName = "\(track.bvid)_\(cid).m4a"
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
