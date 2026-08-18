[根目录](../../CLAUDE.md) > **Player**

## 模块职责

播放引擎核心。管理音频/视频播放、播放队列、推荐算法、音乐内容判定、CDN 选择、播放诊断、网络监测和播放历史。是全局状态的核心。

## 入口与启动

- **文件**: `PlayerEngine.swift`（主入口）
- `PlayerEngine` 由 `BiliMusicApp` 创建并通过 `.environment(engine)` 注入。
- 其他文件：`QueueController.swift`, `RecommendationEngine.swift`, `MusicFilter.swift`, `StreamResolver.swift`, `AudioCDNSelector.swift`, `PlaybackDiagnostics.swift`, `NetworkMonitor.swift`, `PlaybackHistoryStore.swift`, `PlaybackQueueStore.swift`, `LyricsStore.swift`

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
- `lyrics` / `lyricsDocument` — 当前逐行歌词与来源文档（含翻译、逐字时间）
- `lyricSearchResults` / `lyricProvider` — 手动匹配候选与当前平台
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
| `searchLyrics(keyword:provider:)` / `selectLyricsResult(_:)` | 手动搜索并切换歌词候选 |
| `adjustLyricOffset(by:)` / `resetLyricOffset()` | 以 500ms 步进校准歌词并持久化 |
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

候选来源（按质量分层）：收藏夹 seeds → 当前曲目 related → 历史 related → 缓存 related → 搜索 fallback
打分因素：来源基分 + 音乐判定 + 时长 + 同歌手/标题 + 收藏 + 已缓存 - 已播放 - 非音乐提示

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
- 上限 300 条，JSON 持久化到 `Documents/lyrics-library.json`；换曲优先读取本地缓存。

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
- `MusicFilter.swift`
- `StreamResolver.swift`
- `AudioCDNSelector.swift`
- `PlaybackDiagnostics.swift`
- `NetworkMonitor.swift`
- `PlaybackHistoryStore.swift`
- `PlaybackQueueStore.swift`
- `LyricsStore.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-08-19 | 冷启动恢复队列与进度；收藏/首页写入 cid；本地缓存命中会 touch。 |
| 2026-08-19 | 起播加速：换曲复用 AVPlayer、拉流带 Cookie、点歌不抢网拉封面、自动缓存默认开启并在出声 1.5s 后落盘、慢启动 CDN 探测与等待并行。 |
| 2026-07-27 | 全项目 review 修复 + 文档同步：新增 AudioCDNSelector / PlaybackDiagnostics；QueueController 签名改 `nextIndex(mode:queueCount:currentIndex:automatic:)`（repeatOne 手动切歌队尾回绕）；PlayerEngine freshRemote 重试、repeatOne 免重建、观察器清理、UI 测试 fixture 注入。 |
| 2026-06-24 | 初始文档创建。 |
