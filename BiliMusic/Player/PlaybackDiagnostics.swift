import Foundation
import OSLog

private let playbackDiagnosticsLog = Logger(subsystem: "com.fubuki.BiliMusic", category: "playback-diagnostics")

struct PlaybackDiagnosticEvent: Equatable, CustomStringConvertible {
    enum Checkpoint: String, CaseIterable {
        case tap
        case currentAssigned
        case sourceResolved
        case playerItemCreated
        case playRequested
        case firstPlaying
    }

    enum SourceKind: String {
        case localCache
        case preparedRemote
        case freshRemote
        case mvRemote
    }

    let checkpoint: Checkpoint
    let bvid: String
    let cid: Int?
    let sourceKind: SourceKind?
    let qualityLabel: String?
    let bandwidth: Int?
    let elapsedMilliseconds: Double

    var description: String {
        [
            "checkpoint=\(checkpoint.rawValue)",
            "bvid=\(bvid)",
            "cid=\(cid.map(String.init) ?? "nil")",
            "source=\(sourceKind?.rawValue ?? "nil")",
            "quality=\(qualityLabel ?? "nil")",
            "bandwidth=\(bandwidth.map(String.init) ?? "nil")",
            "elapsedMs=\(String(format: "%.1f", elapsedMilliseconds))"
        ].joined(separator: " ")
    }
}

protocol PlaybackDiagnosticSink: AnyObject {
    func record(_ event: PlaybackDiagnosticEvent)
}

final class PlaybackDiagnostics {
    typealias Clock = () -> TimeInterval

    final class OSLogSink: PlaybackDiagnosticSink {
        func record(_ event: PlaybackDiagnosticEvent) {
            playbackDiagnosticsLog.debug("\(event.description, privacy: .public)")
        }
    }

    final class InMemorySink: PlaybackDiagnosticSink {
        private(set) var events: [PlaybackDiagnosticEvent] = []

        func record(_ event: PlaybackDiagnosticEvent) {
            events.append(event)
        }
    }

    private let sink: PlaybackDiagnosticSink
    private let clock: Clock
    private var startedAt: TimeInterval?
    private var activeTrackKey: String?

    init(sink: PlaybackDiagnosticSink = OSLogSink(), clock: @escaping Clock = { CFAbsoluteTimeGetCurrent() }) {
        self.sink = sink
        self.clock = clock
    }

    func begin(track: Track) {
        startedAt = clock()
        activeTrackKey = track.key.description
    }

    func record(
        _ checkpoint: PlaybackDiagnosticEvent.Checkpoint,
        track: Track,
        sourceKind: PlaybackDiagnosticEvent.SourceKind? = nil,
        quality: Int? = nil,
        bandwidth: Int? = nil
    ) {
        let now = clock()
        let trackKey = track.key.description
        if activeTrackKey != trackKey {
            startedAt = now
            activeTrackKey = trackKey
        }
        let start = startedAt ?? now
        if startedAt == nil {
            startedAt = now
            activeTrackKey = trackKey
        }
        sink.record(PlaybackDiagnosticEvent(
            checkpoint: checkpoint,
            bvid: track.bvid,
            cid: track.cid,
            sourceKind: sourceKind,
            qualityLabel: quality.map(String.init),
            bandwidth: bandwidth,
            elapsedMilliseconds: max(0, (now - start) * 1000)))
    }
}
