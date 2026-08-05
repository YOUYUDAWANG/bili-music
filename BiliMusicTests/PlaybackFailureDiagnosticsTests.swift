import Foundation
import XCTest
@testable import BiliMusic

final class PlaybackFailureDiagnosticsTests: XCTestCase {
    func testFailureSnapshotKeepsErrorCodesAndRedactsURLBearingMessage() {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotOpenFile)
        let error = NSError(
            domain: "AVFoundationErrorDomain",
            code: -11828,
            userInfo: [
                NSLocalizedDescriptionKey: "Cannot open https://cdn.example/audio.m4s?token=secret",
                NSUnderlyingErrorKey: underlying
            ])
        let snapshot = PlaybackFailureSnapshot(
            trigger: .itemStatus,
            bvid: "BVDIAGFAIL",
            cid: 1001,
            sourceKind: .preparedRemote,
            host: "cdn.example",
            candidateCount: 3,
            error: error,
            mediaErrors: [
                PlaybackMediaErrorSnapshot(
                    domain: "CoreMediaErrorDomain",
                    code: -12938,
                    host: "backup.example")
            ])

        XCTAssertEqual(snapshot.errorDomain, "AVFoundationErrorDomain")
        XCTAssertEqual(snapshot.errorCode, -11828)
        XCTAssertEqual(snapshot.underlyingDomain, NSURLErrorDomain)
        XCTAssertEqual(snapshot.underlyingCode, NSURLErrorCannotOpenFile)
        XCTAssertEqual(snapshot.errorMessage, "<redacted-url>")
        XCTAssertTrue(snapshot.description.contains("host=cdn.example"))
        XCTAssertTrue(snapshot.description.contains("mediaHost=backup.example"))
        XCTAssertFalse(snapshot.description.contains("https://"))
        XCTAssertFalse(snapshot.description.contains("token=secret"))
    }

    func testCDNProbeSnapshotNeverContainsSignedURL() {
        let snapshot = PlaybackCDNProbeSnapshot(
            host: "upos.example",
            statusCode: 206,
            mimeType: "audio/mp4",
            receivedByte: true,
            milliseconds: 82.4,
            errorDomain: nil,
            errorCode: nil)

        XCTAssertEqual(
            snapshot.description,
            "host=upos.example status=206 mime=audio/mp4 receivedByte=true elapsedMs=82.4 errorDomain=nil errorCode=nil")
        XCTAssertFalse(snapshot.description.contains("?"))
        XCTAssertFalse(snapshot.description.contains("https://"))
    }
}
