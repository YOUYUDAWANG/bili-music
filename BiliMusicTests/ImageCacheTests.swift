import UIKit
import XCTest
@testable import BiliMusic

final class ImageCacheTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            ImageMemoryCache.shared.removeAll()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            ImageMemoryCache.shared.removeAll()
        }
        CountingImageURLProtocol.reset()
        try await super.tearDown()
    }

    @MainActor
    func testMemoryCostUsesPixelDimensions() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 20)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 20))
        }

        XCTAssertEqual(ImageMemoryCache.memoryCost(for: image), 10 * 20 * Int(image.scale * image.scale) * 4)
    }

    @MainActor
    func testImageCacheStoresAndReturnsInsertedImage() {
        let url = URL(string: "https://example.com/fixture-\(UUID().uuidString).jpg")!
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }

        ImageMemoryCache.shared.insert(image, for: url)

        XCTAssertNotNil(ImageMemoryCache.shared.image(for: url))
    }

    @MainActor
    func testImageCacheSeparatesSameURLByTargetPixelSize() {
        let url = URL(string: "https://example.com/shared-cover.jpg")!
        let smallTarget = CGSize(width: 64, height: 36)
        let largeTarget = CGSize(width: 320, height: 180)
        let smallImage = makeImage(size: smallTarget, color: .blue)
        let largeImage = makeImage(size: largeTarget, color: .green)

        ImageMemoryCache.shared.insert(smallImage, for: url, targetPixelSize: smallTarget)
        ImageMemoryCache.shared.insert(largeImage, for: url, targetPixelSize: largeTarget)

        XCTAssertEqual(ImageMemoryCache.shared.image(for: url, targetPixelSize: smallTarget)?.pixelSize, smallTarget)
        XCTAssertEqual(ImageMemoryCache.shared.image(for: url, targetPixelSize: largeTarget)?.pixelSize, largeTarget)
    }

    @MainActor
    func testDownsampledImageDataUsesTargetPixelSizeBeforeCaching() throws {
        let sourceImage = makeImage(size: CGSize(width: 1200, height: 675), color: .purple)
        let sourceData = try XCTUnwrap(sourceImage.jpegData(compressionQuality: 0.9))

        let decoded = try XCTUnwrap(ImageLoadCoordinator.downsample(
            data: sourceData,
            targetPixelSize: CGSize(width: 192, height: 108),
            scale: 1))

        XCTAssertLessThanOrEqual(decoded.pixelSize.width, 192)
        XCTAssertLessThanOrEqual(decoded.pixelSize.height, 108)
        XCTAssertLessThan(ImageMemoryCache.memoryCost(for: decoded), ImageMemoryCache.memoryCost(for: sourceImage))
    }

    func testRepeatedURLAndTargetRequestsCoalesceInFlightLoad() async {
        let payload = makeImage(size: CGSize(width: 300, height: 180), color: .orange).pngData()!
        CountingImageURLProtocol.configure(payload: payload, delay: 0.08)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CountingImageURLProtocol.self]
        config.urlCache = nil
        let coordinator = ImageLoadCoordinator(session: URLSession(configuration: config))
        let url = URL(string: "https://example.com/coalesced-cover.png")!
        let target = CGSize(width: 150, height: 90)

        async let first = coordinator.image(for: url, targetPixelSize: target, headers: [:])
        async let second = coordinator.image(for: url, targetPixelSize: target, headers: [:])
        let images = await [first, second]

        XCTAssertEqual(images.compactMap { $0 }.count, 2)
        XCTAssertEqual(CountingImageURLProtocol.requestCount, 1)
    }

    @MainActor
    func testReleaseReloadableImagesClearsCachedImages() {
        let url = URL(string: "https://example.com/reloadable-cover.jpg")!
        let image = makeImage(size: CGSize(width: 64, height: 36), color: .red)

        ImageMemoryCache.shared.insert(image, for: url, targetPixelSize: image.pixelSize)
        XCTAssertNotNil(ImageMemoryCache.shared.image(for: url, targetPixelSize: image.pixelSize))

        ImageMemoryCache.shared.releaseReloadableImages()

        XCTAssertNil(ImageMemoryCache.shared.image(for: url, targetPixelSize: image.pixelSize))
    }

    @MainActor
    func testBackgroundCleanupReleasesImagesWithoutClearingPlaybackState() async {
        let url = URL(string: "https://example.com/background-cover.jpg")!
        let image = makeImage(size: CGSize(width: 64, height: 36), color: .cyan)
        let tracks = [makeTrack("BVBG00000001"), makeTrack("BVBG00000002")]
        let engine = PlayerEngine()
        engine.installUITestFixture(tracks: tracks, startAt: 1)

        ImageMemoryCache.shared.insert(image, for: url, targetPixelSize: image.pixelSize)

        await AppResourceCleanup.handleBackgrounding(engine: engine)

        XCTAssertNil(ImageMemoryCache.shared.image(for: url, targetPixelSize: image.pixelSize))
        XCTAssertEqual(engine.current?.bvid, tracks[1].bvid)
        XCTAssertEqual(engine.queue.map(\.bvid), tracks.map(\.bvid))
        XCTAssertEqual(engine.queueIndex, 1)
    }

    @MainActor
    func testForegroundRestoreKeepsCurrentArtworkAvailableAfterImageCleanup() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/archive/current-cover.jpg"))
        let artworkURL = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/archive/current-cover.jpg@960w_540h_1c.webp"))
        let targetSize = CGSize(width: 960, height: 540)
        let image = makeImage(size: targetSize, color: .cyan)
        let track = makeTrack("BVBG00000003", coverURL: baseURL)
        let engine = PlayerEngine()
        engine.installUITestFixture(tracks: [track], startAt: 0)

        ImageMemoryCache.shared.insert(image, for: artworkURL, targetPixelSize: targetSize)

        await engine.handleScenePhase(isBackground: false)
        ImageMemoryCache.shared.releaseReloadableImages()

        XCTAssertEqual(engine.current?.bvid, track.bvid)
        XCTAssertEqual(engine.currentCoverImage?.pixelSize, targetSize)
    }

    @MainActor
    func testBackgroundCleanupPreservesCurrentArtwork() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/archive/background-current-cover.jpg"))
        let artworkURL = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/archive/background-current-cover.jpg@960w_540h_1c.webp"))
        let targetSize = CGSize(width: 960, height: 540)
        let image = makeImage(size: targetSize, color: .cyan)
        let track = makeTrack("BVBG00000005", coverURL: baseURL)
        let engine = PlayerEngine()
        engine.installUITestFixture(tracks: [track], startAt: 0)

        ImageMemoryCache.shared.insert(image, for: artworkURL, targetPixelSize: targetSize)

        await AppResourceCleanup.handleBackgrounding(engine: engine)

        XCTAssertNil(ImageMemoryCache.shared.image(for: artworkURL, targetPixelSize: targetSize))
        XCTAssertEqual(engine.current?.bvid, track.bvid)
        XCTAssertEqual(engine.currentCoverImage?.pixelSize, targetSize)
    }

    @MainActor
    func testBackgroundCleanupPreservesCurrentArtworkFromThumbnailVariant() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/archive/background-current-thumbnail.jpg"))
        let thumbnailURL = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/archive/background-current-thumbnail.jpg@150w_85h_1c.webp"))
        let targetSize = CGSize(width: 150, height: 85)
        let image = makeImage(size: targetSize, color: .cyan)
        let track = makeTrack("BVBG00000006", coverURL: baseURL)
        let engine = PlayerEngine()
        engine.installUITestFixture(tracks: [track], startAt: 0)

        ImageMemoryCache.shared.insert(image, for: thumbnailURL, targetPixelSize: targetSize)

        await AppResourceCleanup.handleBackgrounding(engine: engine)

        XCTAssertNil(ImageMemoryCache.shared.image(for: thumbnailURL, targetPixelSize: targetSize))
        XCTAssertEqual(engine.current?.bvid, track.bvid)
        XCTAssertEqual(engine.currentCoverImage?.pixelSize, targetSize)
    }

    @MainActor
    func testBackgroundCleanupUpgradesMiniArtworkBeforeImageRelease() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/archive/background-current-upgrade.jpg"))
        let artworkURL = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/archive/background-current-upgrade.jpg@960w_540h_1c.webp"))
        let miniImage = makeImage(size: CGSize(width: 150, height: 85), color: .green)
        let largeSize = CGSize(width: 960, height: 540)
        let largeImage = makeImage(size: largeSize, color: .cyan)
        let track = makeTrack("BVBG00000007", coverURL: baseURL)
        let engine = PlayerEngine()
        engine.installUITestFixture(tracks: [track], startAt: 0)

        engine.rememberCurrentCover(miniImage, for: track)
        ImageMemoryCache.shared.insert(largeImage, for: artworkURL, targetPixelSize: largeSize)

        await AppResourceCleanup.handleBackgrounding(engine: engine)

        XCTAssertNil(ImageMemoryCache.shared.image(for: artworkURL, targetPixelSize: largeSize))
        XCTAssertEqual(engine.current?.bvid, track.bvid)
        XCTAssertEqual(engine.currentCoverImage?.pixelSize, largeSize)
    }

    @MainActor
    func testRememberCurrentCoverDoesNotReplaceLargeArtworkWithMiniArtwork() {
        let track = makeTrack("BVBG00000004")
        let engine = PlayerEngine()
        engine.installUITestFixture(tracks: [track], startAt: 0)
        let large = makeImage(size: CGSize(width: 960, height: 540), color: .blue)
        let mini = makeImage(size: CGSize(width: 44, height: 25), color: .green)

        engine.rememberCurrentCover(large, for: track)
        engine.rememberCurrentCover(mini, for: track)

        XCTAssertEqual(engine.currentCoverImage?.pixelSize, large.pixelSize)
    }

    @MainActor
    func testMemoryWarningHandlerReleasesReloadableImages() {
        let url = URL(string: "https://example.com/memory-warning-cover.jpg")!
        let image = makeImage(size: CGSize(width: 64, height: 36), color: .magenta)

        ImageMemoryCache.shared.insert(image, for: url, targetPixelSize: image.pixelSize)
        AppResourceCleanup.handleMemoryWarning(
            Notification(name: UIApplication.didReceiveMemoryWarningNotification))

        XCTAssertNil(ImageMemoryCache.shared.image(for: url, targetPixelSize: image.pixelSize))
    }

    @MainActor
    func testMemoryWarningPreservesCurrentArtworkBeforeImageRelease() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/archive/memory-current-cover.jpg"))
        let thumbnailURL = try XCTUnwrap(URL(string: "https://i0.hdslb.com/bfs/archive/memory-current-cover.jpg@150w_85h_1c.webp"))
        let targetSize = CGSize(width: 150, height: 85)
        let image = makeImage(size: targetSize, color: .cyan)
        let track = makeTrack("BVBG00000008", coverURL: baseURL)
        let engine = PlayerEngine()
        engine.installUITestFixture(tracks: [track], startAt: 0)

        ImageMemoryCache.shared.insert(image, for: thumbnailURL, targetPixelSize: targetSize)
        AppResourceCleanup.handleMemoryWarning(
            Notification(name: UIApplication.didReceiveMemoryWarningNotification),
            engine: engine)

        XCTAssertNil(ImageMemoryCache.shared.image(for: thumbnailURL, targetPixelSize: targetSize))
        XCTAssertEqual(engine.current?.bvid, track.bvid)
        XCTAssertEqual(engine.currentCoverImage?.pixelSize, targetSize)
    }

    @MainActor
    func testCachedAsyncImagePrefersCurrentLoadedImageOverFallback() {
        let loaded = makeImage(size: CGSize(width: 960, height: 540), color: .blue)
        let fallback = makeImage(size: CGSize(width: 150, height: 85), color: .green)

        let displayed = CachedImageDisplayState.preferredImage(
            loadedImage: loaded,
            loadedIdentifier: "cover#960x540",
            currentIdentifier: "cover#960x540",
            fallbackImage: fallback)

        XCTAssertTrue(displayed === loaded)
    }

    @MainActor
    func testCachedAsyncImageUsesFallbackInsteadOfLoadedImageForOldIdentifier() {
        let staleLoaded = makeImage(size: CGSize(width: 960, height: 540), color: .blue)
        let currentFallback = makeImage(size: CGSize(width: 150, height: 85), color: .green)

        let displayed = CachedImageDisplayState.preferredImage(
            loadedImage: staleLoaded,
            loadedIdentifier: "old-cover#960x540",
            currentIdentifier: "new-cover#960x540",
            fallbackImage: currentFallback)

        XCTAssertTrue(displayed === currentFallback)
    }

    private func makeImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeTrack(_ bvid: String, coverURL: URL? = nil) -> Track {
        Track(
            aid: nil,
            ownerMid: nil,
            bvid: bvid,
            cid: 1,
            title: "Test Track \(bvid)",
            artist: "Tester",
            coverURL: coverURL,
            duration: 180)
    }
}

private extension UIImage {
    var pixelSize: CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }
}

private final class CountingImageURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var payload = Data()
    private static var responseDelay: TimeInterval = 0
    private(set) static var requestCount = 0

    static func configure(payload: Data, delay: TimeInterval) {
        lock.lock()
        self.payload = payload
        responseDelay = delay
        requestCount = 0
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        payload = Data()
        responseDelay = 0
        requestCount = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.requestCount += 1
        let payload = Self.payload
        let responseDelay = Self.responseDelay
        Self.lock.unlock()

        DispatchQueue.global().asyncAfter(deadline: .now() + responseDelay) { [weak self] in
            guard let self,
                  let url = self.request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "image/png"])
            else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: payload)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
