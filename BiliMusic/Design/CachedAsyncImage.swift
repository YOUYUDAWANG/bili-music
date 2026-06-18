import SwiftUI
import UIKit

@MainActor
final class ImageMemoryCache {
    static let shared = ImageMemoryCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL, cost: Int? = nil) {
        cache.setObject(image, forKey: url as NSURL, cost: cost ?? Self.memoryCost(for: image))
    }

    static func memoryCost(for image: UIImage) -> Int {
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        return max(1, width * height * 4)
    }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var headers: [String: String] = BiliClient.headers
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard let url else {
            image = nil
            return
        }
        if let cached = ImageMemoryCache.shared.image(for: url) {
            image = cached
            return
        }
        image = nil
        do {
            var request = URLRequest(url: url)
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            let (data, _) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return }
            let decoded = await Task.detached(priority: .utility) {
                UIImage(data: data)
            }.value
            guard !Task.isCancelled, let decoded else { return }
            ImageMemoryCache.shared.insert(decoded, for: url)
            image = decoded
        } catch {
            image = nil
        }
    }
}
