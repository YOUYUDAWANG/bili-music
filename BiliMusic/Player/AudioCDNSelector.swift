import Foundation
import OSLog

private let cdnLog = Logger(subsystem: "com.fubuki.BiliMusic", category: "cdn")

enum AudioCDNSelector {
    static let preferredHostDefaultsKey = "preferredAudioCDNHost"

    struct Measurement: Identifiable, Equatable {
        let host: String
        let milliseconds: Double?
        let reachable: Bool

        var id: String { host }
    }

    private enum ProbeResult {
        case reachable(URL, milliseconds: Double)
        case failed(URL)
        case timedOut
    }

    private static let hostHealth = AudioCDNHostHealth()

    static func deduped(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let key = url.absoluteString
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(url)
        }
        return result
    }

    static func fallbackCandidates(from urls: [URL], excluding current: URL) -> [URL] {
        deduped(urls).filter { $0.absoluteString != current.absoluteString }
    }

    static func rankedCandidates(_ urls: [URL]) async -> [URL] {
        let ranked = await hostHealth.ranked(deduped(urls))
        return applyPreferredHost(to: ranked)
    }

    static func preferredURL(from urls: [URL]) -> URL? {
        guard let preferredHost = preferredHost else { return nil }
        return deduped(urls).first { $0.host()?.caseInsensitiveCompare(preferredHost) == .orderedSame }
    }

    static func recordPlaybackSuccess(url: URL) async {
        await hostHealth.recordSuccess(url: url, milliseconds: nil)
    }

    static func recordPlaybackFailure(url: URL) async {
        await hostHealth.recordFailure(url: url)
    }

    static func fastestReachableURL(
        from urls: [URL],
        timeout: Duration = .milliseconds(900),
        maxConcurrentProbes: Int = 4
    ) async -> URL? {
        let candidates = await rankedCandidates(urls)
        let probeCandidates = Array(candidates.prefix(max(1, maxConcurrentProbes)))
        guard !probeCandidates.isEmpty else { return nil }

        return await withTaskGroup(of: ProbeResult.self) { group in
            for url in probeCandidates {
                group.addTask {
                    await probe(url: url, timeout: timeout)
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timedOut
            }

            var failedCount = 0
            for await result in group {
                switch result {
                case .reachable(let url, let milliseconds):
                    await hostHealth.recordSuccess(url: url, milliseconds: milliseconds)
                    group.cancelAll()
                    return url
                case .timedOut:
                    group.cancelAll()
                    return nil
                case .failed(let url):
                    await hostHealth.recordFailure(url: url)
                    failedCount += 1
                    // 所有 probe 都已失败时不必等满 timeout,立即返回。
                    if failedCount == probeCandidates.count {
                        group.cancelAll()
                        return nil
                    }
                    continue
                }
            }
            return nil
        }
    }

    static func measureCandidates(
        from urls: [URL],
        timeout: Duration = .milliseconds(1200),
        maxConcurrentProbes: Int = 6
    ) async -> [Measurement] {
        let candidates = Array(dedupedByHost(deduped(urls)).prefix(max(1, maxConcurrentProbes)))
        guard !candidates.isEmpty else { return [] }

        var measurements: [Measurement] = []
        await withTaskGroup(of: ProbeResult.self) { group in
            for url in candidates {
                group.addTask {
                    await probe(url: url, timeout: timeout)
                }
            }

            for await result in group {
                switch result {
                case .reachable(let url, let milliseconds):
                    await hostHealth.recordSuccess(url: url, milliseconds: milliseconds)
                    measurements.append(Measurement(
                        host: url.host() ?? url.absoluteString,
                        milliseconds: milliseconds,
                        reachable: true))
                case .failed(let url):
                    await hostHealth.recordFailure(url: url)
                    measurements.append(Measurement(
                        host: url.host() ?? url.absoluteString,
                        milliseconds: nil,
                        reachable: false))
                case .timedOut:
                    break
                }
            }
        }

        return measurements.sorted { lhs, rhs in
            switch (lhs.reachable, rhs.reachable) {
            case (true, false): return true
            case (false, true): return false
            case (true, true):
                return (lhs.milliseconds ?? .greatestFiniteMagnitude) < (rhs.milliseconds ?? .greatestFiniteMagnitude)
            case (false, false):
                return lhs.host.localizedStandardCompare(rhs.host) == .orderedAscending
            }
        }
    }

    private static func probe(url: URL, timeout: Duration) async -> ProbeResult {
        guard !Task.isCancelled else { return .failed(url) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        BiliClient.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.timeoutInterval = timeout.timeInterval

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard !Task.isCancelled else { return .failed(url) }
            guard let http = response as? HTTPURLResponse else { return .failed(url) }
            if (200...299).contains(http.statusCode) || http.statusCode == 206 {
                var iterator = bytes.makeAsyncIterator()
                _ = try await iterator.next()
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                cdnLog.debug("probe ok host=\(url.host() ?? "nil", privacy: .public) status=\(http.statusCode) \(elapsed, format: .fixed(precision: 1))ms")
                return .reachable(url, milliseconds: elapsed)
            }
            cdnLog.debug("probe rejected host=\(url.host() ?? "nil", privacy: .public) status=\(http.statusCode)")
            return .failed(url)
        } catch {
            cdnLog.debug("probe failed host=\(url.host() ?? "nil", privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return .failed(url)
        }
    }

    private static var preferredHost: String? {
        let raw = UserDefaults.standard.string(forKey: preferredHostDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private static func applyPreferredHost(to urls: [URL]) -> [URL] {
        guard let preferredHost else { return urls }
        let preferred = urls.filter { $0.host()?.caseInsensitiveCompare(preferredHost) == .orderedSame }
        guard !preferred.isEmpty else { return urls }
        let rest = urls.filter { $0.host()?.caseInsensitiveCompare(preferredHost) != .orderedSame }
        return preferred + rest
    }

    private static func dedupedByHost(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let host = url.host() ?? url.absoluteString
            let key = host.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(url)
        }
        return result
    }

#if DEBUG
    static func resetHostHealthForTesting() async {
        await hostHealth.reset()
        UserDefaults.standard.removeObject(forKey: preferredHostDefaultsKey)
    }

    static func recordProbeSuccessForTesting(url: URL, milliseconds: Double) async {
        await hostHealth.recordSuccess(url: url, milliseconds: milliseconds)
    }

    static func recordProbeFailureForTesting(url: URL) async {
        await hostHealth.recordFailure(url: url)
    }

    static func setPreferredHostForTesting(_ host: String?) {
        if let host, !host.isEmpty {
            UserDefaults.standard.set(host, forKey: preferredHostDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: preferredHostDefaultsKey)
        }
    }
#endif
}

private actor AudioCDNHostHealth {
    private struct Stats {
        var successes = 0
        var failures = 0
        var ewmaMilliseconds: Double?
    }

    private var statsByHost: [String: Stats] = [:]

    func ranked(_ urls: [URL]) -> [URL] {
        urls.enumerated().sorted { lhs, rhs in
            let leftScore = score(for: lhs.element)
            let rightScore = score(for: rhs.element)
            if leftScore == rightScore {
                return lhs.offset < rhs.offset
            }
            return leftScore > rightScore
        }.map(\.element)
    }

    func recordSuccess(url: URL, milliseconds: Double?) {
        guard let host = url.host(), !host.isEmpty else { return }
        var stats = statsByHost[host] ?? Stats()
        stats.successes += 1
        stats.failures = max(0, stats.failures - 1)
        if let milliseconds {
            if let existing = stats.ewmaMilliseconds {
                stats.ewmaMilliseconds = existing * 0.7 + milliseconds * 0.3
            } else {
                stats.ewmaMilliseconds = milliseconds
            }
        }
        statsByHost[host] = stats
    }

    func recordFailure(url: URL) {
        guard let host = url.host(), !host.isEmpty else { return }
        var stats = statsByHost[host] ?? Stats()
        stats.failures += 1
        statsByHost[host] = stats
    }

    func reset() {
        statsByHost.removeAll(keepingCapacity: true)
    }

    private func score(for url: URL) -> Double {
        guard let host = url.host(), let stats = statsByHost[host] else { return 0 }
        let latencyScore = stats.ewmaMilliseconds.map { max(-120, 120 - $0 / 5) } ?? 30
        return latencyScore
            + Double(stats.successes) * 25
            - Double(stats.failures) * 220
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
