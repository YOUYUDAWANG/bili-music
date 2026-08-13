import Foundation

enum PlayerListWindow {
    struct Item: Equatable, Identifiable {
        let index: Int
        let track: Track

        var id: String { track.id }
    }

    static func items(tracks: [Track], current: Track?, maxRows: Int) -> [Item] {
        guard maxRows > 0, !tracks.isEmpty else { return [] }

        let limit = min(maxRows, tracks.count)
        let currentIndex = current.flatMap { current in
            tracks.firstIndex { $0.key.matches(current) }
        } ?? 0
        let leading = limit / 2
        let proposedStart = currentIndex - leading
        let start = min(max(0, proposedStart), max(0, tracks.count - limit))

        return (start..<(start + limit)).map { index in
            Item(index: index, track: tracks[index])
        }
    }

    static func positionText(tracks: [Track], current: Track?) -> String {
        guard let current,
              let index = tracks.firstIndex(where: { $0.key.matches(current) }) else {
            return "\(tracks.count) 首"
        }
        return "\(index + 1)/\(tracks.count)"
    }
}
