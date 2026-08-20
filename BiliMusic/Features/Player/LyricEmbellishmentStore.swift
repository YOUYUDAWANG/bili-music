import Foundation
import Observation

/// 露娜（Luna）单条微巧思指示
struct LyricEmbellishmentCue: Codable, Equatable, Sendable {
    let lineIndex: Int
    let wordIndex: Int?
    let style: LyricEmbellishmentStyle
    let note: String?

    init(lineIndex: Int, wordIndex: Int? = nil, style: LyricEmbellishmentStyle, note: String? = nil) {
        self.lineIndex = lineIndex
        self.wordIndex = wordIndex
        self.style = style
        self.note = note
    }
}

/// 露娜（Luna）全曲微巧思谱表
struct LyricEmbellishmentScore: Codable, Equatable, Sendable {
    let version: String
    let trackID: String
    let lyricsHash: String
    let mood: String
    let cues: [LyricEmbellishmentCue]

    init(
        version: String = "lyric-embellish-v1",
        trackID: String,
        lyricsHash: String,
        mood: String,
        cues: [LyricEmbellishmentCue]
    ) {
        self.version = version
        self.trackID = trackID
        self.lyricsHash = lyricsHash
        self.mood = mood
        self.cues = cues
    }

    /// 获取特定行或词的微巧思风格
    func style(forLine lineIndex: Int, wordIndex: Int? = nil) -> LyricEmbellishmentStyle? {
        if let wordIndex {
            // 优先查找词级精准匹配
            if let wordCue = cues.first(where: { $0.lineIndex == lineIndex && $0.wordIndex == wordIndex }) {
                return wordCue.style
            }
        }
        // 查找句级主导风格
        if let lineCue = cues.first(where: { $0.lineIndex == lineIndex && $0.wordIndex == nil }) {
            return lineCue.style
        }
        return nil
    }
}

/// 露娜微巧思本地持久化存储
@Observable
final class LyricEmbellishmentStore {
    static let shared = LyricEmbellishmentStore()

    private var memoryCache: [String: LyricEmbellishmentScore] = [:]
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = docs.appendingPathComponent("lyric-embellishments.json")
        }
        loadFromDisk()
    }

    /// 获取指定曲目和歌词哈希对应的微巧思谱表
    func score(for trackID: String, lyricsHash: String) -> LyricEmbellishmentScore? {
        guard let cached = memoryCache[trackID], cached.lyricsHash == lyricsHash else {
            return nil
        }
        return cached
    }

    /// 保存微巧思谱表并异步落盘
    func save(_ score: LyricEmbellishmentScore) {
        memoryCache[score.trackID] = score
        scheduleSaveToDisk()
    }

    /// 清除特定曲目的微巧思
    func remove(for trackID: String) {
        memoryCache.removeValue(forKey: trackID)
        scheduleSaveToDisk()
    }

    // MARK: - Disk I/O

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let scores = try JSONDecoder().decode([String: LyricEmbellishmentScore].self, from: data)
            memoryCache = scores
        } catch {
            memoryCache = [:]
        }
    }

    private func scheduleSaveToDisk() {
        saveTask?.cancel()
        let snapshot = memoryCache
        let targetURL = fileURL
        saveTask = Task.detached(priority: .background) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: targetURL, options: .atomic)
            } catch {
                // 忽略磁盘错误
            }
        }
    }
}
