[根目录](../../CLAUDE.md) > **Player**

## 模块职责

播放引擎核心。管理音频/视频播放、播放队列、推荐算法、音乐内容判定、网络监测和播放历史。是全局状态的核心。

## 入口与启动

- **文件**: `PlayerEngine.swift`（主入口）
- `PlayerEngine` 由 `BiliMusicApp` 创建并通过 `.environment(engine)` 注入。
- 其他文件：`QueueController.swift`, `RecommendationEngine.swift`, `MusicFilter.swift`, `StreamResolver.swift`, `NetworkMonitor.swift`, `PlaybackHistoryStore.swift`

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
- `lyrics` — `[LyricLine]` 歌词
- `isScrubbing` — 是否正在拖动进度条

核心方法：
| 方法 | 用途 |
|------|------|
| `play(tracks:startAt:queueMode:)` | 替换队列并从指定位置播放 |
| `playRadio(seed:)` | 电台播放 |
| `playNext()` / `playPrevious()` | 上下曲 |
| `jump(to:)` | 跳到队列中指定位置 |
| `removeFromQueue(at:)` | 从队列移除 |
| `appendToQueue(_:)` | 追加到队列尾部 |
| `togglePlayPause()` / `play()` / `pause()` | 播放/暂停 |
| `seek(to:)` | 跳转到指定秒 |
| `beginScrub()` / `endScrub(to:)` | 进度条拖动开始/结束 |
| `setPlaybackMode(_:)` | 切换音乐/MV 模式 |
| `setPlaybackQuality(_:)` | 切换音质 |
| `preload(tracks:)` | 批量预取（5 首，无延迟） |
| `preload(tracks:limit:delay:)` | 批量预取（自定义） |
| `schedulePreload(_:)` | 单曲预加载（列表滚动时） |
| `play(bvid:)` | 直接按 BV 号播放（调试） |
| `upgradeMVForFullscreen()` | 全屏时提升 MV 画质 |
| `handleScenePhase(isBackground:)` | 场景切换处理 |

### QueueController（static 枚举）

- `nextIndex(mode:queueCount:currentIndex:)` — 计算下一曲下标
- `appendUnique(_:to:)` — 去重追加
- `remove(at:from:currentIndex:)` — 删除并维护下标

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

### NetworkMonitor（`@Observable` 单例）

- `isWiFi` — 是否 Wi-Fi 网络（供 Wi-Fi 优先 MV 策略判断）
- 使用 `NWPathMonitor` 实时监测网络状态

### PlaybackHistoryStore（`@Observable` 单例）

- `record(_:)` — 记录播放（去重置顶 + 次数累加，防抖写盘）
- `clear()` — 清空历史
- `flush()` — 立即写盘
- 上限 300 条，JSON 持久化到 `Documents/playback-history.json`

## 关键依赖与配置

- `AVPlayer` — 核心播放器
- `AVAudioSession.category(.playback, mode: .default)` — 后台播放
- `AVPlayer.automaticallyWaitsToMinimizeStalling = false` — 快起播 + 手动断流恢复
- `preferredForwardBufferDuration = 10`（在线流）/ `0`（本地）
- StreamResolver 的 playurl 缓存 TTL：90 分钟
- RecommendationPoolCache 的候选池 TTL：8 分钟
- PlaybackHistoryStore 上限：300 条
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

- `PlayerEngine.swift`（851 行）
- `QueueController.swift`
- `RecommendationEngine.swift`
- `MusicFilter.swift`
- `StreamResolver.swift`
- `NetworkMonitor.swift`
- `PlaybackHistoryStore.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-06-24 | 初始文档创建。 |
