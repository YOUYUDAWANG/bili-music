import XCTest
@testable import BiliMusic

final class LDDCLyricsBackendClientTests: XCTestCase {
    override func tearDown() {
        LDDCMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testClientMapsValidatedBackendWordsIntoLyricsDocument() async throws {
        let response = """
        {
          "schema": "bilimusic-lddc-lyrics-v1",
          "requestID": "BV1lddc:123:cover",
          "candidates": [{
            "source": "kugou",
            "id": "kg-1",
            "title": "心拍数#0822",
            "artist": "鹿乃",
            "album": null,
            "durationSeconds": 322,
            "timingKind": "word",
            "lyricLines": [{
              "startMilliseconds": 1000,
              "endMilliseconds": 2000,
              "text": "心拍",
              "words": [
                {"startMilliseconds":1000,"endMilliseconds":1500,"text":"心"},
                {"startMilliseconds":1500,"endMilliseconds":2000,"text":"拍"}
              ]
            }],
            "translationLines": [{
              "startMilliseconds": 1000,
              "endMilliseconds": 2000,
              "text": "心跳",
              "words": []
            }],
            "romanizationLines": [],
            "titleScore": 100,
            "artistScore": 100,
            "fromCache": false
          }]
        }
        """.data(using: .utf8)!
        LDDCMockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            return (http, response)
        }
        let client = LDDCLyricsBackendClient(
            baseURL: URL(string: "https://lyrics.example")!,
            accessToken: "test-token",
            session: session())

        let hits = try await client.lookup(
            track: track(),
            metadata: metadata(),
            preferCover: true)

        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].result.provider, .kugou)
        XCTAssertEqual(hits[0].result.timingKindHint, .word)
        XCTAssertEqual(hits[0].document.timingKind, .word)
        XCTAssertEqual(hits[0].document.translatedLyric, "[00:01.000]心跳")
        let lines = LyricsParser.lines(from: hits[0].document, duration: 322)
        XCTAssertEqual(lines.map(\.text), ["心拍"])
        XCTAssertEqual(lines[0].words.map(\.text), ["心", "拍"])
    }

    func testCoverOriginalPassExplicitlyAllowsDurationMismatchForSafeAppPolicy() async throws {
        let response = """
        {"schema":"bilimusic-lddc-lyrics-v1","requestID":"BV1lddc:123:original","candidates":[]}
        """.data(using: .utf8)!
        LDDCMockURLProtocol.handler = { request in
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response)
        }
        let client = LDDCLyricsBackendClient(
            baseURL: URL(string: "https://lyrics.example")!,
            accessToken: "test-token",
            session: session())

        let hits = try await client.lookup(
            track: track(),
            metadata: metadata(),
            preferCover: false)

        XCTAssertTrue(hits.isEmpty)
    }

    func testManualSearchReturnsVerifiedWordHint() async throws {
        let response = """
        {
          "schema":"bilimusic-lddc-lyrics-v1",
          "requestID":"BV1lddc:123:manual",
          "candidates":[{
            "source":"tencent","id":"manual-word","title":"心拍数#0822","artist":"鹿乃",
            "durationSeconds":322,"timingKind":"word",
            "lyricLines":[{"startMilliseconds":1000,"endMilliseconds":2000,"text":"心","words":[{"startMilliseconds":1000,"endMilliseconds":2000,"text":"心"}]}],
            "translationLines":[],"romanizationLines":[],"titleScore":100,"artistScore":100,"fromCache":false
          }]
        }
        """.data(using: .utf8)!
        LDDCMockURLProtocol.handler = { request in
            let body = try requestBody(from: request)
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(payload["requireDurationMatch"] as? Bool, false)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response)
        }
        let client = LDDCLyricsBackendClient(
            baseURL: URL(string: "https://lyrics.example")!,
            accessToken: "test-token",
            session: session())

        let hits = try await client.search(
            keyword: "心拍数#0822-鹿乃",
            track: track(),
            metadata: metadata())

        XCTAssertEqual(hits.map(\.result.id), ["manual-word"])
        XCTAssertEqual(hits.first?.result.timingKindHint, .word)
    }

    func testClientRejectsWordOutsideItsLineBounds() async {
        let response = """
        {
          "schema":"bilimusic-lddc-lyrics-v1",
          "requestID":"BV1lddc:123:cover",
          "candidates":[{
            "source":"tencent","id":"bad","title":"心拍数#0822","artist":"鹿乃",
            "durationSeconds":322,"timingKind":"word",
            "lyricLines":[{"startMilliseconds":1000,"endMilliseconds":2000,"text":"心","words":[{"startMilliseconds":900,"endMilliseconds":1200,"text":"心"}]}],
            "translationLines":[],"romanizationLines":[],"titleScore":100,"artistScore":100,"fromCache":false
          }]
        }
        """.data(using: .utf8)!
        LDDCMockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, response)
        }
        let client = LDDCLyricsBackendClient(
            baseURL: URL(string: "https://lyrics.example")!,
            accessToken: "test-token",
            session: session())

        do {
            _ = try await client.lookup(track: track(), metadata: metadata(), preferCover: true)
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(error as? LDDCLyricsBackendError, .invalidResponse)
        }
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LDDCMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func track() -> Track {
        Track(
            bvid: "BV1lddc",
            cid: 123,
            title: "鹿乃 翻唱《心拍数#0822》",
            artist: "鹿乃ちゃん",
            coverURL: nil,
            duration: 322)
    }

    private func metadata() -> NormalizedTrackMetadata {
        NormalizedTrackMetadata(
            canonicalTitle: "心拍数#0822",
            originalArtists: ["蝶々P"],
            coverPerformers: ["鹿乃"],
            uploader: "鹿乃ちゃん",
            language: "ja",
            aliases: ["心拍数♯0822"],
            lyricSearchQueries: ["心拍数#0822 鹿乃", "心拍数#0822 蝶々P"],
            isCover: true,
            confidence: 0.98,
            needsReview: false,
            serviceVersion: "test")
    }
}

private func requestBody(from request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else {
        throw URLError(.cannotDecodeContentData)
    }
    stream.open()
    defer { stream.close() }
    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeContentData)
        }
        if count == 0 { break }
        body.append(contentsOf: buffer.prefix(count))
    }
    return body
}

private final class LDDCMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
