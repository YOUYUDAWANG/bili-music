import Foundation
import XCTest
@testable import BiliMusic

final class AudioPerformanceMapV2Tests: XCTestCase {
    func testMapValidationSamplingFingerprintAndSummaryAreDeterministic() throws {
        let map = fixtureMap(fingerprint: "audio-a")

        let safe = try XCTUnwrap(map.validated(expectedAudioFingerprint: "audio-a", expectedDuration: 2))
        XCTAssertEqual(
            try XCTUnwrap(safe.envelope(.energy, at: 1)),
            128.0 / 255.0,
            accuracy: 0.001)
        XCTAssertEqual(
            try XCTUnwrap(safe.nearestOnset(to: 1.02, tolerance: 0.05)).time,
            1,
            accuracy: 0.001)
        XCTAssertEqual(safe.fingerprint, map.fingerprint)

        let lines = [
            PlayerEngine.LyricLine(from: 0, to: 1, text: "first"),
            PlayerEngine.LyricLine(from: 1, to: 2, text: "second"),
        ]
        let first = safe.summary(for: lines)
        let second = safe.summary(for: lines)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.version, AudioPerformanceMapV2Version.stageSummary)
        XCTAssertEqual(first.mapFingerprint, safe.fingerprint)
        XCTAssertEqual(try XCTUnwrap(first.bpm), 120, accuracy: 0.001)
        XCTAssertEqual(first.lines.count, 2)
        XCTAssertEqual(first.sections.count, 1)
        XCTAssertEqual(first.lines[0].onsetStrength, 0.7, accuracy: 0.001)
        XCTAssertEqual(first.lines[1].onsetStrength, 0.9, accuracy: 0.001)
        XCTAssertGreaterThan(first.lines[0].longToneRatio, 0)
        XCTAssertFalse(first.summaryHash.isEmpty)

        let emptyA = LyricStageAudioSummaryV3.empty(duration: 2)
        let emptyB = LyricStageAudioSummaryV3.empty(duration: 2)
        XCTAssertEqual(emptyA, emptyB)
        XCTAssertNil(emptyA.bpm)
        XCTAssertFalse(emptyA.summaryHash.isEmpty)
    }

    func testMapRejectsMismatchedFingerprintAndNonMonotonicFacts() {
        let map = fixtureMap(fingerprint: "audio-a")
        XCTAssertNil(map.validated(expectedAudioFingerprint: "audio-b"))
        XCTAssertNil(map.validated(expectedAnalysisVersion: "older-analysis"))

        let staleAnalyzer = AudioPerformanceMapV2(
            version: map.version,
            analysisVersion: "older-analysis",
            audioFingerprint: map.audioFingerprint,
            duration: map.duration,
            tempoSegments: map.tempoSegments,
            beats: map.beats,
            downbeats: map.downbeats,
            onsets: map.onsets,
            envelopes: map.envelopes,
            regions: map.regions,
            confidence: map.confidence)
        XCTAssertNil(staleAnalyzer.validated())

        let invalid = AudioPerformanceMapV2(
            version: map.version,
            analysisVersion: map.analysisVersion,
            audioFingerprint: map.audioFingerprint,
            duration: map.duration,
            tempoSegments: map.tempoSegments,
            beats: [0.5, 0.4],
            downbeats: map.downbeats,
            onsets: map.onsets,
            envelopes: map.envelopes,
            regions: map.regions,
            confidence: map.confidence)
        XCTAssertNil(invalid.validated())
    }

    func testLocalAnalyzerProducesVersionedCompactFactsFromSyntheticAudio() throws {
        let sampleRate = 8_000.0
        let duration = 8.0
        var samples = [Float](repeating: 0, count: Int(sampleRate * duration))
        for index in samples.indices {
            let time = Double(index) / sampleRate
            let envelope = time < 2 ? 0.12 : (time < 6 ? 0.32 : 0.08)
            samples[index] = Float(sin(time * 2 * .pi * 220) * envelope)
        }
        for beat in stride(from: 0.25, to: duration, by: 0.5) {
            let start = Int(beat * sampleRate)
            for offset in 0..<min(90, samples.count - start) {
                samples[start + offset] += Float(0.8 * exp(-Double(offset) / 18))
            }
        }

        let map = try LocalAudioPerformanceAnalyzer.analyze(
            samples: samples,
            sampleRate: sampleRate,
            audioFingerprint: "synthetic")

        XCTAssertEqual(map.version, AudioPerformanceMapV2Version.current)
        XCTAssertEqual(map.analysisVersion, AudioPerformanceMapV2Version.analyzer)
        XCTAssertNotNil(map.validated(expectedAudioFingerprint: "synthetic", expectedDuration: duration))
        XCTAssertGreaterThan(map.beats.count, 4)
        XCTAssertFalse(map.tempoSegments.isEmpty)
        XCTAssertFalse(map.onsets.isEmpty)
        XCTAssertEqual(Set(map.envelopes.map(\.kind)), Set(AudioPerformanceEnvelopeKind.allCases))
        XCTAssertEqual(try XCTUnwrap(map.regions.first(where: { $0.kind == .acousticSection })).from, 0)
        XCTAssertEqual(
            try XCTUnwrap(map.regions.last(where: { $0.kind == .acousticSection })).to,
            duration,
            accuracy: 0.001)
    }

    func testNativePCMDecoderFallbackResamplesWithoutChangingDuration() throws {
        let sourceRate = 44_100.0
        let destinationRate = 22_050.0
        let source = (0..<44_100).map { index in
            Float(sin(Double(index) / sourceRate * 2 * .pi * 440))
        }

        let resampled = try LocalAudioPerformanceAnalyzer.resampleMono(
            source,
            from: sourceRate,
            to: destinationRate)

        XCTAssertEqual(resampled.count, 22_050)
        XCTAssertEqual(
            Double(resampled.count) / destinationRate,
            Double(source.count) / sourceRate,
            accuracy: 1 / destinationRate)
        XCTAssertEqual(resampled[100], source[200], accuracy: 0.000_1)
    }

    func testStorePersistsExactFingerprintAndKeepsLatestCompactMap() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-map-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("maps.json")
        let key = TrackKey(bvid: "BV-store", cid: 7)
        let writer = AudioPerformanceMapStore(fileURLForTesting: fileURL)
        try await writer.save(fixtureMap(fingerprint: "audio-a"), for: key)

        let reader = AudioPerformanceMapStore(fileURLForTesting: fileURL)
        let exact = await reader.map(for: key, audioFingerprint: "audio-a")
        let mismatch = await reader.map(for: key, audioFingerprint: "audio-b")
        let latest = await reader.latestMap(for: key)
        XCTAssertNotNil(exact)
        XCTAssertNil(mismatch)
        XCTAssertEqual(latest?.audioFingerprint, "audio-a")
    }

    func testStoreFuzzyLookupNeverConfusesResolvedParts() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-map-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AudioPerformanceMapStore(
            fileURLForTesting: directory.appendingPathComponent("maps.json"))
        let first = TrackKey(bvid: "BV-parts", cid: 1)
        let second = TrackKey(bvid: "BV-parts", cid: 2)
        let unresolved = TrackKey(bvid: "BV-parts", cid: nil)

        try await store.save(fixtureMap(fingerprint: "part-1"), for: first)
        try await store.save(fixtureMap(fingerprint: "part-2"), for: second)
        try await store.save(fixtureMap(fingerprint: "unresolved"), for: unresolved)
        let ambiguous = await store.latestMap(for: unresolved)
        let unresolvedFallback = await store.latestMap(for: TrackKey(bvid: "BV-parts", cid: 3))
        let resolvedFirst = await store.latestMap(for: first)
        let resolvedSecond = await store.latestMap(for: second)
        XCTAssertNil(ambiguous)
        XCTAssertEqual(unresolvedFallback?.audioFingerprint, "unresolved")
        XCTAssertEqual(resolvedFirst?.audioFingerprint, "part-1")
        XCTAssertEqual(resolvedSecond?.audioFingerprint, "part-2")

        try await store.remove(for: unresolved)
        try await store.remove(for: first)
        let retainedSecond = await store.latestMap(for: second)
        let uniqueUnresolved = await store.latestMap(for: unresolved)
        let uniqueWrongResolved = await store.latestMap(for: TrackKey(bvid: "BV-parts", cid: 3))
        XCTAssertEqual(retainedSecond?.audioFingerprint, "part-2")
        XCTAssertEqual(uniqueUnresolved?.audioFingerprint, "part-2")
        XCTAssertNil(uniqueWrongResolved)
    }

    func testStoreResolvedKeyCanEnrichButNotMisreadAnUnresolvedEntry() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-map-enrichment-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AudioPerformanceMapStore(
            fileURLForTesting: directory.appendingPathComponent("maps.json"))
        let unresolved = TrackKey(bvid: "BV-enrich", cid: nil)
        let resolved = TrackKey(bvid: "BV-enrich", cid: 9)

        try await store.save(fixtureMap(fingerprint: "unresolved"), for: unresolved)
        let fallback = await store.latestMap(for: resolved)
        XCTAssertEqual(fallback?.audioFingerprint, "unresolved")
        try await store.save(fixtureMap(fingerprint: "resolved"), for: resolved)
        let enriched = await store.latestMap(for: unresolved)
        XCTAssertEqual(enriched?.audioFingerprint, "resolved")
    }

    @MainActor
    func testServiceNeverAnalyzesWithoutLocalCacheAndDoesNotReuseLatestForReplacementAudio() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-map-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AudioPerformanceMapStore(fileURLForTesting: directory.appendingPathComponent("maps.json"))
        let track = Track(
            bvid: "BV-service",
            cid: 9,
            title: "fixture",
            artist: "artist",
            coverURL: nil,
            duration: 2)
        try await store.save(fixtureMap(fingerprint: "old-audio"), for: track.key)

        let evictedService = AudioPerformanceAnalysisService(
            store: store,
            analyzer: StubAnalyzer(),
            localAudioURLProvider: { _ in nil })
        let evictedMap = try await evictedService.cachedMap(for: track)
        XCTAssertEqual(evictedMap?.audioFingerprint, "old-audio")
        do {
            _ = try await evictedService.analyzeCachedAudio(for: track)
            XCTFail("Analysis must require a real CacheStore local file URL")
        } catch let error as AudioPerformanceAnalysisError {
            guard case .localAudioUnavailable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let replacementURL = directory.appendingPathComponent("replacement.m4a")
        try Data("replacement-recording".utf8).write(to: replacementURL)
        let replacementService = AudioPerformanceAnalysisService(
            store: store,
            analyzer: StubAnalyzer(),
            localAudioURLProvider: { _ in replacementURL })
        let replacementMap = try await replacementService.cachedMap(for: track)
        XCTAssertNil(replacementMap)
    }

    @MainActor
    func testServiceDoesNotCoalesceDifferentAudioFingerprintsForOneTrack() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-map-inflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("first.m4a")
        let secondURL = directory.appendingPathComponent("second.m4a")
        try Data("first-recording".utf8).write(to: firstURL)
        try Data("second-recording".utf8).write(to: secondURL)
        let firstFingerprint = try AudioPerformanceFingerprint.audioFile(at: firstURL)
        let secondFingerprint = try AudioPerformanceFingerprint.audioFile(at: secondURL)
        let analyzer = DelayedMapAnalyzer(maps: [
            firstFingerprint: fixtureMap(fingerprint: firstFingerprint),
            secondFingerprint: fixtureMap(fingerprint: secondFingerprint),
        ])
        let selected = SelectedAudioURL(firstURL)
        let service = AudioPerformanceAnalysisService(
            store: AudioPerformanceMapStore(
                fileURLForTesting: directory.appendingPathComponent("maps.json")),
            analyzer: analyzer,
            localAudioURLProvider: { _ in selected.url })
        let track = Track(
            bvid: "BV-inflight",
            cid: 11,
            title: "fixture",
            artist: "artist",
            coverURL: nil,
            duration: 2)

        let firstRequest = Task { try await service.analyzeCachedAudio(for: track) }
        while await analyzer.requestCount == 0 { await Task.yield() }
        selected.url = secondURL
        let secondRequest = Task { try await service.analyzeCachedAudio(for: track) }
        let firstMap = try await firstRequest.value
        let secondMap = try await secondRequest.value
        let analyzerRequestCount = await analyzer.requestCount

        XCTAssertEqual(Set([firstMap.audioFingerprint, secondMap.audioFingerprint]),
                       Set([firstFingerprint, secondFingerprint]))
        XCTAssertEqual(analyzerRequestCount, 2)
    }

    private func fixtureMap(fingerprint: String) -> AudioPerformanceMapV2 {
        let confidence = AudioPerformanceConfidence(
            beat: 0.8,
            downbeat: 0.6,
            onset: 0.7,
            energy: 1,
            pitch: 0.5,
            regions: 0.8,
            overall: 0.73)
        let envelope: (AudioPerformanceEnvelopeKind, [UInt8], Double, Double) -> AudioPerformanceEnvelope = {
            AudioPerformanceEnvelope(
                kind: $0,
                startTime: 0,
                sampleRateHz: 1,
                minimum: $2,
                maximum: $3,
                samples: Data($1))
        }
        return AudioPerformanceMapV2(
            version: AudioPerformanceMapV2Version.current,
            analysisVersion: AudioPerformanceMapV2Version.analyzer,
            audioFingerprint: fingerprint,
            duration: 2,
            tempoSegments: [
                AudioPerformanceTempoSegment(from: 0, to: 2, bpm: 120, confidence: 0.8),
            ],
            beats: [0, 0.5, 1, 1.5],
            downbeats: [0],
            onsets: [
                AudioPerformanceOnset(time: 0.5, strength: 0.7),
                AudioPerformanceOnset(time: 1, strength: 0.9),
            ],
            envelopes: [
                envelope(.energy, [0, 128, 255], 0, 1),
                envelope(.brightness, [32, 64, 96], 0, 1),
                envelope(.pitch, [64, 96, 128], 36, 96),
                envelope(.pitchConfidence, [128, 192, 192], 0, 1),
                envelope(.vocalActivity, [64, 192, 128], 0, 1),
            ],
            regions: [
                AudioPerformanceRegion(id: "section-0", kind: .acousticSection, from: 0, to: 2, confidence: 0.8),
                AudioPerformanceRegion(id: "silence-0", kind: .silence, from: 0, to: 0.25, confidence: 0.7),
            ],
            confidence: confidence)
    }
}

private struct StubAnalyzer: AudioPerformanceAnalyzing {
    func analyzeCachedAudio(
        at localFileURL: URL,
        audioFingerprint: String
    ) async throws -> AudioPerformanceMapV2 {
        throw AudioPerformanceAnalysisError.unsupportedAudio
    }
}

@MainActor
private final class SelectedAudioURL {
    var url: URL

    init(_ url: URL) {
        self.url = url
    }
}

private actor DelayedMapAnalyzer: AudioPerformanceAnalyzing {
    let maps: [String: AudioPerformanceMapV2]
    private(set) var requestCount = 0

    init(maps: [String: AudioPerformanceMapV2]) {
        self.maps = maps
    }

    func analyzeCachedAudio(
        at localFileURL: URL,
        audioFingerprint: String
    ) async throws -> AudioPerformanceMapV2 {
        requestCount += 1
        try await Task.sleep(for: .milliseconds(120))
        guard let map = maps[audioFingerprint] else {
            throw AudioPerformanceAnalysisError.invalidMap
        }
        return map
    }
}
