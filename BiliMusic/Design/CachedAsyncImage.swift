import SwiftUI
import UIKit
import ImageIO

enum BiliArtworkURL {
    static func thumbnail(
        _ url: URL?,
        width: Int,
        height: Int,
        rejectsTransparentPlaceholder: Bool = true
    ) -> URL? {
        guard let url else { return nil }
        let raw = url.absoluteString
        if rejectsTransparentPlaceholder,
           raw.localizedCaseInsensitiveContains("transparent.png") {
            return nil
        }
        guard raw.contains("hdslb.com"), !raw.contains("@") else { return url }
        return URL(string: raw + "@\(max(1, width))w_\(max(1, height))h_1c.webp")
    }

    static func widescreenThumbnail(_ url: URL?, width: Int) -> URL? {
        thumbnail(url, width: width, height: max(1, Int(Double(width) * 9.0 / 16.0)))
    }
}

@MainActor
final class ImageMemoryCache {
    static let shared = ImageMemoryCache()

    private let cache = NSCache<NSString, UIImage>()
    private var cacheKeysByCanonicalURL: [String: Set<String>] = [:]
    private var canonicalURLOrder: [String] = []
    private let canonicalURLLimit = 300

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        image(for: url, targetPixelSize: nil)
    }

    func image(for url: URL, targetPixelSize: CGSize?) -> UIImage? {
        cache.object(forKey: Self.cacheKey(for: url, targetPixelSize: targetPixelSize) as NSString)
    }

    func bestImage(forAnyVariantOf url: URL) -> UIImage? {
        let canonicalURL = Self.canonicalURLKey(for: url)
        guard let keys = cacheKeysByCanonicalURL[canonicalURL] else { return nil }
        let liveEntries = keys.compactMap { key in
            cache.object(forKey: key as NSString).map { (key, $0) }
        }
        let liveKeys = Set(liveEntries.map(\.0))
        if liveKeys.isEmpty {
            cacheKeysByCanonicalURL[canonicalURL] = nil
            canonicalURLOrder.removeAll { $0 == canonicalURL }
            return nil
        }
        if liveKeys != keys {
            cacheKeysByCanonicalURL[canonicalURL] = liveKeys
        }
        return liveEntries
            .map(\.1)
            .max { Self.pixelArea(for: $0) < Self.pixelArea(for: $1) }
    }

    func insert(_ image: UIImage, for url: URL, cost: Int? = nil) {
        insert(image, for: url, targetPixelSize: nil, cost: cost)
    }

    func insert(_ image: UIImage, for url: URL, targetPixelSize: CGSize?, cost: Int? = nil) {
        let key = Self.cacheKey(for: url, targetPixelSize: targetPixelSize)
        cache.setObject(
            image,
            forKey: key as NSString,
            cost: cost ?? Self.memoryCost(for: image))
        let canonicalURL = Self.canonicalURLKey(for: url)
        cacheKeysByCanonicalURL[canonicalURL, default: []].insert(key)
        touchCanonicalURL(canonicalURL)
        pruneCanonicalURLsIfNeeded()
    }

    func releaseReloadableImages() {
        cache.removeAllObjects()
        cacheKeysByCanonicalURL.removeAll()
        canonicalURLOrder.removeAll()
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

    private static func cacheKey(for url: URL, targetPixelSize: CGSize?) -> String {
        guard let targetPixelSize else {
            return "\(url.absoluteString)#original"
        }
        let width = max(1, Int(ceil(targetPixelSize.width)))
        let height = max(1, Int(ceil(targetPixelSize.height)))
        return "\(url.absoluteString)#\(width)x\(height)"
    }

    private static func canonicalURLKey(for url: URL) -> String {
        let raw = url.absoluteString
        guard raw.contains("hdslb.com"),
              let variantIndex = raw.firstIndex(of: "@") else {
            return raw
        }
        return String(raw[..<variantIndex])
    }

    private func touchCanonicalURL(_ key: String) {
        canonicalURLOrder.removeAll { $0 == key }
        canonicalURLOrder.append(key)
    }

    private func pruneCanonicalURLsIfNeeded() {
        while canonicalURLOrder.count > canonicalURLLimit {
            let evicted = canonicalURLOrder.removeFirst()
            let keys = cacheKeysByCanonicalURL.removeValue(forKey: evicted) ?? []
            for key in keys {
                cache.removeObject(forKey: key as NSString)
            }
        }
    }

    private static func pixelArea(for image: UIImage) -> CGFloat {
        image.size.width * image.scale * image.size.height * image.scale
    }
}

actor ImageLoadCoordinator {
    static let shared = ImageLoadCoordinator()

    private let session: URLSession
    private var inFlight: [ImageLoadKey: Task<UIImage?, Never>] = [:]

    init(session: URLSession = ImageLoadCoordinator.makeDefaultSession()) {
        self.session = session
    }

    func image(
        for url: URL,
        targetPixelSize: CGSize?,
        headers: [String: String] = BiliClient.headers,
        scale: CGFloat = 1,
        priority: TaskPriority = .utility
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
        let task = Task<UIImage?, Never>(priority: priority) {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    return nil
                }
                let decoded = await Task.detached(priority: priority) {
                    Self.downsample(data: data, targetPixelSize: target, scale: scale)
                }.value
                // 解码成功即写入内存缓存:即使发起加载的视图已取消/复用,
                // 结果也不会丢,后续同 URL 的视图能直接命中。
                if let decoded {
                    await ImageMemoryCache.shared.insert(decoded, for: url, targetPixelSize: target)
                }
                return decoded
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

enum CachedImageDisplayState {
    static func preferredImage(
        loadedImage: UIImage?,
        loadedIdentifier: String?,
        currentIdentifier: String,
        fallbackImage: UIImage?,
        reusableImage: UIImage? = nil
    ) -> UIImage? {
        if loadedIdentifier == currentIdentifier, let loadedImage {
            return loadedImage
        }
        return largestImage(fallbackImage, reusableImage)
    }

    private static func largestImage(_ lhs: UIImage?, _ rhs: UIImage?) -> UIImage? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return pixelArea(lhs) >= pixelArea(rhs) ? lhs : rhs
    }

    private static func pixelArea(_ image: UIImage) -> CGFloat {
        image.size.width * image.scale * image.size.height * image.scale
    }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var headers: [String: String] = BiliClient.headers
    var targetSize: CGSize?
    var fallbackImage: UIImage?
    var onImageLoaded: @MainActor (UIImage) -> Void = { _ in }
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var loadedIdentifier: String?

    var body: some View {
        let resolvedDisplayImage = displayImage
        Group {
            if let resolvedDisplayImage {
                content(Image(uiImage: resolvedDisplayImage))
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
            loadedIdentifier = nil
            return
        }
        let identifier = loadIdentifier
        let scale = max(displayScale, 1)
        let targetPixelSize = ImageMemoryCache.targetPixelSize(for: targetSize, scale: scale)
        if let cached = ImageMemoryCache.shared.image(for: url, targetPixelSize: targetPixelSize) {
            guard identifier == loadIdentifier else { return }
            image = cached
            loadedIdentifier = identifier
            onImageLoaded(cached)
            return
        }
        if let reusable = ImageMemoryCache.shared.bestImage(forAnyVariantOf: url) {
            guard identifier == loadIdentifier else { return }
            image = reusable
            loadedIdentifier = identifier
            onImageLoaded(reusable)
        }
        // 不提前清空 image：保留旧图或占位图，避免磁盘缓存命中时的闪烁
        guard let decoded = await ImageLoadCoordinator.shared.image(
            for: url,
            targetPixelSize: targetPixelSize,
            headers: headers,
            scale: scale),
              !Task.isCancelled else { return }
        guard identifier == loadIdentifier else { return }
        // 内存缓存写入已在 ImageLoadCoordinator 内完成,视图侧只负责展示
        image = decoded
        loadedIdentifier = identifier
        onImageLoaded(decoded)
    }

    private var displayImage: UIImage? {
        // loaded 图可用时直接返回,跳过 bestImage 的变体扫描(每次 body 求值都会走到这里)
        if loadedIdentifier == loadIdentifier, let image {
            return image
        }
        let reusableImage = url.flatMap { ImageMemoryCache.shared.bestImage(forAnyVariantOf: $0) }
        return CachedImageDisplayState.preferredImage(
            loadedImage: image,
            loadedIdentifier: loadedIdentifier,
            currentIdentifier: loadIdentifier,
            fallbackImage: fallbackImage,
            reusableImage: reusableImage)
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
