import UIKit
import XCTest
@testable import BiliMusic

final class ImageCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Task { @MainActor in
            ImageMemoryCache.shared.removeAll()
        }
    }

    override func tearDown() {
        Task { @MainActor in
            ImageMemoryCache.shared.removeAll()
        }
        CountingImageURLProtocol.reset()
        super.tearDown()
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

    private func makeImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
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
