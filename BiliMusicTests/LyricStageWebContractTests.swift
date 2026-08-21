import Foundation
import XCTest

final class LyricStageWebContractTests: XCTestCase {
    private struct Document: Decodable {
        let version: String
        let recordingID: String
        let durationMs: Int
        let lines: [Line]
    }

    private struct Line: Decodable {
        let lineIndex: Int
        let fromMs: Int
        let toMs: Int
        let text: String
        let words: [Word]?
        let voiceRole: String?
        let overlapGroup: String?
    }

    private struct Word: Decodable {
        let wordIndex: Int
        let fromMs: Int
        let toMs: Int
        let text: String
    }

    private let fixtureNames = [
        "line-only-ja",
        "word-timed-mixed",
        "long-line",
        "repeated-hook",
        "duet-overlap",
        "long-song-structure",
    ]

    func testSharedWebFixturesPreserveTextTimingAndVoices() throws {
        for name in fixtureNames {
            let document = try decodeFixture(named: name)
            XCTAssertEqual(document.version, "lyric-document-v0", name)
            XCTAssertFalse(document.recordingID.isEmpty, name)
            XCTAssertFalse(document.lines.isEmpty, name)

            var previousFrom = -1
            for (expectedIndex, line) in document.lines.enumerated() {
                XCTAssertEqual(line.lineIndex, expectedIndex, name)
                XCTAssertFalse(line.text.isEmpty, name)
                XCTAssertGreaterThanOrEqual(line.fromMs, previousFrom, name)
                XCTAssertGreaterThan(line.toMs, line.fromMs, name)
                XCTAssertLessThanOrEqual(line.toMs, document.durationMs, name)
                previousFrom = line.fromMs

                for (expectedWordIndex, word) in (line.words ?? []).enumerated() {
                    XCTAssertEqual(word.wordIndex, expectedWordIndex, name)
                    XCTAssertFalse(word.text.isEmpty, name)
                    XCTAssertGreaterThanOrEqual(word.fromMs, line.fromMs, name)
                    XCTAssertLessThanOrEqual(word.toMs, line.toMs, name)
                }
            }
        }
    }

    func testLineOnlyFixtureDoesNotInventWordTiming() throws {
        let document = try decodeFixture(named: "line-only-ja")
        XCTAssertTrue(document.lines.allSatisfy { ($0.words ?? []).isEmpty })
    }

    func testOverlapFixtureKeepsTwoVoicesAtTheSameTime() throws {
        let document = try decodeFixture(named: "duet-overlap")
        XCTAssertEqual(document.lines[2].fromMs, document.lines[3].fromMs)
        XCTAssertEqual(document.lines[2].overlapGroup, "bridge")
        XCTAssertEqual(document.lines[3].overlapGroup, "bridge")
        XCTAssertEqual(document.lines[2].voiceRole, "duetA")
        XCTAssertEqual(document.lines[3].voiceRole, "duetB")
    }

    private func decodeFixture(named name: String) throws -> Document {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json"),
            "Missing shared fixture \(name).json in BiliMusicTests resources"
        )
        return try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
    }
}
