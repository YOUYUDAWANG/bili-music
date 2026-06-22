import Foundation

/// 判定内容是否为音乐的启发式：B 站音乐分区 typeID + 标题/时长规则。宁可漏判也不错判。
enum MusicFilter {
    // B 站音乐分区及常见音乐子分区。
    // 3: 音乐, 28: 原创音乐, 31: 翻唱, 30: VOCALOID/UTAU, 59: 演奏,
    // 29: 音乐现场, 193: MV, 130: 音乐综合, 243/244: 音乐竖屏子类型。
    private static let musicTypeIDs: Set<Int> = [3, 28, 29, 30, 31, 59, 130, 193, 243, 244]

    private static let musicHints = [
        "music", "mv", "live", "cover", "remix", "ost", "op", "ed", "bgm", "piano",
        "guitar", "bass", "drum", "vocal", "lyrics", "lyric", "playlist", "album",
        "song", "sing", "singer", "concert", "audio", "instrumental", "dj",
        "音乐", "歌曲", "歌单", "唱歌", "翻唱", "现场", "演唱", "演奏", "钢琴", "吉他",
        "贝斯", "鼓", "歌词", "纯音乐", "伴奏", "专辑", "单曲", "主题曲", "片头曲",
        "片尾曲", "插曲", "原声", "音频", "电台", "合集", "周杰伦", "陈奕迅",
    ]

    private static let nonMusicHints = [
        "解说", "影视", "电影", "电视剧", "纪录片", "预告", "剪辑", "混剪", "游戏", "攻略",
        "实况", "直播回放", "三国杀", "原神", "王者", "吃鸡", "教程", "教学", "公开课",
        "新闻", "资讯", "评测", "开箱", "测评", "搞笑", "鬼畜", "相声", "脱口秀",
        "篮球", "足球", "比赛", "赛事", "vlog", "reaction", "review", "trailer",
        "gameplay", "walkthrough", "tutorial", "news", "movie", "drama",
        "盘点", "排行", "top", "切片", "clip", "合集剪辑", "耐久", "作业用", "字幕组",
        "中字", "解析", "分析",
    ]

    private static let weakMusicHints: Set<String> = ["合集", "playlist"]

    /// 宽松判定（用于推荐扩列，允许更多疑似音乐通过）。
    static func isMusic(_ track: Track) -> Bool {
        isMusic(title: track.title, artist: track.artist, duration: track.duration)
    }

    /// 严格判定（用于电台种子等高质量场景，时长门槛更窄）。
    static func isStrictMusic(_ track: Track) -> Bool {
        isStrictMusic(title: track.title, artist: track.artist, duration: track.duration)
    }

    /// 搜索结果专用判定：结合分区、非音乐关键词与查询词相关性，更严格地排除泛内容。
    static func isSearchResultMusic(_ track: Track, query: String? = nil) -> Bool {
        // 搜索页宁可少一点,也不要混进解说/剪辑/教程/影视/游戏等泛内容。
        guard (60...720).contains(track.duration) else { return false }
        let text = (track.title + " " + track.artist).lowercased()
        let hasMusicHint = musicHints.contains { text.contains($0.lowercased()) }
        if let typeID = track.typeID, !musicTypeIDs.contains(typeID) {
            return false
        }
        if nonMusicHints.contains(where: { text.contains($0.lowercased()) }) {
            return false
        }
        if let query, !isRelevantToSearchQuery(track, query: query) {
            return false
        }
        if track.typeID != nil {
            return true
        }
        return hasMusicHint || looksLikeSongTitle(text)
    }

    /// 搜索模式专用入口：音乐默认收紧，MV 要明确有 MV 信号，扩大搜索允许跨分区但仍排除明显泛内容。
    static func isSearchResult(_ track: Track, query: String? = nil, mode: SearchResultMode) -> Bool {
        switch mode {
        case .music:
            return isSearchResultMusic(track, query: query)
        case .mv:
            return isSearchResultMV(track, query: query)
        case .expanded:
            return isExpandedSearchResult(track, query: query)
        }
    }

    private static func isSearchResultMV(_ track: Track, query: String? = nil) -> Bool {
        guard (60...900).contains(track.duration) else { return false }
        let text = (track.title + " " + track.artist).lowercased()
        guard hasMVSignal(track, text: text) else { return false }
        if nonMusicHints.contains(where: { text.contains($0.lowercased()) }),
           !musicHints.contains(where: { text.contains($0.lowercased()) }) {
            return false
        }
        if let query, !isRelevantToSearchQuery(track, query: query) {
            return false
        }
        return true
    }

    private static func isExpandedSearchResult(_ track: Track, query: String? = nil) -> Bool {
        guard (45...900).contains(track.duration) else { return false }
        let text = (track.title + " " + track.artist).lowercased()
        let hasMusicHint = musicHints.contains { text.contains($0.lowercased()) }
        let hasStrongMusicHint = musicHints.contains { hint in
            let normalizedHint = hint.lowercased()
            return !weakMusicHints.contains(normalizedHint) && text.contains(normalizedHint)
        }
        if nonMusicHints.contains(where: { text.contains($0.lowercased()) }), !hasStrongMusicHint {
            return false
        }
        if let query, !isRelevantToSearchQuery(track, query: query) {
            return false
        }
        if let typeID = track.typeID, musicTypeIDs.contains(typeID) {
            return true
        }
        return hasStrongMusicHint || (hasMusicHint && !nonMusicHints.contains { text.contains($0.lowercased()) })
            || looksLikeSongTitle(text)
    }

    private static func hasMVSignal(_ track: Track, text: String) -> Bool {
        track.typeID == 193
            || text.contains("mv")
            || text.contains("music video")
            || text.contains("official video")
            || text.contains("官方视频")
            || text.contains("官方影像")
    }

    /// 结果是否与搜索词相关，避免仅因时长像歌就混入无关视频。
    private static func isRelevantToSearchQuery(_ track: Track, query: String) -> Bool {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return true }
        let normalizedText = normalize(track.title + " " + track.artist)
        let compactQuery = normalizedQuery.replacingOccurrences(of: " ", with: "")
        let compactText = normalizedText.replacingOccurrences(of: " ", with: "")

        if compactText.contains(compactQuery) || normalizedText.contains(normalizedQuery) {
            return true
        }

        let tokens = normalizedQuery
            .split(separator: " ")
            .map(String.init)
            .filter { token in
                token.count >= 2 || token.unicodeScalars.contains { $0.value > 127 }
            }
        guard !tokens.isEmpty else { return true }

        let matchedCount = tokens.filter { normalizedText.contains($0) || compactText.contains($0) }.count
        if tokens.count == 1 {
            return matchedCount == 1
        }
        return matchedCount == tokens.count || (tokens.count >= 3 && matchedCount >= tokens.count - 1)
    }

    /// 归一化：小写、去音调/全半角、清理高亮标签与标点空白，便于比较。
    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "<em class=\"keyword\">", with: "")
            .replacingOccurrences(of: "</em>", with: "")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"[\p{P}\p{S}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 宽松判定的底层实现（时长 60~720 秒 + 关键词/命名启发）。
    static func isMusic(title: String, artist: String, duration: Int) -> Bool {
        guard (60...720).contains(duration) else { return false }
        let text = (title + " " + artist).lowercased()

        if nonMusicHints.contains(where: { text.contains($0.lowercased()) }) {
            return musicHints.contains(where: { text.contains($0.lowercased()) })
        }

        if musicHints.contains(where: { text.contains($0.lowercased()) }) {
            return true
        }

        // 很多歌曲投稿就是简单的「歌手 - 歌名」或「歌名 / 歌手」。
        return looksLikeSongTitle(text) && duration <= 600
    }

    /// 严格判定的底层实现（时长 75~540 秒，命中非音乐词直接否决）。
    static func isStrictMusic(title: String, artist: String, duration: Int) -> Bool {
        guard (75...540).contains(duration) else { return false }
        let text = (title + " " + artist).lowercased()
        if nonMusicHints.contains(where: { text.contains($0.lowercased()) }) {
            return false
        }
        if musicHints.contains(where: { text.contains($0.lowercased()) }) {
            return true
        }
        return looksLikeSongTitle(text)
    }

    /// 标题是否像「歌手 - 歌名」「《歌名》」之类的歌曲命名。
    private static func looksLikeSongTitle(_ text: String) -> Bool {
        text.contains(" - ") || text.contains("《") || text.contains("》")
            || text.contains("「") || text.contains("」") || text.contains("|")
    }
}
