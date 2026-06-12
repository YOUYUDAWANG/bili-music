import Foundation

/// B 站接口客户端。所有请求带 Referer + 浏览器 UA,否则 CDN 403。
struct BiliClient {
    static let headers = [
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
        "Referer": "https://www.bilibili.com",
    ]

    struct APIError: LocalizedError {
        let code: Int
        let message: String
        var errorDescription: String? { "B站接口错误 \(code): \(message)" }
    }

    private struct Envelope<T: Decodable>: Decodable {
        let code: Int
        let message: String
        let data: T?
    }

    private func get<T: Decodable>(_ url: String) async throws -> T {
        var req = URLRequest(url: URL(string: url)!)
        Self.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if let cookie = CookieStore.cookie {
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        let (data, _) = try await URLSession.shared.data(for: req)
        let env = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard env.code == 0, let payload = env.data else {
            throw APIError(code: env.code, message: env.message)
        }
        return payload
    }

    // MARK: - 视频信息

    struct VideoInfo: Decodable {
        struct Owner: Decodable { let name: String; let face: String }
        struct Page: Decodable { let cid: Int; let page: Int; let part: String; let duration: Int }
        let bvid: String
        let title: String
        let pic: String
        let owner: Owner
        let pages: [Page]
    }

    func videoInfo(bvid: String) async throws -> VideoInfo {
        try await get("https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)")
    }

    // MARK: - 音频流

    struct PlayInfo: Decodable {
        struct Dash: Decodable {
            struct Audio: Decodable { let id: Int; let baseUrl: String; let bandwidth: Int }
            struct Flac: Decodable { let audio: Audio? }
            let audio: [Audio]?
            let flac: Flac?
        }
        let dash: Dash?
    }

    /// 按设置里的音质偏好取音频流。返回 URL(约 2 小时过期,不可持久化)和实际选中的音质 id。
    /// 偏好 0 = 最高(含 Hi-Res);否则选不超过偏好的最高一档。
    func audioStream(bvid: String, cid: Int) async throws -> (url: URL, quality: Int) {
        let info: PlayInfo = try await get(
            "https://api.bilibili.com/x/player/playurl?bvid=\(bvid)&cid=\(cid)&fnval=16&fourk=1")
        guard let dash = info.dash, let audios = dash.audio, !audios.isEmpty else {
            throw APIError(code: -1, message: "无 DASH 音频流")
        }
        let pref = UserDefaults.standard.integer(forKey: "preferredQuality")
        let chosen: PlayInfo.Dash.Audio
        if pref == 0 {
            chosen = dash.flac?.audio ?? audios.max { $0.id < $1.id }!
        } else {
            chosen = audios.filter { $0.id <= pref }.max { $0.id < $1.id }
                ?? audios.min { $0.id < $1.id }!
        }
        guard let url = URL(string: chosen.baseUrl) else {
            throw APIError(code: -1, message: "音频 URL 非法")
        }
        return (url, chosen.id)
    }

    /// 音质 id 的展示名
    static func qualityName(_ id: Int) -> String {
        switch id {
        case 30216: return "64K"
        case 30232: return "132K"
        case 30280: return "192K"
        case 30250: return "杜比全景声"
        case 30251: return "Hi-Res"
        default: return "\(id)"
        }
    }

    // MARK: - 搜索 (WBI)

    struct SearchData: Decodable {
        let result: [SearchItem]?
    }

    struct SearchItem: Decodable {
        let bvid: String
        let title: String
        let author: String
        let pic: String
        let duration: String

        /// 去掉关键词高亮标签的标题
        var cleanTitle: String {
            title
                .replacingOccurrences(of: "<em class=\"keyword\">", with: "")
                .replacingOccurrences(of: "</em>", with: "")
                .replacingOccurrences(of: "&amp;", with: "&")
        }

        /// pic 是 //i0.hdslb.com/... 的协议相对地址
        var coverURL: URL? {
            URL(string: pic.hasPrefix("//") ? "https:" + pic : pic)
        }

        /// "5:18" / "1:02:58" → 秒
        var durationSeconds: Int {
            duration.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
        }
    }

    func search(keyword: String, page: Int = 1) async throws -> [SearchItem] {
        let query = try await WBISigner.sign([
            "search_type": "video",
            "keyword": keyword,
            "page": String(page),
        ])
        let data: SearchData = try await get(
            "https://api.bilibili.com/x/web-interface/wbi/search/type?\(query)")
        return data.result ?? []
    }

    // MARK: - 相关推荐 (电台连播数据源)

    struct RelatedItem: Decodable {
        struct Owner: Decodable { let name: String }
        let bvid: String
        let cid: Int?
        let title: String
        let pic: String
        let duration: Int
        let owner: Owner
    }

    func related(bvid: String) async throws -> [RelatedItem] {
        try await get("https://api.bilibili.com/x/web-interface/archive/related?bvid=\(bvid)")
    }

    // MARK: - 扫码登录

    struct QRCode: Decodable {
        let url: String
        let qrcode_key: String
    }

    func qrCodeGenerate() async throws -> QRCode {
        try await get("https://passport.bilibili.com/x/passport-login/web/qrcode/generate")
    }

    enum QRPollResult {
        case waiting          // 未扫码 (86101) 或已扫码待确认 (86090)
        case expired          // 二维码过期 (86038)
        case success(cookie: String)
    }

    func qrCodePoll(key: String) async throws -> QRPollResult {
        struct Poll: Decodable {
            let url: String
            let code: Int
            let message: String
        }
        let poll: Poll = try await get(
            "https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=\(key)")
        switch poll.code {
        case 0:
            // url 形如 https://passport.biligame.com/crossDomain?DedeUserID=..&SESSDATA=..&bili_jct=..
            guard let components = URLComponents(string: poll.url),
                  let items = components.queryItems else {
                throw APIError(code: -1, message: "登录回调 URL 解析失败")
            }
            let wanted = ["SESSDATA", "bili_jct", "DedeUserID"]
            let pairs = items.filter { wanted.contains($0.name) }
                .compactMap { item in item.value.map { "\(item.name)=\($0)" } }
            guard pairs.count == wanted.count else {
                throw APIError(code: -1, message: "登录回调缺少 Cookie 字段")
            }
            return .success(cookie: pairs.joined(separator: "; "))
        case 86038: return .expired
        default: return .waiting
        }
    }

    // MARK: - 收藏夹 (需登录)

    struct FavFolder: Decodable, Identifiable {
        let id: Int
        let title: String
        let media_count: Int
    }

    func favFolders() async throws -> [FavFolder] {
        guard let mid = CookieStore.mid else {
            throw APIError(code: -101, message: "未登录")
        }
        struct ListData: Decodable { let list: [FavFolder]? }
        let data: ListData = try await get(
            "https://api.bilibili.com/x/v3/fav/folder/created/list-all?up_mid=\(mid)")
        return data.list ?? []
    }

    struct FavItem: Decodable {
        struct Upper: Decodable { let name: String }
        let bvid: String
        let title: String
        let cover: String
        let duration: Int
        let upper: Upper
        let attr: Int   // 非 0 = 已失效
    }

    struct FavPage: Decodable {
        let medias: [FavItem]?
        let has_more: Bool
    }

    func favItems(folderId: Int, page: Int) async throws -> FavPage {
        try await get(
            "https://api.bilibili.com/x/v3/fav/resource/list?media_id=\(folderId)&pn=\(page)&ps=40&platform=web")
    }

    // MARK: - 首页推荐 (WBI;登录后个性化)

    struct FeedItem: Decodable {
        struct Owner: Decodable { let name: String }
        let bvid: String?
        let title: String?
        let pic: String?
        let duration: Int?
        let owner: Owner?
    }

    func homeFeed(freshIdx: Int) async throws -> [FeedItem] {
        struct FeedData: Decodable { let item: [FeedItem]? }
        let query = try await WBISigner.sign([
            "ps": "30",
            "fresh_idx": String(freshIdx),
            "fresh_type": "4",
        ])
        let data: FeedData = try await get(
            "https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd?\(query)")
        return data.item ?? []
    }

    // MARK: - 用户信息

    struct UserInfo: Decodable {
        let uname: String
        let face: String
    }

    func myInfo() async throws -> UserInfo {
        try await get("https://api.bilibili.com/x/web-interface/nav")
    }
}
