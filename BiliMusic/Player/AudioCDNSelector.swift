import Foundation
import OSLog

private let cdnLog = Logger(subsystem: "com.fubuki.BiliMusic", category: "cdn")

enum AudioCDNSelector {
    private enum ProbeResult {
        case reachable(URL)
        case failed
        case timedOut
    }

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

    static func fastestReachableURL(
        from urls: [URL],
        timeout: Duration = .milliseconds(900)
    ) async -> URL? {
        let candidates = deduped(urls)
        guard !candidates.isEmpty else { return nil }

        return await withTaskGroup(of: ProbeResult.self) { group in
            for url in candidates {
                group.addTask {
                    await probe(url: url, timeout: timeout)
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timedOut
            }

            for await result in group {
                switch result {
                case .reachable(let url):
                    group.cancelAll()
                    return url
                case .timedOut:
                    group.cancelAll()
                    return nil
                case .failed:
                    continue
                }
            }
            return nil
        }
    }

    private static func probe(url: URL, timeout: Duration) async -> ProbeResult {
        guard !Task.isCancelled else { return .failed }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        BiliClient.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.timeoutInterval = timeout.timeInterval

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard !Task.isCancelled else { return .failed }
            guard let http = response as? HTTPURLResponse else { return .failed }
            if (200...299).contains(http.statusCode) || http.statusCode == 206 {
                var iterator = bytes.makeAsyncIterator()
                _ = try await iterator.next()
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                cdnLog.debug("probe ok host=\(url.host() ?? "nil", privacy: .public) status=\(http.statusCode) \(elapsed, format: .fixed(precision: 1))ms")
                return .reachable(url)
            }
            cdnLog.debug("probe rejected host=\(url.host() ?? "nil", privacy: .public) status=\(http.statusCode)")
            return .failed
        } catch {
            cdnLog.debug("probe failed host=\(url.host() ?? "nil", privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
