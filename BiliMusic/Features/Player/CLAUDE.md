[根目录](../../../CLAUDE.md) > [Features](../) > **NowPlaying (播放器 UI)**

## 模块职责

全屏正在播放页的 UI 实现。内容视觉采用“横版影像唱片机”：16:9 封面、电影字幕式信息与封面派生双色光场。首页封面入口使用 Home 局部 matched geometry 动画层，mini player 入口使用 LNPopupController。

## 入口与启动

- **文件**: `NowPlayingView.swift`（主入口）、`PlayerControlViews.swift`（控制子视图）、`PlayerSheetViews.swift`（歌词/合集/收藏等 sheet）
- 由 `RootView` 的 LNPopupUI `.floatingCompact + .automatic` 容器承载。
- 首页被点封面通过 Home 局部 matched geometry 动画层原位展开并反向缩回；关闭第一帧动画层停止命中测试，让底层 ScrollView 同时保持可滚动。
- 迷你播放器、主播放器开合、跟手下滑和安全区停靠由 vendored LNPopupController 统一管理；播放页自身不维护全屏级纵向关闭手势。

## 对外接口

### NowPlayingView


### 页面组成

| 子视图 | 用途 |
|--------|------|
| 播放器模式选择器 | 音乐/MV 切换 |
| 封面/视频 | 16:9 封面或 AVPlayer 视频播放器 |
| 曲目信息 | 标题、歌手、错误信息 |
| PlayerProgressBar | 原生 `Slider` 进度条（独立子视图限制 currentTime 订阅范围，并桥接 scrub 生命周期） |
| 控制按钮 | 上一曲、播放/暂停、下一曲 |
| 操作栏 | 收藏（短按/长按）、下载、音乐/MV 切换、更多 |
| 接下来播放页 | 与主播放器同屏切换；显示完整当前队列和 AutoPlay 相关推荐 |
| 歌词页 | LyricSheetView（滚动高亮、自动居中） |
| MV 全屏 | MVFullscreenView（全屏视频播放） |

### 视觉边界

- 竖屏封面接近屏幕边缘，标题/歌手左对齐并与封面左缘同基线；横屏信息也保持左对齐。
- 背景仅使用 `PlayerArtworkPalette.top → bottom` 的克制双色渐变和轻微暗化，不做封面模糊、径向 glow 或高饱和硬撞色。
- 系统 Liquid Glass 由 RootView 的底栏浮岛和必要 MV 浮层承担；播放内容层与队列不新增材质卡。

## 关键依赖与配置

- `PlayerEngine` — 所有状态通过 Environment 读取。
- `RecommendationEngine(.relatedPanel)` — 推荐歌曲数据源。
- `BiliClient.upPlaylistContaining` — 合集检测。
- `FavoriteManager` — 收藏操作。
- `CacheStore` — 检查/显示下载状态。
- `DownloadManager` — 下载操作。

## 数据模型

所有使用的模型在 PlayerEngine 或其他模块中定义。本模块内：
- `PlaylistLookupResult` — 合集查找结果（private struct）
- `QueuePresentationState` — 底部抽屉 collapsed/split/full 展开状态
- `BottomContextTab` — 底部抽屉内的当前列表、合集、推荐切换状态

## 相关文件清单

- `NowPlayingView.swift`
- `PlayerControlViews.swift`
- `PlayerSheetViews.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-08-14 | 首页封面原位放大与反向缩回改为非阻塞局部动画层；缩回期间瀑布流仍可操作。 |
| 2026-08-14 | 建立横版影像唱片机视觉：封面贴近边缘、电影字幕式左对齐、封面双色光场；系统玻璃只保留在外壳。 |
| 2026-08-14 | 按 Apple 官方正在播放与队列行为重构：LNPopup 原生 grabber、系统音量/AirPlay、同屏 Queue + AutoPlay，移除主页面常驻抽屉。 |
| 2026-08-14 | 收紧播放器纵向节奏；collapsed 显示下一首标题，split 在固定可视高度内开放完整队列滚动。 |
| 2026-08-14 | 融合 LNPopup 性能架构与底部三段式抽屉；移除已由框架取代的自制开合手势和逐帧 frame 监听。 |
| 2026-07-27 | 全项目 review 修复 + 文档同步：播放器子视图拆分并补充列表与手势回归；UI 层行为由 `BiliMusicUITests/PlayerChromeUITests` 以 fixture 覆盖。 |
| 2026-06-24 | 初始文档创建。 |
