import XCTest
@testable import BiliMusic

final class LyricStageClientV4Tests: XCTestCase {
    override func tearDown() {
        LyricStageV4MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testRich180LineRequestIsBoundedDeterministicAndPreservesCompleteLyrics() async throws {
        let lines = makeV4FixtureLines(count: 180, longText: true)
        let score = makeV4FixtureScore(lines: lines)
        let track = Track(
            bvid: "BVV4PAYLOAD",
            cid: 180,
            title: "V4 payload",
            artist: "Fixture",
            coverURL: nil,
            duration: 760)
        let client = LyricStageClientV4(
            endpoint: URL(string: "https://director.example/v4/lyrics/direct")!,
            apiKey: "test-token",
            session: makeV4Session())

        let first = try await client.prepareRequest(track: track, lines: lines, audioScore: score)
        let second = try await client.prepareRequest(track: track, lines: lines, audioScore: score)
        let firstBody = try v4RequestBody(first.request)
        let secondBody = try v4RequestBody(second.request)

        XCTAssertEqual(firstBody, secondBody)
        XCTAssertEqual(first.bodyByteCount, firstBody.count)
        XCTAssertLessThanOrEqual(firstBody.count, LyricStageClientV4.workerHardRequestLimitBytes)
        XCTAssertEqual(first.audioScore.fingerprint, second.audioScore.fingerprint)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
        XCTAssertEqual(json["version"] as? String, LyricStagePlanV4Version.current)
        XCTAssertEqual(json["audioScoreHash"] as? String, first.audioScore.fingerprint)
        let requestLines = try XCTUnwrap(json["lines"] as? [[String: Any]])
        XCTAssertEqual(requestLines.count, lines.count)
        for (requestLine, sourceLine) in zip(requestLines, lines) {
            XCTAssertEqual(requestLine["text"] as? String, sourceLine.text)
            XCTAssertEqual(requestLine["from"] as? Double, sourceLine.from)
            XCTAssertEqual(requestLine["to"] as? Double, sourceLine.to)
            XCTAssertNil(requestLine["words"])
        }
        let audioScore = try XCTUnwrap(json["audioScore"] as? [String: Any])
        XCTAssertEqual((audioScore["lineFacts"] as? [[Any]])?.count, lines.count)
        XCTAssertLessThanOrEqual((audioScore["lineDetails"] as? [[Any]])?.count ?? .max, 64)
        XCTAssertLessThanOrEqual((audioScore["moments"] as? [[Any]])?.count ?? .max, 32)
    }

    func testMalformedAndInvalidScenesAreLocallyDiscardedOrRepairedWithoutChangingLyrics() async throws {
        let lines = makeV4FixtureLines(count: 6)
        let snapshot = lines
        let score = makeV4FixtureScore(lines: lines)
        let track = Track(
            bvid: "BVV4REPAIR",
            cid: 9,
            title: "Repair",
            artist: "Fixture",
            coverURL: nil,
            duration: 760)
        LyricStageV4MockURLProtocol.handler = { request in
            let body = try v4RequestBody(request)
            let input = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let response: [String: Any] = [
                "version": LyricStagePlanV4Version.current,
                "grammarVersion": LyricStagePlanV4Version.grammar,
                "directorVersion": "fixture-network-v4",
                "trackID": input["trackID"]!,
                "lyricsHash": input["lyricsHash"]!,
                "lineCount": lines.count,
                "audioScoreHash": input["audioScoreHash"]!,
                "stageBible": [
                    "concept": "repair",
                    "intensityArc": "quiet resolve",
                    "primaryMotif": ["signature": "rail", "axis": "horizontal", "cadence": "phrase"],
                ],
                "scenes": [
                    42,
                    NSNull(),
                    [
                        "lineIndex": 0,
                        "family": "railHandoff",
                        "topology": "contour",
                        "entrance": "aperture",
                        "focus": "tokenRange",
                        "sustain": "echo",
                        "continuity": "clear",
                        "driver": "structuralMoment",
                        "landmarkIDs": [],
                        "companionLineIndices": [],
                        "motifPhase": "develop",
                        "intensity": 3,
                    ],
                    [
                        "lineIndex": 1,
                        "family": "semanticLens",
                        "topology": "anchor",
                        "entrance": "settle",
                        "focus": "tokenRange",
                        "tokenRange": ["startTokenIndex": 99, "endTokenIndex": 120],
                        "sustain": "sweep",
                        "continuity": "clear",
                        "driver": "wordReveal",
                        "landmarkIDs": [],
                        "companionLineIndices": [],
                        "motifPhase": "develop",
                        "intensity": 0.7,
                    ],
                    [
                        "lineIndex": 2,
                        "family": "railHandoff",
                        "topology": "anchor",
                        "entrance": "settle",
                        "focus": "wholeLine",
                        "sustain": "none",
                        "continuity": "handoff",
                        "driver": "lyricReveal",
                        "landmarkIDs": [],
                        "companionLineIndices": [],
                        "motifPhase": "resolve",
                        "intensity": 0.5,
                    ],
                ],
                "degraded": false,
                "partial": false,
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            return (http, data)
        }
        let client = LyricStageClientV4(
            endpoint: URL(string: "https://director.example/v4/lyrics/direct")!,
            apiKey: "test-token",
            session: makeV4Session())

        let result = try await client.direct(track: track, lines: lines, audioScore: score)

        XCTAssertEqual(lines, snapshot)
        XCTAssertEqual(result.direction.scenes.map(\.lineIndex), [0, 2])
        let repaired = try XCTUnwrap(result.direction.scenes.first)
        XCTAssertEqual(repaired.topology, .relay)
        XCTAssertEqual(repaired.entrance, .slide)
        XCTAssertEqual(repaired.focus, .wholeLine)
        XCTAssertEqual(repaired.sustain, .railTravel)
        XCTAssertEqual(repaired.continuity, .handoff)
        XCTAssertEqual(repaired.driver, .lyricReveal)
        XCTAssertEqual(repaired.intensity, 1)
    }

    func testCompleteOutlineOverHardLimitFailsBeforeNetworkAndNeverTruncates() async throws {
        let lines = (0..<180).map { index in
            PlayerEngine.LyricLine(
                from: Double(index) * 2,
                to: Double(index) * 2 + 1.5,
                text: "\(index)-" + String(repeating: "界", count: 900))
        }
        let score = AudioStructureScoreBuilderV4.make(map: nil, lines: lines, availability: .missingCache)
        let track = Track(
            bvid: "BVV4OVERSIZE",
            title: "Oversize",
            artist: "Fixture",
            coverURL: nil,
            duration: 400)
        let client = LyricStageClientV4(
            endpoint: URL(string: "https://director.example/v4/lyrics/direct")!,
            apiKey: "test-token",
            session: makeV4Session())

        do {
            _ = try await client.prepareRequest(track: track, lines: lines, audioScore: score)
            XCTFail("Expected the complete outline to exceed the hard limit")
        } catch let error as LyricStageClientV4.ClientError {
            guard case .completeLyricsExceedHardLimit(let bytes) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertGreaterThan(bytes, LyricStageClientV4.workerHardRequestLimitBytes)
        }
    }
}

private func makeV4Session() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LyricStageV4MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func v4RequestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { throw URLError(.cannotDecodeContentData) }
    stream.open()
    defer { stream.close() }
    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
        if count == 0 { break }
        body.append(contentsOf: buffer.prefix(count))
    }
    return body
}

private final class LyricStageV4MockURLProtocol: URLProtocol {
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
