import XCTest
@testable import BiliMusic

final class RecommendationSchedulingTests: XCTestCase {
    func testHomeRecommendationPolicyIsExplicitBoundedAndLowerPriority() {
        let policy = RecommendationSchedulingPolicy.home(trigger: .initialHomeLoad)

        XCTAssertEqual(policy.trigger, .initialHomeLoad)
        XCTAssertEqual(policy.favoriteSeedLimit, 5)
        XCTAssertEqual(policy.relatedPerFavoriteSeedLimit, 10)
        XCTAssertEqual(policy.historySeedLimit, 2)
        XCTAssertEqual(policy.cachedSeedLimit, 2)
        XCTAssertEqual(policy.fallbackKeywordLimit, 1)
        XCTAssertEqual(policy.scoringPriority, .utility)
    }

    func testDirectPlaybackDoesNotReferenceHomeRecommendationRefresh() throws {
        let source = try Self.sourceFile("BiliMusic/Player/PlayerEngine.swift")

        XCTAssertFalse(source.contains("mode: .home"))
        XCTAssertFalse(source.contains("initialHomeLoad"))
        XCTAssertFalse(source.contains("manualRefresh"))
    }

    func testRadioRecommendationPolicyKeepsInteractivePriority() {
        let policy = RecommendationSchedulingPolicy.default(for: .radio)

        XCTAssertEqual(policy.scoringPriority, .userInitiated)
        XCTAssertNil(policy.trigger)
    }

    private static func sourceFile(_ relativePath: String) throws -> String {
        let testURL = URL(fileURLWithPath: #filePath)
        let rootURL = testURL.deletingLastPathComponent().deletingLastPathComponent()
        let url = rootURL.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
