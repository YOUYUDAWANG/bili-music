import XCTest
@testable import BiliMusic

final class MusicMetadataTests: XCTestCase {
    func testComposedMetadataPrefersNormalizedTitleAndArtist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("music-metadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let fileURL = directory.appendingPathComponent("track-metadata.json")
        let store = TrackMetadataStore(fileURLForTesting: fileURL)
        let dirty = Track(
            bvid: "BVMETA",
            cid: 9,
            title: "【4K】夏夜のマジック / 花譜",
            artist: "搬运UP",
            coverURL: nil,
            duration: 240)
        let normalized = NormalizedTrackMetadata(
            canonicalTitle: "夏夜のマジック",
            originalArtists: ["土岐麻子"],
            coverPerformers: ["花譜"],
            uploader: "搬运UP",
            language: "ja",
            aliases: ["夏夜的魔法"],
            lyricSearchQueries: [
                "夏夜のマジック 土岐麻子",
                "夏夜のマジック",
                "夏夜のマジック 花譜",
            ],
            isCover: true,
            confidence: 0.9,
            needsReview: false,
            serviceVersion: "test")

        let expectation = expectation(description: "metadata saved")
        Task {
            await store.save(normalized, for: dirty)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        let metadata = MusicMetadata.compose(track: dirty, metadataStore: store)
        XCTAssertEqual(metadata.displayTitle, "夏夜のマジック")
        XCTAssertEqual(metadata.displayArtist, "花譜（翻唱） · 原唱：土岐麻子")
        XCTAssertEqual(metadata.applying(to: dirty).title, "夏夜のマジック")
    }

    func testDisplayCoverFallsBackToTrackArtwork() {
        let track = Track(
            bvid: "BVCOVER",
            title: "Song",
            artist: "A",
            coverURL: URL(string: "https://example.com/bili.jpg"),
            duration: 120)
        let metadata = MusicMetadata(
            trackKey: track.key,
            sourceTitle: track.title,
            sourceArtist: track.artist,
            normalized: nil,
            lyricsDocument: nil,
            lyricOffsetMilliseconds: 0,
            albumArtURL: URL(string: "https://example.com/album.jpg"),
            updatedAt: Date())

        XCTAssertEqual(
            MusicDisplayMetadata.coverURL(for: track, metadata: metadata, preferMetadataCover: true),
            URL(string: "https://example.com/album.jpg"))
        XCTAssertEqual(
            MusicDisplayMetadata.coverURL(for: track, metadata: metadata, preferMetadataCover: false),
            track.coverURL)
    }
}
