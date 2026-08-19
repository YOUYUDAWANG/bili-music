import AVFoundation
import Foundation

/// 整段平移校准：用歌词落点在视频里是否站得住来打分，有本地音频时再和能量/onset 互相关。
/// 时长差只当弱先验，用来分辨片头还是片尾，而不是直接当成偏移。
/// 不能修变速翻唱或句间节奏不同的版本。
enum LyricsOffsetEstimator {
    struct Suggestion: Equatable, Sendable {
        var offsetMilliseconds: Int
        var confidence: Double
    }

    static let hop = 0.05
    static let minAbsMilliseconds = 150
    static let maxAbsSeconds = 10.0

    static func suggestedOffsetMilliseconds(
        trackDuration: Int,
        lyricsDuration: Int?,
        lineStarts: [Double],
        timingKind: LyricsTimingKind,
        wordStarts: [Double] = [],
        audioRMS: [Double]? = nil
    ) -> Int? {
        suggest(
            trackDuration: trackDuration,
            lyricsDuration: lyricsDuration,
            lineStarts: lineStarts,
            timingKind: timingKind,
            wordStarts: wordStarts,
            audioRMS: audioRMS)?.offsetMilliseconds
    }

    static func suggestedOffsetMilliseconds(
        for document: LyricsDocument,
        trackDuration: Int,
        audioRMS: [Double]? = nil
    ) -> Int? {
        suggest(for: document, trackDuration: trackDuration, audioRMS: audioRMS)?.offsetMilliseconds
    }

    static func suggest(
        for document: LyricsDocument,
        trackDuration: Int,
        audioRMS: [Double]? = nil,
        allowStructure: Bool = true
    ) -> Suggestion? {
        let lines = LyricsParser.lines(from: document, duration: trackDuration)
        let wordStarts = lines.flatMap { $0.words.map(\.from) }
        return suggest(
            trackDuration: trackDuration,
            lyricsDuration: document.result.duration,
            lineStarts: sungLineStarts(lines),
            timingKind: document.timingKind,
            wordStarts: wordStarts,
            audioRMS: audioRMS,
            allowStructure: allowStructure)
    }

    static func suggest(
        trackDuration: Int,
        lyricsDuration: Int?,
        lineStarts: [Double],
        timingKind: LyricsTimingKind,
        wordStarts: [Double] = [],
        audioRMS: [Double]? = nil,
        allowStructure: Bool = true
    ) -> Suggestion? {
        guard timingKind != .none, trackDuration > 0 else { return nil }
        let timed = lineStarts.filter { $0 >= 0 }.sorted()
        guard timed.count >= 3 else { return nil }
        let first = timed[0]
        let last = timed[timed.count - 1]
        let span = last - first
        let track = Double(trackDuration)
        let coversCatalog: Bool = {
            if let lyricsDuration, lyricsDuration > 0 {
                return span >= Double(lyricsDuration) * 0.4 && last <= Double(lyricsDuration) + 8
            }
            return span >= min(40, track * 0.35)
        }()

        if let audioRMS, let audio = audioSuggestion(
            rms: audioRMS,
            lyricOnsets: wordStarts.isEmpty ? timed : (timed + wordStarts).sorted(),
            lyricsDuration: lyricsDuration,
            trackDuration: track
        ), audio.confidence >= 0.42 {
            return audio
        }

        guard allowStructure, coversCatalog else { return nil }
        return structureSuggestion(
            first: first,
            last: last,
            trackDuration: track,
            lyricsDuration: lyricsDuration)
    }

    static func sungLineStarts(_ lines: [LyricsLinePayload]) -> [Double] {
        lines.compactMap { line in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.from < 0.45, isCreditLine(text) { return nil }
            if line.from < 0.2, text.count <= 1 { return nil }
            return line.from
        }
    }

    private static func structureSuggestion(
        first: Double,
        last: Double,
        trackDuration: Double,
        lyricsDuration: Int?
    ) -> Suggestion? {
        let maxSteps = Int((maxAbsSeconds / hop).rounded())
        var scored: [(lag: Double, score: Double)] = []
        scored.reserveCapacity(maxSteps * 2 + 1)
        var zeroScore = 0.0
        for step in -maxSteps...maxSteps {
            let lag = Double(step) * hop
            let score = structureScore(
                offset: lag,
                first: first,
                last: last,
                trackDuration: trackDuration,
                lyricsDuration: lyricsDuration)
            scored.append((lag, score))
            if step == 0 { zeroScore = score }
        }
        guard let best = scored.max(by: { $0.score < $1.score }) else { return nil }
        let secondScore = scored
            .filter { abs($0.lag - best.lag) > 0.45 }
            .map(\.score)
            .max() ?? -1_000

        let snapped = snap(best.lag)
        if abs(snapped) < Double(minAbsMilliseconds) / 1000 {
            return nil
        }
        let beatsZero = best.score >= zeroScore + 0.28
        let sharp = best.score >= secondScore + 0.05
        guard beatsZero, sharp else { return nil }
        let confidence = min(0.9, 0.4 + (best.score - zeroScore) * 0.22 + (best.score - secondScore) * 0.15)
        return Suggestion(offsetMilliseconds: milliseconds(snapped), confidence: confidence)
    }

    static func structureScore(
        offset: Double,
        first: Double,
        last: Double,
        trackDuration: Double,
        lyricsDuration: Int?
    ) -> Double {
        let videoFirst = first - offset
        let videoLast = last - offset
        var score = 0.0

        if videoFirst < -0.2 {
            score -= 9 * abs(videoFirst + 0.2)
        }
        if videoLast > trackDuration + 0.6 {
            score -= 7 * (videoLast - trackDuration - 0.6)
        }

        score += introPlausibility(videoFirst)
        score += outroPlausibility(trackDuration - videoLast)
        score += 0.28 * gaussian(offset, sigma: 0.5)

        guard let lyricsDuration, lyricsDuration > 0 else { return score }
        let catalog = Double(lyricsDuration)
        let extraVideo = trackDuration - catalog
        let catalogTail = catalog - last
        let durationOffset = catalog - trackDuration

        if abs(extraVideo) <= maxAbsSeconds, abs(extraVideo) >= 2 {
            let introPrior: Double
            if first < 4.5 {
                introPrior = extraVideo > 0 ? 1.85 : 0.35
            } else if first < 9 {
                introPrior = extraVideo > 0 ? 0.7 : 0.9
            } else {
                introPrior = extraVideo > 0 ? 0.28 : 1.35
            }
            score += introPrior * gaussian(offset - durationOffset, sigma: 1.05)

            let outroPrior: Double
            if extraVideo > 2, catalogTail > 8, first > 7 {
                outroPrior = 1.45
            } else if extraVideo > 2, first < 4.5 {
                outroPrior = 0.18
            } else if extraVideo > 2 {
                outroPrior = 0.55
            } else {
                outroPrior = 0.2
            }
            score += outroPrior * gaussian(offset, sigma: 0.55)
        }

        return score
    }

    private static func audioSuggestion(
        rms: [Double],
        lyricOnsets: [Double],
        lyricsDuration: Int?,
        trackDuration: Double
    ) -> Suggestion? {
        let hop = Self.hop
        guard rms.count >= 80, lyricOnsets.count >= 3 else { return nil }
        let novelty = onsetNovelty(rms)
        let normalizedAudio = unitEnergy(novelty)
        let (peakLag, peak, ratio, zero) = bestCorrelationLag(
            audio: normalizedAudio,
            hop: hop,
            lyricOnsets: lyricOnsets)

        var score = peak
        if let intro = firstSustainedEnergy(rms, hop: hop),
           intro >= 0.35, intro <= maxAbsSeconds {
            score += 0.16 * gaussian(peakLag + intro, sigma: 0.45)
        }
        if let lyricsDuration {
            let prior = Double(lyricsDuration) - trackDuration
            if abs(prior) <= maxAbsSeconds {
                score += 0.1 * gaussian(peakLag - prior, sigma: 1.1)
            }
        }

        guard peak >= 0.05, ratio >= 1.12, score >= 0.07 else { return nil }
        let snapped = snap(peakLag)
        let confidence = min(0.96, 0.38 + peak * 1.8 + (ratio - 1) * 0.7)
        if abs(snapped) < Double(minAbsMilliseconds) / 1000 {
            return Suggestion(offsetMilliseconds: 0, confidence: confidence)
        }
        guard peak >= zero * 1.12 else { return nil }
        return Suggestion(offsetMilliseconds: milliseconds(snapped), confidence: confidence)
    }

    static func onsetNovelty(_ rms: [Double]) -> [Double] {
        guard rms.count >= 2 else { return rms }
        let sorted = rms.sorted()
        let floor = sorted[min(sorted.count / 2, sorted.count - 1)]
        var out = Array(repeating: 0.0, count: rms.count)
        for i in 1..<rms.count {
            let lifted = max(0, rms[i] - floor * 1.35)
            let previous = max(0, rms[i - 1] - floor * 1.35)
            out[i] = 0.78 * max(0, lifted - previous) + 0.22 * lifted
        }
        return out
    }

    static func bestCorrelationLag(
        audio: [Double],
        hop: Double,
        lyricOnsets: [Double]
    ) -> (lag: Double, peak: Double, ratio: Double, zero: Double) {
        let maxLagSteps = Int((maxAbsSeconds / hop).rounded())
        let gridStart = -maxAbsSeconds
        let lastLyric = lyricOnsets.max() ?? 0
        let lyricCount = Int(((lastLyric - gridStart) + maxAbsSeconds) / hop) + 4
        var lyric = Array(repeating: 0.0, count: max(lyricCount, 8))
        for onset in lyricOnsets {
            let center = Int(((onset - gridStart) / hop).rounded())
            for delta in -2...2 {
                let index = center + delta
                guard lyric.indices.contains(index) else { continue }
                lyric[index] += 1 - Double(abs(delta)) / 3
            }
        }
        lyric = unitEnergy(lyric)

        var bestLag = 0.0
        var best = -1.0
        var second = -1.0
        var zero = 0.0
        for step in -maxLagSteps...maxLagSteps {
            let lag = Double(step) * hop
            var sum = 0.0
            for i in audio.indices {
                let lyricTime = Double(i) * hop + lag
                let j = Int(((lyricTime - gridStart) / hop).rounded())
                if lyric.indices.contains(j) {
                    sum += audio[i] * lyric[j]
                }
            }
            if step == 0 { zero = sum }
            if sum > best {
                if abs(lag - bestLag) > 0.35 {
                    second = best
                }
                best = sum
                bestLag = lag
            } else if sum > second, abs(lag - bestLag) > 0.35 {
                second = sum
            }
        }
        let ratio = second > 0.02 ? best / second : 8
        return (bestLag, best, ratio, zero)
    }

    static func firstSustainedEnergy(_ rms: [Double], hop: Double) -> Double? {
        let probe = Array(rms.prefix(max(6, Int(0.6 / hop))))
        let sorted = probe.sorted()
        let noise = sorted[min(sorted.count / 3, max(sorted.count - 1, 0))] 
        let threshold = max(0.018, noise * 3.2)
        var run = 0
        for (index, value) in rms.enumerated() {
            if value >= threshold {
                run += 1
                if run >= 8 {
                    return Double(index - 7) * hop
                }
            } else {
                run = 0
            }
        }
        return nil
    }

    static func rmsEnvelope(from url: URL, hop: Double = hop, maxSeconds: Double = 36) -> [Double]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 8000 else { return nil }
        let readable = min(Double(file.length), sampleRate * maxSeconds)
        let maxFrames = AVAudioFrameCount(readable)
        guard maxFrames > AVAudioFrameCount(sampleRate * 6) else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maxFrames) else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }
        let frames = Int(buffer.frameLength)
        let hopFrames = max(1, Int(sampleRate * hop))
        let channels = Int(format.channelCount)
        guard let samples = buffer.floatChannelData else { return nil }

        var rms: [Double] = []
        rms.reserveCapacity(frames / hopFrames)
        var start = 0
        while start + hopFrames <= frames {
            var acc = 0.0
            for frame in 0..<hopFrames {
                var mixed = 0.0
                for channel in 0..<max(channels, 1) {
                    mixed += Double(samples[channel][start + frame])
                }
                mixed /= Double(max(channels, 1))
                acc += mixed * mixed
            }
            rms.append(sqrt(acc / Double(hopFrames)))
            start += hopFrames
        }
        return rms.count >= 80 ? rms : nil
    }

    private static func unitEnergy(_ values: [Double]) -> [Double] {
        let mean = values.reduce(0, +) / Double(max(values.count, 1))
        let centered = values.map { max(0, $0 - mean * 0.15) }
        let norm = sqrt(centered.reduce(0) { $0 + $1 * $1 })
        guard norm > 1e-8 else { return centered }
        return centered.map { $0 / norm }
    }

    private static func introPlausibility(_ time: Double) -> Double {
        if time < 0 { return -2.2 }
        if time < 20 { return 1.15 - time / 36 }
        if time < 30 { return 0.25 }
        return -0.35 * (time - 30) / 8
    }

    private static func outroPlausibility(_ time: Double) -> Double {
        if time < -0.6 { return -3.2 }
        if time < 0 { return -0.4 }
        if time < 24 { return 1.05 }
        if time < 36 { return 0.25 }
        return -0.15
    }

    private static func isCreditLine(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        return ["作词", "作曲", "编曲", "作詞", "演唱", "歌词", "Lyric", "Composer"].contains { compact.contains($0) }
    }

    private static func gaussian(_ x: Double, sigma: Double) -> Double {
        exp(-0.5 * pow(x / max(sigma, 0.05), 2))
    }

    private static func snap(_ seconds: Double) -> Double {
        (seconds * 20).rounded() / 20
    }

    private static func milliseconds(_ seconds: Double) -> Int {
        let value = Int((seconds * 1000).rounded())
        return min(max(value, -10_000), 10_000)
    }
}
