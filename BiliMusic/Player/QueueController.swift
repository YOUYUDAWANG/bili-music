import Foundation

enum QueueController {
    static func nextIndex(
        mode: PlayerEngine.QueueMode,
        queueCount: Int,
        currentIndex: Int,
        automatic: Bool
    ) -> Int? {
        switch mode {
        case .repeatOne:
            if automatic {
                return currentIndex
            }
            // 手动切歌在队尾回绕到队首:hasNext 在单曲循环下恒为 true,
            // 锁屏「下一曲」按钮可点,返回 nil 会让它看起来无响应。
            guard queueCount > 0 else { return nil }
            let next = currentIndex + 1
            return next < queueCount ? next : 0
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
}
