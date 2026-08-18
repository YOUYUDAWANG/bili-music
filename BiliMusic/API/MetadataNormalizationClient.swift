import Foundation

struct MetadataNormalizationResponse: Decodable, Sendable {
    let version: String
    let canonicalTitle: String
    let artists: [String]
    let performers: [String]
    let uploader: String?
    let language: String
    let aliases: [String]
    let searchQueries: [String]
    let confidence: Double
    let needsReview: Bool
    let degraded: Bool

    var metadata: NormalizedTrackMetadata {
        NormalizedTrackMetadata(
            canonicalTitle: canonicalTitle,
            artists: artists,
            performers: performers,
            uploader: uploader,
            language: language,
            aliases: aliases,
            searchQueries: searchQueries,
            confidence: confidence,
            needsReview: needsReview,
            serviceVersion: version)
    }
}

actor MetadataNormalizationClient: TrackMetadataNormalizing {
    enum ClientError: LocalizedError {
        case unconfigured
        case invalidResponse
        case server(Int)
        case degraded

        var errorDescription: String? {
            switch self {
            case .unconfigured: "歌曲元数据服务尚未配置"
            case .invalidResponse: "歌曲元数据服务返回格式异常"
            case .server(let status): "歌曲元数据服务暂时不可用（\(status)）"
            case .degraded: "歌曲元数据服务未完成在线清洗"
            }
        }
    }

    private let endpoint: URL?
    private let apiKey: String
    private let session: URLSession

    init(endpoint: URL? = nil, apiKey: String? = nil, session: URLSession? = nil) {
        self.endpoint = endpoint ?? Self.configuredEndpoint
        self.apiKey = apiKey ?? Self.bundleString(for: "BiliMusicMetadataAPIKey") ?? ""
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 25
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    func normalize(_ track: Track) async throws -> NormalizedTrackMetadata {
        guard let endpoint, !apiKey.isEmpty else { throw ClientError.unconfigured }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("BiliMusic/iOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "title": track.title,
            "uploader": track.artist,
            "duration": track.duration,
            "bvid": track.bvid,
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ClientError.server(http.statusCode) }
        let result = try JSONDecoder().decode(MetadataNormalizationResponse.self, from: data)
        guard !result.degraded else { throw ClientError.degraded }
        let title = result.canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ClientError.invalidResponse }
        return result.metadata
    }

    private static var configuredEndpoint: URL? {
        let value = bundleString(for: "BiliMusicMetadataAPIURL")
            ?? "https://bilimusic-metadata.mercari-email-sale-worker.workers.dev/v1/music/normalize"
        return URL(string: value)
    }

    private static func bundleString(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}
