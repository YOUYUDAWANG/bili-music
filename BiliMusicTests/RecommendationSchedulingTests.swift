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

    func testRecommendationTapMarksPanelStaleWithoutImmediateRefresh() {
        let policy = RecommendationPanelRefreshPolicy.currentTrackChanged(
            suppressImmediateRefresh: true,
            recommendationPanelVisible: true)

        XCTAssertFalse(policy.shouldLoadImmediately)
        XCTAssertTrue(policy.shouldMarkStale)
    }

    func testRecommendationTapSetsSuppressionBeforePlayback() throws {
        let source = try Self.sourceFile("BiliMusic/Features/Player/NowPlayingView.swift")
        let suppressionRange = try XCTUnwrap(source.range(of: "suppressNextRecommendationRefresh = true"))
        let playbackRange = try XCTUnwrap(source.range(of: "Task { await engine.play(tracks: recommendedTracks, startAt: index, queueMode: .radio) }"))

        XCTAssertLessThan(suppressionRange.lowerBound, playbackRange.lowerBound)
    }

    func testVisibleExternalTrackChangeLoadsRecommendationsImmediately() {
        let policy = RecommendationPanelRefreshPolicy.currentTrackChanged(
            suppressImmediateRefresh: false,
            recommendationPanelVisible: true)

        XCTAssertTrue(policy.shouldLoadImmediately)
        XCTAssertFalse(policy.shouldMarkStale)
    }

    func testHiddenTrackChangeMarksRecommendationsStale() {
        let policy = RecommendationPanelRefreshPolicy.currentTrackChanged(
            suppressImmediateRefresh: false,
            recommendationPanelVisible: false)

        XCTAssertFalse(policy.shouldLoadImmediately)
        XCTAssertTrue(policy.shouldMarkStale)
    }

    func testRecommendationDisplayFilterRejectsObviousNonMusic() {
        let gameplay = makeRecommendationTrack(
            typeID: 17,
            bvid: "BVGAME",
            title: "三国杀实况攻略合集",
            artist: "游戏区UP")

        XCTAssertFalse(RecommendationEngine.isDisplayableRecommendation(gameplay, mode: .home))
        XCTAssertFalse(RecommendationEngine.isDisplayableRecommendation(gameplay, mode: .relatedPanel))
        XCTAssertFalse(RecommendationEngine.isDisplayableRecommendation(gameplay, mode: .radio))
    }

    func testRecommendationDisplayFilterAcceptsMusicMV() {
        let mv = makeRecommendationTrack(
            typeID: 193,
            bvid: "BVMUSIC",
            title: "周杰伦《晴天》Official MV",
            artist: "周杰伦")

        XCTAssertTrue(RecommendationEngine.isDisplayableRecommendation(mv, mode: .home))
        XCTAssertTrue(RecommendationEngine.isDisplayableRecommendation(mv, mode: .relatedPanel))
        XCTAssertTrue(RecommendationEngine.isDisplayableRecommendation(mv, mode: .radio))
    }

    func testHomeAndNowPlayingRecommendationStateStaySeparate() throws {
        let home = try Self.sourceFile("BiliMusic/Features/Home/HomeView.swift")
        let nowPlaying = try Self.sourceFile("BiliMusic/Features/Player/NowPlayingView.swift")

        XCTAssertTrue(home.contains("@State private var tracks: [Track] = []"))
        XCTAssertTrue(nowPlaying.contains("@State private var recommendedTracks: [Track] = []"))
        XCTAssertTrue(nowPlaying.contains("RecommendationPanelRefreshPolicy.currentTrackChanged"))
        XCTAssertFalse(home.contains("recommendedTracks"))
    }

    private static func sourceFile(_ relativePath: String) throws -> String {
        let testURL = URL(fileURLWithPath: #filePath)
        let rootURL = testURL.deletingLastPathComponent().deletingLastPathComponent()
        let url = rootURL.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private func makeRecommendationTrack(
    typeID: Int? = 3,
    bvid: String,
    title: String,
    artist: String,
    duration: Int = 269
) -> Track {
    Track(typeID: typeID, bvid: bvid, title: title, artist: artist, coverURL: nil, duration: duration)
}
