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
    private var operationIDs: [TrackKey: UUID] = [:]

    private let client = BiliClient()

    private init() {}

    func isDownloading(_ track: Track) -> Bool {
        operationIDs.keys.contains { $0.matches(track) }
    }

    func progress(for track: Track) -> Double? {
        progress[track.key] ?? progress.first { $0.key.matches(track) }?.value
    }

    /// 下载整曲到本地缓存：补全 cid → 取流 → 边下边报进度 → 落盘并写索引。已在下载或已缓存则跳过。
    func download(track: Track) async {
        // 先等索引加载完成再判重,冷启动时 entry(for:) 才不会恒 miss 导致重复下载
        await CacheStore.shared.loadIfNeeded()
        guard !isDownloading(track),
              CacheStore.shared.entry(for: track) == nil else { return }
        let initialKey = track.key
        let operationID = UUID()
        operationIDs[initialKey] = operationID
        progress[initialKey] = 0
        var activeKey = initialKey
        defer {
            for key in Set([initialKey, activeKey]) where operationIDs[key] == operationID {
                operationIDs[key] = nil
                progress[key] = nil
            }
        }
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
                operationIDs[activeKey] = operationID
                operationIDs[initialKey] = nil
                progress[activeKey] = progress.removeValue(forKey: initialKey) ?? 0
            }
            let stream = try await client.audioStream(
                bvid: track.bvid, cid: cid,
                preferredQuality: UserDefaults.standard.integer(forKey: "downloadQuality"))

            var req = URLRequest(url: stream.url)
            BiliClient.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
            let key = track.key
            let watcher = ProgressWatcher { [weak self] fraction in
                Task { @MainActor in
                    guard self?.operationIDs[key] == operationID else { return }
                    self?.progress[key] = fraction
                }
            }
            let (tempURL, response) = try await URLSession.shared.download(for: req, delegate: watcher)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw BiliClient.APIError(code: http.statusCode, message: "缓存下载失败")
            }

            let fileName = "\(track.key.fileStem).m4a"
            let finalURL = CacheStore.audioDir.appendingPathComponent(fileName)
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: finalURL.path) {
                _ = try fileManager.replaceItemAt(finalURL, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: finalURL)
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int64) ?? 0
            guard size > 0 else {
                try? fileManager.removeItem(at: finalURL)
                throw BiliClient.APIError(code: -1, message: "缓存文件为空")
            }

            let entry = CachedEntry(
                bvid: track.bvid, cid: cid, title: track.title, artist: track.artist,
                coverURL: track.coverURL?.absoluteString, duration: track.duration,
                fileName: fileName, fileSize: size, downloadedAt: Date(),
                quality: stream.quality)
            do {
                try await CacheStore.shared.addPersisting(entry)
            } catch {
                try? fileManager.removeItem(at: finalURL)
                throw error
            }
            lastError = nil
        } catch {
            // 带上曲目标识,避免并发下载时错误信息无从对应
            lastError = "「\(track.title)」缓存失败：\(error.localizedDescription)"
        }
    }
}

/// URLSessionDownloadTask 的进度回调适配器，把字节进度换算成 0...1 回调出去。
private final class ProgressWatcher: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var lastReportedFraction = 0.0
    private var lastReportedAt = CFAbsoluteTimeGetCurrent()

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let fraction: Double
        if totalBytesExpectedToWrite > 0 {
            fraction = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        } else {
            // chunked 响应拿不到总长:用渐近曲线给一个保守的活动信号,
            // 单调递增且永远到不了 1,不会误报「即将完成」。
            let written = Double(max(0, totalBytesWritten))
            fraction = written / (written + 4 * 1024 * 1024)
        }
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let shouldReport = fraction >= 1
            || fraction - lastReportedFraction >= 0.01
            || now - lastReportedAt >= 0.15
        if shouldReport {
            lastReportedFraction = fraction
            lastReportedAt = now
        }
        lock.unlock()
        if shouldReport {
            onProgress(fraction)
        }
    }

    // async download(for:) 自己处理完成回调,这里只需要进度;但协议要求实现该方法
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
