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

    func testPlayInfoDecodesAudioMIMETypeAndCodec() throws {
        let data = Data("""
        {
          "dash": {
            "audio": [{
              "id": 30280,
              "base_url": "https://base.example/audio.m4s",
              "backup_url": [],
              "bandwidth": 192000,
              "mime_type": "audio/mp4",
              "codecs": "mp4a.40.2"
            }]
          }
        }
        """.utf8)

        let info = try JSONDecoder().decode(BiliClient.PlayInfo.self, from: data)
        let audio = try XCTUnwrap(info.dash?.audio?.first)

        XCTAssertEqual(audio.mimeType, "audio/mp4")
        XCTAssertEqual(audio.codecs, "mp4a.40.2")
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

    func testFallbackCandidatesPreferDifferentHostOverSameHostSignedVariant() throws {
        let primary = try XCTUnwrap(URL(string: "https://primary.example/audio.m4s?token=1"))
        let sameHost = try XCTUnwrap(URL(string: "https://primary.example/audio.m4s?token=2"))
        let otherHost = try XCTUnwrap(URL(string: "https://backup.example/audio.m4s?token=3"))

        let candidates = AudioCDNSelector.fallbackCandidates(
            from: [primary, sameHost, otherHost],
            excluding: primary)

        XCTAssertEqual(candidates, [otherHost])
    }

    func testRankedCandidatesPreserveUnknownHostOrder() async throws {
        await AudioCDNSelector.resetHostHealthForTesting()
        let primary = try XCTUnwrap(URL(string: "https://base.example/audio.m4a"))
        let backupA = try XCTUnwrap(URL(string: "https://backup-a.example/audio.m4a"))
        let backupB = try XCTUnwrap(URL(string: "https://backup-b.example/audio.m4a"))

        let ranked = await AudioCDNSelector.rankedCandidates([primary, backupA, backupB])

        XCTAssertEqual(ranked, [primary, backupA, backupB])
    }

    func testRankedCandidatesPreferHealthyHostAndPenalizeFailedHost() async throws {
        await AudioCDNSelector.resetHostHealthForTesting()
        let primary = try XCTUnwrap(URL(string: "https://slow.example/audio.m4a"))
        let backup = try XCTUnwrap(URL(string: "https://fast.example/audio.m4a"))

        await AudioCDNSelector.recordProbeFailureForTesting(url: primary)
        await AudioCDNSelector.recordProbeSuccessForTesting(url: backup, milliseconds: 80)

        let ranked = await AudioCDNSelector.rankedCandidates([primary, backup])

        XCTAssertEqual(ranked, [backup, primary])
    }

    func testPreferredURLSelectsMatchingBackupHost() throws {
        AudioCDNSelector.setPreferredHostForTesting("backup.example")
        defer { AudioCDNSelector.setPreferredHostForTesting(nil) }
        let primary = try XCTUnwrap(URL(string: "https://base.example/audio.m4a"))
        let backup = try XCTUnwrap(URL(string: "https://backup.example/audio.m4a"))

        let selected = AudioCDNSelector.preferredURL(from: [primary, backup])

        XCTAssertEqual(selected, backup)
    }

    func testRankedCandidatesPutPreferredHostFirst() async throws {
        await AudioCDNSelector.resetHostHealthForTesting()
        AudioCDNSelector.setPreferredHostForTesting("backup.example")
        defer { AudioCDNSelector.setPreferredHostForTesting(nil) }
        let primary = try XCTUnwrap(URL(string: "https://base.example/audio.m4a"))
        let backup = try XCTUnwrap(URL(string: "https://backup.example/audio.m4a"))

        let ranked = await AudioCDNSelector.rankedCandidates([primary, backup])

        XCTAssertEqual(ranked, [backup, primary])
    }
}
