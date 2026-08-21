import XCTest
@testable import BiliMusic

final class AudioStructureScoreV4Tests: XCTestCase {
    func testBuilderProducesBoundedCompleteQuantizedScore() throws {
        let lines = makeV4FixtureLines(count: 180)
        let score = AudioStructureScoreBuilderV4.make(map: makeV4FixtureMap(), lines: lines)

        XCTAssertNotNil(score.validated(lineCount: lines.count))
        XCTAssertEqual(score.version, LyricStagePlanV4Version.audioScore)
        XCTAssertEqual(score.availability, .ready)
        XCTAssertEqual(score.semantics, .localAnalyzer)
        XCTAssertEqual(score.lineFacts.map(\.lineIndex), Array(lines.indices))
        XCTAssertLessThanOrEqual(score.tempoSegments.count, 8)
        XCTAssertLessThanOrEqual(score.sections.count, 24)
        XCTAssertLessThanOrEqual(score.lineDetails.count, 64)
        XCTAssertLessThanOrEqual(score.moments.count, 32)
        XCTAssertTrue(score.lineDetails.allSatisfy {
            $0.energyContourQ.count == 4
                && $0.pitchContourTenths.count == 3
                && $0.accentEvents.count <= 3
        })
        XCTAssertEqual(score.fingerprint, AudioStructureScoreBuilderV4.make(
            map: makeV4FixtureMap(),
            lines: lines).fingerprint)
    }

    func testMissingAudioRetainsOneFactPerLineAndExplicitStatus() throws {
        let lines = makeV4FixtureLines(count: 20)
        let score = AudioStructureScoreBuilderV4.make(
            map: nil,
            lines: lines,
            availability: .missingCache)

        XCTAssertNotNil(score.validated(lineCount: lines.count))
        XCTAssertEqual(score.availability, .missingCache)
        XCTAssertEqual(score.lineFacts.count, lines.count)
        XCTAssertTrue(score.lineDetails.isEmpty)
        XCTAssertTrue(score.moments.isEmpty)
        XCTAssertTrue(score.lineFacts.allSatisfy {
            $0.meanEnergyQ == nil
                && $0.signedNearestBeatMilliseconds == nil
                && $0.onsetCount == 0
        })
    }

    func testDeterministicDegradationNeverDropsAllLineFacts() {
        let lines = makeV4FixtureLines(count: 180)
        let score = makeV4FixtureScore(lines: lines)
        let first = score.deterministicallyLimited(
            lineDetailCount: 8,
            momentCount: 4,
            includeContours: false)
        let second = score.deterministicallyLimited(
            lineDetailCount: 8,
            momentCount: 4,
            includeContours: false)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.lineFacts, score.lineFacts)
        XCTAssertEqual(first.lineFacts.count, lines.count)
        XCTAssertLessThanOrEqual(first.lineDetails.count, 8)
        XCTAssertLessThanOrEqual(first.moments.count, 4)
        XCTAssertTrue(first.lineDetails.allSatisfy {
            $0.energyContourQ.isEmpty && $0.pitchContourTenths.isEmpty
        })
        XCTAssertNotEqual(first.fingerprint, score.fingerprint)
    }

    func testEncodedTupleOrderRoundTripsExactly() throws {
        let lines = makeV4FixtureLines(count: 12)
        let score = makeV4FixtureScore(lines: lines)
        let data = try JSONEncoder().encode(score)
        let decoded = try JSONDecoder().decode(AudioStructureScoreV4.self, from: data)

        XCTAssertEqual(decoded, score)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["tempoSegments"] as? [[Any]])?.first?.count, 4)
        XCTAssertEqual((json["sections"] as? [[Any]])?.first?.count, 18)
        XCTAssertEqual((json["lineFacts"] as? [[Any]])?.first?.count, 13)
        XCTAssertEqual((json["lineDetails"] as? [[Any]])?.first?.count, 6)
        XCTAssertEqual((json["moments"] as? [[Any]])?.first?.count, 7)
    }
}
