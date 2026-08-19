import XCTest
@testable import BiliMusic

final class ListeningTasteTests: XCTestCase {
    func testPrefersNormalizedOriginalArtistOverUploader() {
        let track = Track(
            bvid: "BVTASTE1",
            title: "【高音质】夜に駆ける / YOASOBI",
            artist: "某搬运UP",
            coverURL: nil,
            duration: 260)
        let metadata = NormalizedTrackMetadata.manual(
            canonicalTitle: "夜に駆ける",
            originalArtists: ["YOASOBI"],
            coverPerformers: [],
            uploader: "某搬运UP",
            isCover: false,
            serviceVersion: "test")

        let taste = ListeningTaste.build(
            liked: [track],
            library: [],
            history: [],
            metadataFor: { _ in metadata })

        XCTAssertEqual(taste.artists.map(\.name), ["YOASOBI"])
        XCTAssertEqual(taste.titles.map(\.name), ["夜に駆ける"])
        XCTAssertEqual(taste.seedTracks.map(\.bvid), ["BVTASTE1"])
    }

    func testIgnoresUploaderWhenTitleHasNoSongStructure() {
        let track = Track(
            bvid: "BVUPONLY",
            title: "今天随便剪的东西",
            artist: "HikariChannel",
            coverURL: nil,
            duration: 200)

        XCTAssertTrue(ListeningTaste.artists(in: track, metadata: nil).isEmpty)
    }

    func testLikedOutweighsOneOffHistory() {
        let favorite = Track(bvid: "BVLIKE", title: "米津玄师《Lemon》", artist: "米津玄师", coverURL: nil, duration: 255)
        let once = Track(bvid: "BVONCE", title: "周杰伦《晴天》", artist: "周杰伦", coverURL: nil, duration: 269)
        let metadata: [String: NormalizedTrackMetadata] = [
            "BVLIKE": .manual(
                canonicalTitle: "Lemon",
                originalArtists: ["米津玄师"],
                coverPerformers: [],
                uploader: nil,
                isCover: false,
                serviceVersion: "test"),
            "BVONCE": .manual(
                canonicalTitle: "晴天",
                originalArtists: ["周杰伦"],
                coverPerformers: [],
                uploader: nil,
                isCover: false,
                serviceVersion: "test"),
        ]

        let taste = ListeningTaste.build(
            liked: [favorite],
            library: [],
            history: [(once, 1)],
            metadataFor: { metadata[$0.bvid] })

        XCTAssertEqual(taste.artists.first?.name, "米津玄师")
        XCTAssertGreaterThan(taste.artists[0].weight, taste.artists[1].weight)
    }

    func testRejectsGenericUploaderNames() {
        let track = Track(
            bvid: "BVJUNK",
            title: "随机高音质歌曲合集",
            artist: "高音质搬运",
            coverURL: nil,
            duration: 200)

        XCTAssertTrue(ListeningTaste.artists(in: track, metadata: nil).isEmpty)
        XCTAssertFalse(ListeningTaste.isUsableArtist("官方高音质"))
        XCTAssertFalse(ListeningTaste.isUsableArtist("BV1234567890"))
        XCTAssertTrue(ListeningTaste.isUsableArtist("Ado"))
    }

    func testParsesHighConfidenceTitleWhenMetadataIsMissing() {
        let track = Track(
            bvid: "BVPARSE",
            title: "Ado - 唱",
            artist: "剪辑频道123",
            coverURL: nil,
            duration: 193)

        XCTAssertEqual(ListeningTaste.artists(in: track, metadata: nil), ["Ado"])
    }

    func testMatchesLooksAtTitleAndArtistTogether() {
        let taste = ListeningTaste(
            artists: [ListeningTaste.Artist(name: "YOASOBI", weight: 12)],
            seedTracks: [])
        XCTAssertTrue(taste.matches(title: "夜に駆ける", artist: "YOASOBI"))
        XCTAssertTrue(taste.matches(title: "YOASOBI / 群青", artist: "搬运UP"))
        XCTAssertFalse(taste.matches(title: "晴天", artist: "周杰伦"))
    }

    func testSearchPlanSpreadsArtistsAndTitlesAcrossPages() {
        let artists = [
            ListeningTaste.Artist(name: "YOASOBI", weight: 12),
            ListeningTaste.Artist(name: "Ado", weight: 9),
        ]
        let titles = [
            ListeningTaste.Artist(name: "夜に駆ける", weight: 12),
            ListeningTaste.Artist(name: "唱", weight: 8),
        ]
        let plan = ListeningTaste.searchPlan(
            artists: artists,
            titles: titles,
            artistLimit: 2,
            titleLimit: 2,
            page: 1)

        XCTAssertEqual(Set(plan.map(\.keyword)), ["YOASOBI", "Ado", "夜に駆ける", "唱"])
        XCTAssertEqual(Set(plan.map(\.page)), [1, 2])
        XCTAssertTrue(plan.allSatisfy { (1...3).contains($0.page) })
    }

    func testMatchesSongTitleFromLibrary() {
        let taste = ListeningTaste(
            artists: [],
            titles: [ListeningTaste.Artist(name: "夜に駆ける", weight: 10)],
            seedTracks: [])
        XCTAssertTrue(taste.matches(title: "夜に駆ける piano ver.", artist: "未知UP"))
        XCTAssertFalse(taste.matches(title: "晴天", artist: "周杰伦"))
    }

    func testPickSearchNamesStaysWithinTopArtists() {
        let artists = (1...6).map { ListeningTaste.Artist(name: "歌手\($0)", weight: 10 - $0) }
        let picked = ListeningTaste.pickSearchNames(from: artists, limit: 3)
        XCTAssertEqual(picked.count, 3)
        XCTAssertTrue(Set(picked).isSubset(of: Set(artists.map(\.name))))
    }
}
