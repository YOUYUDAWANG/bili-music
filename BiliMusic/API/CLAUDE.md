[根目录](../../CLAUDE.md) > **API**

## 模块职责

B 站接口客户端层。所有对 B 站 API 的 HTTP 调用都在此模块内，包括视频信息、音频/视频流、搜索、相关推荐、扫码登录、收藏夹 CRUD、UP 主合集/系列和用户信息。

## 入口与启动

- **文件**: `BiliClient.swift`、`WBISigner.swift`、`LyricsClient.swift`
- `BiliClient` 是 struct，调用处直接创建实例。
- 启动时应在 utility 优先级调用 `WBISigner.prewarm()` 预热签名 key 缓存。

## 对外接口

### BiliClient

| 方法 | 用途 | 是否需要登录 |
|------|------|-------------|
| `videoInfo(bvid:)` | 视频详情（含分 P、UP 主、合集） | 否 |
| `pageList(bvid:)` | 分 P 列表（轻量） | 否 |
| `audioStream(bvid:cid:preferredQuality:)` | 音频 DASH 流 URL | 否 |
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

### LyricsClient

- `lyrics(for:)` —— 为 Track 匹配同步歌词。流程：解析歌名 → LRCLIB 搜索 → 歌名相似 + 时长双门槛匹配 → LRC 解析为 `[PlayerEngine.LyricLine]`。
- 时长门槛（`bestCandidate`）：无歌手信号时时长差 ≤25s；有歌手信号（artist 匹配得分 >0）放宽到 ≤45s，容忍 MV 片头片尾。
- 极短歌名（归一化后 <3 字符，如《光》《海》）的 contains 匹配大幅降分，不过总分门槛，避免误配。
- LRC 解析支持 `[t1][t2]歌词` 多时间标签行，展开为同一文本的多行。
- 只使用 LRCLIB（`lrclib.net`），不 fallback 到 B 站字幕。

## 关键依赖与配置

- `CookieStore` —— 需要登录的接口自动读取。
- `URLSessionConfiguration` —— `timeoutIntervalForRequest = 12`，`waitsForConnectivity = true`。
- 所有请求带 `BiliClient.headers`（`Referer: https://www.bilibili.com` + Chrome UA）。
- 音质 ID 权威清单：`BiliClient.qualityOptions` —— 所有引用它，勿重复定义。

## 数据模型

- `VideoInfo` —— 视频详情（aid, bvid, title, pic, owner, pages, ugc_season）
- `PlayInfo` / `VideoPlayInfo` —— 音频 DASH / 视频 MP4 播放信息
- `SearchItem` —— 搜索结果条目（aid, bvid, title, author, pic, duration, typeid）
- `RelatedItem` —— 相关推荐条目
- `FavFolder`, `FavItem` —— 收藏夹 / 收藏内容
- `UPPlaylist`, `UPPlaylistItem` —— UP 主合集/系列及其条目
- `QRCode` / `QRPollResult` —— 扫码登录相关
- `UserInfo` —— 当前登录用户信息
- `APIError` —— B 站 API 错误（code + message）

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-07-27 | 全项目 review 修复 + 文档同步：WBI 签名前过滤 `!'()*`；LyricsClient 时长门槛 25s/45s、多时间标签展开、极短歌名降分。 |
| 2026-06-24 | 初始文档创建。 |
