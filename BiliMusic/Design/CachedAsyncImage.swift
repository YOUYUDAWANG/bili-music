import SwiftUI
import UIKit
import ImageIO

@MainActor
final class ImageMemoryCache {
    static let shared = ImageMemoryCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        image(for: url, targetPixelSize: nil)
    }

    func image(for url: URL, targetPixelSize: CGSize?) -> UIImage? {
        cache.object(forKey: Self.cacheKey(for: url, targetPixelSize: targetPixelSize))
    }

    func insert(_ image: UIImage, for url: URL, cost: Int? = nil) {
        insert(image, for: url, targetPixelSize: nil, cost: cost)
    }

    func insert(_ image: UIImage, for url: URL, targetPixelSize: CGSize?, cost: Int? = nil) {
        cache.setObject(
            image,
            forKey: Self.cacheKey(for: url, targetPixelSize: targetPixelSize),
            cost: cost ?? Self.memoryCost(for: image))
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    static func memoryCost(for image: UIImage) -> Int {
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        return max(1, width * height * 4)
    }

    static func targetPixelSize(for displaySize: CGSize?, scale: CGFloat) -> CGSize? {
        guard let displaySize,
              displaySize.width.isFinite,
              displaySize.height.isFinite,
              displaySize.width > 0,
              displaySize.height > 0,
              scale.isFinite,
              scale > 0 else {
            return nil
        }
        return CGSize(
            width: ceil(displaySize.width * scale),
            height: ceil(displaySize.height * scale))
    }

    private static func cacheKey(for url: URL, targetPixelSize: CGSize?) -> NSString {
        guard let targetPixelSize else {
            return "\(url.absoluteString)#original" as NSString
        }
        let width = max(1, Int(ceil(targetPixelSize.width)))
        let height = max(1, Int(ceil(targetPixelSize.height)))
        return "\(url.absoluteString)#\(width)x\(height)" as NSString
    }
}

actor ImageLoadCoordinator {
    static let shared = ImageLoadCoordinator()

    private let session: URLSession
    private var inFlight: [ImageLoadKey: Task<UIImage?, Never>] = [:]

    init(session: URLSession = ImageLoadCoordinator.makeDefaultSession()) {
        self.session = session
    }

    func image(for url: URL, headers: [String: String] = BiliClient.headers) async -> UIImage? {
        await image(for: url, targetPixelSize: nil, headers: headers)
    }

    func image(
        for url: URL,
        targetPixelSize: CGSize?,
        headers: [String: String] = BiliClient.headers,
        scale: CGFloat = 1
    ) async -> UIImage? {
        let normalizedTarget = Self.normalizedTargetPixelSize(targetPixelSize)
        let key = ImageLoadKey(url: url, targetPixelSize: normalizedTarget)
        if let task = inFlight[key] {
            return await task.value
        }

        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let session = session
        let target = normalizedTarget
        let task = Task<UIImage?, Never>(priority: .utility) {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    return nil
                }
                return await Task.detached(priority: .utility) {
                    Self.downsample(data: data, targetPixelSize: target, scale: scale)
                }.value
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        return image
    }

    static func downsample(data: Data, targetPixelSize: CGSize?, scale: CGFloat = 1) -> UIImage? {
        guard let targetPixelSize = normalizedTargetPixelSize(targetPixelSize) else {
            return UIImage(data: data)
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return UIImage(data: data)
        }
        let maxPixelSize = max(targetPixelSize.width, targetPixelSize.height)
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(ceil(maxPixelSize)))
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    private static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "BiliMusicImages")
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 12
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }

    private static func normalizedTargetPixelSize(_ targetPixelSize: CGSize?) -> CGSize? {
        guard let targetPixelSize,
              targetPixelSize.width.isFinite,
              targetPixelSize.height.isFinite,
              targetPixelSize.width > 0,
              targetPixelSize.height > 0 else {
            return nil
        }
        return CGSize(
            width: max(1, ceil(targetPixelSize.width)),
            height: max(1, ceil(targetPixelSize.height)))
    }

    private struct ImageLoadKey: Hashable {
        let url: URL
        let pixelWidth: Int?
        let pixelHeight: Int?

        init(url: URL, targetPixelSize: CGSize?) {
            self.url = url
            pixelWidth = targetPixelSize.map { Int(ceil($0.width)) }
            pixelHeight = targetPixelSize.map { Int(ceil($0.height)) }
        }
    }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var headers: [String: String] = BiliClient.headers
    var targetSize: CGSize?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: loadIdentifier) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard let url else {
            image = nil
            return
        }
        let scale = max(displayScale, 1)
        let targetPixelSize = ImageMemoryCache.targetPixelSize(for: targetSize, scale: scale)
        if let cached = ImageMemoryCache.shared.image(for: url, targetPixelSize: targetPixelSize) {
            image = cached
            return
        }
        // 不提前清空 image：保留旧图或占位图，避免磁盘缓存命中时的闪烁
        guard let decoded = await ImageLoadCoordinator.shared.image(
            for: url,
            targetPixelSize: targetPixelSize,
            headers: headers,
            scale: scale),
              !Task.isCancelled else {
            return
        }
        ImageMemoryCache.shared.insert(decoded, for: url, targetPixelSize: targetPixelSize)
        image = decoded
    }

    private var loadIdentifier: String {
        guard let url else { return "nil" }
        let scale = max(displayScale, 1)
        let targetPixelSize = ImageMemoryCache.targetPixelSize(for: targetSize, scale: scale)
        if let targetPixelSize {
            return "\(url.absoluteString)#\(Int(ceil(targetPixelSize.width)))x\(Int(ceil(targetPixelSize.height)))"
        }
        return "\(url.absoluteString)#original"
    }
}
