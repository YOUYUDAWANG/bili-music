import Foundation
import OSLog

private let log = Logger(subsystem: "com.fubuki.BiliMusic", category: "network")

/// B 站接口客户端。所有请求带 Referer + 浏览器 UA,否则 CDN 403。
struct BiliClient {
    /// 音质选项的权威清单（id + 展示名）。各处引用此处，勿重复定义。
    static let qualityOptions: [(id: Int, title: String)] = [
        (0,     "自动(最高)"),
        (30251, "Hi-Res"),
        (30250, "杜比全景声"),
        (30280, "高码率 192K"),
        (30232, "标准 132K"),
        (30216, "流畅 64K"),
    ]

    static let videoQualityOptions: [(id: Int, title: String)] = [
        (0,   "自动(最高)"),
        (120, "4K"),
        (116, "1080P 60帧"),
        (112, "1080P 高码率"),
        (80,  "1080P"),
        (64,  "720P"),
    ]

    /// 所有请求必带的浏览器伪装头（Referer + UA），缺则 CDN 返回 403。
    static let headers = [
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
        "Referer": "https://www.bilibili.com",
    ]

    // 默认 URLSession.shared 的请求超时是 60s——某个接口卡住时用户要干等一分钟,
    // 预取任务也会一直挂着。元数据接口都很轻,12s 足够,失败快速暴露。
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    /// B 站接口返回的错误（code + message）。
    struct APIError: LocalizedError {
        let code: Int
        let message: String
        var errorDescription: String? { "B站接口错误 \(code): \(message)" }
    }

    /// B 站统一响应信封 { code, message, data }。
    private struct Envelope<T: Decodable>: Decodable {
        let code: Int
        let message: String
        let data: T?
    }

    /// 发 GET：带统一头 + Cookie，解信封，code≠0 抛错。
    /// 注意：传入的 url 必须已是合法编码。搜索的 query 由 WBISigner 百分号编码并据此签名,
    /// 其余接口的参数都是 ASCII(bvid/cid/页码)。**不能**在这里再 addingPercentEncoding——
    /// 那会把 `%E5` 二次编码成 `%25E5`,服务器收到的是字面量而非中文,搜索静默返回错误结果。
    private func get<T: Decodable>(_ url: String) async throws -> T {
        let start = CFAbsoluteTimeGetCurrent()
        guard let urlObj = URL(string: url) else {
            throw APIError(code: -1, message: "URL 非法")
        }
        var req = URLRequest(url: urlObj)
        Self.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if let cookie = CookieStore.cookie {
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        let (data, _) = try await Self.session.data(for: req)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let truncated = url.count > 80 ? String(url.prefix(80)) + "…" : url
        log.debug("GET \(elapsed, format: .fixed(precision: 1))ms \(truncated)")
        let env = try await Self.decode(Envelope<T>.self, from: data)
        guard env.code == 0, let payload = env.data else {
            throw APIError(code: env.code, message: env.message)
        }
        return payload
    }

    /// 发表单 POST（无返回体）：带统一头 + Cookie，code≠0 抛错。
    private func postVoid(_ url: String, form: [String: String]) async throws {
        let start = CFAbsoluteTimeGetCurrent()
        guard let urlObj = URL(string: url) else {
            throw APIError(code: -1, message: "URL 非法")
        }
        var req = URLRequest(url: urlObj)
        req.httpMethod = "POST"
        Self.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let cookie = CookieStore.cookie {
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        var components = URLComponents()
        components.queryItems = form.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = components.percentEncodedQuery?
            .replacingOccurrences(of: "%20", with: "+")
            .data(using: .utf8)
        let (data, _) = try await Self.session.data(for: req)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let truncated = url.count > 80 ? String(url.prefix(80)) + "…" : url
        log.debug("POST \(elapsed, format: .fixed(precision: 1))ms \(truncated)")
        struct VoidEnvelope: Decodable {
            let code: Int
            let message: String
        }
        let env = try await Self.decode(VoidEnvelope.self, from: data)
        guard env.code == 0 else {
            throw APIError(code: env.code, message: env.message)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            try JSONDecoder().decode(type, from: data)
        }.value
    }

    // MARK: - 视频信息

    /// 视频详情（含分 P、UP 主、合集树 ugc_season）。
    struct VideoInfo: Decodable {
        struct Owner: Decodable { let mid: Int; let name: String; let face: String }
        struct Page: Decodable { let cid: Int; let page: Int; let part: String; let duration: Int }
        struct UGCSeason: Decodable {
            struct Section: Decodable {
                struct Episode: Decodable {
                    struct Arc: Decodable {
                        let bvid: String?
                        let title: String?
                        let pic: String?
                        let duration: Int?
                    }
                    let aid: Int?
                    let bvid: String?
                    let cid: Int?
                    let title: String?
                    let arc: Arc?
                }
                let episodes: [Episode]?
            }
            let id: Int
            let title: String
            let sections: [Section]?
        }
        let aid: Int
        let bvid: String
        let title: String
        let pic: String
        let owner: Owner
        let pages: [Page]
        let ugc_season: UGCSeason?
    }

    /// 取视频详情。
    func videoInfo(bvid: String) async throws -> VideoInfo {
        try await get("https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)")
    }

    /// 分 P 条目。
    struct PageListItem: Decodable {
        let cid: Int
        let page: Int
        let part: String
        let duration: Int
    }

    /// 取分 P 列表（比 videoInfo 轻量，只为补 cid/时长）。
    func pageList(bvid: String) async throws -> [PageListItem] {
        try await get("https://api.bilibili.com/x/player/pagelist?bvid=\(bvid)")
    }

    // MARK: - 音频流

    /// DASH 播放信息（音频流列表 + flac）。
    struct PlayInfo: Decodable {
        struct Dash: Decodable {
            struct Audio: Decodable {
                let id: Int
                let baseUrl: String
                let backupUrl: [String]?
                let bandwidth: Int

                private enum CodingKeys: String, CodingKey {
                    case id
                    case baseUrl
                    case base_url
                    case backupUrl
                    case backup_url
                    case bandwidth
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    id = try container.decode(Int.self, forKey: .id)
                    baseUrl = try container.decodeIfPresent(String.self, forKey: .baseUrl)
                        ?? container.decode(String.self, forKey: .base_url)
                    backupUrl = try container.decodeIfPresent([String].self, forKey: .backupUrl)
                        ?? container.decodeIfPresent([String].self, forKey: .backup_url)
                    bandwidth = try container.decode(Int.self, forKey: .bandwidth)
                }
            }
            struct Flac: Decodable { let audio: Audio? }
            let audio: [Audio]?
            let flac: Flac?
        }
        let dash: Dash?
    }

    /// 单文件 MP4 播放信息（MV 用）。
    struct VideoPlayInfo: Decodable {
        struct DURL: Decodable { let url: String }
        let quality: Int?
        let durl: [DURL]?
    }

    struct VideoStream {
        let url: URL
        let quality: Int
    }

    /// 按设置里的音质偏好取音频流。返回 URL(约 2 小时过期,不可持久化)和实际选中的音质 id。
    /// 偏好 0 = 最高(含 Hi-Res);否则选不超过偏好的最高一档。
    /// preferredQuality:0 = 最高(含 Hi-Res),否则选不超过该 id 的最高一档。播放/下载各传各的偏好。
    func audioStream(bvid: String, cid: Int, preferredQuality pref: Int) async throws -> (url: URL, candidateURLs: [URL], quality: Int, bandwidth: Int) {
        let info: PlayInfo = try await get(
            "https://api.bilibili.com/x/player/playurl?bvid=\(bvid)&cid=\(cid)&fnval=16&fourk=1")
        guard let dash = info.dash, let audios = dash.audio, !audios.isEmpty else {
            throw APIError(code: -1, message: "无 DASH 音频流")
        }
        let chosen: PlayInfo.Dash.Audio
        if pref == 0 {
            chosen = dash.flac?.audio ?? audios.max { $0.id < $1.id }!
        } else if pref == 30251, let flac = dash.flac?.audio {
            chosen = flac
        } else {
            chosen = audios.filter { $0.id <= pref }.max { $0.id < $1.id }
                ?? audios.min { $0.id < $1.id }!
        }
        guard let url = URL(string: chosen.baseUrl) else {
            throw APIError(code: -1, message: "音频 URL 非法")
        }
        let backups = (chosen.backupUrl ?? []).compactMap(URL.init(string:))
        let candidates = AudioCDNSelector.deduped([url] + backups)
        let selected = AudioCDNSelector.preferredURL(from: candidates) ?? url
        return (selected, candidates, chosen.id, chosen.bandwidth)
    }

    /// MV 取流场景：内嵌优先稳定快速，全屏优先高清并自动降级。
    enum VideoStreamProfile {
        case inline
        case fullscreen

        func qualityCandidates(preferredQuality: Int = 0) -> [Int] {
            let defaults: [Int]
            switch self {
            case .inline:
                // 内嵌播放器优先快速、稳定。
                defaults = [112, 80, 64]
            case .fullscreen:
                // 全屏时优先尝试更高清晰度,失败或账号权限不足时自动降级。
                defaults = [120, 116, 112, 80, 64]
            }
            guard preferredQuality > 0 else { return defaults }
            let fallback = defaults.filter { $0 < preferredQuality }
            return [preferredQuality] + fallback
        }
    }

    static func videoQualityName(_ id: Int) -> String {
        videoQualityOptions.first(where: { $0.id == id })?.title ?? "\(id)"
    }

    func videoStreamResult(
        bvid: String,
        cid: Int,
        profile: VideoStreamProfile = .inline,
        preferredQuality: Int = 0
    ) async throws -> VideoStream {
        for qn in profile.qualityCandidates(preferredQuality: preferredQuality) {
            do {
                let info: VideoPlayInfo = try await get(
                    "https://api.bilibili.com/x/player/playurl?bvid=\(bvid)&cid=\(cid)&qn=\(qn)&fnval=0&fourk=1")
                if let raw = info.durl?.first?.url, let url = URL(string: raw) {
                    return VideoStream(url: url, quality: info.quality ?? qn)
                }
            } catch {
                continue
            }
        }
        throw APIError(code: -1, message: "无可播放 MP4 视频流")
    }

    /// 取单文件 MP4 视频流,用于 MV 模式。全屏路径会优先尝试更高 qn。
    func videoStream(bvid: String, cid: Int, profile: VideoStreamProfile = .inline) async throws -> URL {
        try await videoStreamResult(bvid: bvid, cid: cid, profile: profile).url
    }

    /// 音质 id 的展示名
    static func qualityName(_ id: Int) -> String {
        switch id {
        case 30216: return "64K"
        case 30232: return "132K"
        case 30280: return "高码率"
        case 30250: return "杜比全景声"
        case 30251: return "Hi-Res"
        default: return "\(id)"
        }
    }

    // MARK: - 搜索 (WBI)

    /// 搜索结果包装。
    struct SearchData: Decodable {
        let result: [SearchItem]?
    }

    /// 搜索结果条目（自定义解码，兼容 typeid 字符串/数字混用）。
    struct SearchItem: Decodable {
        let aid: Int?
        let mid: Int?
        let typeid: Int?
        let bvid: String
        let title: String
        let author: String
        let pic: String
        let duration: String

        private enum CodingKeys: String, CodingKey {
            case aid, mid, typeid, bvid, title, author, pic, duration
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            aid = try container.decodeIfPresent(Int.self, forKey: .aid)
            mid = try container.decodeIfPresent(Int.self, forKey: .mid)
            if let intValue = try? container.decodeIfPresent(Int.self, forKey: .typeid) {
                typeid = intValue
            } else if let stringValue = try? container.decodeIfPresent(String.self, forKey: .typeid) {
                typeid = Int(stringValue)
            } else {
                typeid = nil
            }
            bvid = try container.decode(String.self, forKey: .bvid)
            title = try container.decode(String.self, forKey: .title)
            author = try container.decode(String.self, forKey: .author)
            pic = try container.decode(String.self, forKey: .pic)
            duration = try container.decode(String.self, forKey: .duration)
        }

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

    /// 搜索视频（WBI 签名；musicOnly 限定音乐分区 tids=3）。
    func search(keyword: String, page: Int = 1, musicOnly: Bool = false) async throws -> [SearchItem] {
        var params = [
            "search_type": "video",
            "keyword": keyword,
            "page": String(page),
        ]
        if musicOnly {
            params["tids"] = "3"
        }
        let query = try await WBISigner.sign(params)
        let data: SearchData = try await get(
            "https://api.bilibili.com/x/web-interface/wbi/search/type?\(query)")
        return data.result ?? []
    }

    // MARK: - 相关推荐 (电台连播数据源)

    /// 相关推荐条目（电台连播数据源）。
    struct RelatedItem: Decodable {
        struct Owner: Decodable { let mid: Int?; let name: String }
        let aid: Int?
        let bvid: String
        let cid: Int?
        let title: String
        let pic: String
        let duration: Int
        let owner: Owner
    }

    /// 取相关推荐（电台连播主力数据源）。
    func related(bvid: String) async throws -> [RelatedItem] {
        try await get("https://api.bilibili.com/x/web-interface/archive/related?bvid=\(bvid)")
    }

    // MARK: - 字幕/歌词

    /// 字幕轨列表信息。
    struct SubtitleInfo: Decodable {
        struct Subtitle: Decodable {
            struct Item: Decodable {
                let lan: String
                let lan_doc: String
                let subtitle_url: String
            }
            let subtitles: [Item]?
        }
        let subtitle: Subtitle?
    }

    /// 字幕文件（分行带时间）。
    struct SubtitleFile: Decodable {
        struct Line: Decodable {
            let from: Double
            let to: Double
            let content: String
        }
        let body: [Line]
    }

    /// 取字幕轨列表。
    func subtitles(bvid: String, cid: Int) async throws -> [SubtitleInfo.Subtitle.Item] {
        let info: SubtitleInfo = try await get(
            "https://api.bilibili.com/x/player/v2?bvid=\(bvid)&cid=\(cid)")
        return info.subtitle?.subtitles ?? []
    }

    /// 下载并解析某条字幕轨。
    func subtitleFile(_ subtitle: SubtitleInfo.Subtitle.Item) async throws -> SubtitleFile {
        let raw = subtitle.subtitle_url.hasPrefix("//") ? "https:" + subtitle.subtitle_url : subtitle.subtitle_url
        guard let url = URL(string: raw) else {
            throw APIError(code: -1, message: "字幕 URL 非法")
        }
        var req = URLRequest(url: url)
        Self.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if let cookie = CookieStore.cookie {
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        let (data, _) = try await Self.session.data(for: req)
        return try await Self.decode(SubtitleFile.self, from: data)
    }

    // MARK: - 扫码登录

    /// 登录二维码（展示用 url + 轮询用 key）。
    struct QRCode: Decodable {
        let url: String
        let qrcode_key: String
    }

    /// 申请登录二维码。
    func qrCodeGenerate() async throws -> QRCode {
        try await get("https://passport.bilibili.com/x/passport-login/web/qrcode/generate")
    }

    /// 扫码轮询结果：等待 / 过期 / 成功（带 Cookie）。
    enum QRPollResult {
        case waiting          // 未扫码 (86101) 或已扫码待确认 (86090)
        case expired          // 二维码过期 (86038)
        case success(cookie: String)
    }

    /// 轮询扫码状态；成功时从回调 URL 解出 SESSDATA/bili_jct/DedeUserID 拼成 Cookie。
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

    /// 收藏夹。
    struct FavFolder: Decodable, Identifiable {
        let id: Int
        let title: String
        let media_count: Int
    }

    /// 取我创建的收藏夹列表（需登录）。
    func favFolders() async throws -> [FavFolder] {
        guard let mid = CookieStore.mid else {
            throw APIError(code: -101, message: "未登录")
        }
        struct ListData: Decodable { let list: [FavFolder]? }
        let data: ListData = try await get(
            "https://api.bilibili.com/x/v3/fav/folder/created/list-all?up_mid=\(mid)")
        return data.list ?? []
    }

    /// 收藏夹内的一条内容（attr≠0 表示已失效）。
    struct FavItem: Decodable {
        struct Upper: Decodable { let name: String }
        let bvid: String
        let title: String
        let cover: String
        let duration: Int
        let upper: Upper
        let attr: Int   // 非 0 = 已失效
    }

    /// 收藏夹内容分页。
    struct FavPage: Decodable {
        let medias: [FavItem]?
        let has_more: Bool
    }

    /// 分页取某收藏夹的内容。
    func favItems(folderId: Int, page: Int) async throws -> FavPage {
        try await get(
            "https://api.bilibili.com/x/v3/fav/resource/list?media_id=\(folderId)&pn=\(page)&ps=40&platform=web")
    }

    /// resource/ids 一次返回整个收藏夹的全部条目 id(只含 bvid,极轻量),
    /// 用来构建「已收藏」全集以便从推荐里排除。兼容 bvid / bv_id 两种字段名。
    private struct FavResourceID: Decodable {
        let bvid: String
        private enum CodingKeys: String, CodingKey { case bvid, bv_id }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let v = try? c.decode(String.self, forKey: .bvid) {
                bvid = v
            } else {
                bvid = try c.decode(String.self, forKey: .bv_id)
            }
        }
    }

    /// 取整个收藏夹的全部 bvid(单请求,不分页)。
    func favItemIDs(folderId: Int) async throws -> [String] {
        let items: [FavResourceID] = try await get(
            "https://api.bilibili.com/x/v3/fav/resource/ids?media_id=\(folderId)&platform=web")
        return items.map(\.bvid)
    }

    /// 收藏 / 取消收藏（写操作，需 CSRF token）。
    func setFavorite(aid: Int, folderId: Int, add: Bool) async throws {
        guard let csrf = CookieStore.csrf else {
            throw APIError(code: -101, message: "未登录或缺少 bili_jct")
        }
        try await postVoid(
            "https://api.bilibili.com/x/v3/fav/resource/deal",
            form: [
                "rid": String(aid),
                "type": "2",
                "add_media_ids": add ? String(folderId) : "",
                "del_media_ids": add ? "" : String(folderId),
                "csrf": csrf,
            ])
    }

    // MARK: - UP 主合集/系列

    /// UP 主合集/系列（type 1=合集 season，否则系列 series）。
    struct UPPlaylist: Decodable, Identifiable, Hashable {
        let id: Int
        let title: String
        let mediaCount: Int
        let type: Int
        let items: [UPPlaylistItem]?

        enum CodingKeys: String, CodingKey {
            case id
            case title = "name"
            case mediaCount = "total"
            case type
        }

        init(id: Int, title: String, mediaCount: Int, type: Int, items: [UPPlaylistItem]? = nil) {
            self.id = id
            self.title = title
            self.mediaCount = mediaCount
            self.type = type
            self.items = items
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            mediaCount = try container.decode(Int.self, forKey: .mediaCount)
            type = try container.decode(Int.self, forKey: .type)
            items = nil
        }
    }

    /// 合集/系列里的一条视频。
    struct UPPlaylistItem: Decodable, Hashable {
        let bvid: String
        let aid: Int?
        let cid: Int?
        let title: String
        let pic: String?
        let duration: Int?

        init(bvid: String, aid: Int?, cid: Int?, title: String, pic: String?, duration: Int?) {
            self.bvid = bvid
            self.aid = aid
            self.cid = cid
            self.title = title
            self.pic = pic
            self.duration = duration
        }
    }

    /// 合集内容分页。
    struct UPPlaylistPage {
        let items: [UPPlaylistItem]
        let hasMore: Bool
    }

    /// 取 UP 主公开的合集 + 系列列表。
    func upPlaylists(mid: Int) async throws -> [UPPlaylist] {
        struct Data: Decodable {
            struct ListBox: Decodable { let items_lists: [UPPlaylist]? }
            let seasons_list: ListBox?
            let series_list: ListBox?
        }
        let data: Data = try await get(
            "https://api.bilibili.com/x/polymer/web-space/seasons_series_list?mid=\(mid)&page_num=1&page_size=20")
        return (data.seasons_list?.items_lists ?? []) + (data.series_list?.items_lists ?? [])
    }

    /// 取当前视频自带的合集（ugc_season），无则返回 nil。
    func currentVideoPlaylist(bvid: String) async throws -> UPPlaylist? {
        let info = try await videoInfo(bvid: bvid)
        guard let season = info.ugc_season else { return nil }
        let items: [UPPlaylistItem] = season.sections?
            .flatMap { $0.episodes ?? [] }
            .compactMap {
                guard let bvid = $0.bvid ?? $0.arc?.bvid else { return nil }
                return UPPlaylistItem(
                    bvid: bvid,
                    aid: $0.aid,
                    cid: $0.cid,
                    title: $0.title ?? $0.arc?.title ?? "未命名",
                    pic: $0.arc?.pic,
                    duration: $0.arc?.duration)
            } ?? []
        return UPPlaylist(
            id: season.id,
            title: season.title,
            mediaCount: items.count,
            type: 1,
            items: items)
    }

    /// 分页取合集/系列的视频（已内嵌 items 则直接返回）。
    func upPlaylistItems(mid: Int, playlist: UPPlaylist, page: Int = 1) async throws -> UPPlaylistPage {
        if let items = playlist.items {
            return UPPlaylistPage(items: items, hasMore: false)
        }
        struct Data: Decodable {
            let archives: [UPPlaylistItem]?
            let page: Page?
            struct Page: Decodable {
                let page_num: Int?
                let page_size: Int?
                let total: Int?
            }
        }
        let idParam = playlist.type == 1 ? "season_id" : "series_id"
        let data: Data = try await get(
            "https://api.bilibili.com/x/polymer/web-space/seasons_archives_list?mid=\(mid)&\(idParam)=\(playlist.id)&page_num=\(page)&page_size=30")
        let items = data.archives ?? []
        let current = data.page?.page_num ?? page
        let size = data.page?.page_size ?? 30
        let total = data.page?.total ?? items.count
        return UPPlaylistPage(items: items, hasMore: current * size < total)
    }

    /// 在 UP 主公开的合集/系列里查找包含某个 BV 的列表。
    /// 限制扫描范围,避免正在播放页为了 UI 检测发过多请求。
    func upPlaylistContaining(bvid: String, mid: Int, maxPlaylists: Int = 12, maxPages: Int = 5) async throws -> UPPlaylist? {
        let playlists = try await upPlaylists(mid: mid)
        for playlist in playlists.prefix(maxPlaylists) {
            var page = 1
            var collected: [UPPlaylistItem] = []
            while page <= maxPages {
                let result = try await upPlaylistItems(mid: mid, playlist: playlist, page: page)
                collected.append(contentsOf: result.items)
                if collected.contains(where: { $0.bvid == bvid }) {
                    return UPPlaylist(
                        id: playlist.id,
                        title: playlist.title,
                        mediaCount: playlist.mediaCount,
                        type: playlist.type,
                        items: collected)
                }
                guard result.hasMore else { break }
                page += 1
            }
        }
        return nil
    }

    // MARK: - 首页推荐 (WBI;登录后个性化)

    /// 首页推荐条目。
    struct FeedItem: Decodable {
        struct Owner: Decodable { let name: String }
        let bvid: String?
        let title: String?
        let pic: String?
        let duration: Int?
        let owner: Owner?
    }

    /// 取首页推荐流（WBI 签名；登录后个性化）。
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

    /// 当前登录用户信息。
    struct UserInfo: Decodable {
        let uname: String
        let face: String
    }

    /// 取当前登录用户信息（nav 接口）。
    func myInfo() async throws -> UserInfo {
        try await get("https://api.bilibili.com/x/web-interface/nav")
    }
}
