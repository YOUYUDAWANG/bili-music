import Foundation
import HuggingFace
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioSTT
import NaturalLanguage

struct OnDeviceAlignedWord: Equatable, Sendable {
    let text: String
    let startTime: Double
    let endTime: Double
}

extension String {
    var localizedAlignerStatus: String {
        let value = lowercased()
        if value.contains("download") { return "正在下载本机模型" }
        if value.contains("tokenizer") || value.contains("weight") { return "正在载入本机模型" }
        if value.contains("ready") { return "本机模型已就绪" }
        return self
    }
}

struct OnDeviceLyricsAlignmentResult: Equatable, Sendable {
    let words: [OnDeviceAlignedWord]
    let language: String
    let audioDuration: Double
    let elapsedTime: Double
    let peakMemoryGB: Double
    var lineRanges: [OnDeviceAlignedLineRange] = []
    var rebuiltTimeline = false
    var timelineCalibration: OnDeviceTimelineCalibration? = nil
    var timelineEstimateStarts: [Double] = []
}

struct OnDeviceAlignedLineRange: Equatable, Sendable {
    let from: Double
    let to: Double
}

struct OnDeviceASRChunk: Equatable, Sendable {
    let text: String
    let from: Double
    let to: Double
}

struct OnDeviceCoarseTimeline: Equatable, Sendable {
    let lineRanges: [OnDeviceAlignedLineRange]
    let lineEstimates: [OnDeviceAlignedLineRange]
    let characterCoverage: Double
    let lineCoverage: Double
}

struct OnDeviceTimelineCalibration: Equatable, Sendable {
    let offsetSeconds: Double
    let confidence: Double
    let sampleCount: Int
    let dispersion: Double
}

struct OnDeviceAlignmentUnit: Equatable, Sendable {
    let modelText: String
    var surfaceText: String
    var displayTexts: [String]

    init(modelText: String, surfaceText: String, displayTexts: [String]? = nil) {
        self.modelText = modelText
        self.surfaceText = surfaceText
        self.displayTexts = displayTexts ?? [surfaceText]
    }
}

struct OnDeviceAlignmentInput: Equatable, Sendable {
    let text: String
    let language: String
    let unitsByLine: [[OnDeviceAlignmentUnit]]
}

struct OnDeviceAlignmentSegment: Equatable, Sendable {
    let lineIndices: [Int]
    let startTime: Double
    let endTime: Double
    let text: String
    let expectedUnitCount: Int
}

enum OnDeviceLyricsAlignerError: LocalizedError, Equatable {
    case noAudio
    case noTimedLyrics
    case unsupportedAudio
    case emptyAlignment
    case tokenCountMismatch(expected: Int, actual: Int)
    case invalidTimeline
    case lowQualityTimeline(shortPercent: Int, suspiciousLines: Int, totalLines: Int)
    case coarseTranscriptionEmpty
    case coarseAlignmentLowConfidence

    var errorDescription: String? {
        switch self {
        case .noAudio:
            "需要先把当前歌曲缓存到本机"
        case .noTimedLyrics:
            "当前歌词没有可用于逐字生成的逐行时间轴"
        case .unsupportedAudio:
            "本地音频无法解码为模型需要的 16 kHz 单声道数据"
        case .emptyAlignment:
            "本机模型没有生成有效的逐字时间轴"
        case let .tokenCountMismatch(expected, actual):
            "模型分词数量不一致（预计 \(expected)，实际 \(actual)），已保留原歌词"
        case .invalidTimeline:
            "模型返回的时间轴不连续，已保留原歌词"
        case let .lowQualityTimeline(shortPercent, suspiciousLines, totalLines):
            "模型生成的逐字时间过于拥挤或跳跃（短时间 \(shortPercent)% · 异常行 \(suspiciousLines)/\(totalLines)），已保留原歌词"
        case .coarseTranscriptionEmpty:
            "本机识别没有找到可用于定位歌词的声音"
        case .coarseAlignmentLowConfidence:
            "歌词文字正确，但本机没有找到足够可靠的声音锚点，已保留原歌词"
        }
    }
}

actor OnDeviceLyricsAligner {
    static let shared = OnDeviceLyricsAligner()
    static let modelID = "mlx-community/Qwen3-ForcedAligner-0.6B-4bit"
    static let coarseModelID = "mlx-community/Qwen3-ASR-0.6B-4bit"

    typealias ProgressHandler = @Sendable (Double, String) -> Void

    private var model: Qwen3ForcedAlignerModel?
    private var coarseModel: Qwen3ASRModel?

    func prepareModel(progress: @escaping ProgressHandler) async throws {
        _ = try await loadModel(progress: progress)
        model = nil
    }

    func prepareCompletePipeline(progress: @escaping ProgressHandler) async throws {
        _ = try await loadCoarseModel(progress: progress)
        coarseModel = nil
        _ = try await loadModel(progress: progress)
        model = nil
    }

    func align(
        audioURL: URL,
        input: OnDeviceAlignmentInput,
        lines: [PlayerEngine.LyricLine],
        rebuildTimeline: Bool = false,
        calibrateTimeline: Bool = false,
        progress: @escaping ProgressHandler
    ) async throws -> OnDeviceLyricsAlignmentResult {
        guard !input.text.isEmpty, input.unitsByLine.count == lines.count else {
            throw OnDeviceLyricsAlignerError.noTimedLyrics
        }

        progress(0, "正在解码本地音频")
        let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: 16_000)
        guard audio.dim(0) > 0 else { throw OnDeviceLyricsAlignerError.unsupportedAudio }
        let duration = Double(audio.dim(0)) / 16_000
        var workingLines = lines
        var totalElapsed = 0.0
        var peakMemoryGB = 0.0
        var timelineCalibration: OnDeviceTimelineCalibration?
        var timelineEstimateStarts: [Double] = []
        if rebuildTimeline || calibrateTimeline {
            progress(0.02, "正在识别整首歌曲的歌词位置")
            do {
                let coarse = try await transcribeForCoarseTimeline(
                    audio: audio,
                    language: input.language,
                    progress: progress)
                Memory.clearCache()
                guard !coarse.chunks.isEmpty else {
                    throw OnDeviceLyricsAlignerError.coarseTranscriptionEmpty
                }
                let timeline = try OnDeviceCoarseTimelineBuilder.build(
                    lines: lines,
                    chunks: coarse.chunks,
                    audioDuration: duration)
                timelineEstimateStarts = timeline.lineEstimates.map(\.from)
                if rebuildTimeline {
                    let vocalRanges = OnDeviceKaraokeBuilder.sharedVocalWindows(
                        lines: lines,
                        ranges: timeline.lineRanges)
                    workingLines = zip(lines, vocalRanges).map { line, range in
                        PlayerEngine.LyricLine(
                            from: range.from,
                            to: range.to,
                            text: line.text,
                            translation: line.translation,
                            words: [],
                            voiceRole: line.voiceRole,
                            layerID: line.layerID,
                            overlapGroup: line.overlapGroup)
                    }
                } else if let suggestion = OnDeviceTimelineCalibrator.suggest(
                    lines: lines,
                    timeline: timeline),
                    suggestion.confidence >= 0.50,
                    abs(suggestion.offsetSeconds) >= 0.15 {
                    timelineCalibration = suggestion
                    workingLines = lines.map { line in
                        let from = min(max(0, duration - 0.08), max(0, line.from - suggestion.offsetSeconds))
                        let to = min(duration, max(from + 0.08, line.to - suggestion.offsetSeconds))
                        return PlayerEngine.LyricLine(
                            from: from,
                            to: to,
                            text: line.text,
                            translation: line.translation,
                            words: [],
                            voiceRole: line.voiceRole,
                            layerID: line.layerID,
                            overlapGroup: line.overlapGroup)
                    }
                }
                totalElapsed += coarse.elapsedTime
                peakMemoryGB = max(peakMemoryGB, coarse.peakMemoryGB)
                progress(0.35, timelineCalibration == nil && !rebuildTimeline
                    ? "未发现稳定整曲偏移，沿用原时间轴"
                    : "粗时间轴已建立，正在切换逐字模型")
            } catch {
                guard !rebuildTimeline else { throw error }
                Memory.clearCache()
                progress(0.35, "整曲校准置信度不足，沿用原时间轴")
            }
        }
        let segments = OnDeviceKaraokeBuilder.alignmentSegments(
            lines: workingLines,
            input: input,
            audioDuration: duration,
            contextSeconds: timelineCalibration == nil ? 0.25 : 2.5)
        guard !segments.isEmpty else { throw OnDeviceLyricsAlignerError.noTimedLyrics }

        let loadedModel = try await loadModel(progress: progress)
        defer { model = nil }
        var words: [OnDeviceAlignedWord] = []

        for (index, segment) in segments.enumerated() {
            try Task.checkCancellation()
            let lowerSample = max(0, min(audio.dim(0), Int((segment.startTime * 16_000).rounded(.down))))
            let upperSample = max(lowerSample + 1, min(audio.dim(0), Int((segment.endTime * 16_000).rounded(.up))))
            let base = rebuildTimeline || calibrateTimeline ? 0.4 : 0.0
            let fraction = base + (1 - base) * Double(index) / Double(max(segments.count, 1))
            progress(fraction, "正在对齐第 \(index + 1)/\(segments.count) 段")
            let generated = loadedModel.generate(
                audio: audio[lowerSample..<upperSample],
                text: segment.text,
                language: input.language)
            guard generated.items.count == segment.expectedUnitCount else {
                throw OnDeviceLyricsAlignerError.tokenCountMismatch(
                    expected: segment.expectedUnitCount,
                    actual: generated.items.count)
            }
            words.append(contentsOf: generated.items.map {
                OnDeviceAlignedWord(
                    text: $0.text,
                    startTime: $0.startTime + segment.startTime,
                    endTime: $0.endTime + segment.startTime)
            })
            totalElapsed += generated.totalTime
            peakMemoryGB = max(peakMemoryGB, generated.peakMemoryUsage)
        }
        progress(1, "逐字时间轴已生成")
        guard !words.isEmpty else { throw OnDeviceLyricsAlignerError.emptyAlignment }
        return OnDeviceLyricsAlignmentResult(
            words: words,
            language: input.language,
            audioDuration: duration,
            elapsedTime: totalElapsed,
            peakMemoryGB: peakMemoryGB,
            lineRanges: workingLines.map { .init(from: $0.from, to: $0.to) },
            rebuiltTimeline: rebuildTimeline,
            timelineCalibration: timelineCalibration,
            timelineEstimateStarts: timelineEstimateStarts)
    }

    private func transcribeForCoarseTimeline(
        audio: MLXArray,
        language: String,
        progress: @escaping ProgressHandler
    ) async throws -> (chunks: [OnDeviceASRChunk], elapsedTime: Double, peakMemoryGB: Double) {
        let loaded = try await loadCoarseModel(progress: progress)
        defer { coarseModel = nil }
        progress(0.15, "正在分块识别歌词锚点")
        let output = loaded.generate(
            audio: audio,
            maxTokens: 4_096,
            temperature: 0,
            language: language,
            chunkDuration: 20,
            minChunkDuration: 2)
        let chunks = (output.segments ?? []).compactMap { value -> OnDeviceASRChunk? in
            guard let text = value["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let from = Self.number(value["start"]),
                  let to = Self.number(value["end"]),
                  to > from else { return nil }
            return OnDeviceASRChunk(text: text, from: from, to: to)
        }
        return (chunks, output.totalTime, output.peakMemoryUsage)
    }

    private nonisolated static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: value
        case let value as Float: Double(value)
        case let value as Int: Double(value)
        case let value as NSNumber: value.doubleValue
        default: nil
        }
    }

    func removeDownloadedModel() throws {
        model = nil
        coarseModel = nil
        for directory in [Self.modelDirectory, Self.experimentalModelDirectory, Self.coarseModelDirectory]
            where FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    nonisolated static var modelDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalModels", isDirectory: true)
            .appendingPathComponent("Qwen3-ForcedAligner-0.6B-4bit", isDirectory: true)
    }

    nonisolated static var experimentalModelDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalModels", isDirectory: true)
            .appendingPathComponent("Qwen3-ForcedAligner-0.6B-8bit", isDirectory: true)
    }

    nonisolated static var coarseModelDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalModels", isDirectory: true)
            .appendingPathComponent("Qwen3-ASR-0.6B-4bit", isDirectory: true)
    }

    nonisolated static var downloadedModelBytes: Int64 {
        directoryBytes(modelDirectory)
            + directoryBytes(experimentalModelDirectory)
            + directoryBytes(coarseModelDirectory)
    }

    nonisolated static var downloadedAlignerBytes: Int64 {
        directoryBytes(modelDirectory)
    }

    nonisolated static var downloadedCoarseModelBytes: Int64 {
        directoryBytes(coarseModelDirectory)
    }

    private nonisolated static func directoryBytes(_ directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    nonisolated static var isModelDownloaded: Bool {
        downloadedAlignerBytes > 900_000_000
    }

    nonisolated static var isCompletePipelineDownloaded: Bool {
        isModelDownloaded && downloadedCoarseModelBytes > 500_000_000
    }

    private func loadModel(progress: @escaping ProgressHandler) async throws -> Qwen3ForcedAlignerModel {
        if let model { return model }
        if Self.downloadedAlignerBytes > 900_000_000,
           FileManager.default.fileExists(atPath: Self.experimentalModelDirectory.path) {
            try? FileManager.default.removeItem(at: Self.experimentalModelDirectory)
        }
        let directory = try Self.prepareModelDirectory()
        progress(0.05, "Downloading model")
        let loaded = try await Qwen3ForcedAlignerModel.fromPretrained(
            Self.modelID,
            cache: HubCache(cacheDirectory: directory))
        progress(0.95, "Loading model weights")
        model = loaded
        return loaded
    }

    private func loadCoarseModel(progress: @escaping ProgressHandler) async throws -> Qwen3ASRModel {
        if let coarseModel { return coarseModel }
        let directory = try Self.prepareModelDirectory(Self.coarseModelDirectory)
        progress(0.02, "正在下载粗定位模型")
        let loaded = try await Qwen3ASRModel.fromPretrained(
            Self.coarseModelID,
            cache: HubCache(cacheDirectory: directory))
        progress(0.12, "正在载入粗定位模型")
        coarseModel = loaded
        return loaded
    }

    private nonisolated static func prepareModelDirectory() throws -> URL {
        try prepareModelDirectory(modelDirectory)
    }

    private nonisolated static func prepareModelDirectory(_ directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
        return directory
    }

}

enum OnDeviceKaraokeBuilder {
    static let maximumSegmentDuration = 12.0
    static let maximumSegmentUnits = 48

    static func preparedInput(
        from lines: [PlayerEngine.LyricLine],
        preferredLanguageCode: String? = nil
    ) -> OnDeviceAlignmentInput {
        let sourceText = lines.map(\.text).joined(separator: "\n")
        let language = alignerLanguage(
            preferredLanguageCode: preferredLanguageCode,
            lyricText: sourceText)
        let unitsByLine = lines.map { alignmentUnits(in: $0.text, language: language) }
        let text = unitsByLine.flatMap { $0 }.map(\.modelText).joined(separator: " ")
        return OnDeviceAlignmentInput(text: text, language: language, unitsByLine: unitsByLine)
    }

    static func alignerLanguage(
        preferredLanguageCode: String?,
        lyricText: String
    ) -> String {
        let preferred: String?
        switch preferredLanguageCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "zh", "zh-cn", "zh-hans", "chinese":
            preferred = "Chinese"
        case "yue", "zh-yue", "cantonese":
            preferred = "Cantonese"
        case "ja", "jp", "japanese":
            preferred = "Japanese"
        case "ko", "kr", "korean":
            preferred = "Korean"
        case "en", "english":
            preferred = "English"
        case "de", "german":
            preferred = "German"
        case "es", "spanish":
            preferred = "Spanish"
        case "fr", "french":
            preferred = "French"
        case "it", "italian":
            preferred = "Italian"
        case "pt", "portuguese":
            preferred = "Portuguese"
        case "ru", "russian":
            preferred = "Russian"
        default:
            preferred = nil
        }

        let detected = detectedLanguage(in: lyricText)
        switch detected {
        case "Japanese", "Korean":
            // Kana and Hangul are unambiguous evidence from the exact text sent
            // to the model, so they beat catalog metadata.
            return detected
        case "Chinese":
            // Han-only lyrics are ambiguous between Chinese, Cantonese and
            // Japanese; this is where the initial metadata cleanup is useful.
            if let preferred, ["Chinese", "Cantonese", "Japanese"].contains(preferred) {
                return preferred
            }
            return detected
        default:
            // Latin-script lyrics should not inherit an unrelated CJK catalog
            // language. Keep metadata only when it identifies a Latin-script
            // language supported by the aligner.
            if let preferred,
               ["English", "German", "Spanish", "French", "Italian", "Portuguese"].contains(preferred) {
                return preferred
            }
            return detected
        }
    }

    static func detectedLanguage(in text: String) -> String {
        var hasHan = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF:
                return "Japanese"
            case 0xAC00...0xD7AF:
                return "Korean"
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                hasHan = true
            default:
                continue
            }
        }
        return hasHan ? "Chinese" : "English"
    }

    static func upgradedDocument(
        from source: LyricsDocument,
        lines: [PlayerEngine.LyricLine],
        input: OnDeviceAlignmentInput,
        alignment: OnDeviceLyricsAlignmentResult
    ) throws -> LyricsDocument {
        let tokenCounts = input.unitsByLine.map(\.count)
        let expected = tokenCounts.reduce(0, +)
        guard expected == alignment.words.count else {
            throw OnDeviceLyricsAlignerError.tokenCountMismatch(
                expected: expected,
                actual: alignment.words.count)
        }
        var wordOffset = 0
        var karaokeLines: [String] = []
        var translatedLines: [String] = []
        var vocalLines: [LyricsVocalLine] = []
        var modelTimingLines: [[OnDeviceAlignedWord]] = []
        var stabilizedLineCount = 0
        var previousLineStart = -Double.infinity
        var previousOverlapGroup: String?
        let timedLines: [PlayerEngine.LyricLine]
        if alignment.lineRanges.count == lines.count {
            timedLines = zip(lines, alignment.lineRanges).map { line, range in
                PlayerEngine.LyricLine(
                    from: range.from,
                    to: range.to,
                    text: line.text,
                    translation: line.translation,
                    words: line.words,
                    voiceRole: line.voiceRole,
                    layerID: line.layerID,
                    overlapGroup: line.overlapGroup)
            }
        } else {
            timedLines = lines
        }

        for (index, line) in timedLines.enumerated() {
            let count = tokenCounts[index]
            guard count > 0 else { continue }
            let rawWords = Array(alignment.words[wordOffset..<(wordOffset + count)])
            let units = input.unitsByLine[index]
            wordOffset += count
            guard timelineIsValid(rawWords, audioDuration: alignment.audioDuration),
                  let repairedModelWords = repairedWords(
                    rawWords,
                    line: line,
                    audioDuration: alignment.audioDuration,
                    anchorToLineStart: !alignment.rebuiltTimeline) else {
                throw OnDeviceLyricsAlignerError.invalidTimeline
            }
            let stabilized = stabilizedModelWords(repairedModelWords, units: units, line: line)
            if stabilized.didStabilize { stabilizedLineCount += 1 }
            modelTimingLines.append(stabilized.words)
            let expanded = zip(stabilized.words, units).flatMap { word, unit in
                expandedDisplayWords(word, unit: unit)
            }
            let displayTexts = units.flatMap(\.displayTexts)
            guard expanded.count == displayTexts.count,
                  let first = expanded.first,
                  let last = expanded.last,
                  (line.overlapGroup != nil && line.overlapGroup == previousOverlapGroup)
                    || first.startTime + 0.001 >= previousLineStart else {
                throw OnDeviceLyricsAlignerError.invalidTimeline
            }
            if line.overlapGroup != nil && line.overlapGroup == previousOverlapGroup {
                previousLineStart = max(previousLineStart, first.startTime)
            } else {
                previousLineStart = first.startTime
            }
            previousOverlapGroup = line.overlapGroup

            let lineStartMS = max(0, Int((first.startTime * 1_000).rounded()))
            let lineEndMS = max(lineStartMS + 80, Int((last.endTime * 1_000).rounded()))
            let lineDurationMS = lineEndMS - lineStartMS
            let body = zip(expanded, displayTexts).map { word, text in
                let startMS = max(lineStartMS, Int((word.startTime * 1_000).rounded()))
                let endMS = max(startMS + 20, Int((word.endTime * 1_000).rounded()))
                let text = sanitizedWordText(text)
                return "<\(startMS - lineStartMS),\(endMS - startMS),0>\(text)"
            }.joined()
            guard !body.isEmpty else { continue }
            karaokeLines.append("[\(lineStartMS),\(lineDurationMS)]\(body)")
            vocalLines.append(LyricsVocalLine(
                from: Double(lineStartMS) / 1_000,
                to: Double(lineEndMS) / 1_000,
                text: line.text,
                translation: line.translation,
                words: zip(expanded, displayTexts).map { word, text in
                    LyricsWordPayload(
                        from: word.startTime,
                        to: word.endTime,
                        text: sanitizedWordText(text))
                },
                voiceRole: line.voiceRole,
                layerID: line.layerID,
                overlapGroup: line.overlapGroup))
            if let translation = line.translation?.trimmingCharacters(in: .whitespacesAndNewlines),
               !translation.isEmpty {
                translatedLines.append("[\(lineStartMS),\(lineDurationMS)]\(translation)")
            }
        }

        guard !karaokeLines.isEmpty else { throw OnDeviceLyricsAlignerError.emptyAlignment }
        let quality = timelineQuality(modelTimingLines)
        guard quality.isAcceptable else {
            throw OnDeviceLyricsAlignerError.lowQualityTimeline(
                shortPercent: quality.shortPercent,
                suspiciousLines: quality.suspiciousLines,
                totalLines: quality.totalLines)
        }
        return LyricsDocument(
            result: source.result,
            lyric: source.lyric,
            translatedLyric: source.translatedLyric,
            romanizedLyric: source.romanizedLyric,
            karaokeLyric: karaokeLines.joined(separator: "\n"),
            karaokeTranslatedLyric: translatedLines.isEmpty ? source.karaokeTranslatedLyric : translatedLines.joined(separator: "\n"),
            versionScope: source.versionScope,
            timingKind: .word,
            timingNeedsConfirmation: source.timingNeedsConfirmation || stabilizedLineCount > 0,
            appliesToCurrentCover: true,
            vocalLines: vocalLines)
    }

    static func alignmentSegments(
        lines: [PlayerEngine.LyricLine],
        input: OnDeviceAlignmentInput,
        audioDuration: Double,
        contextSeconds: Double = 0.25
    ) -> [OnDeviceAlignmentSegment] {
        guard lines.count == input.unitsByLine.count, audioDuration > 0 else { return [] }
        return lines.indices.compactMap { index in
            guard !input.unitsByLine[index].isEmpty else { return nil }
            let rawStart = max(0, lines[index].from)
            let sourceEnd = min(audioDuration, max(lines[index].to, rawStart + 0.2))
            let visibleUnitCount = input.unitsByLine[index].flatMap(\.displayTexts).count
            let expectedVocalDuration = min(8, max(2, 1.1 + Double(visibleUnitCount) * 0.42))
            let rawEnd = min(sourceEnd, rawStart + expectedVocalDuration)
            guard rawEnd > rawStart else { return nil }
            let text = input.unitsByLine[index]
                .map(\.modelText)
                .joined(separator: " ")
            let count = input.unitsByLine[index].count
            guard count > 0, !text.isEmpty else { return nil }
            return OnDeviceAlignmentSegment(
                lineIndices: [index],
                startTime: max(0, rawStart - contextSeconds),
                endTime: min(audioDuration, rawEnd + contextSeconds),
                text: text,
                expectedUnitCount: count)
        }
    }

    static func sharedVocalWindows(
        lines: [PlayerEngine.LyricLine],
        ranges: [OnDeviceAlignedLineRange]
    ) -> [OnDeviceAlignedLineRange] {
        guard lines.count == ranges.count else { return ranges }
        var result = ranges
        let groups = Dictionary(grouping: lines.indices.compactMap { index -> (String, Int)? in
            guard let group = lines[index].overlapGroup else { return nil }
            return (group, index)
        }, by: \.0)
        for members in groups.values where members.count > 1 {
            let indices = members.map(\.1)
            guard let start = indices.map({ ranges[$0].from }).min(),
                  let end = indices.map({ ranges[$0].to }).max() else { continue }
            let shared = OnDeviceAlignedLineRange(from: start, to: end)
            for index in indices {
                result[index] = shared
            }
        }
        return result
    }

    static func alignmentUnits(in text: String, language: String) -> [OnDeviceAlignmentUnit] {
        switch language {
        case "Japanese":
            return japaneseUnits(in: text)
        case "Chinese", "Korean":
            return characterUnits(in: text)
        default:
            return whitespaceUnits(in: text)
        }
    }

    private static func japaneseUnits(in text: String) -> [OnDeviceAlignmentUnit] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result: [OnDeviceAlignmentUnit] = []
        var cursor = text.startIndex

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            appendDecoration(String(text[cursor..<range.lowerBound]), to: &result)
            result.append(contentsOf: japaneseModelUnits(in: String(text[range])))
            cursor = range.upperBound
            return true
        }
        appendDecoration(String(text[cursor..<text.endIndex]), to: &result)
        return result
    }

    /// Mirrors MLXAudio's ForceAlignProcessor: Japanese words must first be
    /// externally segmented, while Han characters remain individual model
    /// tokens. Kana runs stay intact for the model and are expanded back to
    /// display characters only after alignment.
    private static func japaneseModelUnits(in token: String) -> [OnDeviceAlignmentUnit] {
        var units: [OnDeviceAlignmentUnit] = []
        var buffer = ""

        func flushBuffer() {
            let cleaned = cleanedToken(buffer)
            guard !cleaned.isEmpty else {
                buffer = ""
                return
            }
            let displayTexts = containsJapaneseScript(buffer)
                ? buffer.filter { $0.isLetter || $0.isNumber }.map(String.init)
                : [buffer]
            units.append(OnDeviceAlignmentUnit(
                modelText: cleaned,
                surfaceText: buffer,
                displayTexts: displayTexts))
            buffer = ""
        }

        for character in token {
            if isHan(character) {
                flushBuffer()
                units.append(OnDeviceAlignmentUnit(
                    modelText: String(character),
                    surfaceText: String(character),
                    displayTexts: [String(character)]))
            } else if character.isLetter || character.isNumber || character == "'" {
                buffer.append(character)
            } else {
                flushBuffer()
                appendDecoration(String(character), to: &units)
            }
        }
        flushBuffer()
        return units
    }

    private static func appendDecoration(
        _ value: String,
        to units: inout [OnDeviceAlignmentUnit]
    ) {
        let decoration = String(value.filter { !$0.isWhitespace })
        guard !decoration.isEmpty, !units.isEmpty else { return }
        units[units.count - 1].surfaceText.append(decoration)
        if units[units.count - 1].displayTexts.isEmpty {
            units[units.count - 1].displayTexts = [decoration]
        } else {
            units[units.count - 1].displayTexts[units[units.count - 1].displayTexts.count - 1]
                .append(decoration)
        }
    }

    private static func containsJapaneseScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)
        }
    }

    private static func isHan(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                true
            default:
                false
            }
        }
    }

    private static func characterUnits(in text: String) -> [OnDeviceAlignmentUnit] {
        var units: [OnDeviceAlignmentUnit] = []
        var latinBuffer = ""

        func flushLatin() {
            let cleaned = cleanedToken(latinBuffer)
            if !cleaned.isEmpty {
                units.append(OnDeviceAlignmentUnit(modelText: cleaned, surfaceText: latinBuffer))
            }
            latinBuffer = ""
        }

        for character in text {
            if character.isWhitespace {
                flushLatin()
            } else if character.isASCII, character.isLetter || character.isNumber || character == "'" {
                latinBuffer.append(character)
            } else if character.isLetter || character.isNumber {
                flushLatin()
                units.append(OnDeviceAlignmentUnit(
                    modelText: String(character),
                    surfaceText: String(character)))
            } else {
                flushLatin()
                appendDecoration(String(character), to: &units)
            }
        }
        flushLatin()
        return units
    }

    private static func whitespaceUnits(in text: String) -> [OnDeviceAlignmentUnit] {
        text.split(whereSeparator: \.isWhitespace).compactMap { segment in
            let surface = String(segment)
            let cleaned = cleanedToken(surface)
            guard !cleaned.isEmpty else { return nil }
            return OnDeviceAlignmentUnit(modelText: cleaned, surfaceText: surface)
        }
    }

    private static func cleanedToken(_ text: String) -> String {
        String(text.filter { $0.isLetter || $0.isNumber || $0 == "'" })
    }

    private static func timelineIsValid(
        _ words: [OnDeviceAlignedWord],
        audioDuration: Double
    ) -> Bool {
        var previousStart = -Double.infinity
        for word in words {
            guard word.startTime.isFinite,
                  word.endTime.isFinite,
                  word.startTime >= 0,
                  word.endTime >= word.startTime,
                  word.startTime + 0.35 >= previousStart,
                  word.endTime <= audioDuration + 5 else { return false }
            previousStart = word.startTime
        }
        return true
    }

    private static func repairedWords(
        _ words: [OnDeviceAlignedWord],
        line: PlayerEngine.LyricLine,
        audioDuration: Double,
        anchorToLineStart: Bool
    ) -> [OnDeviceAlignedWord]? {
        guard !words.isEmpty else { return nil }
        let lineStart = min(audioDuration, max(0, line.from))
        let lineEnd = min(audioDuration, max(line.to, lineStart + 0.08))
        let available = lineEnd - lineStart
        guard available > 0 else { return nil }

        // A downloaded line-timed lyric owns the line onset; the fine model
        // only supplies the rhythm inside that line. For a timeline rebuilt
        // from plain text/ASR, the range is merely a search boundary and the
        // fine model may still choose a more precise onset.
        let rawFirst = words[0].startTime
        let rawLast = words.last?.endTime ?? rawFirst
        let minimumUnit = min(0.04, available / Double(max(words.count, 1)))
        let minimumSpan = min(available, max(minimumUnit, Double(words.count) * minimumUnit))
        let sourceSpan = max(minimumUnit, rawLast - rawFirst)
        let targetStart = anchorToLineStart
            ? lineStart
            : min(lineEnd - minimumSpan, max(lineStart, rawFirst))
        let targetEnd = anchorToLineStart
            ? min(lineEnd, max(targetStart + minimumSpan, targetStart + sourceSpan))
            : min(lineEnd, max(targetStart + minimumSpan, rawLast))
        let scale = min(1, (targetEnd - targetStart) / sourceSpan)
        let adjusted = words.map { word in
            OnDeviceAlignedWord(
                text: word.text,
                startTime: targetStart + max(0, word.startTime - rawFirst) * scale,
                endTime: targetStart + max(0, word.endTime - rawFirst) * scale)
        }

        var starts: [Double] = []
        starts.reserveCapacity(adjusted.count)
        var previousStart = lineStart - minimumUnit
        for (index, word) in adjusted.enumerated() {
            let remaining = adjusted.count - index - 1
            let latest = max(lineStart, lineEnd - Double(remaining + 1) * minimumUnit)
            let start = min(latest, max(previousStart + minimumUnit, word.startTime))
            starts.append(start)
            previousStart = start
        }

        return adjusted.indices.map { index in
            let start = starts[index]
            let upperBound = index + 1 < starts.count
                ? starts[index + 1]
                : min(lineEnd, max(start + minimumUnit, adjusted[index].endTime))
            return OnDeviceAlignedWord(
                text: adjusted[index].text,
                startTime: start,
                // Karaoke highlighting is perceptually steadier when the
                // current character remains active until the next character
                // begins. The model's independent end tokens often leave
                // visible dead gaps or overlaps on sustained singing.
                endTime: max(start + minimumUnit, upperBound))
        }
    }

    private static func expandedDisplayWords(
        _ word: OnDeviceAlignedWord,
        unit: OnDeviceAlignmentUnit
    ) -> [OnDeviceAlignedWord] {
        let texts = unit.displayTexts.isEmpty ? [unit.surfaceText] : unit.displayTexts
        guard texts.count > 1 else {
            return [OnDeviceAlignedWord(
                text: texts.first ?? unit.surfaceText,
                startTime: word.startTime,
                endTime: word.endTime)]
        }
        let span = max(0, word.endTime - word.startTime)
        let weights = texts.map(timingWeight)
        let totalWeight = max(0.001, weights.reduce(0, +))
        var elapsedWeight = 0.0
        return texts.indices.map { index in
            let start = word.startTime + span * elapsedWeight / totalWeight
            elapsedWeight += weights[index]
            let end = word.startTime + span * elapsedWeight / totalWeight
            return OnDeviceAlignedWord(text: texts[index], startTime: start, endTime: end)
        }
    }

    private static func stabilizedModelWords(
        _ words: [OnDeviceAlignedWord],
        units: [OnDeviceAlignmentUnit],
        line: PlayerEngine.LyricLine
    ) -> (words: [OnDeviceAlignedWord], didStabilize: Bool) {
        guard words.count == units.count, words.count >= 3 else { return (words, false) }
        let durations = words.map { max(0, $0.endTime - $0.startTime) }
        let weights = units.map { unit in
            max(0.5, unit.displayTexts.map(timingWeight).reduce(0, +))
        }
        let shortCount = durations.filter { $0 <= 0.045 }.count
        let longest = durations.max() ?? 0
        let lineSpan = max(0.001, (words.last?.endTime ?? 0) - (words.first?.startTime ?? 0))
        let weightedRates = zip(durations, weights).map { duration, weight in duration / weight }
        let slowestRate = weightedRates.max() ?? 0
        let fastestRate = max(0.02, weightedRates.min() ?? 0.02)
        let severeImbalance = slowestRate / fastestRate > 10 && longest > lineSpan * 0.35
        let suspicious = shortCount >= max(2, Int(ceil(Double(words.count) * 0.3)))
            || (longest >= max(2.5, lineSpan * 0.72) && shortCount >= 2)
            || severeImbalance
            || longest > 8
        guard suspicious, let first = words.first else { return (words, false) }

        let totalWeight = max(1, weights.reduce(0, +))
        let start = min(line.to, max(line.from, first.startTime))
        let available = max(0.08, line.to - start)
        let estimatedVocalSpan = min(6.5, max(1, totalWeight * 0.28 + 0.45))
        let span = min(available, estimatedVocalSpan)
        var elapsedWeight = 0.0
        let redistributed = words.indices.map { index in
            let wordStart = start + span * elapsedWeight / totalWeight
            elapsedWeight += weights[index]
            let wordEnd = start + span * elapsedWeight / totalWeight
            return OnDeviceAlignedWord(
                text: words[index].text,
                startTime: wordStart,
                endTime: wordEnd)
        }
        return (redistributed, true)
    }

    private static func timingWeight(_ text: String) -> Double {
        let weight = text.unicodeScalars.reduce(0.0) { result, scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                result + 2
            case 0x3041, 0x3043, 0x3045, 0x3047, 0x3049,
                 0x3083, 0x3085, 0x3087, 0x3063,
                 0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9,
                 0x30E3, 0x30E5, 0x30E7, 0x30C3, 0x30FC:
                result + 0.5
            case 0x3040...0x30FF:
                result + 1
            default:
                CharacterSet.alphanumerics.contains(scalar) ? result + 1 : result
            }
        }
        return max(0.25, weight)
    }

    private static func timelineQuality(
        _ lines: [[OnDeviceAlignedWord]]
    ) -> (isAcceptable: Bool, shortPercent: Int, suspiciousLines: Int, totalLines: Int) {
        let meaningful = lines.filter { $0.count >= 3 }
        guard !meaningful.isEmpty else { return (true, 0, 0, 0) }
        var total = 0
        var short = 0
        var suspiciousLines = 0

        for words in meaningful {
            let durations = words.map { max(0, $0.endTime - $0.startTime) }
            let shortCount = durations.filter { $0 <= 0.045 }.count
            let longest = durations.max() ?? 0
            let lineSpan = max(0.001, (words.last?.endTime ?? 0) - (words.first?.startTime ?? 0))
            total += durations.count
            short += shortCount
            if shortCount >= max(2, Int(ceil(Double(words.count) * 0.3)))
                || (longest >= max(2.5, lineSpan * 0.72) && shortCount >= 2)
                || longest > 8 {
                suspiciousLines += 1
            }
        }

        let shortRatio = Double(short) / Double(max(total, 1))
        let allowedSuspiciousLines = Int(floor(Double(meaningful.count) * 0.2))
        return (
            shortRatio <= 0.3 && suspiciousLines <= allowedSuspiciousLines,
            Int((shortRatio * 100).rounded()),
            suspiciousLines,
            meaningful.count)
    }

    private static func sanitizedWordText(_ text: String) -> String {
        text.replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
    }
}

enum OnDeviceCoarseTimelineBuilder {
    private static let maximumTokenCount = 3_500

    private struct TimedToken {
        let value: UInt32
        let time: Double
    }

    static func build(
        lines: [PlayerEngine.LyricLine],
        chunks: [OnDeviceASRChunk],
        audioDuration: Double
    ) throws -> OnDeviceCoarseTimeline {
        guard !lines.isEmpty, audioDuration > 0 else {
            throw OnDeviceLyricsAlignerError.coarseAlignmentLowConfidence
        }

        var lyricTokens: [UInt32] = []
        var lineTokenRanges: [Range<Int>?] = []
        for line in lines {
            let values = normalizedScalars(line.text)
            let start = lyricTokens.count
            lyricTokens.append(contentsOf: values)
            lineTokenRanges.append(values.isEmpty ? nil : start..<lyricTokens.count)
        }

        var asrTokens: [TimedToken] = []
        for chunk in chunks where chunk.to > chunk.from {
            let values = normalizedScalars(chunk.text)
            guard !values.isEmpty else { continue }
            for (index, value) in values.enumerated() {
                let fraction = (Double(index) + 0.5) / Double(values.count)
                asrTokens.append(TimedToken(
                    value: value,
                    time: chunk.from + (chunk.to - chunk.from) * fraction))
            }
        }

        guard !lyricTokens.isEmpty,
              !asrTokens.isEmpty,
              lyricTokens.count <= maximumTokenCount,
              asrTokens.count <= maximumTokenCount else {
            throw OnDeviceLyricsAlignerError.coarseAlignmentLowConfidence
        }

        let matches = longestCommonSubsequenceMatches(
            lyricTokens,
            asrTokens.map(\.value))
        let matchedLines = Set(matches.compactMap { match -> Int? in
            lineTokenRanges.firstIndex { range in range?.contains(match.lyricIndex) == true }
        })
        let nonemptyLineCount = max(1, lineTokenRanges.compactMap { $0 }.count)
        let characterCoverage = Double(matches.count) / Double(lyricTokens.count)
        let lineCoverage = Double(matchedLines.count) / Double(nonemptyLineCount)
        let minimumMatches = min(
            lyricTokens.count,
            min(24, max(4, lyricTokens.count / 20)))
        guard matches.count >= minimumMatches,
              characterCoverage >= 0.12,
              lineCoverage >= 0.25 else {
            throw OnDeviceLyricsAlignerError.coarseAlignmentLowConfidence
        }

        let anchors = matches.map { match in
            (position: match.lyricIndex, time: asrTokens[match.asrIndex].time)
        }
        let secondsPerToken = representativeSecondsPerToken(
            anchors: anchors,
            fallback: audioDuration / Double(max(lyricTokens.count, 1)))

        var previousFallback = 0.0
        var estimates: [OnDeviceAlignedLineRange] = []
        let ranges = lineTokenRanges.map { tokenRange -> OnDeviceAlignedLineRange in
            guard let tokenRange else {
                let from = min(max(0, audioDuration - 0.2), previousFallback)
                let to = min(audioDuration, max(from + 0.2, from))
                previousFallback = to
                estimates.append(OnDeviceAlignedLineRange(from: from, to: to))
                return OnDeviceAlignedLineRange(from: from, to: to)
            }
            let first = estimateTime(
                at: tokenRange.lowerBound,
                anchors: anchors,
                secondsPerToken: secondsPerToken)
            let last = estimateTime(
                at: max(tokenRange.lowerBound, tokenRange.upperBound - 1),
                anchors: anchors,
                secondsPerToken: secondsPerToken)
            let estimatedFrom = min(audioDuration, max(0, first))
            let estimatedTo = min(audioDuration, max(estimatedFrom + 0.08, last + secondsPerToken))
            estimates.append(OnDeviceAlignedLineRange(from: estimatedFrom, to: estimatedTo))
            // These are deliberately broad search bounds. The fine aligner,
            // not this ASR interpolation, decides the saved character times.
            let from = min(max(0, audioDuration - 0.2), max(0, estimatedFrom - 1.2))
            let to = min(audioDuration, max(from + 0.2, estimatedTo + 1.2))
            previousFallback = to
            return OnDeviceAlignedLineRange(from: from, to: to)
        }

        return OnDeviceCoarseTimeline(
            lineRanges: ranges,
            lineEstimates: estimates,
            characterCoverage: characterCoverage,
            lineCoverage: lineCoverage)
    }

    private static func normalizedScalars(_ text: String) -> [UInt32] {
        text.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .unicodeScalars
            .compactMap { scalar in
                CharacterSet.alphanumerics.contains(scalar) ? scalar.value : nil
            }
    }

    private static func longestCommonSubsequenceMatches(
        _ left: [UInt32],
        _ right: [UInt32]
    ) -> [(lyricIndex: Int, asrIndex: Int)] {
        let columns = right.count + 1
        var table = [UInt16](repeating: 0, count: (left.count + 1) * columns)
        if !left.isEmpty, !right.isEmpty {
            for i in 1...left.count {
                for j in 1...right.count {
                    let index = i * columns + j
                    if left[i - 1] == right[j - 1] {
                        table[index] = table[(i - 1) * columns + j - 1] + 1
                    } else {
                        table[index] = max(
                            table[(i - 1) * columns + j],
                            table[i * columns + j - 1])
                    }
                }
            }
        }

        var matches: [(lyricIndex: Int, asrIndex: Int)] = []
        var i = left.count
        var j = right.count
        while i > 0, j > 0 {
            if left[i - 1] == right[j - 1],
               table[i * columns + j] == table[(i - 1) * columns + j - 1] + 1 {
                matches.append((i - 1, j - 1))
                i -= 1
                j -= 1
            } else if table[(i - 1) * columns + j] >= table[i * columns + j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return matches.reversed()
    }

    private static func representativeSecondsPerToken(
        anchors: [(position: Int, time: Double)],
        fallback: Double
    ) -> Double {
        let slopes = zip(anchors, anchors.dropFirst()).compactMap { pair -> Double? in
            let distance = pair.1.position - pair.0.position
            guard distance > 0 else { return nil }
            let value = (pair.1.time - pair.0.time) / Double(distance)
            return (0.02...2.0).contains(value) ? value : nil
        }.sorted()
        let value = slopes.isEmpty ? fallback : slopes[slopes.count / 2]
        return min(1.2, max(0.04, value))
    }

    private static func estimateTime(
        at position: Int,
        anchors: [(position: Int, time: Double)],
        secondsPerToken: Double
    ) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return 0 }
        if position <= first.position {
            return first.time - Double(first.position - position) * secondsPerToken
        }
        if position >= last.position {
            return last.time + Double(position - last.position) * secondsPerToken
        }

        var low = 0
        var high = anchors.count - 1
        while low + 1 < high {
            let middle = (low + high) / 2
            if anchors[middle].position <= position {
                low = middle
            } else {
                high = middle
            }
        }
        let before = anchors[low]
        let after = anchors[high]
        let distance = max(1, after.position - before.position)
        let fraction = Double(position - before.position) / Double(distance)
        return before.time + (after.time - before.time) * fraction
    }
}

enum OnDeviceTimelineCalibrator {
    static func suggest(
        lines: [PlayerEngine.LyricLine],
        timeline: OnDeviceCoarseTimeline
    ) -> OnDeviceTimelineCalibration? {
        guard lines.count == timeline.lineEstimates.count,
              timeline.characterCoverage >= 0.12,
              timeline.lineCoverage >= 0.25 else { return nil }
        let candidates = zip(lines, timeline.lineEstimates).compactMap { line, estimate -> Double? in
            guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  line.from >= 0,
                  estimate.from > 0.15 else { return nil }
            return line.from - estimate.from
        }.filter { abs($0) <= LyricsOffsetEstimator.maxAbsSeconds }
        guard candidates.count >= 3 else { return nil }

        let consensusRadius = 2.25
        let inliers = candidates.reduce(into: [Double]()) { best, center in
            let cluster = candidates.filter { abs($0 - center) <= consensusRadius }
            if cluster.count > best.count { best = cluster }
        }
        guard inliers.count >= max(3, Int((Double(candidates.count) * 0.60).rounded(.up))) else {
            return nil
        }

        let offset = median(inliers)
        let deviations = inliers.map { abs($0 - offset) }
        let mad = median(deviations)
        let sorted = inliers.sorted()
        let p25 = sorted[Int(Double(sorted.count - 1) * 0.25)]
        let p75 = sorted[Int(Double(sorted.count - 1) * 0.75)]
        let dispersion = max(mad, p75 - p25)
        guard abs(offset) >= 0.15, dispersion <= 3.5 else { return nil }
        let agreement = Double(inliers.count) / Double(candidates.count)
        let confidence = min(
            0.98,
            timeline.characterCoverage * 0.30
                + timeline.lineCoverage * 0.30
                + agreement * 0.25
                + max(0, 0.18 - dispersion * 0.04))
        return OnDeviceTimelineCalibration(
            offsetSeconds: offset,
            confidence: confidence,
            sampleCount: inliers.count,
            dispersion: dispersion)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
