[根目录](../../CLAUDE.md) > **Player**

## 模块职责

播放引擎核心。管理音频/视频播放、播放队列、推荐算法、音乐内容判定、CDN 选择、播放诊断、网络监测和播放历史。是全局状态的核心。

## 入口与启动

- **文件**: `PlayerEngine.swift`（主入口）
- `PlayerEngine` 由 `BiliMusicApp` 创建并通过 `.environment(engine)` 注入。
- 其他文件：`QueueController.swift`, `RecommendationEngine.swift`, `RecommendationMemory.swift`, `ListeningTaste.swift`, `MusicFilter.swift`, `StreamResolver.swift`, `AudioCDNSelector.swift`, `PlaybackDiagnostics.swift`, `NetworkMonitor.swift`, `PlaybackHistoryStore.swift`, `PlaybackQueueStore.swift`, `LyricsStore.swift`, `TrackMetadataStore.swift`, `MusicMetadata.swift`, `MusicMetadataController.swift`, `OnDeviceLyricsAligner.swift`

## 对外接口

### PlayerEngine（`@Observable @MainActor`）

核心属性：
- `state` — idle / loading / playing / paused / failed(String)
- `queue` — `[Track]` 播放队列
- `queueIndex` — 当前播放下标
- `currentTime` — 当前播放进度
- `current` — 当前曲目
- `queueMode` — 顺序/随机/单曲循环/电台
- `playbackMode` — 音乐/MV
- `lyrics` / `lyricsDocument` — 当前逐行歌词与来源文档（含翻译、逐字时间、是否跟随播放）
- `lyricSearchResults` / `lyricProvider` — 手动聚合搜索候选与当前选中来源
- `lyricOffsetMilliseconds` — 当前曲目的用户校准偏移
- `isScrubbing` — 是否正在拖动进度条

核心方法：
| 方法 | 用途 |
|------|------|
| `play(tracks:startAt:queueMode:)` | 替换队列并从指定位置播放 |
| `playRadio(seed:)` | 电台播放 |
| `playNext()` / `playPrevious()` | 上下曲 |
| `jump(to:)` | 跳到队列中指定位置 |
| `appendToQueue(_:)` | 追加到队列尾部 |
| `togglePlayPause()` / `play()` / `pause()` | 播放/暂停 |
| `seek(to:)` | 跳转到指定秒 |
| `searchLyrics(keyword:)` / `selectLyricsResult(_:)` | 手动聚合搜索网易云/QQ/酷狗/LRCLIB/VocaDB；点选后保留 LRC/逐字时间轴，不再套用「原唱待确认」冻结 |
| `setLyricOffset(milliseconds:persist:userSet:)` / `resetLyricOffset()` / `autoAlignLyricOffset()` | 歌词校准：±10 秒滑块；首次匹配不自动平移。后台只在本地音频互相关明显好过 0 轴时才改；「自动对齐」才用落点打分 |
| `generateOnDeviceWordTimings(rebuildTimeline:replaceExistingWordTimings:progress:)` | 仅供工程 smoke test 保留的实验路径；真机 MLX Metal SIGABRT 后不再从 UI 调用 |
| `generatePrecisionHostWordTimings(progress:)` | 用户主动把缓存音频交给 Windows 高精度主机；结果经客户端二次门禁后才以独立来源保存并应用 |
| `seek(to lyricLine:)` | 点击歌词行跳转播放进度 |
| `beginScrub()` / `endScrub(to:)` | 进度条拖动开始/结束 |
| `setPlaybackMode(_:)` | 切换音乐/MV 模式 |
| `setPlaybackQuality(_:)` | 切换音质 |
| `preload(tracks:)` | 批量预取（5 首，无延迟） |
| `preload(tracks:limit:delay:)` | 批量预取（自定义） |
| `play(bvid:)` | `AUTOPLAY_BV` 诊断入口按 BV 号直播放 |
| `upgradeMVForFullscreen()` | 全屏时提升 MV 画质 |
| `handleScenePhase(isBackground:)` | 场景切换处理 |
| `installUITestFixture(tracks:startAt:)` | UI 测试下注入 fixture 队列（`BILIMUSIC_UITEST_FIXTURE=1` 时走此路径，不建真实 AVPlayer 流） |

行为要点：
- freshRemote 起播失败时会失效 StreamResolver 缓存并重取流重试。
- repeatOne 自动循环直接 `seek(to: .zero)`，不重建 AVPlayer（避免静音间隙）；item 失效才走完整 `startCurrent` 重启。
- `tearDownPlayerObservers()` 集中拆除 KVO/时间观察器/通知；`deinit`（非 MainActor）兜底清理，token 只在 init 阶段写入以避开 `@Observable` 访问器。

### QueueController（static 枚举）

- `nextIndex(mode:queueCount:currentIndex:automatic:)` — 计算下一曲下标。repeatOne 下 `automatic: true`（自然播完）返回原下标；手动切歌在队尾回绕到 0（`hasNext` 在单曲循环下恒为 true，锁屏「下一曲」按钮保持可用）。
- `appendUnique(_:to:)` — 去重追加，返回实际新增的曲目。

### RecommendationEngine（无状态 struct）

三种模式: `.home`、`.radio`、`.relatedPanel`
- `recommendations(mode:context:limit:)` — 获取推荐曲目列表
- `nextRadioTrack(after:excludedKeys:)` — 电台模式最佳下一首

首页候选：按 `ListeningTaste` 常听歌手和歌名搜音乐区（页码 1–3 错开）；够 8 首品味命中就不再补推荐流/related。
电台/面板：当前曲 related、清洗后的歌手搜索、歌单邻居。
打分：来源基分 + 音乐判定 + 时长 + 同歌手/标题 + 收藏 + 已缓存 + 品味命中 - 已播放 - 非音乐提示 - 多源重复（hub）惩罚。
`RecommendationMemory` 记住 6 小时内展示/选中的 BV；`RadioRelatedPicker` 跳过这些 BV，并在剩余音乐里抽样，避免总拿 related 第一条。

### MusicFilter（static 枚举）

| 方法 | 用途 | 时长门槛 |
|------|------|---------|
| `isMusic(_:)` | 宽松判定（推荐扩列） | 60~720s |
| `isStrictMusic(_:)` | 严格判定（电台种子） | 75~540s |
| `isSearchResultMusic(_:query:)` | 搜索专用判定 | 60~720s + 分区+关键词 |
| `isSearchResult(_:query:mode:)` | 按 mode 分发 | 见上 |

### StreamResolver（`@MainActor` class）

- `prepareAudio(for:preferredQuality:)` — 准备音频流（补全 cid → 取 playurl → 缓存 90 分钟）
- `cachedAudio(for:)` — 查内存缓存
- `invalidateAudio(for:)` — 失效缓存

### AudioCDNSelector（static 枚举）

- 音频 CDN 竞速选择器：对 playurl 返回的多个 CDN 候选 URL 去重（`deduped(_:)`）、并发探测可达性与延迟。
- 记录 host 健康度（`AudioCDNHostHealth`），优选 host 持久化在 `UserDefaults`（key `preferredAudioCDNHost`）。
- 测量结果暴露为 `Measurement`（host、毫秒、可达性），OSLog category `cdn`。

### PlaybackDiagnostics

- `PlaybackDiagnosticEvent` — 起播链路诊断事件。checkpoint：tap → currentAssigned → sourceResolved → playerItemCreated → playRequested → firstPlaying。
- 记录来源（localCache / preparedRemote / freshRemote / mvRemote）、音质、带宽与各阶段耗时，OSLog category `playback-diagnostics`。

### NetworkMonitor（`@Observable` 单例）

- `isWiFi` — 是否 Wi-Fi 网络（供 Wi-Fi 优先 MV 策略判断）
- 使用 `NWPathMonitor` 实时监测网络状态

### PlaybackHistoryStore（`@Observable` 单例）

- `record(_:)` — 记录播放（去重置顶 + 次数累加，防抖写盘）
- `clear()` — 清空历史
- `flush()` — 立即写盘
- 上限 300 条，JSON 持久化到 `Documents/playback-history.json`

### PlaybackQueueStore（`@MainActor` 单例）

- 冷启动恢复队列、下标、模式和进度；JSON 持久化到 `Documents/playback-queue.json`
- 最多 200 首，超出时保留当前曲附近窗口；电台恢复为顺序播放
- 只持久化曲目元数据，不保存会过期的流 URL；恢复后暂停待命，不自动续播
- `flush()` 立即写盘（切后台）

### LyricsStore（`@MainActor` 单例）

- 保存用户选定的 `LyricsDocument`、平台和时间偏移，按 `TrackKey` 支持 cid 补全匹配。
- 上限 300 条，JSON 持久化到 `Documents/lyrics-library.json`；换曲优先读取本地缓存。加载时丢弃已停用的 B 站字幕条目。

### MusicMetadata / MusicMetadataController

- `Track` 只表示 B 站播放物；清洗后的歌名/歌手、歌词和偏移组成 `MusicMetadata`，挂在 `TrackKey` 上。
- `MusicMetadataController` 负责歌词自动匹配、手动候选和偏移持久化；`PlayerEngine` 只在出声后调用，不进入起播热路径。
- `LyricsResolver` 每个翻唱/原唱 pass 先试私有 LDDC 聚合服务，只有逐字候选通过 App 自身的标题、歌手、时长与版本范围门禁才能提前返回；否则继续现有曲库直连。
- 手动候选先按版本范围排序，然后把已取回且通过双重校验的逐字词置顶；逐字质量不能跨过翻唱/原唱身份层级。
- 已标记为翻唱的曲目在原唱 pass 中即使时长相近，也强制记为 `canonicalOriginal`，不得伪装成 `sameRecording` 精确同版本。

### OnDeviceLyricsAligner

- 当前用户入口已停用：真机 ASR 与 Forced Aligner 各有一次 `mlx::core::gpu::check_error` → `SIGABRT`，无法由 Swift 捕获。设置只允许删除已有权重；以下是保留的实验实现，不代表可用产品能力。
- actor 封装 MLXAudio `Qwen3ForcedAlignerModel`；4-bit 权重按需存到 Application Support，完成任务后释放模型引用。
- `OnDeviceKaraokeBuilder` 负责中日韩字符/英文词预分；强脚本证据优先，纯汉字等歧义才使用首次元数据清洗返回的语言。已有 LRC 先用整曲 ASR 多行稠密共识估计全局平移，门禁不过就保留原轴；校准后的行首拥有决定权，Forced Aligner 只负责 ±2.5 秒窗口内的行内节奏。只有 ASR 完整重建粗轴允许模型细化 onset。生成后修复单字回摆、越界、重叠与空档，再输出无省略 QRC。
- 无时间轴或用户强制重建时，`Qwen3ASRModel` 按 20 秒分块提供粗文本锚点；`OnDeviceCoarseTimelineBuilder` 用 LCS 与正确歌词匹配并执行覆盖率门禁。ASR 释放并清 cache 后才加载 Forced Aligner，不允许双模型同时驻留。
- 同时演唱用 `LyricVoiceRole + layerID + overlapGroup` 表达；同组声部共享 ASR 粗搜索窗口，再由 Forced Aligner 在同一音频窗口独立对齐，逐字结果允许重叠并通过 `LyricsDocument.vocalLines` 持久化。
- 两个模型都不在 IPA 内；设置页可补全下载或一起删除。该服务只能由显式用户操作触发。

### PrecisionLyricsHostClient

- Windows 精修是显式、异步增强来源，不进入播放或自动歌词热路径。`PlayerEngine` 只负责确保音频已缓存、隔离切歌后的陈旧结果，并在门禁成功后让 `MusicMetadataController` 持久化。
- 客户端先对 Tailscale 与局域网备用地址各做 5 秒健康探测，全部不可达时明确失败；不得用 `waitsForConnectivity` 长时间挂起。计算进度持续反馈，服务端缓存仍按确定性 job ID 复用。
- 当前要求逐行 LRC 且无 `vocalLines`；本机 MLX 已停用，所以纯文本暂不生成，并行声部保持原数据不被扁平结果覆盖。
- 写回仍要求全文、行数、单调轴、全局位移和回退比例过门。WhisperX 字符覆盖低于 50% 拒绝，50–79% 保存但标记需确认，80% 以上确认。
- 服务端失败只返回异常摘要；客户端仍需从任意多行错误中提取最后一个有意义的异常并截到 180 字，禁止把 Python/PowerShell traceback 直接显示给用户。
- 最终全局 offset 必须排除距第一遍搜索窗边界 ≤0.25s 的 onset；局部 Qwen/WhisperX 即使相互差 ≤0.8s，距全局锚点超过 1.25s 也只能提供逐字节奏，不能改行首（第一行放宽到 3s）。pipeline 版本进入 job ID，算法升级后不得复用旧缓存。
- `precisionHost` 的 offset 永远为 0：读取旧缓存时清掉残留手动偏移并写回，也不为该来源运行 RMS 自动 offset refine。
- 校准 Sheet 只有实际观察到 Slider `editing=true` 后，才允许 `editing=false` 把当前值标为用户设置；禁止仅打开/关闭 Sheet 就把自动 offset 重新分类为手动。
- 质量门禁分别比较物理 LRC/QRC/主机行数与排版后的源/结果行数；不能把 raw line count 和 `LyricVocalArrangement` 拆出的声部数直接比较。同一 `overlapGroup` 的同时行允许相同起点，其他非单调仍拒绝。

## 关键依赖与配置

- `AVPlayer` — 核心播放器；换曲复用同一实例，只 `replaceCurrentItem`
- `AVAudioSession.category(.playback, mode: .default)` — 后台播放
- `AVPlayer.automaticallyWaitsToMinimizeStalling = false` — 快起播 + 手动断流恢复
- 远程拉流使用 `BiliClient.playbackHeaders`（UA + Referer + Origin + 可选 Cookie）
- 点歌时只从内存恢复封面；网络封面等到出声后再拉
- 自动缓存默认开启，出声约 1.5s 后后台落盘
- `preferredForwardBufferDuration = 30`（在线音频）/ `6`（MV）/ `0`（本地）
- StreamResolver 的 playurl 缓存 TTL：90 分钟
- RecommendationPoolCache 的候选池 TTL：8 分钟
- PlaybackHistoryStore 上限：300 条
- PlaybackQueueStore 上限：200 首
- 音质偏好：`UserDefaults.integer(forKey: "playbackQuality")`

## 数据模型

- `Track` — 曲目 struct（aid, ownerMid, typeID, bvid, cid, title, artist, coverURL, duration）
- `TrackKey` — (bvid, cid?) 精确到分 P 的标识符
- `PlayerEngine.State` — idle / loading / playing / paused / failed
- `PlayerEngine.QueueMode` — sequential / shuffle / repeatOne / radio
- `PlayerEngine.PlaybackMode` — music / mv
- `PlayerEngine.LyricLine` — 歌词行（from, to, text）
- `PlaybackHistoryEntry` — 播放历史条目（track, playCount, lastPlayedAt）

## 相关文件清单

- `PlayerEngine.swift`
- `QueueController.swift`
- `RecommendationEngine.swift`
- `RecommendationMemory.swift`
- `ListeningTaste.swift`
- `MusicFilter.swift`
- `StreamResolver.swift`
- `AudioCDNSelector.swift`
- `PlaybackDiagnostics.swift`
- `NetworkMonitor.swift`
- `PlaybackHistoryStore.swift`
- `PlaybackQueueStore.swift`
- `LyricsStore.swift`、`LyricHighlightModel.swift`、`LyricsOffsetEstimator.swift`
- `OnDeviceLyricsAligner.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-08-19 | 真机两次 MLX Metal SIGABRT 后停用本机生成 UI；算法实现仅留给 smoke test。 |
| 2026-08-19 | 自动与手动歌词接入 LDDC 私有聚合优先级；可靠逐字候选同版本置顶，未命中继续直连。 |
| 2026-08-19 | 接入 Windows 高精度主机来源；显式上传、任务缓存、切歌隔离和二次质量门禁后才写回。 |
| 2026-08-19 | 增加主唱/和声/二重唱并行声部模型、保守解析、共享粗窗口和独立逐字对齐。 |
| 2026-08-19 | iPhone 本机接入 Qwen3 0.6B 4-bit 逐字对齐；整曲改为短段推理，避免 per-process-limit Jetsam。 |
| 2026-08-19 | 首页找歌改为常听歌手搜索；推荐流和 related 只补数量。 |
| 2026-08-19 | 首页推荐改走换页 feed；增加展示记忆与 related hub 惩罚。 |
| 2026-08-19 | 文本候选在时长接近时恢复跟随播放；时长差过大才不跟播。 |
| 2026-08-19 | 同版本优先有时间轴的歌词；文本候选保留 LRC 但不跟随播放。 |
| 2026-08-19 | 歌词自动对齐改为落点打分 + 本地音频互相关；手动偏移不再被后台修正。 |
| 2026-08-19 | 歌词搜索改用清洗后的日文原名；中文译名不再进入检索词。 |
| 2026-08-19 | 歌词校准改为 ±10 秒滑块 sheet，拖动即时预览，松手后落盘。 |
| 2026-08-19 | 冷启动恢复队列与进度；收藏/首页写入 cid；本地缓存命中会 touch。 |
| 2026-08-19 | 歌词与清洗元数据从 `PlayerEngine` 抽到 `MusicMetadataController`；显示层继续优先用 `TrackMetadataStore`。 |
| 2026-08-19 | 起播加速：换曲复用 AVPlayer、拉流带 Cookie、点歌不抢网拉封面、自动缓存默认开启并在出声 1.5s 后落盘、慢启动 CDN 探测与等待并行。 |
| 2026-07-27 | 全项目 review 修复 + 文档同步：新增 AudioCDNSelector / PlaybackDiagnostics；QueueController 签名改 `nextIndex(mode:queueCount:currentIndex:automatic:)`（repeatOne 手动切歌队尾回绕）；PlayerEngine freshRemote 重试、repeatOne 免重建、观察器清理、UI 测试 fixture 注入。 |
| 2026-06-24 | 初始文档创建。 |
