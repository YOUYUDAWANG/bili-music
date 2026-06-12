import Foundation
import Observation

@Observable
@MainActor
final class PlaybackHistoryStore {
    static let shared = PlaybackHistoryStore()

    private(set) var entries: [PlaybackHistoryEntry] = []
    private let fileURL: URL

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playback-history.json")
        load()
    }

    func record(_ track: Track) {
        if let index = entries.firstIndex(where: { $0.bvid == track.bvid }) {
            entries[index].playCount += 1
            entries[index].lastPlayedAt = Date()
            entries[index].track = track
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
        } else {
            entries.insert(PlaybackHistoryEntry(track: track, playCount: 1, lastPlayedAt: Date()), at: 0)
        }
        if entries.count > 300 {
            entries.removeLast(entries.count - 300)
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([PlaybackHistoryEntry].self, from: data) else { return }
        entries = decoded.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

struct PlaybackHistoryEntry: Identifiable, Codable, Equatable {
    var track: Track
    var playCount: Int
    var lastPlayedAt: Date

    var id: String { track.bvid }
    var bvid: String { track.bvid }
}
