import XCTest
@testable import BiliMusic

final class PrecisionLyricsHostClientTests: XCTestCase {
    override func tearDown() {
        PrecisionHostMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testHostResultBecomesAWordTimedSourceOnlyAfterQualityGate() throws {
        let source = sourceDocument()
        let result = PrecisionLyricsHostClient.JobResult(
            schema: PrecisionLyricsHostClient.schema,
            jobID: "BV1precision-abc",
            bvid: "BV1precision",
            karaokeLyric: "[1000,1000]<0,500,0>目<500,500,0>覚\n[3000,1000]<0,500,0>合<500,500,0>図\n",
            quality: quality())

        let alignment = try PrecisionLyricsHostClient.alignment(
            result: result,
            source: source,
            track: track())

        XCTAssertEqual(alignment.document.result.provider, .precisionHost)
        XCTAssertEqual(alignment.document.timingKind, .word)
        XCTAssertEqual(alignment.document.lyric, source.lyric)
        XCTAssertEqual(alignment.document.translatedLyric, source.translatedLyric)
        XCTAssertEqual(
            LyricsParser.lines(from: alignment.document, duration: 10).map(\.text),
            ["目覚", "合図"])
    }

    func testHostResultCannotReplaceLyricsWhenDisplayTextChanges() {
        let result = PrecisionLyricsHostClient.JobResult(
            schema: PrecisionLyricsHostClient.schema,
            jobID: "BV1precision-abc",
            bvid: "BV1precision",
            karaokeLyric: "[1000,1000]<0,500,0>目<500,500,0>覚\n[3000,1000]<0,500,0>別<500,500,0>詞\n",
            quality: quality())

        XCTAssertThrowsError(try PrecisionLyricsHostClient.alignment(
            result: result,
            source: sourceDocument(),
            track: track())) { error in
                XCTAssertEqual(
                    error as? PrecisionLyricsHostError,
                    .qualityRejected("歌词全文没有被完整保留"))
            }
    }

    func testHostResultRejectsWeakGlobalConsensus() {
        var weak = quality()
        weak = PrecisionLyricsHostQuality(
            lineCount: weak.lineCount,
            characterCount: weak.characterCount,
            modelConsensusLines: weak.modelConsensusLines,
            globalAnchorLines: weak.globalAnchorLines,
            rhythmFallbackLines: weak.rhythmFallbackLines,
            whisperXCharacterLines: weak.whisperXCharacterLines,
            globalSampleCount: 3,
            globalCandidateCount: weak.globalCandidateCount,
            globalMedianAbsoluteDeviation: weak.globalMedianAbsoluteDeviation,
            globalOffsetSeconds: weak.globalOffsetSeconds,
            minimumCharacterSeconds: weak.minimumCharacterSeconds,
            medianCharacterSeconds: weak.medianCharacterSeconds,
            elapsedSeconds: weak.elapsedSeconds,
            qrcBytes: weak.qrcBytes)
        let result = PrecisionLyricsHostClient.JobResult(
            schema: PrecisionLyricsHostClient.schema,
            jobID: "BV1precision-abc",
            bvid: "BV1precision",
            karaokeLyric: "[1000,1000]<0,500,0>目<500,500,0>覚\n[3000,1000]<0,500,0>合<500,500,0>図\n",
            quality: weak)

        XCTAssertThrowsError(try PrecisionLyricsHostClient.alignment(
            result: result,
            source: sourceDocument(),
            track: track()))
    }

    func testHalfIndependentCharacterCoverageIsAcceptedButMarkedForConfirmation() throws {
        let base = quality()
        let partial = PrecisionLyricsHostQuality(
            lineCount: base.lineCount,
            characterCount: base.characterCount,
            modelConsensusLines: base.modelConsensusLines,
            globalAnchorLines: base.globalAnchorLines,
            rhythmFallbackLines: base.rhythmFallbackLines,
            whisperXCharacterLines: 1,
            globalSampleCount: base.globalSampleCount,
            globalCandidateCount: base.globalCandidateCount,
            globalMedianAbsoluteDeviation: base.globalMedianAbsoluteDeviation,
            globalOffsetSeconds: base.globalOffsetSeconds,
            minimumCharacterSeconds: base.minimumCharacterSeconds,
            medianCharacterSeconds: base.medianCharacterSeconds,
            elapsedSeconds: base.elapsedSeconds,
            qrcBytes: base.qrcBytes)
        let result = PrecisionLyricsHostClient.JobResult(
            schema: PrecisionLyricsHostClient.schema,
            jobID: "BV1precision-partial",
            bvid: "BV1precision",
            karaokeLyric: "[1000,1000]<0,500,0>目<500,500,0>覚\n[3000,1000]<0,500,0>合<500,500,0>図\n",
            quality: partial)

        let alignment = try PrecisionLyricsHostClient.alignment(
            result: result,
            source: sourceDocument(),
            track: track())

        XCTAssertTrue(alignment.document.timingNeedsConfirmation)
    }

    func testLessThanHalfIndependentCharacterCoverageIsRejected() {
        let base = quality()
        let weak = PrecisionLyricsHostQuality(
            lineCount: base.lineCount,
            characterCount: base.characterCount,
            modelConsensusLines: base.modelConsensusLines,
            globalAnchorLines: base.globalAnchorLines,
            rhythmFallbackLines: base.rhythmFallbackLines,
            whisperXCharacterLines: 0,
            globalSampleCount: base.globalSampleCount,
            globalCandidateCount: base.globalCandidateCount,
            globalMedianAbsoluteDeviation: base.globalMedianAbsoluteDeviation,
            globalOffsetSeconds: base.globalOffsetSeconds,
            minimumCharacterSeconds: base.minimumCharacterSeconds,
            medianCharacterSeconds: base.medianCharacterSeconds,
            elapsedSeconds: base.elapsedSeconds,
            qrcBytes: base.qrcBytes)
        let result = PrecisionLyricsHostClient.JobResult(
            schema: PrecisionLyricsHostClient.schema,
            jobID: "BV1precision-weak-characters",
            bvid: "BV1precision",
            karaokeLyric: "[1000,1000]<0,500,0>目<500,500,0>覚\n[3000,1000]<0,500,0>合<500,500,0>図\n",
            quality: weak)

        XCTAssertThrowsError(try PrecisionLyricsHostClient.alignment(
            result: result,
            source: sourceDocument(),
            track: track())) { error in
                XCTAssertEqual(
                    error as? PrecisionLyricsHostError,
                    .qualityRejected("独立字符复核覆盖不足"))
            }
    }

    func testHealthCheckFallsBackToReachableHost() async throws {
        PrecisionHostMockURLProtocol.handler = { request in
            guard request.url?.host == "192.168.10.129" else {
                throw URLError(.cannotConnectToHost)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            let data = Data(#"{"schema":"bilimusic-precision-host-v1","status":"ok","queueDepth":0}"#.utf8)
            return (response, data)
        }
        let client = PrecisionLyricsHostClient(
            session: mockSession(),
            baseURLs: [
                URL(string: "http://100.78.10.98:8765")!,
                URL(string: "http://192.168.10.129:8765")!,
            ])

        let latency = try await client.healthCheck()

        XCTAssertGreaterThanOrEqual(latency, 0)
    }

    func testHealthCheckFailsInsteadOfWaitingForeverWhenHostsAreOffline() async {
        PrecisionHostMockURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let client = PrecisionLyricsHostClient(
            session: mockSession(),
            baseURLs: [URL(string: "http://100.78.10.98:8765")!])

        do {
            _ = try await client.healthCheck()
            XCTFail("Expected an unreachable-host error")
        } catch {
            XCTAssertEqual(error as? PrecisionLyricsHostError, .hostUnreachable)
        }
    }

    func testRawHostLineCountDoesNotRejectOneLineSplitIntoBackingVoice() throws {
        let source = LyricsDocument(
            result: LyricsSearchResult(
                provider: .netease,
                id: "duet-source",
                title: "Duet",
                artist: "Singer",
                album: nil,
                duration: 10,
                artworkID: nil),
            lyric: "[00:01.00]主唱（和声：伴唱）",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil,
            timingKind: .line)
        let duetQuality = PrecisionLyricsHostQuality(
            lineCount: 1,
            characterCount: 6,
            modelConsensusLines: 1,
            globalAnchorLines: 0,
            rhythmFallbackLines: 0,
            whisperXCharacterLines: 1,
            globalSampleCount: 6,
            globalCandidateCount: 8,
            globalMedianAbsoluteDeviation: 0.04,
            globalOffsetSeconds: 0,
            minimumCharacterSeconds: 0.05,
            medianCharacterSeconds: 0.18,
            elapsedSeconds: 1,
            qrcBytes: 120)
        let result = PrecisionLyricsHostClient.JobResult(
            schema: PrecisionLyricsHostClient.schema,
            jobID: "BV1precision-duet",
            bvid: "BV1precision",
            karaokeLyric: "[1000,1200]<0,200,0>主<200,200,0>唱（<400,200,0>和<600,200,0>声：<800,200,0>伴<1000,200,0>唱）",
            quality: duetQuality)

        let alignment = try PrecisionLyricsHostClient.alignment(
            result: result,
            source: source,
            track: track())

        XCTAssertEqual(LyricsParser.lines(from: alignment.document, duration: 10).count, 2)
    }

    func testServerErrorDescriptionCollapsesTracebackToOneReadableLine() {
        let error = PrecisionLyricsHostError.server("""
        Traceback (most recent call last):
          File \"refine_segments.py\", line 1, in main
        ValueError: forced-aligner token crossed a repeated-line boundary
            + CategoryInfo: OperationStopped
            + FullyQualifiedErrorId: Qwen segment refinement failed
        """)

        XCTAssertEqual(
            error.localizedDescription,
            "高精度主机生成失败：ValueError: forced-aligner token crossed a repeated-line boundary")
        XCTAssertFalse(error.localizedDescription.contains("Traceback"))
    }

    private func track() -> Track {
        Track(
            bvid: "BV1precision",
            cid: 123,
            title: "You＆合図",
            artist: "Mili",
            coverURL: nil,
            duration: 10)
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PrecisionHostMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func sourceDocument() -> LyricsDocument {
        LyricsDocument(
            result: LyricsSearchResult(
                provider: .netease,
                id: "source",
                title: "You＆合図",
                artist: "Mili",
                album: nil,
                duration: 10,
                artworkID: nil),
            lyric: "[00:01.00]目覚\n[00:03.00]合図",
            translatedLyric: "[00:01.00]醒来\n[00:03.00]信号",
            romanizedLyric: nil,
            karaokeLyric: nil,
            karaokeTranslatedLyric: nil,
            timingKind: .line)
    }

    private func quality() -> PrecisionLyricsHostQuality {
        PrecisionLyricsHostQuality(
            lineCount: 2,
            characterCount: 4,
            modelConsensusLines: 2,
            globalAnchorLines: 0,
            rhythmFallbackLines: 0,
            whisperXCharacterLines: 2,
            globalSampleCount: 6,
            globalCandidateCount: 8,
            globalMedianAbsoluteDeviation: 0.04,
            globalOffsetSeconds: 6.32,
            minimumCharacterSeconds: 0.05,
            medianCharacterSeconds: 0.18,
            elapsedSeconds: 60,
            qrcBytes: 120)
    }
}

private final class PrecisionHostMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
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
