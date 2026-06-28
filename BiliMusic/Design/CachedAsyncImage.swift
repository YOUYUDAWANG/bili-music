import SwiftUI
import UIKit
import ImageIO

@MainActor
final class ImageMemoryCache {
    static let shared = ImageMemoryCache()

    private let cache = NSCache<NSString, UIImage>()
    private var cacheKeysByCanonicalURL: [String: Set<String>] = [:]

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
        return keys
            .compactMap { cache.object(forKey: $0 as NSString) }
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
        cacheKeysByCanonicalURL[Self.canonicalURLKey(for: url), default: []].insert(key)
    }

    func removeAll() {
        cache.removeAllObjects()
        cacheKeysByCanonicalURL.removeAll()
    }

    func releaseReloadableImages() {
        cache.removeAllObjects()
        cacheKeysByCanonicalURL.removeAll()
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

    func image(for url: URL, headers: [String: String] = BiliClient.headers) async -> UIImage? {
        await image(for: url, targetPixelSize: nil, headers: headers)
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
                return await Task.detached(priority: priority) {
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
    var debugIdentifier: String?
    var onImageLoaded: @MainActor (UIImage) -> Void = { _ in }
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var loadedIdentifier: String?

    var body: some View {
        let resolvedDisplayImage = displayImage
        let hasDisplayImage = resolvedDisplayImage != nil
        let identifier = loadIdentifier

#if DEBUG
        Group {
            if let resolvedDisplayImage {
                content(Image(uiImage: resolvedDisplayImage))
            } else {
                placeholder()
            }
        }
        .onAppear {
            debugLog("body.appear hasDisplay=\(hasDisplayImage) identifier=\(identifier)")
        }
        .onChange(of: hasDisplayImage) { _, hasDisplayImage in
            debugLog("body.displayChanged hasDisplay=\(hasDisplayImage) identifier=\(loadIdentifier)")
        }
        .onChange(of: identifier) { _, identifier in
            debugLog("body.identifierChanged identifier=\(identifier)")
        }
        .task(id: loadIdentifier) {
            await load()
        }
#else
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
#endif
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
#if DEBUG
        let startedAt = CFAbsoluteTimeGetCurrent()
        debugLog("load.start identifier=\(identifier) target=\(debugTargetDescription(targetPixelSize))")
#endif
        if let cached = ImageMemoryCache.shared.image(for: url, targetPixelSize: targetPixelSize) {
            guard identifier == loadIdentifier else { return }
            image = cached
            loadedIdentifier = identifier
#if DEBUG
            debugLog("load.exactCacheHit elapsed=\(debugElapsedMS(since: startedAt)) image=\(debugImageDescription(cached))")
#endif
            onImageLoaded(cached)
            return
        }
        if let reusable = ImageMemoryCache.shared.bestImage(forAnyVariantOf: url) {
            guard identifier == loadIdentifier else { return }
            image = reusable
            loadedIdentifier = identifier
#if DEBUG
            debugLog("load.reusableCacheHit elapsed=\(debugElapsedMS(since: startedAt)) image=\(debugImageDescription(reusable))")
#endif
            onImageLoaded(reusable)
        }
        // 不提前清空 image：保留旧图或占位图，避免磁盘缓存命中时的闪烁
        guard let decoded = await ImageLoadCoordinator.shared.image(
            for: url,
            targetPixelSize: targetPixelSize,
            headers: headers,
            scale: scale),
              !Task.isCancelled else {
#if DEBUG
            debugLog("load.downloadNil elapsed=\(debugElapsedMS(since: startedAt))")
#endif
            return
        }
        guard identifier == loadIdentifier else { return }
        ImageMemoryCache.shared.insert(decoded, for: url, targetPixelSize: targetPixelSize)
        image = decoded
        loadedIdentifier = identifier
#if DEBUG
        debugLog("load.downloadDone elapsed=\(debugElapsedMS(since: startedAt)) image=\(debugImageDescription(decoded))")
#endif
        onImageLoaded(decoded)
    }

    private var displayImage: UIImage? {
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

#if DEBUG
    private func debugLog(_ message: String) {
        guard let debugIdentifier else { return }
        NSLog("ARTWORK_DIAG cachedAsyncImage %@ %@", debugIdentifier, message)
    }

    private func debugTargetDescription(_ target: CGSize?) -> String {
        guard let target else { return "nil" }
        return "\(Int(target.width.rounded()))x\(Int(target.height.rounded()))"
    }

    private func debugImageDescription(_ image: UIImage?) -> String {
        guard let image else { return "nil" }
        let width = Int((image.size.width * image.scale).rounded())
        let height = Int((image.size.height * image.scale).rounded())
        return "\(width)x\(height)@\(String(format: "%.1f", image.scale))"
    }

    private func debugElapsedMS(since start: CFAbsoluteTime) -> String {
        String(format: "%.1fms", (CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
#endif
}
