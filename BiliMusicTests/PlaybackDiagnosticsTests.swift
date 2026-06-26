import XCTest
@testable import BiliMusic

final class PlaybackDiagnosticsTests: XCTestCase {
    func testRecordsTapToFirstPlayingCheckpointsInOrder() {
        let sink = PlaybackDiagnostics.InMemorySink()
        var ticks: [TimeInterval] = [100, 100.012, 100.034, 100.055, 100.069, 100.091, 100.107]
        let diagnostics = PlaybackDiagnostics(sink: sink) {
            ticks.removeFirst()
        }
        let track = Self.track()

        diagnostics.begin(track: track)
        diagnostics.record(.tap, track: track)
        diagnostics.record(.currentAssigned, track: track)
        diagnostics.record(.sourceResolved, track: track, sourceKind: .freshRemote, quality: 30280, bandwidth: 192_000)
        diagnostics.record(.playerItemCreated, track: track, sourceKind: .freshRemote, quality: 30280, bandwidth: 192_000)
        diagnostics.record(.playRequested, track: track, sourceKind: .freshRemote, quality: 30280, bandwidth: 192_000)
        diagnostics.record(.firstPlaying, track: track, sourceKind: .freshRemote, quality: 30280, bandwidth: 192_000)

        XCTAssertEqual(sink.events.map(\.checkpoint), [
            .tap,
            .currentAssigned,
            .sourceResolved,
            .playerItemCreated,
            .playRequested,
            .firstPlaying
        ])
        XCTAssertEqual(sink.events.last?.bvid, "BVDIAG001")
        XCTAssertEqual(sink.events.last?.cid, 1001)
        XCTAssertEqual(sink.events.last?.sourceKind, .freshRemote)
        XCTAssertEqual(sink.events.last?.qualityLabel, "30280")
        XCTAssertEqual(sink.events.last?.bandwidth, 192_000)
        XCTAssertGreaterThan(sink.events.last?.elapsedMilliseconds ?? 0, 0)
    }

    func testDiagnosticPayloadsAreSanitized() throws {
        let sink = PlaybackDiagnostics.InMemorySink()
        let diagnostics = PlaybackDiagnostics(sink: sink) { 42 }
        let track = Self.track()

        diagnostics.begin(track: track)
        diagnostics.record(.sourceResolved, track: track, sourceKind: .preparedRemote, quality: 30280, bandwidth: 192_000)

        let event = try XCTUnwrap(sink.events.first)
        let rendered = event.description

        XCTAssertEqual(event.bvid, "BVDIAG001")
        XCTAssertEqual(event.cid, 1001)
        XCTAssertEqual(event.sourceKind, .preparedRemote)
        XCTAssertFalse(rendered.contains("https://"))
        XCTAssertFalse(rendered.localizedCaseInsensitiveContains("cookie"))
        XCTAssertFalse(rendered.localizedCaseInsensitiveContains("sessdata"))
        XCTAssertFalse(rendered.contains("AVURLAssetHTTPHeaderFieldsKey"))
        XCTAssertFalse(rendered.contains("mcdn.bilivideo.cn"))
    }

#if DEBUG
    func testDefaultDebugDiagnosticsMirrorRecentEventsForRealDeviceUAT() throws {
        PlaybackDiagnostics.DebugRecentEventStore.shared.clear()
        var ticks: [TimeInterval] = [200, 200.01, 200.04, 200.08]
        let diagnostics = PlaybackDiagnostics {
            ticks.removeFirst()
        }
        let track = Self.track()

        diagnostics.begin(track: track)
        diagnostics.record(.tap, track: track)
        diagnostics.record(.playRequested, track: track, sourceKind: .freshRemote, quality: 30280, bandwidth: 192_000)
        diagnostics.record(.firstPlaying, track: track, sourceKind: .freshRemote, quality: 30280, bandwidth: 192_000)

        let events = PlaybackDiagnostics.DebugRecentEventStore.shared.snapshot()

        XCTAssertEqual(events.map(\.checkpoint), [.tap, .playRequested, .firstPlaying])
        XCTAssertEqual(events.last?.bvid, "BVDIAG001")
        XCTAssertEqual(events.last?.sourceKind, .freshRemote)
        XCTAssertEqual(events.last?.bandwidth, 192_000)
        XCTAssertFalse(try XCTUnwrap(events.last).description.contains("https://"))
    }

    func testDebugRecentEventStoreKeepsOnlyNewestEvents() {
        let store = PlaybackDiagnostics.DebugRecentEventStore(capacity: 3)
        let track = Self.track()
        let diagnostics = PlaybackDiagnostics(sink: store) { 300 }

        diagnostics.begin(track: track)
        diagnostics.record(.tap, track: track)
        diagnostics.record(.currentAssigned, track: track)
        diagnostics.record(.sourceResolved, track: track, sourceKind: .freshRemote)
        diagnostics.record(.playRequested, track: track, sourceKind: .freshRemote)

        XCTAssertEqual(store.snapshot().map(\.checkpoint), [.currentAssigned, .sourceResolved, .playRequested])
    }
#endif

    private static func track() -> Track {
        Track(
            typeID: 3,
            bvid: "BVDIAG001",
            cid: 1001,
            title: "Fixture Song",
            artist: "Fixture Artist",
            coverURL: nil,
            duration: 211)
    }
}
