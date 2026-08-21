import XCTest
@testable import BiliMusic

@MainActor
final class LyricStageStoreV4Tests: XCTestCase {
    func testStoreKeepsSameBVIDDifferentCIDEntriesIsolated() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LyricStageStoreV4(fileURLForTesting: url)
        let lines = makeV4FixtureLines(count: 10)
        let score = makeV4FixtureScore(lines: lines)
        let firstTrack = Track(
            bvid: "BVV4MULTIPART",
            cid: 101,
            title: "Part 1",
            artist: "Fixture",
            coverURL: nil,
            duration: 760)
        let secondTrack = Track(
            bvid: "BVV4MULTIPART",
            cid: 202,
            title: "Part 2",
            artist: "Fixture",
            coverURL: nil,
            duration: 760)
        let first = makeV4Direction(
            track: firstTrack,
            lines: lines,
            score: score,
            scenes: [makeV4RailRecipe(lineIndex: 1, intensity: 0.4)])
        let second = makeV4Direction(
            track: secondTrack,
            lines: lines,
            score: score,
            scenes: [makeV4RailRecipe(lineIndex: 2, intensity: 0.8)])

        let savedFirst = await store.save(first, for: firstTrack, lines: lines, audioScore: score)
        let savedSecond = await store.save(second, for: secondTrack, lines: lines, audioScore: score)
        XCTAssertTrue(savedFirst)
        XCTAssertTrue(savedSecond)

        let loadedFirst = await store.direction(for: firstTrack, lines: lines, audioScore: score)
        let loadedSecond = await store.direction(for: secondTrack, lines: lines, audioScore: score)
        XCTAssertEqual(loadedFirst?.trackID, firstTrack.key.description)
        XCTAssertEqual(loadedFirst?.scenes.first?.lineIndex, 1)
        XCTAssertEqual(loadedSecond?.trackID, secondTrack.key.description)
        XCTAssertEqual(loadedSecond?.scenes.first?.lineIndex, 2)
    }

    func testStoreRejectsPersistedWrongSchemaVersion() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let lines = makeV4FixtureLines(count: 8)
        let score = makeV4FixtureScore(lines: lines)
        let track = Track(
            bvid: "BVV4VERSION",
            cid: 303,
            title: "Version",
            artist: "Fixture",
            coverURL: nil,
            duration: 760)
        let direction = makeV4Direction(
            track: track,
            lines: lines,
            score: score,
            scenes: [makeV4RailRecipe(lineIndex: 1)])
        let writer = LyricStageStoreV4(fileURLForTesting: url)
        let saved = await writer.save(direction, for: track, lines: lines, audioScore: score)
        XCTAssertTrue(saved)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        payload[0]["schemaVersion"] = "obsolete-v4"
        try JSONSerialization.data(withJSONObject: payload).write(to: url, options: .atomic)

        let reader = LyricStageStoreV4(fileURLForTesting: url)
        let loaded = await reader.direction(for: track, lines: lines, audioScore: score)

        XCTAssertNil(loaded)
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lyric-stage-v4-\(UUID().uuidString).json")
    }
}
