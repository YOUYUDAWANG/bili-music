import Foundation

struct MetadataNormalizationResponse: Decodable, Sendable {
    let version: String
    let canonicalTitle: String
    let originalArtists: [String]
    let coverPerformers: [String]
    let uploader: String?
    let language: String
    let aliases: [String]
    let lyricSearchQueries: [String]
    let isCover: Bool
    let confidence: Double
    let needsReview: Bool
    let degraded: Bool

    var metadata: NormalizedTrackMetadata {
        NormalizedTrackMetadata(
            canonicalTitle: canonicalTitle,
            originalArtists: originalArtists,
            coverPerformers: coverPerformers,
            uploader: uploader,
            language: language,
            aliases: aliases,
            lyricSearchQueries: lyricSearchQueries,
            isCover: isCover,
            confidence: confidence,
            needsReview: needsReview,
            serviceVersion: version)
    }

    private enum CodingKeys: String, CodingKey {
        case version, canonicalTitle
        case originalArtists, artists
        case coverPerformers, performers
        case uploader, language, aliases
        case lyricSearchQueries, searchQueries
        case isCover, confidence, needsReview, degraded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        canonicalTitle = try container.decode(String.self, forKey: .canonicalTitle)
        originalArtists = Self.decodeNames(container, .originalArtists, .artists)
        coverPerformers = Self.decodeNames(container, .coverPerformers, .performers)
        uploader = try container.decodeIfPresent(String.self, forKey: .uploader)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "und"
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        lyricSearchQueries = Self.decodeNames(container, .lyricSearchQueries, .searchQueries)
        isCover = try container.decodeIfPresent(Bool.self, forKey: .isCover)
            ?? !coverPerformers.isEmpty
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        needsReview = try container.decodeIfPresent(Bool.self, forKey: .needsReview) ?? false
        degraded = try container.decodeIfPresent(Bool.self, forKey: .degraded) ?? false
    }

    private static func decodeNames(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ keys: CodingKeys...
    ) -> [String] {
        for key in keys {
            if let values = try? container.decode([String].self, forKey: key) {
                return values
            }
        }
        return []
    }
}

actor MetadataNormalizationClient: TrackMetadataNormalizing {
    static let currentServiceVersion = "music-metadata-v7-layered-identity"

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
        var body: [String: Any] = [
            "title": track.title,
            "uploader": track.artist,
            "duration": track.duration,
            "bvid": track.bvid,
        ]
        if let cid = track.cid {
            body["cid"] = cid
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ClientError.server(http.statusCode) }
        let result = try JSONDecoder().decode(MetadataNormalizationResponse.self, from: data)
        guard !result.degraded else { throw ClientError.degraded }
        guard result.version == Self.currentServiceVersion else { throw ClientError.invalidResponse }
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
