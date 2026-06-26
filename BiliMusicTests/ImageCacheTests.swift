import UIKit
import XCTest
@testable import BiliMusic

final class ImageCacheTests: XCTestCase {
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
}
