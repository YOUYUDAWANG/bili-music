[根目录](../../CLAUDE.md) > **API**

## 模块职责

B 站与歌词服务客户端层。包括 B 站视频信息、音频/视频流、搜索、相关推荐、登录与收藏接口，以及 BM 标题整理和网易云/酷狗/QQ 音乐歌词读取。

## 入口与启动

- **文件**: `BiliClient.swift`、`WBISigner.swift`、`MetingLyricsClient.swift`、`TrackTitleParser.swift`
- `BiliClient` 是 struct，调用处直接创建实例。
- 启动时应在 utility 优先级调用 `WBISigner.prewarm()` 预热签名 key 缓存。

## 对外接口

### BiliClient

| 方法 | 用途 | 是否需要登录 |
|------|------|-------------|
| `videoInfo(bvid:)` | 视频详情（含分 P、UP 主、合集） | 否 |
| `pageList(bvid:)` | 分 P 列表（轻量） | 否 |
| `audioStream(bvid:cid:preferredQuality:)` | 音频 DASH 流 URL（WBI `/x/player/wbi/playurl`） | 否 |
| `videoStreamResult(bvid:cid:profile:)` | 视频 MP4 流 URL、画质与码率 | 否 |
| `search(keyword:page:musicOnly:)` | 搜索视频（WBI 签名） | 否 |
| `related(bvid:)` | 相关推荐视频 | 否 |
| `qrCodeGenerate()` | 申请登录二维码 | 否 |
| `qrCodePoll(key:)` | 轮询扫码结果 | 否 |
| `favFolders()` | 收藏夹列表 | 是 |
| `favItems(folderId:page:)` | 收藏夹内容分页 | 是 |
| `favItemIDs(folderId:)` | 收藏夹全部 bvid（极轻量） | 是 |
| `setFavorite(aid:folderId:add:)` | 收藏/取消收藏 | 是（需 CSRF） |
| `upPlaylists(mid:)` | UP 主合集+系列列表 | 否 |
| `upPlaylistItems(mid:playlist:page:)` | 合集/系列内容分页 | 否 |
| `currentVideoPlaylist(bvid:)` | 视频自带的合集（ugc_season） | 否 |
| `upPlaylistContaining(bvid:mid:maxPlaylists:maxPages:)` | 在 UP 主合集中查找包含某 BV 的列表 | 否 |
| `myInfo()` | 当前登录用户信息（nav） | 是 |

### WBISigner

- `sign(_:)` —— 对参数字典签名，返回完整 query string（含 wts + w_rid）。
- `prewarm()` —— 预热 mixin key 缓存（12h TTL）。
- 内部使用 64 字符重排表混淆 nav 接口返回的 img/sub key → MD5 签名。
- 签名前把参数值中的 `!'()*` 五个字符**删除**（不是编码，参考实现要求）。

### MetingLyricsClient / TrackTitleParser

- `automaticLyrics(for:)` —— 把原始 B 站标题 POST 到 BM `/ai`，取得搜索关键词后选择默认平台、搜索候选并读取第一份可用歌词。
- `search(keyword:provider:limit:)` / `fetchLyrics(for:)` —— 支持网易云、酷狗、QQ 音乐的手动候选选择；歌词平台由 app 直连，不经 BM 代理。
- `LyricsParser.lines(from:duration:)` —— 解析普通 LRC、多时间标签、翻译对齐和网易云逐字歌词，产出逐行与逐字时间模型。
- 自动候选只按 BM 关键词做标题/歌手一致性排序，避免同歌手错误首项；不恢复 LRCLIB 时长/相似度评分。
- `TrackTitleParser` 只负责 B 站标题的本地展示清洗与结构解析；不使用 B 站自动字幕。

## 关键依赖与配置

- `CookieStore` —— 需要登录的接口自动读取。
- `URLSessionConfiguration` —— `timeoutIntervalForRequest = 12`，`waitsForConnectivity = true`。
- 所有 API 请求带 `BiliClient.headers`（`Referer: https://www.bilibili.com` + Chrome UA）。
- CDN 拉流/下载使用 `BiliClient.playbackHeaders`（上述头 + `Origin` + 登录 Cookie）。
- `audioStream` 走 WBI `/x/player/wbi/playurl`；签名被拒（-403）时刷新 mixin key 再试一次。
- 音质 ID 权威清单：`BiliClient.qualityOptions` —— 所有引用它，勿重复定义。

## 数据模型

- `VideoInfo` —— 视频详情（aid, bvid, title, pic, owner, pages, ugc_season）
- `PlayInfo` / `VideoPlayInfo` —— 音频 DASH / 视频 MP4 播放信息
- `SearchItem` —— 搜索结果条目（aid, bvid, title, author, pic, duration, typeid）
- `RelatedItem` —— 相关推荐条目
- `FavFolder`, `FavItem` —— 收藏夹 / 收藏内容（`FavItem.resolvedCID` 来自顶层 `cid` 或 `ugc.first_cid`）
- `UPPlaylist`, `UPPlaylistItem` —— UP 主合集/系列及其条目
- `QRCode` / `QRPollResult` —— 扫码登录相关
- `UserInfo` —— 当前登录用户信息
- `APIError` —— B 站 API 错误（code + message）

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-08-19 | `FavItem` 解码 `ugc.first_cid` / 顶层 `cid`，供首页和收藏夹少走 pageList。 |
| 2026-08-19 | 音频流改 WBI playurl；新增 `playbackHeaders` 给 CDN 拉流/下载使用。 |
| 2026-08-19 | 移除 LRCLIB；接入 BM 标题整理与网易云/酷狗/QQ 多平台歌词，加入翻译、逐字歌词与手动候选。 |
| 2026-07-27 | 全项目 review 修复 + 文档同步：WBI 签名前过滤 `!'()*`；LyricsClient 时长门槛 25s/45s、多时间标签展开、极短歌名降分。 |
| 2026-06-24 | 初始文档创建。 |
