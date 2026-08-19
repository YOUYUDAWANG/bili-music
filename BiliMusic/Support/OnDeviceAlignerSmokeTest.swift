#if DEBUG
import AVFoundation
import Foundation
import UIKit

@MainActor
enum OnDeviceAlignerSmokeTest {
    private static let environmentKey = "BILIMUSIC_ONDEVICE_ALIGNER_SMOKE"
    private static let sampleURL = URL(
        string: "https://qianwen-res.oss-cn-beijing.aliyuncs.com/Qwen3-ASR-Repo/asr_zh.wav")!
    private static let sourceText = "甚至出现交易几乎停滞的情况。"
    private static let repeatCount = 45
    private static var didStart = false

    private struct Report: Codable {
        let completedAt: Date
        let succeeded: Bool
        let error: String?
        let modelID: String
        let modelBytes: Int64
        let physicalMemoryBytes: UInt64
        let audioDuration: Double?
        let modelElapsedTime: Double?
        let wallElapsedTime: Double
        let peakMemoryGB: Double?
        let expectedUnitCount: Int
        let alignedUnitCount: Int
        let segmentCount: Int
        let alignedText: String?
    }

    static func runIfRequested() async {
        guard ProcessInfo.processInfo.environment[environmentKey] == "1", !didStart else { return }
        didStart = true
        let startedAt = Date()
        var expectedCount = 0
        var segmentCount = 0

        do {
            let (downloadedURL, _) = try await URLSession.shared.download(from: sampleURL)
            let repeated = try repeatedAudio(from: downloadedURL, count: repeatCount)
            let lines = (0..<repeatCount).map { index in
                PlayerEngine.LyricLine(
                    from: Double(index) * repeated.sampleDuration,
                    to: Double(index + 1) * repeated.sampleDuration,
                    text: sourceText)
            }
            let input = OnDeviceKaraokeBuilder.preparedInput(from: lines)
            expectedCount = input.unitsByLine.flatMap { $0 }.count
            segmentCount = OnDeviceKaraokeBuilder.alignmentSegments(
                lines: lines,
                input: input,
                audioDuration: repeated.totalDuration).count
            print("ALIGNER_SMOKE started expected_units=\(expectedCount) segments=\(segmentCount)")
            let result = try await OnDeviceLyricsAligner.shared.align(
                audioURL: repeated.url,
                input: input,
                lines: lines
            ) { progress, message in
                print("ALIGNER_SMOKE progress=\(progress) status=\(message)")
            }
            let alignedText = zip(result.words, input.unitsByLine.flatMap { $0 })
                .map { $0.1.surfaceText }
                .joined()
            guard result.words.count == expectedCount,
                  alignedText == String(repeating: sourceText, count: repeatCount) else {
                throw OnDeviceLyricsAlignerError.tokenCountMismatch(
                    expected: expectedCount,
                    actual: result.words.count)
            }
            let report = Report(
                completedAt: Date(),
                succeeded: true,
                error: nil,
                modelID: OnDeviceLyricsAligner.modelID,
                modelBytes: OnDeviceLyricsAligner.downloadedModelBytes,
                physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                audioDuration: result.audioDuration,
                modelElapsedTime: result.elapsedTime,
                wallElapsedTime: Date().timeIntervalSince(startedAt),
                peakMemoryGB: result.peakMemoryGB,
                expectedUnitCount: expectedCount,
                alignedUnitCount: result.words.count,
                segmentCount: segmentCount,
                alignedText: alignedText)
            try write(report)
            print("ALIGNER_SMOKE succeeded elapsed=\(result.elapsedTime) peak_gb=\(result.peakMemoryGB)")
        } catch {
            let report = Report(
                completedAt: Date(),
                succeeded: false,
                error: error.localizedDescription,
                modelID: OnDeviceLyricsAligner.modelID,
                modelBytes: OnDeviceLyricsAligner.downloadedModelBytes,
                physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                audioDuration: nil,
                modelElapsedTime: nil,
                wallElapsedTime: Date().timeIntervalSince(startedAt),
                peakMemoryGB: nil,
                expectedUnitCount: expectedCount,
                alignedUnitCount: 0,
                segmentCount: segmentCount,
                alignedText: nil)
            try? write(report)
            print("ALIGNER_SMOKE failed error=\(error.localizedDescription)")
        }
    }

    private static func repeatedAudio(from sourceURL: URL, count: Int) throws -> (
        url: URL,
        sampleDuration: Double,
        totalDuration: Double
    ) {
        let source = try AVAudioFile(forReading: sourceURL)
        let frameCount = AVAudioFrameCount(source.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: source.processingFormat,
                frameCapacity: frameCount) else {
            throw OnDeviceLyricsAlignerError.unsupportedAudio
        }
        try source.read(into: buffer)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("on-device-aligner-long-smoke.wav")
        let output = try AVAudioFile(
            forWriting: outputURL,
            settings: source.fileFormat.settings)
        for _ in 0..<count {
            try output.write(from: buffer)
        }
        let sampleDuration = Double(buffer.frameLength) / source.processingFormat.sampleRate
        return (outputURL, sampleDuration, sampleDuration * Double(count))
    }

    private static func write(_ report: Report) throws {
        let data = try JSONEncoder().encode(report)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("on-device-aligner-smoke.json")
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
enum OnDeviceCurrentLyricsSmokeTest {
    private static let environmentKey = "BILIMUSIC_ONDEVICE_CURRENT_LYRICS_SMOKE"
    private static let targetBVIDKey = "BILIMUSIC_ONDEVICE_CURRENT_LYRICS_TARGET_BVID"
    private static let rebuildTimelineKey = "BILIMUSIC_ONDEVICE_CURRENT_LYRICS_REBUILD_TIMELINE"
    private static let calibrateTimelineKey = "BILIMUSIC_ONDEVICE_CURRENT_LYRICS_CALIBRATE_TIMELINE"
    private static let dryRunKey = "BILIMUSIC_ONDEVICE_CURRENT_LYRICS_DRY_RUN"
    private static var didStart = false

    private struct Report: Codable {
        let completedAt: Date
        let succeeded: Bool
        let error: String?
        let bvid: String?
        let lineCount: Int
        let alignedUnitCount: Int
        let modelElapsedTime: Double?
        let peakMemoryGB: Double?
        let offsetMilliseconds: Int?
        let sourceLineStarts: [Double]?
        let alignedLineStarts: [Double]?
        let generatedLineStarts: [Double]?
        let calibrationOffsetSeconds: Double?
        let calibrationConfidence: Double?
        let calibrationDispersion: Double?
        let timelineEstimateStarts: [Double]?
    }

    static func runIfRequested(engine: PlayerEngine) async {
        guard ProcessInfo.processInfo.environment[environmentKey] == "1", !didStart else { return }
        didStart = true
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        print("ALIGNER_CURRENT_SMOKE waiting_for_restored_track")
        for _ in 0..<80 where engine.queue.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
        }
        let targetBVID = ProcessInfo.processInfo.environment[targetBVIDKey]
        let shouldRebuildTimeline = ProcessInfo.processInfo.environment[rebuildTimelineKey] == "1"
        let shouldCalibrateTimeline = ProcessInfo.processInfo.environment[calibrateTimelineKey] == "1"
        let isDryRun = ProcessInfo.processInfo.environment[dryRunKey] == "1"
        let track = targetBVID.flatMap { bvid in
            engine.queue.first { $0.bvid == bvid }
        } ?? engine.current
        guard let track else {
            writeFailure("没有恢复到当前歌曲", track: nil, lineCount: 0)
            return
        }

        await CacheStore.shared.loadIfNeeded()
        await LyricsStore.shared.loadIfNeeded()
        guard let entry = await LyricsStore.shared.entry(for: track),
              let document = entry.document,
              document.timingKind == .line || (document.timingKind == .word && document.hasLineSync) else {
            writeFailure("当前歌曲没有可转换的逐行歌词", track: track, lineCount: 0)
            return
        }
        let sourceDocument: LyricsDocument
        if document.timingKind == .word {
            sourceDocument = LyricsDocument(
                result: document.result,
                lyric: document.lyric,
                translatedLyric: document.translatedLyric,
                romanizedLyric: document.romanizedLyric,
                karaokeLyric: nil,
                karaokeTranslatedLyric: nil,
                versionScope: document.versionScope,
                timingKind: .line,
                timingNeedsConfirmation: document.timingNeedsConfirmation,
                appliesToCurrentCover: document.appliesToCurrentCover,
                followsPlayback: true,
                vocalLines: nil)
        } else {
            sourceDocument = document
        }
        let lines = LyricsParser.lines(from: sourceDocument, duration: track.duration).map { line in
            PlayerEngine.LyricLine(
                from: line.from,
                to: line.to,
                text: line.text,
                translation: line.translation,
                voiceRole: line.voiceRole,
                layerID: line.layerID,
                overlapGroup: line.overlapGroup)
        }
        let lineCount = lines.count
        let input = OnDeviceKaraokeBuilder.preparedInput(from: lines)

        do {
            if CacheStore.shared.localAudioURL(for: track) == nil {
                await DownloadManager.shared.download(track: track)
            }
            guard let audioURL = CacheStore.shared.localAudioURL(for: track) else {
                throw OnDeviceLyricsAlignerError.noAudio
            }
            let result = try await OnDeviceLyricsAligner.shared.align(
                audioURL: audioURL,
                input: input,
                lines: lines,
                rebuildTimeline: shouldRebuildTimeline,
                calibrateTimeline: shouldCalibrateTimeline
            ) { progress, message in
                print("ALIGNER_CURRENT_SMOKE progress=\(progress) status=\(message)")
            }
            let upgraded = try OnDeviceKaraokeBuilder.upgradedDocument(
                from: sourceDocument,
                lines: lines,
                input: input,
                alignment: result)
            if !isDryRun {
                await LyricsStore.shared.save(
                    document: upgraded,
                    offsetMilliseconds: entry.offsetMilliseconds,
                    offsetIsUserSet: entry.offsetIsUserSet,
                    for: track)
            }
            let report = Report(
                completedAt: Date(),
                succeeded: true,
                error: nil,
                bvid: track.bvid,
                lineCount: lineCount,
                alignedUnitCount: result.words.count,
                modelElapsedTime: result.elapsedTime,
                peakMemoryGB: result.peakMemoryGB,
                offsetMilliseconds: entry.offsetMilliseconds,
                sourceLineStarts: lines.map(\.from),
                alignedLineStarts: result.lineRanges.map(\.from),
                generatedLineStarts: LyricsParser.lines(from: upgraded, duration: track.duration).map(\.from),
                calibrationOffsetSeconds: result.timelineCalibration?.offsetSeconds,
                calibrationConfidence: result.timelineCalibration?.confidence,
                calibrationDispersion: result.timelineCalibration?.dispersion,
                timelineEstimateStarts: result.timelineEstimateStarts)
            try write(report)
            print("ALIGNER_CURRENT_SMOKE succeeded bvid=\(track.bvid) units=\(result.words.count)")
        } catch {
            writeFailure(error.localizedDescription, track: track, lineCount: lineCount)
        }
    }

    private static func writeFailure(_ message: String, track: Track?, lineCount: Int) {
        let report = Report(
            completedAt: Date(),
            succeeded: false,
            error: message,
            bvid: track?.bvid,
            lineCount: lineCount,
            alignedUnitCount: 0,
            modelElapsedTime: nil,
            peakMemoryGB: nil,
            offsetMilliseconds: nil,
            sourceLineStarts: nil,
            alignedLineStarts: nil,
            generatedLineStarts: nil,
            calibrationOffsetSeconds: nil,
            calibrationConfidence: nil,
            calibrationDispersion: nil,
            timelineEstimateStarts: nil)
        try? write(report)
        print("ALIGNER_CURRENT_SMOKE failed error=\(message)")
    }

    private static func write(_ report: Report) throws {
        let data = try JSONEncoder().encode(report)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("on-device-current-lyrics-smoke.json")
        try data.write(to: url, options: .atomic)
    }
}
#endif
