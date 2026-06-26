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

    final class FanoutSink: PlaybackDiagnosticSink {
        private let sinks: [PlaybackDiagnosticSink]

        init(_ sinks: [PlaybackDiagnosticSink]) {
            self.sinks = sinks
        }

        func record(_ event: PlaybackDiagnosticEvent) {
            for sink in sinks {
                sink.record(event)
            }
        }
    }

    final class InMemorySink: PlaybackDiagnosticSink {
        private(set) var events: [PlaybackDiagnosticEvent] = []

        func record(_ event: PlaybackDiagnosticEvent) {
            events.append(event)
        }
    }

#if DEBUG
    final class DebugRecentEventStore: PlaybackDiagnosticSink {
        static let shared = DebugRecentEventStore()

        private let lock = NSLock()
        private let capacity: Int
        private var events: [PlaybackDiagnosticEvent] = []

        init(capacity: Int = 60) {
            self.capacity = max(1, capacity)
        }

        func record(_ event: PlaybackDiagnosticEvent) {
            lock.withLock {
                events.append(event)
                if events.count > capacity {
                    events.removeFirst(events.count - capacity)
                }
            }
        }

        func snapshot() -> [PlaybackDiagnosticEvent] {
            lock.withLock { events }
        }

        func clear() {
            lock.withLock {
                events.removeAll(keepingCapacity: true)
            }
        }
    }
#endif

    private let sink: PlaybackDiagnosticSink
    private let clock: Clock
    private var startedAt: TimeInterval?
    private var activeTrackKey: String?

    init(sink: PlaybackDiagnosticSink? = nil, clock: @escaping Clock = { CFAbsoluteTimeGetCurrent() }) {
        self.sink = sink ?? Self.defaultSink()
        self.clock = clock
    }

    private static func defaultSink() -> PlaybackDiagnosticSink {
#if DEBUG
        FanoutSink([OSLogSink(), DebugRecentEventStore.shared])
#else
        OSLogSink()
#endif
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
