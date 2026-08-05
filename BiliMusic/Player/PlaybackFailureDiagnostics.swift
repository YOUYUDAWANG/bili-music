import AVFoundation
import Foundation
import OSLog

private let playbackFailureLog = Logger(
    subsystem: "com.fubuki.BiliMusic",
    category: "playback-failure")

struct PlaybackMediaErrorSnapshot: Equatable, CustomStringConvertible {
    let domain: String
    let code: Int
    let host: String?

    var description: String {
        "mediaDomain=\(domain) mediaCode=\(code) mediaHost=\(host ?? "nil")"
    }
}

struct PlaybackFailureSnapshot: Equatable, CustomStringConvertible {
    enum Trigger: String {
        case itemStatus
        case failedToEnd
        case freshResolution
    }

    let trigger: Trigger
    let bvid: String
    let cid: Int?
    let sourceKind: PlaybackDiagnosticEvent.SourceKind
    let host: String?
    let candidateCount: Int
    let errorDomain: String?
    let errorCode: Int?
    let errorMessage: String?
    let underlyingDomain: String?
    let underlyingCode: Int?
    let mediaErrors: [PlaybackMediaErrorSnapshot]

    init(
        trigger: Trigger,
        bvid: String,
        cid: Int?,
        sourceKind: PlaybackDiagnosticEvent.SourceKind,
        host: String?,
        candidateCount: Int,
        error: Error?,
        mediaErrors: [PlaybackMediaErrorSnapshot] = []
    ) {
        let nsError = error as NSError?
        let underlying = nsError?.userInfo[NSUnderlyingErrorKey] as? NSError
        self.trigger = trigger
        self.bvid = bvid
        self.cid = cid
        self.sourceKind = sourceKind
        self.host = host
        self.candidateCount = candidateCount
        self.errorDomain = nsError?.domain
        self.errorCode = nsError?.code
        self.errorMessage = Self.sanitizedMessage(nsError?.localizedDescription)
        self.underlyingDomain = underlying?.domain
        self.underlyingCode = underlying?.code
        self.mediaErrors = mediaErrors
    }

    var description: String {
        let media = mediaErrors.isEmpty
            ? "mediaErrors=none"
            : "mediaErrors=[\(mediaErrors.map(\.description).joined(separator: ";"))]"
        return [
            "trigger=\(trigger.rawValue)",
            "bvid=\(bvid)",
            "cid=\(cid.map(String.init) ?? "nil")",
            "source=\(sourceKind.rawValue)",
            "host=\(host ?? "nil")",
            "candidates=\(candidateCount)",
            "errorDomain=\(errorDomain ?? "nil")",
            "errorCode=\(errorCode.map(String.init) ?? "nil")",
            "message=\(errorMessage ?? "nil")",
            "underlyingDomain=\(underlyingDomain ?? "nil")",
            "underlyingCode=\(underlyingCode.map(String.init) ?? "nil")",
            media
        ].joined(separator: " ")
    }

    private static func sanitizedMessage(_ message: String?) -> String? {
        guard let message else { return nil }
        let singleLine = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard !singleLine.localizedCaseInsensitiveContains("http://"),
              !singleLine.localizedCaseInsensitiveContains("https://") else {
            return "<redacted-url>"
        }
        return String(singleLine.prefix(160))
    }
}

struct PlaybackCDNProbeSnapshot: Equatable, CustomStringConvertible {
    let host: String
    let statusCode: Int?
    let mimeType: String?
    let receivedByte: Bool
    let milliseconds: Double
    let errorDomain: String?
    let errorCode: Int?

    var description: String {
        [
            "host=\(host)",
            "status=\(statusCode.map(String.init) ?? "nil")",
            "mime=\(mimeType ?? "nil")",
            "receivedByte=\(receivedByte)",
            "elapsedMs=\(String(format: "%.1f", milliseconds))",
            "errorDomain=\(errorDomain ?? "nil")",
            "errorCode=\(errorCode.map(String.init) ?? "nil")"
        ].joined(separator: " ")
    }
}

enum PlaybackFailureDiagnostics {
    enum RetryAction: String {
        case candidateFallback
        case invalidatePrepared
        case freshResolved
        case surfaceFailure
    }

    static func report(
        trigger: PlaybackFailureSnapshot.Trigger,
        source: PlaybackSource,
        error: Error?,
        item: AVPlayerItem?
    ) {
        let mediaErrors = item?.errorLog()?.events.suffix(4).map {
            PlaybackMediaErrorSnapshot(
                domain: $0.errorDomain,
                code: $0.errorStatusCode,
                host: $0.uri.flatMap(URL.init(string:))?.host)
        } ?? []
        let snapshot = PlaybackFailureSnapshot(
            trigger: trigger,
            bvid: source.track.bvid,
            cid: source.track.cid,
            sourceKind: source.kind,
            host: source.url.host(),
            candidateCount: source.candidateURLs.count,
            error: error,
            mediaErrors: mediaErrors)
        emit("PLAYBACK_FAILURE \(snapshot.description)")

        let candidates = Array(AudioCDNSelector.deduped(source.candidateURLs).prefix(4))
        guard !source.isLocal, !candidates.isEmpty else { return }
        Task.detached(priority: .utility) {
            let probes = await probe(candidates: candidates)
            for probe in probes {
                emit("PLAYBACK_CDN_PROBE bvid=\(source.track.bvid) cid=\(source.track.cid.map(String.init) ?? "nil") \(probe.description)")
            }
        }
    }

    static func reportRetry(
        _ action: RetryAction,
        source: PlaybackSource,
        targetURL: URL? = nil
    ) {
        emit([
            "PLAYBACK_RETRY",
            "action=\(action.rawValue)",
            "bvid=\(source.track.bvid)",
            "cid=\(source.track.cid.map(String.init) ?? "nil")",
            "source=\(source.kind.rawValue)",
            "fromHost=\(source.url.host() ?? "nil")",
            "toHost=\(targetURL?.host() ?? "nil")"
        ].joined(separator: " "))
    }

    private static func probe(candidates: [URL]) async -> [PlaybackCDNProbeSnapshot] {
        await withTaskGroup(of: PlaybackCDNProbeSnapshot.self, returning: [PlaybackCDNProbeSnapshot].self) { group in
            for url in candidates {
                group.addTask {
                    await probe(url: url)
                }
            }
            var results: [PlaybackCDNProbeSnapshot] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.host < $1.host }
        }
    }

    private static func probe(url: URL) async -> PlaybackCDNProbeSnapshot {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        BiliClient.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let startedAt = CFAbsoluteTimeGetCurrent()
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            var iterator = bytes.makeAsyncIterator()
            let firstByte = try await iterator.next()
            let http = response as? HTTPURLResponse
            return PlaybackCDNProbeSnapshot(
                host: url.host() ?? "nil",
                statusCode: http?.statusCode,
                mimeType: http?.mimeType,
                receivedByte: firstByte != nil,
                milliseconds: (CFAbsoluteTimeGetCurrent() - startedAt) * 1000,
                errorDomain: nil,
                errorCode: nil)
        } catch {
            let nsError = error as NSError
            return PlaybackCDNProbeSnapshot(
                host: url.host() ?? "nil",
                statusCode: nil,
                mimeType: nil,
                receivedByte: false,
                milliseconds: (CFAbsoluteTimeGetCurrent() - startedAt) * 1000,
                errorDomain: nsError.domain,
                errorCode: nsError.code)
        }
    }

    private static func emit(_ message: String) {
        playbackFailureLog.error("\(message, privacy: .public)")
#if DEBUG
        print(message)
#endif
    }
}
