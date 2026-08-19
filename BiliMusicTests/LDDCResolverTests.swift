import XCTest
@testable import BiliMusic

final class LDDCResolverTests: XCTestCase {
    @MainActor
    func testBackendWordHitWinsWithoutCallingDirectCatalog() async throws {
        let store = try makeStore(prefix: "LDDCResolverWord")
        let catalog = LDDCCountingCatalog()
        let backend = LDDCFakeBackend(mode: .exactCover)
        let resolver = LyricsResolver(catalog: catalog, lddcProvider: backend)

        let result = await resolver.resolve(
            track: track(),
            metadata: metadata(),
            store: store,
            ignoreCache: true)

        XCTAssertEqual(result.session.document?.result.id, "lddc-cover")
        XCTAssertEqual(result.session.document?.timingKind, .word)
        XCTAssertEqual(result.session.document?.versionScope, .exactCover)
        let directSearchCount = await catalog.searchCount()
        XCTAssertEqual(directSearchCount, 0)
        XCTAssertEqual(result.networkRequests, 1)
    }

    @MainActor
    func testOriginalBackendWordOnCoverUsesCanonicalSafetyPolicy() async throws {
        let store = try makeStore(prefix: "LDDCResolverOriginal")
        let backend = LDDCFakeBackend(mode: .farOriginal)
        let resolver = LyricsResolver(catalog: LDDCCountingCatalog(), lddcProvider: backend)

        let result = await resolver.resolve(
            track: track(),
            metadata: metadata(),
            store: store,
            ignoreCache: true)

        XCTAssertEqual(result.session.document?.result.id, "lddc-original")
        XCTAssertEqual(result.session.document?.versionScope, .canonicalOriginal)
        XCTAssertEqual(result.session.document?.timingKind, LyricsTimingKind.none)
        XCTAssertEqual(result.session.document?.followsPlayback, false)
        XCTAssertEqual(result.session.document?.timingNeedsConfirmation, true)
    }

    @MainActor
    func testRejectedBackendWordDoesNotSuppressDirectFallback() async throws {
        let store = try makeStore(prefix: "LDDCResolverRejected")
        let catalog = LDDCCountingCatalog()
        let resolver = LyricsResolver(
            catalog: catalog,
            lddcProvider: LDDCFakeBackend(mode: .wrongCover))

        _ = await resolver.resolve(
            track: track(),
            metadata: metadata(),
            store: store,
            ignoreCache: true,
            scope: .coverVersion)

        let directSearchCount = await catalog.searchCount()
        XCTAssertGreaterThan(directSearchCount, 0)
    }

    @MainActor
    private func makeStore(prefix: String) throws -> LyricsStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return LyricsStore(fileURLForTesting: directory.appendingPathComponent("lyrics.json"))
    }

    private func track() -> Track {
        Track(
            bvid: "BV1lddcresolver",
            cid: 123,
            title: "【花譜】日文翻唱《パレード》",
            artist: "花譜",
            coverURL: nil,
            duration: 240)
    }

    private func metadata() -> NormalizedTrackMetadata {
        NormalizedTrackMetadata(
            canonicalTitle: "パレード",
            originalArtists: ["ヨルシカ"],
            coverPerformers: ["花譜"],
            uploader: "花譜",
            language: "ja",
            aliases: [],
            lyricSearchQueries: ["パレード 花譜", "パレード ヨルシカ"],
            isCover: true,
            confidence: 0.98,
            needsReview: false,
            serviceVersion: "test")
    }
}

private actor LDDCCountingCatalog: LyricsCatalogSearching {
    private var searches = 0

    func search(keyword: String, provider: LyricsProvider) async throws -> [LyricsSearchResult] {
        searches += 1
        return []
    }

    func fetchLyrics(for result: LyricsSearchResult) async throws -> LyricsDocument {
        throw MetingLyricsClient.ClientError.noLyrics
    }

    func searchCount() -> Int { searches }
}

private actor LDDCFakeBackend: LDDCLyricsBackendSearching {
    enum Mode { case exactCover, farOriginal, wrongCover }
    let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    func lookup(
        track: Track,
        metadata: NormalizedTrackMetadata?,
        preferCover: Bool
    ) async throws -> [LyricsExternalHit] {
        switch mode {
        case .exactCover:
            return preferCover ? [hit(id: "lddc-cover", artist: "花譜", duration: 240)] : []
        case .farOriginal:
            return preferCover ? [] : [hit(id: "lddc-original", artist: "ヨルシカ", duration: 300)]
        case .wrongCover:
            return preferCover
                ? [hit(id: "lddc-wrong", title: "Overdose", artist: "花譜", duration: 240)]
                : []
        }
    }

    private func hit(
        id: String,
        title: String = "パレード",
        artist: String,
        duration: Int
    ) -> LyricsExternalHit {
        let result = LyricsSearchResult(
            provider: .kugou,
            id: id,
            title: title,
            artist: artist,
            album: nil,
            duration: duration,
            artworkID: nil)
        let document = LyricsDocument(
            result: result,
            lyric: "[00:01.00]身体",
            translatedLyric: nil,
            romanizedLyric: nil,
            karaokeLyric: "[1000,1000]<0,500,0>身<500,500,0>体",
            karaokeTranslatedLyric: nil)
        return LyricsExternalHit(result: result, document: document)
    }
}
