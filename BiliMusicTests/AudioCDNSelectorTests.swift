import XCTest
@testable import BiliMusic

final class AudioCDNSelectorTests: XCTestCase {
    func testPlayInfoDecodesCamelCaseBackupURLs() throws {
        let data = Data("""
        {
          "dash": {
            "audio": [
              {
                "id": 30280,
                "baseUrl": "https://base.example/audio.m4a",
                "backupUrl": [
                  "https://backup-a.example/audio.m4a",
                  "https://backup-b.example/audio.m4a"
                ],
                "bandwidth": 192000
              }
            ]
          }
        }
        """.utf8)

        let info = try JSONDecoder().decode(BiliClient.PlayInfo.self, from: data)
        let audio = try XCTUnwrap(info.dash?.audio?.first)

        XCTAssertEqual(audio.baseUrl, "https://base.example/audio.m4a")
        XCTAssertEqual(audio.backupUrl, [
            "https://backup-a.example/audio.m4a",
            "https://backup-b.example/audio.m4a",
        ])
    }

    func testPlayInfoDecodesSnakeCaseBackupURLs() throws {
        let data = Data("""
        {
          "dash": {
            "audio": [
              {
                "id": 30232,
                "base_url": "https://base.example/audio.m4a",
                "backup_url": [
                  "https://backup.example/audio.m4a"
                ],
                "bandwidth": 132000
              }
            ]
          }
        }
        """.utf8)

        let info = try JSONDecoder().decode(BiliClient.PlayInfo.self, from: data)
        let audio = try XCTUnwrap(info.dash?.audio?.first)

        XCTAssertEqual(audio.baseUrl, "https://base.example/audio.m4a")
        XCTAssertEqual(audio.backupUrl, ["https://backup.example/audio.m4a"])
    }

    func testPreparedAudioStreamDedupesPrimaryAndBackupCandidates() throws {
        let primary = try XCTUnwrap(URL(string: "https://base.example/audio.m4a"))
        let backup = try XCTUnwrap(URL(string: "https://backup.example/audio.m4a"))

        let stream = StreamResolver.PreparedAudioStream(
            url: primary,
            candidateURLs: [primary, backup, backup],
            cid: 1001,
            duration: 211,
            quality: 30280,
            bandwidth: 192_000,
            fetchedAt: Date())

        XCTAssertEqual(stream.candidateURLs, [primary, backup])
    }

    func testFallbackCandidatesExcludeCurrentURL() throws {
        let primary = try XCTUnwrap(URL(string: "https://base.example/audio.m4a"))
        let backupA = try XCTUnwrap(URL(string: "https://backup-a.example/audio.m4a"))
        let backupB = try XCTUnwrap(URL(string: "https://backup-b.example/audio.m4a"))

        let candidates = AudioCDNSelector.fallbackCandidates(
            from: [primary, backupA, backupB, backupA],
            excluding: primary)

        XCTAssertEqual(candidates, [backupA, backupB])
    }
}
