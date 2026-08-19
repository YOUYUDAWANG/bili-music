import XCTest
@testable import BiliMusic

final class RecommendationMemoryTests: XCTestCase {
    func testRecentBVIDsExpireAfterTTL() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recommendation-memory-\(UUID().uuidString).json")
        let memory = RecommendationMemory(fileURLForTesting: url)
        let now = Date()

        await memory.record(["BVOLD"], at: now.addingTimeInterval(-RecommendationMemory.ttl - 60))
        await memory.record(["BVNEW"], at: now)

        let recent = await memory.recentBVIDs(now: now)
        XCTAssertFalse(recent.contains("BVOLD"))
        XCTAssertTrue(recent.contains("BVNEW"))
    }

    func testFeedIndexAdvancesAndPersists() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recommendation-memory-\(UUID().uuidString).json")
        let memory = RecommendationMemory(fileURLForTesting: url)

        let first = await memory.nextFeedIndices(count: 2)
        await memory.flush()

        let reloaded = RecommendationMemory(fileURLForTesting: url)
        let second = await reloaded.nextFeedIndices(count: 1)

        XCTAssertEqual(first, [1, 2])
        XCTAssertEqual(second, [3])
    }
}
