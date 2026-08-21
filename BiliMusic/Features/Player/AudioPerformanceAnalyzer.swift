import AVFoundation
import Foundation

enum AudioPerformanceAnalysisError: LocalizedError {
    case localAudioUnavailable
    case unsupportedAudio
    case audioTooShort
    case invalidMap

    var errorDescription: String? {
        switch self {
        case .localAudioUnavailable:
            "需要先完成本地音频缓存"
        case .unsupportedAudio:
            "无法读取本地音频"
        case .audioTooShort:
            "本地音频太短，无法分析演出结构"
        case .invalidMap:
            "音频演出事实未通过校验"
        }
    }
}

protocol AudioPerformanceAnalyzing: Sendable {
    func analyzeCachedAudio(
        at localFileURL: URL,
        audioFingerprint: String
    ) async throws -> AudioPerformanceMapV2
}

struct LocalAudioPerformanceAnalyzer: AudioPerformanceAnalyzing, Sendable {
    private static let targetSampleRate = 22_050.0

    func analyzeCachedAudio(
        at localFileURL: URL,
        audioFingerprint: String
    ) async throws -> AudioPerformanceMapV2 {
        guard localFileURL.isFileURL,
              FileManager.default.fileExists(atPath: localFileURL.path) else {
            throw AudioPerformanceAnalysisError.localAudioUnavailable
        }
        let analysisTask = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let decoded = try await Self.decodeMonoAudio(at: localFileURL)
            try Task.checkCancellation()
            return try Self.analyze(
                samples: decoded.samples,
                sampleRate: decoded.sampleRate,
                audioFingerprint: audioFingerprint)
        }
        return try await withTaskCancellationHandler {
            try await analysisTask.value
        } onCancel: {
            analysisTask.cancel()
        }
    }

    static func analyze(
        samples: [Float],
        sampleRate: Double,
        audioFingerprint: String
    ) throws -> AudioPerformanceMapV2 {
        guard sampleRate.isFinite,
              sampleRate >= 4_000,
              !audioFingerprint.isEmpty,
              samples.count >= Int(sampleRate * 0.75) else {
            throw AudioPerformanceAnalysisError.audioTooShort
        }

        let duration = Double(samples.count) / sampleRate
        let frameSize = min(2_048, max(512, Int((sampleRate * 0.09).rounded())))
        let hopSize = max(256, frameSize / 2)
        let frameCount = 1 + (samples.count - frameSize) / hopSize
        guard frameCount >= 4 else { throw AudioPerformanceAnalysisError.audioTooShort }
        let frameRate = sampleRate / Double(hopSize)

        var rawEnergy = [Double](repeating: 0, count: frameCount)
        var zeroCrossing = [Double](repeating: 0, count: frameCount)
        for index in 0..<frameCount {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            let start = index * hopSize
            let end = start + frameSize
            var squareSum = 0.0
            var crossings = 0
            var previous = samples[start]
            for cursor in (start + 1)..<end {
                let value = samples[cursor]
                squareSum += Double(value * value)
                if (value >= 0) != (previous >= 0) { crossings += 1 }
                previous = value
            }
            rawEnergy[index] = sqrt(squareSum / Double(max(1, frameSize - 1)))
            zeroCrossing[index] = Double(crossings) / Double(max(1, frameSize - 1))
        }

        let energy = normalized(rawEnergy.map { log1p($0 * 120) }, low: 0.10, high: 0.95)
        let brightness = normalized(zeroCrossing, low: 0.05, high: 0.95)
        let onsetNovelty = normalized((0..<frameCount).map { index in
            guard index > 0 else { return 0 }
            let energyRise = max(0, energy[index] - energy[index - 1])
            let brightnessRise = max(0, brightness[index] - brightness[index - 1])
            return energyRise * 0.78 + brightnessRise * 0.22
        }, low: 0.20, high: 0.97)

        let onsetIndices = localPeakIndices(
            onsetNovelty,
            threshold: max(0.36, percentile(onsetNovelty, 0.82)),
            minimumDistance: max(1, Int((frameRate * 0.08).rounded())))
        let onsets = onsetIndices.map {
            AudioPerformanceOnset(
                time: min(duration, Double($0) / frameRate),
                strength: onsetNovelty[$0].clamped(to: 0...1))
        }

        var pitchMIDI = [Double](repeating: 36, count: frameCount)
        var pitchConfidence = [Double](repeating: 0, count: frameCount)
        let audibleFloor = max(0.000_5, percentile(rawEnergy, 0.20) * 0.75)
        let pitchStride = 4
        for frameIndex in stride(from: 0, to: frameCount, by: pitchStride) {
            if frameIndex.isMultiple(of: pitchStride * 16) { try Task.checkCancellation() }
            guard rawEnergy[frameIndex] >= audibleFloor else { continue }
            let start = frameIndex * hopSize
            let frame = Array(samples[start..<(start + frameSize)])
            let estimate = try pitchEstimate(frame: frame, sampleRate: sampleRate)
            let upper = min(frameCount, frameIndex + pitchStride)
            for index in frameIndex..<upper {
                pitchMIDI[index] = estimate.midi
                pitchConfidence[index] = estimate.confidence
            }
        }
        let vocalActivity = zip(energy, pitchConfidence).map { energyValue, pitchValue in
            (energyValue * 0.38 + pitchValue * 0.62).clamped(to: 0...1)
        }

        let beatResult = beatGrid(
            onset: onsetNovelty,
            energy: energy,
            frameRate: frameRate,
            duration: duration)
        let tempoSegments: [AudioPerformanceTempoSegment] = beatResult.bpm.map {
            [AudioPerformanceTempoSegment(
                from: 0,
                to: duration,
                bpm: $0,
                confidence: beatResult.confidence)]
        } ?? []

        let sectionRegions = acousticSections(
            energy: energy,
            brightness: brightness,
            frameRate: frameRate,
            duration: duration)
        let silenceRegions = contiguousRegions(
            kind: .silence,
            values: zip(energy, vocalActivity).map { max($0, $1) },
            matching: { $0 <= 0.10 },
            minimumDuration: 0.65,
            frameRate: frameRate,
            duration: duration)
        let lowEnergyRegions = contiguousRegions(
            kind: .lowEnergy,
            values: energy,
            matching: { $0 <= 0.20 },
            minimumDuration: 1.0,
            frameRate: frameRate,
            duration: duration)
        let highEnergyRegions = contiguousRegions(
            kind: .highEnergy,
            values: energy,
            matching: { $0 >= 0.76 },
            minimumDuration: 0.8,
            frameRate: frameRate,
            duration: duration)
        let transitionRegions = sectionRegions.dropFirst().compactMap { region -> AudioPerformanceRegion? in
            let from = max(0, region.from - 0.35)
            let to = min(duration, region.from + 0.35)
            guard to > from else { return nil }
            return AudioPerformanceRegion(
                id: "transition-\(Int((region.from * 1_000).rounded()))",
                kind: .transition,
                from: from,
                to: to,
                confidence: region.confidence)
        }
        let regions = sectionRegions + silenceRegions + lowEnergyRegions + highEnergyRegions + transitionRegions

        let energyConfidence = min(1, max(0, percentile(rawEnergy, 0.95) - percentile(rawEnergy, 0.10)) * 14)
        let onsetConfidence = onsets.isEmpty ? 0 : min(1, mean(onsets.map(\.strength)))
        let pitchConfidenceValue = mean(pitchConfidence.filter { $0 > 0 })
            * min(1, Double(pitchConfidence.filter { $0 >= 0.35 }.count) / Double(frameCount) * 2.5)
        let regionConfidence = mean(sectionRegions.map(\.confidence))
        let confidence = AudioPerformanceConfidence(
            beat: beatResult.confidence,
            downbeat: beatResult.downbeatConfidence,
            onset: onsetConfidence,
            energy: energyConfidence,
            pitch: pitchConfidenceValue.clamped(to: 0...1),
            regions: regionConfidence,
            overall: mean([
                beatResult.confidence,
                onsetConfidence,
                energyConfidence,
                pitchConfidenceValue,
                regionConfidence,
            ]).clamped(to: 0...1))

        let map = AudioPerformanceMapV2(
            version: AudioPerformanceMapV2Version.current,
            analysisVersion: AudioPerformanceMapV2Version.analyzer,
            audioFingerprint: audioFingerprint,
            duration: duration,
            tempoSegments: tempoSegments,
            beats: beatResult.beats,
            downbeats: beatResult.downbeats,
            onsets: onsets,
            envelopes: [
                envelope(kind: .energy, values: energy, sampleRateHz: frameRate, minimum: 0, maximum: 1),
                envelope(kind: .brightness, values: brightness, sampleRateHz: frameRate, minimum: 0, maximum: 1),
                envelope(kind: .pitch, values: pitchMIDI, sampleRateHz: frameRate, minimum: 36, maximum: 96),
                envelope(kind: .pitchConfidence, values: pitchConfidence, sampleRateHz: frameRate, minimum: 0, maximum: 1),
                envelope(kind: .vocalActivity, values: vocalActivity, sampleRateHz: frameRate, minimum: 0, maximum: 1),
            ],
            regions: regions,
            confidence: confidence)
        guard let safe = map.validated(
            expectedAudioFingerprint: audioFingerprint,
            expectedDuration: duration) else {
            throw AudioPerformanceAnalysisError.invalidMap
        }
        return safe
    }

    private static func decodeMonoAudio(at url: URL) async throws -> (samples: [Float], sampleRate: Double) {
        do {
            return try await decodePCM(
                at: url,
                settings: pcmOutputSettings(sampleRate: targetSampleRate, channelCount: 1))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Some AAC/MP4 combinations can be decoded by AVFoundation but cannot be
            // sample-rate-converted or downmixed by AVAssetReaderTrackOutput. Retry in
            // the track's native PCM shape, then do the cheap deterministic conversion
            // locally. This remains entirely off the playback path.
        }
        try Task.checkCancellation()
        let native = try await decodePCM(at: url, settings: pcmOutputSettings())
        let mono = try resampleMono(
            native.samples,
            from: native.sampleRate,
            to: targetSampleRate)
        guard !mono.isEmpty else { throw AudioPerformanceAnalysisError.unsupportedAudio }
        return (mono, targetSampleRate)
    }

    private static func pcmOutputSettings(
        sampleRate: Double? = nil,
        channelCount: Int? = nil
    ) -> [String: Any] {
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        if let sampleRate { settings[AVSampleRateKey] = sampleRate }
        if let channelCount { settings[AVNumberOfChannelsKey] = channelCount }
        return settings
    }

    private static func decodePCM(
        at url: URL,
        settings: [String: Any]
    ) async throws -> (samples: [Float], sampleRate: Double) {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AudioPerformanceAnalysisError.unsupportedAudio
        }
        guard let track = tracks.first else { throw AudioPerformanceAnalysisError.unsupportedAudio }
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AudioPerformanceAnalysisError.unsupportedAudio
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        var decoded: DecodedPCM
        if #available(iOS 27.0, macOS 27.0, *) {
            decoded = try await decodeSamples(reader: reader, output: output)
        } else {
            decoded = try decodeSamplesLegacy(reader: reader, output: output)
        }
        guard !decoded.samples.isEmpty,
              decoded.sampleRate.isFinite,
              decoded.sampleRate >= 4_000 else {
            throw AudioPerformanceAnalysisError.unsupportedAudio
        }
        return (decoded.samples, decoded.sampleRate)
    }

    private struct DecodedPCM {
        var samples: [Float] = []
        var sampleRate: Double = 0
        var channelCount: Int = 0
    }

    @available(iOS 27.0, macOS 27.0, *)
    private static func decodeSamples(
        reader: AVAssetReader,
        output: AVAssetReaderTrackOutput
    ) async throws -> DecodedPCM {
        let provider = reader.outputProvider(for: output)
        do {
            try reader.start()
            var decoded = DecodedPCM()
            while let readySample = try await provider.next() {
                try Task.checkCancellation()
                try readySample.withUnsafeSampleBuffer { sampleBuffer in
                    try appendSamples(from: sampleBuffer, to: &decoded)
                }
            }
            guard reader.status == .completed else {
                throw AudioPerformanceAnalysisError.unsupportedAudio
            }
            return decoded
        } catch is CancellationError {
            reader.cancelReading()
            throw CancellationError()
        } catch {
            reader.cancelReading()
            throw AudioPerformanceAnalysisError.unsupportedAudio
        }
    }

    private static func decodeSamplesLegacy(
        reader: AVAssetReader,
        output: AVAssetReaderTrackOutput
    ) throws -> DecodedPCM {
        guard reader.canAdd(output) else { throw AudioPerformanceAnalysisError.unsupportedAudio }
        reader.add(output)
        guard reader.startReading() else { throw AudioPerformanceAnalysisError.unsupportedAudio }
        var decoded = DecodedPCM()
        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            try appendSamples(from: sampleBuffer, to: &decoded)
        }
        guard reader.status == .completed else {
            throw AudioPerformanceAnalysisError.unsupportedAudio
        }
        return decoded
    }

    private static func appendSamples(
        from sampleBuffer: CMSampleBuffer,
        to decoded: inout DecodedPCM
    ) throws {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw AudioPerformanceAnalysisError.unsupportedAudio
        }
        let format = streamDescription.pointee
        let channelCount = Int(format.mChannelsPerFrame)
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mBitsPerChannel == 32,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
              format.mSampleRate.isFinite,
              format.mSampleRate >= 4_000,
              channelCount > 0 else {
            throw AudioPerformanceAnalysisError.unsupportedAudio
        }
        if decoded.sampleRate == 0 {
            decoded.sampleRate = format.mSampleRate
            decoded.channelCount = channelCount
        } else if abs(decoded.sampleRate - format.mSampleRate) > 0.5
                    || decoded.channelCount != channelCount {
            throw AudioPerformanceAnalysisError.unsupportedAudio
        }
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let byteCount = CMBlockBufferGetDataLength(blockBuffer)
        guard byteCount >= MemoryLayout<Float>.size else { return }
        let floatCount = byteCount / MemoryLayout<Float>.size
        guard floatCount.isMultiple(of: channelCount) else {
            throw AudioPerformanceAnalysisError.unsupportedAudio
        }
        let copyByteCount = floatCount * MemoryLayout<Float>.size
        var chunk = [Float](repeating: 0, count: floatCount)
        let status = chunk.withUnsafeMutableBytes { destination in
            CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: copyByteCount,
                destination: destination.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else {
            throw AudioPerformanceAnalysisError.unsupportedAudio
        }
        if channelCount == 1 {
            decoded.samples.append(contentsOf: chunk)
            return
        }
        decoded.samples.reserveCapacity(decoded.samples.count + floatCount / channelCount)
        for frameStart in stride(from: 0, to: floatCount, by: channelCount) {
            var sum: Float = 0
            for channel in 0..<channelCount { sum += chunk[frameStart + channel] }
            decoded.samples.append(sum / Float(channelCount))
        }
    }

    static func resampleMono(
        _ samples: [Float],
        from sourceSampleRate: Double,
        to destinationSampleRate: Double
    ) throws -> [Float] {
        guard !samples.isEmpty,
              sourceSampleRate.isFinite,
              destinationSampleRate.isFinite,
              sourceSampleRate >= 4_000,
              destinationSampleRate >= 4_000 else {
            throw AudioPerformanceAnalysisError.unsupportedAudio
        }
        guard abs(sourceSampleRate - destinationSampleRate) > 0.5 else { return samples }
        let outputCount = max(1, Int(
            (Double(samples.count) * destinationSampleRate / sourceSampleRate).rounded(.down)))
        var output = [Float](repeating: 0, count: outputCount)
        let sourceStep = sourceSampleRate / destinationSampleRate
        for outputIndex in output.indices {
            if outputIndex.isMultiple(of: 65_536) { try Task.checkCancellation() }
            let sourcePosition = min(Double(samples.count - 1), Double(outputIndex) * sourceStep)
            let lower = Int(sourcePosition.rounded(.down))
            let upper = min(samples.count - 1, lower + 1)
            let fraction = Float(sourcePosition - Double(lower))
            output[outputIndex] = samples[lower] + (samples[upper] - samples[lower]) * fraction
        }
        return output
    }

    private struct BeatGridResult {
        let bpm: Double?
        let confidence: Double
        let downbeatConfidence: Double
        let beats: [Double]
        let downbeats: [Double]
    }

    private static func beatGrid(
        onset: [Double],
        energy: [Double],
        frameRate: Double,
        duration: Double
    ) -> BeatGridResult {
        guard onset.count >= 8 else {
            return BeatGridResult(bpm: nil, confidence: 0, downbeatConfidence: 0, beats: [], downbeats: [])
        }
        let minimumLag = max(1, Int((frameRate * 60 / 210).rounded()))
        let maximumLag = min(onset.count / 2, max(minimumLag, Int((frameRate * 60 / 55).rounded())))
        guard maximumLag >= minimumLag else {
            return BeatGridResult(bpm: nil, confidence: 0, downbeatConfidence: 0, beats: [], downbeats: [])
        }
        let zeroLag = max(0.000_001, onset.reduce(0) { $0 + $1 * $1 })
        var bestLag = minimumLag
        var bestScore = 0.0
        for lag in minimumLag...maximumLag {
            var score = 0.0
            for index in lag..<onset.count { score += onset[index] * onset[index - lag] }
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        let confidence = min(1, bestScore / zeroLag * 1.8)
        guard confidence >= 0.05 else {
            return BeatGridResult(bpm: nil, confidence: confidence, downbeatConfidence: 0, beats: [], downbeats: [])
        }
        let phaseScores = (0..<bestLag).map { phase -> Double in
            stride(from: phase, to: onset.count, by: bestLag).reduce(0) { $0 + onset[$1] }
        }
        let phase = phaseScores.indices.max(by: { phaseScores[$0] < phaseScores[$1] }) ?? 0
        let beatIndices = Array(stride(from: phase, to: onset.count, by: bestLag))
        let beats = beatIndices.map { min(duration, Double($0) / frameRate) }
            .filter { $0 < duration }
        let barScores = (0..<4).map { phase -> Double in
            beatIndices.enumerated().reduce(0) { partial, item in
                guard item.offset % 4 == phase else { return partial }
                return partial + onset[item.element] * 0.65 + energy[item.element] * 0.35
            }
        }
        let barPhase = barScores.indices.max(by: { barScores[$0] < barScores[$1] }) ?? 0
        let sortedBarScores = barScores.sorted(by: >)
        let downbeatConfidence = guardRatio(
            numerator: (sortedBarScores.first ?? 0) - (sortedBarScores.dropFirst().first ?? 0),
            denominator: sortedBarScores.first ?? 0)
        let downbeats = beatIndices.enumerated().compactMap { item -> Double? in
            guard item.offset % 4 == barPhase else { return nil }
            let time = Double(item.element) / frameRate
            return time < duration ? time : nil
        }
        return BeatGridResult(
            bpm: 60 * frameRate / Double(bestLag),
            confidence: confidence,
            downbeatConfidence: downbeatConfidence,
            beats: beats,
            downbeats: downbeats)
    }

    private static func pitchEstimate(
        frame: [Float],
        sampleRate: Double
    ) throws -> (midi: Double, confidence: Double) {
        let decimation = 4
        let reduced = stride(from: 0, to: frame.count, by: decimation).map { Double(frame[$0]) }
        guard reduced.count >= 64 else { return (36, 0) }
        let average = mean(reduced)
        let centered = reduced.map { $0 - average }
        let reducedRate = sampleRate / Double(decimation)
        let minimumLag = max(2, Int((reducedRate / 1_000).rounded(.down)))
        let maximumLag = min(centered.count / 2, max(minimumLag, Int((reducedRate / 65).rounded(.up))))
        var bestLag = minimumLag
        var bestScore = 0.0
        for lag in minimumLag...maximumLag {
            if lag.isMultiple(of: 32) { try Task.checkCancellation() }
            var correlation = 0.0
            var lhsEnergy = 0.0
            var rhsEnergy = 0.0
            for index in lag..<centered.count {
                let lhs = centered[index]
                let rhs = centered[index - lag]
                correlation += lhs * rhs
                lhsEnergy += lhs * lhs
                rhsEnergy += rhs * rhs
            }
            let score = correlation / max(0.000_001, sqrt(lhsEnergy * rhsEnergy))
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        guard bestScore >= 0.18 else { return (36, 0) }
        let frequency = reducedRate / Double(bestLag)
        let midi = (69 + 12 * log2(max(1, frequency) / 440)).clamped(to: 36...96)
        return (midi, min(1, max(0, (bestScore - 0.18) / 0.72)))
    }

    private static func acousticSections(
        energy: [Double],
        brightness: [Double],
        frameRate: Double,
        duration: Double
    ) -> [AudioPerformanceRegion] {
        guard !energy.isEmpty else { return [] }
        let radius = max(1, Int((frameRate * 1.8).rounded()))
        let energyPrefix = prefixSums(energy)
        let brightnessPrefix = prefixSums(brightness)
        var novelty = [Double](repeating: 0, count: energy.count)
        for index in radius..<(energy.count - radius) {
            let beforeEnergy = rangeMean(energyPrefix, from: index - radius, to: index)
            let afterEnergy = rangeMean(energyPrefix, from: index, to: index + radius)
            let beforeBrightness = rangeMean(brightnessPrefix, from: index - radius, to: index)
            let afterBrightness = rangeMean(brightnessPrefix, from: index, to: index + radius)
            novelty[index] = abs(afterEnergy - beforeEnergy) * 0.72
                + abs(afterBrightness - beforeBrightness) * 0.28
        }
        let normalizedNovelty = normalized(novelty, low: 0.45, high: 0.98)
        let candidates = localPeakIndices(
            normalizedNovelty,
            threshold: max(0.52, percentile(normalizedNovelty, 0.86)),
            minimumDistance: max(1, Int((frameRate * 8).rounded())))
            .filter {
                let time = Double($0) / frameRate
                return time >= 6 && time <= duration - 6
            }
        let strongest = candidates.sorted { normalizedNovelty[$0] > normalizedNovelty[$1] }
            .prefix(11)
            .sorted()
        let boundaries = [0.0] + strongest.map { Double($0) / frameRate } + [duration]
        return zip(boundaries, boundaries.dropFirst()).enumerated().map { index, pair in
            let boundaryIndex = strongest[safe: max(0, index - 1)]
            let confidence = boundaryIndex.map { normalizedNovelty[$0] } ?? 0.55
            return AudioPerformanceRegion(
                id: "section-\(index)",
                kind: .acousticSection,
                from: pair.0,
                to: pair.1,
                confidence: confidence.clamped(to: 0...1))
        }
    }

    private static func contiguousRegions(
        kind: AudioPerformanceRegionKind,
        values: [Double],
        matching: (Double) -> Bool,
        minimumDuration: Double,
        frameRate: Double,
        duration: Double
    ) -> [AudioPerformanceRegion] {
        var result: [AudioPerformanceRegion] = []
        var start: Int?
        for index in 0...values.count {
            let matches = index < values.count && matching(values[index])
            if matches, start == nil { start = index }
            if !matches, let regionStart = start {
                let from = Double(regionStart) / frameRate
                let to = min(duration, Double(index) / frameRate)
                if to - from >= minimumDuration {
                    result.append(AudioPerformanceRegion(
                        id: "\(kind.rawValue)-\(result.count)",
                        kind: kind,
                        from: from,
                        to: to,
                        confidence: min(1, 0.55 + (to - from) / 8)))
                }
                start = nil
            }
        }
        return result
    }

    private static func envelope(
        kind: AudioPerformanceEnvelopeKind,
        values: [Double],
        sampleRateHz: Double,
        minimum: Double,
        maximum: Double
    ) -> AudioPerformanceEnvelope {
        let span = max(0.000_001, maximum - minimum)
        let bytes = values.map { value -> UInt8 in
            UInt8(((value - minimum) / span * 255).clamped(to: 0...255).rounded())
        }
        return AudioPerformanceEnvelope(
            kind: kind,
            startTime: 0,
            sampleRateHz: sampleRateHz,
            minimum: minimum,
            maximum: maximum,
            samples: Data(bytes))
    }

    private static func normalized(_ values: [Double], low: Double, high: Double) -> [Double] {
        guard !values.isEmpty else { return [] }
        let lower = percentile(values, low)
        let upper = percentile(values, high)
        guard upper > lower + 0.000_000_1 else { return [Double](repeating: 0, count: values.count) }
        return values.map { (($0 - lower) / (upper - lower)).clamped(to: 0...1) }
    }

    private static func localPeakIndices(
        _ values: [Double],
        threshold: Double,
        minimumDistance: Int
    ) -> [Int] {
        guard values.count >= 3 else { return [] }
        let candidates = (1..<(values.count - 1)).filter {
            values[$0] >= values[$0 - 1]
                && values[$0] > values[$0 + 1]
                && values[$0] >= threshold
        }
        var selected: [Int] = []
        for index in candidates.sorted(by: { values[$0] > values[$1] }) {
            if selected.allSatisfy({ abs($0 - index) >= minimumDistance }) {
                selected.append(index)
            }
        }
        return selected.sorted()
    }

    private static func percentile(_ values: [Double], _ quantile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = quantile.clamped(to: 0...1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(sorted.count - 1, lower + 1)
        let fraction = position - Double(lower)
        return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
    }

    private static func prefixSums(_ values: [Double]) -> [Double] {
        values.reduce(into: [0.0]) { partial, value in partial.append((partial.last ?? 0) + value) }
    }

    private static func rangeMean(_ prefix: [Double], from: Int, to: Int) -> Double {
        guard to > from, from >= 0, to < prefix.count else { return 0 }
        return (prefix[to] - prefix[from]) / Double(to - from)
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func guardRatio(numerator: Double, denominator: Double) -> Double {
        guard denominator > 0 else { return 0 }
        return (numerator / denominator).clamped(to: 0...1)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
