import XCTest
@testable import BiliMusic

final class LyricStageClientV3Tests: XCTestCase {
    override func tearDown() {
        LyricStageV3MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testClientSendsAudioSummaryAndAcceptsStrictSparseDirection() async throws {
        let track = Track(
            bvid: "BVCLIENTV3",
            cid: 9,
            title: "Client V3",
            artist: "Fixture",
            coverURL: nil,
            duration: 30)
        let lines = (0..<10).map { index in
            PlayerEngine.LyricLine(
                from: Double(index) * 2,
                to: Double(index) * 2 + 1.5,
                text: "client line \(index)")
        }
        let audio = LyricStageAudioSummaryV3.empty(duration: 30)
        let direction = LyricStageDirectionV3(
            directorVersion: "test-v3",
            trackID: track.key.description,
            lyricsHash: LyricPerformanceFingerprint.lyricsHash(lines),
            lineCount: lines.count,
            audioSummaryHash: audio.summaryHash,
            stageBible: LyricStageBibleV3(
                concept: "network concept",
                motif: "network motif",
                intensityArc: "quiet build resolve"),
            sections: [
                LyricStageSectionV3(
                    id: "whole",
                    lineFrom: 0,
                    lineTo: 9,
                    kind: .verse,
                    intensity: 0.5,
                    motifPhase: .develop),
            ],
            scenes: [
                LyricStageSceneOverrideV3(lineIndex: 4, composition: .leadingAnchor),
            ],
            provider: "fixture",
            model: "fixture-model")
        let responseData = try JSONEncoder().encode(direction)
        LyricStageV3MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v3/lyrics/direct")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let body = try lyricStageV3RequestBody(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["audioSummaryHash"] as? String, audio.summaryHash)
            XCTAssertNotNil(json["audioSummary"])
            XCTAssertNil(json["tokens"])
            let requestLines = try XCTUnwrap(json["lines"] as? [[String: Any]])
            XCTAssertTrue(requestLines.allSatisfy { $0["words"] == nil })
            XCTAssertTrue(requestLines.allSatisfy { $0["layerID"] == nil })
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            return (response, responseData)
        }
        let client = LyricStageClientV3(
            endpoint: URL(string: "https://director.example/v3/lyrics/direct")!,
            apiKey: "test-token",
            session: makeSession())

        let result = try await client.direct(track: track, lines: lines, audioSummary: audio)

        XCTAssertEqual(result, direction)
    }

    func testMaximumRichAudioPayloadStaysBelowWorkerLimitAndOmitsWordData() async throws {
        let track = Track(
            bvid: "BVCLIENTV3MAX",
            cid: 180,
            title: "Long V3 Payload",
            artist: "Fixture",
            coverURL: nil,
            duration: 760)
        let lines = (0..<180).map { index in
            let from = Double(index) * 4.1
            let text = "\(index)-" + String(repeating: "長い歌詞の完全な一行", count: 8)
            return PlayerEngine.LyricLine(
                from: from,
                to: from + 3.6,
                text: text,
                words: [.init(from: from, to: from + 3.6, text: text)])
        }
        let audio = makeRichAudioSummary(lines: lines, duration: 760)
        let direction = LyricStageDirectionV3(
            directorVersion: "test-v3-max-payload",
            trackID: track.key.description,
            lyricsHash: LyricPerformanceFingerprint.lyricsHash(lines),
            lineCount: lines.count,
            audioSummaryHash: audio.summaryHash,
            stageBible: LyricStageBibleV3(
                concept: "compact request",
                motif: "complete lines",
                intensityArc: "steady"),
            sections: [
                LyricStageSectionV3(
                    id: "whole",
                    lineFrom: 0,
                    lineTo: lines.count - 1,
                    kind: .verse,
                    intensity: 0.5,
                    motifPhase: .develop),
            ],
            scenes: (0..<18).map { index in
                LyricStageSceneOverrideV3(
                    lineIndex: index * 10,
                    composition: index.isMultiple(of: 2) ? .leadingAnchor : .trailingAnchor)
            })
        let responseData = try JSONEncoder().encode(direction)
        LyricStageV3MockURLProtocol.handler = { request in
            let body = try lyricStageV3RequestBody(from: request)
            print("LyricStageClientV3 180-line payload bytes: \(body.count)")
            XCTAssertGreaterThan(body.count, 20_000)
            XCTAssertLessThanOrEqual(body.count, 98_304)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertNil(json["tokens"])
            let requestLines = try XCTUnwrap(json["lines"] as? [[String: Any]])
            XCTAssertEqual(requestLines.count, 180)
            XCTAssertTrue(requestLines.allSatisfy {
                $0["words"] == nil && $0["tokens"] == nil && $0["layerID"] == nil
            })
            for (requestLine, sourceLine) in zip(requestLines, lines) {
                XCTAssertEqual(requestLine["text"] as? String, sourceLine.text)
                XCTAssertEqual(requestLine["from"] as? Double, sourceLine.from)
                XCTAssertEqual(requestLine["to"] as? Double, sourceLine.to)
            }
            let requestAudio = try XCTUnwrap(json["audioSummary"] as? [String: Any])
            XCTAssertEqual(requestAudio["version"] as? String, audio.version)
            XCTAssertEqual(requestAudio["mapFingerprint"] as? String, audio.mapFingerprint)
            XCTAssertEqual(requestAudio["summaryHash"] as? String, audio.summaryHash)
            XCTAssertEqual((requestAudio["sections"] as? [[String: Any]])?.count, audio.sections.count)
            let featureLines = try XCTUnwrap(requestAudio["lines"] as? [[String: Any]])
            XCTAssertEqual(featureLines.count, 96)
            let featureIndices = featureLines.compactMap { $0["lineIndex"] as? Int }
            XCTAssertEqual(featureIndices, featureIndices.sorted())
            let boundaryIndices = Set(audio.sections.flatMap { section in
                [section.lineFrom, section.lineTo].compactMap { $0 }
            })
            XCTAssertTrue(boundaryIndices.isSubset(of: Set(featureIndices)))
            let rawJSON = try XCTUnwrap(String(data: body, encoding: .utf8))
            XCTAssertFalse(rawJSON.contains("\"words\""))
            XCTAssertFalse(rawJSON.contains("\"tokens\""))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            return (response, responseData)
        }
        let client = LyricStageClientV3(
            endpoint: URL(string: "https://director.example/v3/lyrics/direct")!,
            apiKey: "test-token",
            session: makeSession())

        let result = try await client.direct(track: track, lines: lines, audioSummary: audio)

        XCTAssertEqual(result, direction)
    }

    func testClientRejectsMismatchedAudioSummaryIdentity() async throws {
        let track = Track(
            bvid: "BVCLIENTBAD",
            title: "Client V3 Bad",
            artist: "Fixture",
            coverURL: nil,
            duration: 30)
        let lines = (0..<10).map { index in
            PlayerEngine.LyricLine(from: Double(index), to: Double(index) + 0.8, text: "bad line \(index)")
        }
        let audio = LyricStageAudioSummaryV3.empty(duration: 30)
        let direction = LyricStageDirectionV3(
            directorVersion: "test-v3",
            trackID: track.key.description,
            lyricsHash: LyricPerformanceFingerprint.lyricsHash(lines),
            lineCount: lines.count,
            audioSummaryHash: "wrong-audio-summary",
            stageBible: LyricStageBibleV3(concept: "bad", motif: "bad", intensityArc: "bad"),
            sections: [
                LyricStageSectionV3(
                    id: "whole",
                    lineFrom: 0,
                    lineTo: 9,
                    kind: .verse,
                    intensity: 0.5,
                    motifPhase: .develop),
            ],
            scenes: [LyricStageSceneOverrideV3(lineIndex: 4, composition: .leadingAnchor)])
        let responseData = try JSONEncoder().encode(direction)
        LyricStageV3MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseData)
        }
        let client = LyricStageClientV3(
            endpoint: URL(string: "https://director.example/v3/lyrics/direct")!,
            apiKey: "test-token",
            session: makeSession())

        do {
            _ = try await client.direct(track: track, lines: lines, audioSummary: audio)
            XCTFail("Expected strict audio-summary identity rejection")
        } catch let error as LyricStageClientV3.ClientError {
            guard case .invalidResponse = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricStageV3MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeRichAudioSummary(
        lines: [PlayerEngine.LyricLine],
        duration: Double
    ) -> LyricStageAudioSummaryV3 {
        let sectionSize = 15
        let lineFeatures = lines.enumerated().map { index, line in
            let energy = 0.28 + Double(index % 9) * 0.06
            return LyricStageAudioLineSummaryV3(
                lineIndex: index,
                from: line.from,
                to: line.to,
                sectionIndex: index / sectionSize,
                meanEnergy: min(0.92, energy),
                peakEnergy: min(1, energy + 0.16),
                energyDelta: Double((index % 5) - 2) * 0.07,
                onsetCount: 1 + index % 5,
                onsetStrength: 0.45 + Double(index % 6) * 0.08,
                nearestBeatDistance: 0.012 + Double(index % 4) * 0.009,
                pitchStart: 180 + Double(index % 12) * 11,
                pitchEnd: 186 + Double(index % 12) * 11,
                pitchTrend: Double((index % 7) - 3) * 4.5,
                pitchConfidence: 0.58 + Double(index % 4) * 0.08,
                longToneRatio: 0.22 + Double(index % 5) * 0.11,
                silenceBefore: index.isMultiple(of: sectionSize) ? 0.48 : 0.02,
                silenceAfter: (index + 1).isMultiple(of: sectionSize) ? 0.34 : 0.01)
        }
        let sections = stride(from: 0, to: lines.count, by: sectionSize).enumerated().map { section, start in
            let end = min(lines.count - 1, start + sectionSize - 1)
            return LyricStageAudioSectionSummaryV3(
                index: section,
                from: lines[start].from,
                to: lines[end].to,
                lineFrom: start,
                lineTo: end,
                meanEnergy: 0.38 + Double(section % 5) * 0.10,
                energyTrend: Double((section % 3) - 1) * 0.14,
                onsetDensity: 0.8 + Double(section % 4) * 0.35,
                pitchTrend: Double((section % 5) - 2) * 9,
                confidence: 0.78)
        }
        return LyricStageAudioSummaryV3(
            version: AudioPerformanceMapV2Version.stageSummary,
            mapFingerprint: String(repeating: "f", count: 64),
            summaryHash: String(repeating: "a", count: 64),
            duration: duration,
            bpm: 174.5,
            confidence: AudioPerformanceConfidence(
                beat: 0.86,
                downbeat: 0.79,
                onset: 0.91,
                energy: 0.94,
                pitch: 0.82,
                regions: 0.88,
                overall: 0.87),
            sections: sections,
            lines: lineFeatures)
    }
}

private func lyricStageV3RequestBody(from request: URLRequest) throws -> Data {
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

private final class LyricStageV3MockURLProtocol: URLProtocol {
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
