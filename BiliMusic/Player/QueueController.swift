import Foundation

enum QueueController {
    static func nextIndex(
        mode: PlayerEngine.QueueMode,
        queueCount: Int,
        currentIndex: Int
    ) -> Int? {
        switch mode {
        case .repeatOne:
            return currentIndex
        case .shuffle:
            guard queueCount > 1 else { return nil }
            return (0..<queueCount).filter { $0 != currentIndex }.randomElement()
        case .sequential, .radio:
            let next = currentIndex + 1
            return next < queueCount ? next : nil
        }
    }

    static func appendUnique(_ tracks: [Track], to queue: inout [Track]) -> [Track] {
        let additions = tracks.filter { track in
            !queue.contains { $0.key.matches(track) }
        }
        queue.append(contentsOf: additions)
        return additions
    }

    static func remove(at index: Int, from queue: inout [Track], currentIndex: inout Int) -> Bool {
        guard queue.indices.contains(index), queue.count > 1 else { return false }
        queue.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
            return false
        }
        if index == currentIndex {
            currentIndex = min(currentIndex, queue.count - 1)
            return true
        }
        return false
    }
}
