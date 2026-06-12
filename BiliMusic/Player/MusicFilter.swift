import Foundation

enum MusicFilter {
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
    ]

    static func isMusic(_ track: Track) -> Bool {
        isMusic(title: track.title, artist: track.artist, duration: track.duration)
    }

    static func isStrictMusic(_ track: Track) -> Bool {
        isStrictMusic(title: track.title, artist: track.artist, duration: track.duration)
    }

    static func isMusic(title: String, artist: String, duration: Int) -> Bool {
        guard (60...720).contains(duration) else { return false }
        let text = (title + " " + artist).lowercased()

        if nonMusicHints.contains(where: { text.contains($0.lowercased()) }) {
            return musicHints.contains(where: { text.contains($0.lowercased()) })
        }

        if musicHints.contains(where: { text.contains($0.lowercased()) }) {
            return true
        }

        // Many song uploads are simply "artist - title" or "song / artist".
        let hasSongLikeSeparator = text.contains(" - ") || text.contains("《") || text.contains("》")
            || text.contains("「") || text.contains("」") || text.contains("|")
        return hasSongLikeSeparator && duration <= 600
    }

    static func isStrictMusic(title: String, artist: String, duration: Int) -> Bool {
        guard (75...540).contains(duration) else { return false }
        let text = (title + " " + artist).lowercased()
        if nonMusicHints.contains(where: { text.contains($0.lowercased()) }) {
            return false
        }
        if musicHints.contains(where: { text.contains($0.lowercased()) }) {
            return true
        }
        return text.contains(" - ") || text.contains("《") || text.contains("》")
            || text.contains("「") || text.contains("」")
    }
}
