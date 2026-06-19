# CLAUDE.md

本文件为 Claude Code（claude.ai/code）在本仓库工作时提供指引。

## 构建与运行

`.xcodeproj` 由 `project.yml` 生成，不入库。每当修改 `project.yml` 或新增 Swift 文件后都要重新生成：

```bash
xcodegen generate
```

编译检查（无交互式测试 —— 由用户在真机上验证）：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project BiliMusic.xcodeproj -scheme BiliMusic \
  -destination 'generic/platform=iOS Simulator' build
```

没有测试 target。所有验证都通过 AltStore 在真机 iPhone 上完成（免费开发者账号，签名 7 天有效需续签）。

## 架构

单 Module 的 SwiftUI app，iOS 17+，`@Observable` MVVM。无第三方依赖 —— 只用 URLSession + AVPlayer。

### 全局状态

`PlayerEngine` 是唯一的 `@Observable` 类，由 `BiliMusicApp` 通过 `.environment(engine)` 注入。视图用 `@Environment(PlayerEngine.self)` 读取。`CacheStore.shared` 和 `FavoriteManager.shared` 是单例，直接访问。

### 数据流

```
BiliClient (URLSession) → Track struct → PlayerEngine (queue + AVPlayer)
                        ↘ CacheStore (JSON index + Documents/audio/)
```

`Track` 是普通 `struct`（bvid、cid、title、artist、coverURL、duration）。音频/MV 流 URL 是**临时的**（约 2 小时过期）—— 只持久化 bvid/cid。每次播放都通过 `BiliClient.audioStream(bvid:cid:preferredQuality:)` 或 `videoStream(bvid:cid:profile:)` 现取新 URL。

### API 层（`BiliMusic/API/`）

- **`BiliClient`** —— 所有 B站接口。每个请求都必须带上 `BiliClient.headers`（Referer + 浏览器 UA），否则 CDN 返回 403。存在 Cookie（`CookieStore.cookie`）时一并附上。
- **`WBISigner`** —— 搜索和首页推荐接口需要 WBI 签名。用 nav 接口的 key + 64 字符重排表 → MD5。key 缓存 24 小时。启动时调用 `WBISigner.prewarm()`。
- **`LyricsClient`** —— 仅用 LRCLIB。不 fallback 到 B站字幕（自动 CC 会产生「♪音乐♪」噪声）。
- 音质 ID：`30216`=64K，`30232`=132K，`30280`=192K，`30250`=杜比，`30251`=Hi-Res。权威清单是 `BiliClient.qualityOptions` —— 各处引用它，不要重复定义。

### 播放器（`BiliMusic/Player/`）

- **`PlayerEngine`** —— `@Observable @MainActor`。持有 `AVPlayer`、队列（`[Track]`）、`queueIndex`、播放状态、歌词以及 MV/音乐模式。对 `timeControlStatus` 的 KVO 让 UI 与 AVPlayer 的真实状态保持同步。`isScrubbing` 标志位防止拖动进度条时时间观察器与手势冲突。
- **`QueueMode`**：`.sequential`、`.shuffle`、`.repeatOne`、`.radio`。电台模式在当前歌曲开始播放后，通过 `RecommendationEngine` 预取下一首。
- **`RecommendationEngine`** —— 无状态 struct，`@MainActor`。三种模式：`.home`、`.radio`、`.relatedPanel`。从收藏夹（随机页）、相关视频、播放历史、歌单相邻曲目中取候选；用确定性打分 + ±10 随机扰动排序；单次调用内按 bvid 去重。调用方维护跨调用的排除集（`shownBVIDs`），避免多次刷新出现重复。
- **`MusicFilter`** —— 判定是否为音乐内容的启发式规则：B站音乐分区 `typeID` 集合 + 标题/时长规则。
- **`PlaybackHistoryStore.shared`** —— JSON 存于 `Documents/playback-history.json`，上限 300 条。

### 鉴权（`BiliMusic/Auth/`）

- **`CookieStore`** —— 把完整 Cookie 字符串存在 Keychain 里。关键字段：`SESSDATA`、`bili_jct`、`DedeUserID`。发起需要登录的请求前先检查 `CookieStore.isLoggedIn`。

### 缓存（`BiliMusic/Cache/`）

- **`CacheStore.shared`** —— `@Observable`。JSON 索引在 `Documents/cache_index.json`；音频文件在 `Documents/audio/{bvid}_{cid}.m4a`。
- **`DownloadManager.shared`** —— 用 `URLSessionDownloadTask`（不是 `AsyncBytes`）。下载时带同样的 `BiliClient.headers`。

### 功能页（`BiliMusic/Features/`）

- **`RootView`** —— tab bar + 自定义全屏播放器浮层（不是 `.fullScreenCover`）。全屏播放器是一个 `NowPlayingView`，用 `.offset(y:).ignoresSafeArea()` 实现从 mini bar 上滑出现。
- **`NowPlayingView`** —— 三页 `TabView`（队列 ← 当前歌曲 → 推荐）。通过下滑手势关闭；阈值约 130pt 或预测约 260pt。
- **`HomeView`** —— 出现时触发 `RecommendationEngine(.home)`；每次点「换一批」累积 `shownBVIDs` 以避免重复。

### 设计（`BiliMusic/Design/`）

- **`AppTheme`** —— `accent = Color.primary`（不用 B站红）。`playerGradient` 是中性的系统渐变（不做专辑封面虚化 —— 浅色模式下会冲淡内容）。所有颜色都用系统语义色值。

## 关键约束

- **不做模拟器交互测试** —— 只做编译验证；真机测试由用户完成。
- **不强加红色/品牌主色** —— `AppTheme.accent` 保持 `Color.primary`。
- **不做专辑封面虚化背景** —— 用 `AppTheme.playerGradient`（中性）。
- **封面是 16:9** —— B站封面是 16:9；用 `height: coverSize * 9/16`，不要用正方形。
- **新增 Swift 文件要 `xcodegen generate`** —— `.xcodeproj` 是生成的；加文件不重新生成，Xcode 找不到。
- **流 URL 不可持久化** —— 只把 bvid/cid 落盘；URL 约 2 小时后过期。
