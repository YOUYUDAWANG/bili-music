[根目录](../../CLAUDE.md) > **API**

## 模块职责

B 站与歌词服务客户端层。包括 B 站视频信息、音频/视频流、搜索、相关推荐、登录与收藏接口，以及 BM 标题整理、私有 LDDC 逐字歌词聚合和现有曲库直连回退。

## 入口与启动

- **文件**: `BiliClient.swift`、`WBISigner.swift`、`MetingLyricsClient.swift`、`LRCLibLyricsProvider.swift`、`VocaDBLyricsProvider.swift`、`AMLLLyricsProvider.swift`、`TrackTitleParser.swift`、`MetadataNormalizationClient.swift`、`LDDCLyricsBackendClient.swift`、`PrecisionLyricsHostClient.swift`、`LyricPerformanceClient.swift`、`LyricStageClientV2.swift`
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
| `homeFeed(freshIndex:pageSize:)` | 首页推荐流（WBI；`freshIndex` 递增换页） | 个性化需要登录 |
| `qrCodeGenerate()` | 申请登录二维码 | 否 |
| `qrCodePoll(key:)` | 轮询扫码结果（Cookie + refresh_token + buvid3） | 否 |
| `navProfile()` | 读取登录态、用户名、头像和 WBI key | 否 |
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
- `search(keyword:provider:)` / `fetchLyrics(for:)` —— 国内三平台候选；手动聚合搜索同时拉网易云 / 酷狗 / QQ / LRCLIB / VocaDB。不用 LRCLIB 评分。歌词平台由 app 直连。
- `LyricsParser.lines(from:duration:)` —— 解析普通 LRC、多时间标签、翻译对齐和网易云逐字歌词，产出逐行与逐字时间模型。
- 自动候选只按 BM 关键词做标题/歌手一致性排序，避免同歌手错误首项；不恢复 LRCLIB 时长/相似度评分。
- `TrackTitleParser` 只负责 B 站标题的本地展示清洗与结构解析；歌词不使用 B 站字幕，字幕接口已删除。

### LyricPerformanceClient

- Debug 开发工具显式调用自建 Worker `/v1/lyrics/direct`，提交当前歌曲身份和最多 180 行逐行歌词，取得版本化 Luna 演出脚本：逐行文本构图全覆盖，动效 scene 保持稀疏。
- 与元数据 Worker 共用 Bearer keychain 注入；上游 Luna key 只存在 Cloudflare Secret。客户端不自动请求，不进入播放关键路径。
- `lyric-performance-v3` 响应必须通过版本、trackID、lyricsHash、lineCount、每行 1–3 个邻近真实歌词索引、九种 scene allowlist 和参数 clamp；Cascade 还必须对应至少两行构图。失败由 UI 回退本地导演。线上 v3 已部署，App 内真机生成与帧率仍需单独验证。
- 客户端兼容可选 `stageBible + stageDirectives`：请求增加 voiceRole/layerID/overlapGroup，App 对八种 stage behavior、字号、强度、方向、stagger 和 palette role 再校验。生产 Worker 已部署两阶段 v5；若全曲 Stage Bible 或分段 directive 缺失，App 仍可从兼容的 v4 scene 编译 StageScore。

### LyricStageClientV2

- Debug 显式调用生产 Worker `POST /v2/lyrics/direct`，提交歌词与 tokenizer 摘要，取得 `lyric-stage-v2-events`。旧 `/v1/lyrics/direct` 保留。
- V2 已经用户明确授权部署；缓存写入 `lyric-stage-v2.json`，不覆盖 v4 脚本。失败或空场景由本地导演补齐安静基线。客户端请求空闲 90s、总超时 120s；无首包超过该时限会显示「Luna 编排超时」。

### PrecisionLyricsHostClient

- 显式将已缓存音频提交到用户自己的 Windows 高精度主机；任务创建、音频上传与状态轮询分离，重复同一首词直接复用主机缓存。
- 只接受已有逐行 LRC 且无结构化并行声部。主机 QRC 必须通过全文/行数、时间单调、WhisperX 覆盖、全局位移共识和节奏回退比例门禁后，才作为独立 `高精度主机` 来源写回。
- 默认 URL 来自本地 xcconfig，设置页可覆盖；Bearer 由构建脚本从 Mac 钥匙串注入，不能进入仓库。网络或门禁失败不覆盖现有歌词。

### LDDCLyricsBackendClient

- 出声后的自动歌词请求会先访问受 Bearer 保护的私有 `POST /v1/lyrics/resolve`，聚合酷狗 KRC、QQ QRC 和网易云 YRC；未配置、超时、身份门禁失败或无候选时继续现有直连曲库。
- 客户端只接受 `bilimusic-lddc-lyrics-v1`，校验 request ID、行/字时间单调、边界和数量上限；`LyricsResolver` 随后仍按标题、歌手、时长和翻唱/原唱范围二次判定。
- 手动搜索会并行查 LDDC 与现有五个曲库；经服务和 App 双重验证的逐字候选带 `timingKindHint=word`，在同一版本范围内优先排序并显示「逐字」。同平台同 ID 去重保留这份已验证文档。
- URL 来自 `BILIMUSIC_LDDC_LYRICS_API_URL`，Bearer 由 Mac 钥匙串服务 `com.youyudawang.BiliMusic.lddc-lyrics-api` 在构建时注入。LDDC GPL 代码只存在独立 Python 服务，不链接进 App。

## 关键依赖与配置

- `CookieStore` —— 需要登录的接口自动读取。
- `URLSessionConfiguration` —— `timeoutIntervalForRequest = 12`，`waitsForConnectivity = true`。起播走独立 `playbackSession`，发现/搜索走最多 3 条连接的普通 session。
- 所有 API 请求带 `BiliClient.headers`（`Referer: https://www.bilibili.com` + Chrome UA）。
- CDN 拉流/下载使用 `BiliClient.playbackHeaders`（上述头 + `Origin` + 登录 Cookie）。
- `audioStream` 走 WBI `/x/player/wbi/playurl`；签名被拒（-403）时刷新 mixin key 再试一次。
- 音质 ID 权威清单：`BiliClient.qualityOptions` —— 所有引用它，勿重复定义。

## 数据模型

- `VideoInfo` —— 视频详情（aid, bvid, title, pic, owner, pages, ugc_season）
- `PlayInfo` / `VideoPlayInfo` —— 音频 DASH / 视频 MP4 播放信息
- `SearchItem` —— 搜索结果条目（aid, bvid, title, author, pic, duration, typeid）
- `RelatedItem` —— 相关推荐条目
- `FeedItem` —— 首页推荐流条目（bvid, tid, duration, goto）
- `FavFolder`, `FavItem` —— 收藏夹 / 收藏内容（`FavItem.resolvedCID` 来自顶层 `cid` 或 `ugc.first_cid`）
- `UPPlaylist`, `UPPlaylistItem` —— UP 主合集/系列及其条目
- `QRCode` / `QRPollResult` —— 扫码登录相关
- `UserInfo` —— 当前登录用户信息
- `APIError` —— B 站 API 错误（code + message）

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-08-19 | 新增独立 LDDC 私有逐字歌词客户端；双重门禁、直连回退，手动搜索优先标识并排列可靠逐字候选。 |
| 2026-08-19 | 新增认证异步 Windows 高精度歌词来源与客户端二次质量门禁。 |
| 2026-08-19 | `/v2/lyrics/direct` 已部署生产；真实 Event Score 与旧 V1 回归通过，默认舞台仍未切换。 |
| 2026-08-19 | 两阶段 Luna v5 Worker 已部署：全曲 Stage Bible + 分段 stageDirectives 在线返回，兼容 v4 envelope。 |
| 2026-08-19 | Luna envelope 增加可选 Stage Bible/stageDirectives 与多声部输入；本地 Worker 两阶段 v5 尚未部署。 |
| 2026-08-19 | Luna 合同升级 `lyric-performance-v3`，效果 allowlist 从五种扩为九种，并约束 Cascade 只能用于多行构图。 |
| 2026-08-19 | 日语歌词增加 LRCLIB/VocaDB 检索；国内三平台合并后再按时长挑选。 |
| 2026-08-19 | 新增开发阶段 `LyricPerformanceClient` 与 `/v1/lyrics/direct` 合同；显式请求、双层校验，本地回退。 |
| 2026-08-19 | 起播接口改走独立 `playbackSession`，避免被搜索占满连接。 |
| 2026-08-19 | 增加 `homeFeed(freshIndex:)`，对接 WBI 首页推荐流。 |
| 2026-08-19 | VocaDB 歌词检索改用清洗后的日文原名，不拿中文译名或脏标题去搜。 |
| 2026-08-19 | 删除 B 站字幕歌词来源与 `playerSubtitles` / `fetchBCCSubtitle`。 |
| 2026-08-19 | 增加 `navProfile()`；扫码成功带回 refresh_token / buvid3；401/-101 通知会话过期。 |
| 2026-08-19 | `FavItem` 解码 `ugc.first_cid` / 顶层 `cid`，供首页和收藏夹少走 pageList。 |
| 2026-08-19 | 音频流改 WBI playurl；新增 `playbackHeaders` 给 CDN 拉流/下载使用。 |
| 2026-08-19 | 移除 LRCLIB；接入 BM 标题整理与网易云/酷狗/QQ 多平台歌词，加入翻译、逐字歌词与手动候选。 |
| 2026-07-27 | 全项目 review 修复 + 文档同步：WBI 签名前过滤 `!'()*`；LyricsClient 时长门槛 25s/45s、多时间标签展开、极短歌名降分。 |
| 2026-06-24 | 初始文档创建。 |
