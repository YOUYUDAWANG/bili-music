---
type: project_topic
status: active
summary: "Bilibili Music 整机接手手册：当前真相、禁止事项、密钥、部署、验证与下一步。"
tags: [handoff, operations, lyrics, worker, playback]
contains: [procedure, decision, deployment-boundary]
created: "2026-08-20"
updated: "2026-08-20"
related: ["CLAUDE.md", "cairn/ROADMAP.md", "cairn/lyric-performance-director.md", "cairn/lyrics-architecture.md", "cairn/playback-startup.md", "cairn/home-discovery.md"]
authoring_mode: ai_generated
---
# Bilibili Music 接手手册

给下一位代理或人：先读本页，再按任务去读专题，不要从零扫仓库。

规则与架构主本仍是根目录 `CLAUDE.md`。本手册只写**现在怎么接手**，不复制完整架构。

## 1. 三十秒快照

个人自用的 SwiftUI iPhone 音乐客户端。B 站当曲库，Apple Music 式交互，16:9「横版影像唱片机」。部署目标 **iOS 26.0+**，验收机 **iPhone 17 Pro / iOS 27**。Xcode 版本见仓库根 `.xcode-version`（当前 26.5）。

**核心价值：让音乐尽快、稳定地响起来。** 起播和不中断播放优先于歌词、推荐、MV、缓存和 UI。

v1 四个阶段已完成。当前是 Phase 05 原生感与歌词，以及几条已上线的私有服务。产品默认路径仍是「能听、能找、能收藏」；歌词舞台和 Luna 都是 Debug 实验，**Release 不得自动生成演出**。

| 面 | 默认 | 现状 |
|---|---|---|
| 起播 | 复用 AVPlayer + WBI playurl + Cookie 拉流 + 独立 `playbackSession` | 稳定优先，真机日常路径仍要用户确认 |
| 首页 | 1+4 纯封面墙，常听歌手搜新歌，与收藏夹旧歌混排 | 见 `cairn/home-discovery.md` |
| 歌词获取 | 出声后：本地 → LDDC → 曲库直连；不用 B 站字幕 | Mac mini LDDC 已常驻 |
| 歌词舞台 | **本地规则** | V5 / V5.1 / V5.2 / V5.3 仅 Debug |
| Luna V5.1 | 手动「生成 V5.1」才打 `/v2` | Worker 已上线，见第 6 节 |
| 本机 MLX 对齐 | 已停用 | Metal `SIGABRT`，禁止恢复用户入口 |

## 2. 接手后先读

1. 根目录 `CLAUDE.md`
2. `.planning/STATE.md`、`.planning/ROADMAP.md`、`.planning/REQUIREMENTS.md`
3. `cairn/ROADMAP.md` 与 `cairn/LOG.md` 顶部
4. 按任务再读：
   - 起播 / 打不开：`cairn/playback-startup.md`
   - 歌词来源 / 身份 / 对齐：`cairn/lyrics-architecture.md`
   - 舞台 / Luna / Worker：`cairn/lyric-performance-director.md`
   - 首页推荐：`cairn/home-discovery.md`
   - 视觉：`cairn/visual-language.md`

专题文档优先于旧 LOG。不要用过期 LOG 覆盖已更正的真相。

## 3. 绝对不要做

- 不要为了歌词、舞台、推荐去碰起播热路径，或把网络抢回 `api.bilibili.com` 的播放会话。
- 不要改 LNPopup / TabView 手势所有权；首页封面点击必须仍打开同一个 popup 播放器。
- 不要把 Release 默认舞台改成 V5.1 / V5.3，也不要自动请求 Luna。
- 不要用 B 站字幕当歌词；不要把原唱时间轴静默套到翻唱上当精确同步。
- 不要持久化音频/MV 流 URL；只落盘 bvid/cid。
- 不要对 WBI 已编码的 URL 再做一次 `addingPercentEncoding`。
- 不要恢复本机 MLX 生成入口。
- 不要提交 `Local.xcconfig`、钥匙串 Token、Cloudflare Secret、歌词正文日志。
- 未经用户明确要求，不要回退别人的未提交修改，不要重发 Worker。
- 新增 Swift 文件后必须 `xcodegen generate`。

## 4. 本机怎么跑

```bash
cp Local.xcconfig.example Local.xcconfig   # 填 Team ID 与 Bundle ID
xcodegen generate
```

编译检查：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project BiliMusic.xcodeproj -scheme BiliMusic \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation build
```

聚焦单测把 destination 换成 `platform=iOS Simulator,name=iPhone 17`，并加 `-only-testing:BiliMusicTests/<Suite>`。

真机：免费开发者账号，签名约 7 天。构建脚本从钥匙串注入 Token。`ProcessInfoPlistFile` 会覆盖对最终 `Info.plist` 的直接改写，所以 LDDC / 高精度主机 Token 必须写进**独立签名资源**（`BiliMusicLDDCLyrics.plist`、`BiliMusicPrecisionLyricsHost.plist`），不要只改 Info.plist。

模拟器环境变量：

| 变量 | 作用 |
|---|---|
| `BILIMUSIC_LYRIC_STAGE_V51=1` | 启动即 V5.1 |
| `BILIMUSIC_LYRIC_STAGE_V52=1` | 启动即 V5.2 |
| `BILIMUSIC_LYRIC_STAGE_V53=1` | 启动即 V5.3 |
| `AUTOPLAY_BV` | 模拟器自动播一首 |

## 5. 密钥与私有地址

值不进仓库。只记名字和位置。

| 用途 | 钥匙串 account / service | App 注入 |
|---|---|---|
| Metadata / Luna Worker Bearer | `BiliMusic` / `com.youyudawang.BiliMusic.metadata-api` | `BiliMusicMetadataAPIKey` |
| LDDC Bearer | `BiliMusic` / `com.youyudawang.BiliMusic.lddc-lyrics-api` | 独立 `BiliMusicLDDCLyrics.plist` |
| 高精度主机 Bearer | `BiliMusic` / `com.youyudawang.BiliMusic.precision-lyrics-host` | 独立 `BiliMusicPrecisionLyricsHost.plist` |

Cloudflare Worker 密钥：`API_KEY`（对外 Bearer）、`CPA_UPSTREAM_API_KEY`（当前 Gemini 上游）、`UPSTREAM_API_KEY`（旧上游回滚）。vars 当前为 `UPSTREAM_BASE_URL=https://cpa.hachi-mi.uk`、`MODEL=gemini-3.7-flash-high`，并分别版本化 normalize、V1、V2、V3、V4；值不写进仓库或笔记。

读取钥匙串（不要打印到聊天或提交）：

```bash
security find-generic-password -a BiliMusic -s com.youyudawang.BiliMusic.metadata-api -w
```

`Local.xcconfig` 里的 URL：

- Metadata：`https://bilimusic-metadata.mercari-email-sale-worker.workers.dev/v1/music/normalize`
- `BILIMUSIC_LYRIC_DIRECTOR_API_URL` 可留空；App 会从 metadata URL 推导 `/v1`、`/v2`、`/v3` 或 `/v4/lyrics/direct`
- LDDC：Tailscale `100.108.23.60:8788`（常驻 Mac mini）
- 高精度主机：Tailscale 优先，失败走局域网 `192.168.10.129:8765`

## 6. 歌词舞台：版本对照

播放器 `⋯` → Debug「歌词舞台」互斥切换；「Luna」单独负责生成。只换中央画布，不换封面、进度条、LNPopup。

| 名字 | 是什么 | 谁生成 | 缓存 | 何时可用 |
|---|---|---|---|---|
| 本地规则 | `LyricMotionDirector` 逐行克制动效 | 本地 | 无独立舞台缓存 | 默认 |
| V5 行级 | `LyricStageScore` + `LyricStageView` | 本地规则或 Luna `/v1` | `Documents/lyric-performances.json` | Debug |
| V5.1 Event | StyleSheet / Section / Scene / Actor / Event → 预编译 glyph 轨 → 60fps Canvas `sample(at:)` | 本地安静基线，或显式 Luna `/v2` | `Documents/lyric-stage-v2.json` | Debug；切换本身不联网 |
| V5.2 | 「You＆合図」专曲全曲音频舞台 | 离线手工 + `AudioPerformanceMap` | 不写 V2 缓存 | 仅 `BV1XWdrBVEn3` 且歌词 ≥ 14 行 |
| V5.3 | 通用全曲编舞，无 BVID/标题/绝对秒分支 | 本地规划器，或显式 Luna `/v3` 构图 | `Documents/lyric-stage-v3.json` | 任意同步歌词；切换本身不联网 |
| V4 Scene Recipe | `AudioStructureScoreV4` + typed motif + 四种正交演出，叠到完整 V5.3 fallback | 已缓存音频事实 + 显式 Gemini `/v4` | `Documents/lyric-stage-v4.json` | Debug；生成、摘要、清除均显式 |
| 样片 | 18 秒四幕 motion study | 本地硬编码 | 不请求、不写盘 | Debug |

默认歌词和 V4 都遵守 static-first：普通词最多只在落点后短暂缩放 1.5%，36% 进度后归零；永久 tracking breath / cosmic drift、普通 beat/onset 正文缩放均已移除。Impact、Heartbeat 和结构交接仍是允许的稀疏强调。

V4 模拟器性能基线：iPhone 17 Pro / iOS 27 的专用 UI fixture 会断言 `v4:chorusMemory` 后采样双 residue 短 Hook（约 14 次文字绘制，不是理论 96-draw 极限）；最新 240 帧 Canvas draw p50 / p95 / p99 / max 为 0.93 / 3.30 / 5.56 / 12.01ms，0 帧超过 16.67ms。此基线只衡量 Canvas CPU 区间，不等同整帧或 GPU 性能。

硬规则：

- 有逐字轴时，**字的出现时刻只属于歌词轴**。音频 onset/beat 只能做落点后的回弹、冲击和场景强弱，不得把字往后拖。
- 无逐字轴不得伪卡拉 OK，不写 `syncWindow`。
- Luna 不得改写、翻译、合并歌词，只引用 `lineIndex` / token。
- 超预算时删 `.echo` Event，不能只清 `echoLayers` 计数。
- Actor 中心按 `(sceneID, actorID)`；中日文按 token 边界换行。
- 编译期 120 字预算去掉 backdrop/echo，绘制时不要再切正文。

真机 Debug 生成 V5.1：播放有同步歌词的歌 → `⋯` → Luna →「生成 V5.1 演出（线上 /v2）」。成功 toast 带 concept。清除走同一菜单，只删当前曲的 V2 缓存。

## 7. Metadata / Luna Worker

生产：`https://bilimusic-metadata.mercari-email-sale-worker.workers.dev`  
目录：`services/metadata-worker/`  
当前版本（2026-08-21）：`79c3d38c-363f-4c5d-b76b-625c16b3bdf1`。上一 V4 版本：`14834316-d27d-4c15-8bbb-435c3e7fae5c`；V4 上线前版本：`52cc64da-2efd-4ce6-84ad-df1472b9e692`。

| 方法 | 路径 | 合同 |
|---|---|---|
| GET | `/health` | 必须列出 normalize、V1、V2、V3、V4、embellish，并报告 V3/V4 switch |
| POST | `/v1/music/normalize` | `music-metadata-v8-gemini-3.7-flash` |
| POST | `/v1/lyrics/direct` | `lyric-performance-v4` + v5 stage；版本 `luna-lyric-director-v5-stage-preview` |
| POST | `/v2/lyrics/direct` | `lyric-stage-v2-events`；版本 `luna-lyric-director-v2-events` |
| POST | `/v3/lyrics/direct` | `lyric-stage-v3-choreography`；完整本地 V5.3 + 稀疏线上构图 |
| POST | `/v4/lyrics/direct` | `lyric-stage-v4-scene-recipe` / `scene-recipe-grammar-v1`；有界音频结构 + typed recipe |
| POST | `/v1/lyrics/embellish` | 有界语义微巧思 |

鉴权：`Authorization: Bearer <API_KEY>`。无密钥 → 401。Python 默认 UA 会被 Cloudflare 1010 拦截，探测时用 `User-Agent: BiliMusic/iOS-Director-V2`。

V2 实现要点：

- KV 前缀在哈希字符串里：`director-v2:${version}:${json}`，KV key 本身是 SHA-256，不能按 `director-v2:` 前缀列出。
- bible 与最多 4 段 scene **并行**，为了赶在旧 App 45s 无首包超时前返回。
- 空场景必须 `degraded=true`，禁止把假成功写入 KV。
- 非降级且非 partial 才缓存；当前实现是 **await put** 后再 200。
- 客户端：已装旧包仍是 45/55s；源码已改为 90/120s，**下次签名安装才生效**。

部署（需用户明确授权）：

```bash
cd services/metadata-worker
node --test
npx wrangler deploy --message "……"
npx wrangler deployments list --name bilimusic-metadata
```

部署后最低验收：health 六个端点、旧路由与 V4 无 Bearer=401、被修改链路一次 non-degraded 冷请求、相同请求 `cache=hit`、未修改路由回归。V3/V4 有独立 kill switch；不要默认启用任何联网舞台。

Worker 单测：`cd services/metadata-worker && node --test`（当前 53）。

## 8. 歌词从哪来

出声后，不进起播热路径：

1. `Documents/track-metadata.json` 里的分层身份（Worker `/v1/music/normalize`）
2. `LyricsResolver`：本地库 → LDDC `POST /v1/lyrics/resolve` → 网易云 / QQ / 酷狗 / LRCLIB / VocaDB
3. 先匹配版本（翻唱/原唱），再选时间轴质量（逐字 > 逐行 > 纯文本）
4. 原唱词套翻唱：时长差 ≤3s 可跟播但标「时间轴待确认」；更大差值降为纯文本

LDDC：Mac mini `~/Library/Application Support/BiliMusic/LDDCLyricsBackend`，只绑 Tailscale `100.108.23.60:8788`，用户级 LaunchAgent。GPL 代码不进 App。手动搜索用 request generation 隔离，已验证逐字文档按稳定 ID 保留；缺失时按 ID 再取，禁止静默退回普通接口。

高精度主机：Windows `D:\BiliMusicAligner`，仅播放器菜单显式触发。并行声部拒绝覆盖。App 取消轮询不会杀主机任务。错误摘要截到 180 字，禁止把 traceback 铺进 UI。

校准滑块：必须先观察到用户开始拖动，才允许结束回调把 offset 标成用户值。`precisionHost` 结果 offset 必须为 0。

## 9. 播放与首页（不要顺手改）

- `PlayerEngine` 是唯一 environment 全局播放状态。换曲只换 `AVPlayerItem`。
- 起播走 `playbackSession`；发现/搜索最多 2–3 路，点封面取消发现。
- 流 URL 约 2 小时过期。缓存 `Documents/audio/{bvid}_{cid}.m4a`，上限 120，LRU。
- 首页是海报墙，封面上不叠标题。新:旧约 2:3。`RecommendationMemory` 6 小时去重。不要把 related 当找歌主源。
- 工具页继续用克制 `AppTheme.accent`；播放器背景只用封面双色光场，禁止封面虚化。

## 10. 文件地图

| 路径 | 职责 |
|---|---|
| `BiliMusic/Player/PlayerEngine.swift` | 队列、AVPlayer、歌词时钟 |
| `BiliMusic/API/BiliClient.swift` | 全部 B 站接口 |
| `BiliMusic/API/LyricStageClientV2.swift` | `/v2` 客户端 |
| `BiliMusic/API/LyricPerformanceClient.swift` | `/v1` 导演客户端 |
| `BiliMusic/Features/Player/NowPlayingView.swift` | Debug 菜单与生成入口 |
| `BiliMusic/Features/Player/LyricStageCompilerV2.swift` | V5.1 预编译 |
| `BiliMusic/Features/Player/LyricStageCanvasView.swift` | 60fps 采样 |
| `BiliMusic/Features/Player/LyricStagePrototypeView.swift` | V5.2 / V5.3 / 样片 |
| `BiliMusic/Player/LyricsResolver.swift` | 歌词来源编排 |
| `services/metadata-worker/` | normalize + Luna V1/V2 |
| `services/lddc-lyrics-backend/` | 私有逐字聚合 |
| `scripts/windows_lyrics_aligner/` | 高精度主机脚本 |

设备文档（真机 Documents，排障时先看）：

- `playback-queue.json` / `playback-history.json`
- `lyrics-library.json`
- `lyric-performances.json`（V5）
- `lyric-stage-v2.json`（V5.1）
- `track-metadata.json`

## 11. 下一步（按优先级）

这些是未完成的产品验收，不是新功能清单。

1. **真机再点一次「生成 V5.1」**。Worker 已并行，旧包 45s 窗口现在通常够用。确认 toast、中央画布持续换行、重开 App 仍读 `lyric-stage-v2.json`。
2. **四首固定样本 A/B**：本地规则 vs V5 vs V5.1（必要时加 V5.3）。只有 V5.1 明显更好才讨论改默认。
3. **V5.2 vs V5.3** 整首听感。V5.3 不要为「You＆合図」加专用分支。
4. App 内验收 LDDC：翻唱同版本、原唱参考、直连回退。
5. 高精度主机至少再验两首不同结构；并行声部继续拒绝覆盖。
6. 日常听歌真机：首播、搜索、首页混排、LNPopup 开合、长时间跨 Tab。

不要在上述验收完成前继续堆舞台引擎功能。

## 12. 已知陷阱

- **V2 超时**：旧 App 45s 无首包即断。已用并行生成压到约 20s。源码 90/120s 尚未装进用户当前包。
- **假成功**：早期 `/v2` 把校验丢光的场景标成成功。空场景必须 degraded，且不写 KV。
- **V5.1 无动画**：旧入口只切渲染器；Canvas 必须吃 Timeline tick，歌词时钟不能被 Reduce Motion 整段冻结。
- **echo 残留**：预算删除必须去掉 verb=`echo` 的 Event。
- **CJK 不换行**：连续不可断字符会跨 token 黏成一句；按 token 边界拆。
- **partial 二重唱**：Luna 只覆盖一个声部时，补缺不要再塞回完整 [A,B] 本地场。
- **校准 Slider**：未拖动也会在 `editing=false` 时把自动 offset 写成用户值。必须先看到开始编辑。
- **Token 被编进包后又丢**：Xcode 后处理覆盖 Info.plist。用独立签名 plist。
- **Cloudflare 1010**：不要用 Python-urllib 默认 UA 打 Worker。
- **起播约 1 分钟才出声**：先查是不是发现/推荐和 playurl 抢连接，而不是先改歌词。

## 13. 回滚

- App 舞台：Debug「本地规则」+「清除 V5.1 演出」。不删用户歌词库。
- Worker：`npx wrangler rollback` 或部署列表里回到上一版。`/v1` 必须与 `/v2` 同 Worker 共存，不要只撤 V2 路由却弄丢 normalize。
- LDDC：停 LaunchAgent 即可；App 会回退直连曲库。
- 高精度主机：用户不点菜单就不会走。

## 14. 完成工作时

宣称完成、修复或验证之前，按 Cairn 门禁更新 `cairn/LOG.md`（最新在顶部，≤20 行），并把稳定结论写回对应专题。不要把完整计划抄进 `cairn/ROADMAP.md`。
