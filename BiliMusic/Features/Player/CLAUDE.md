[根目录](../../../CLAUDE.md) > [Features](../) > **NowPlaying (播放器 UI)**

## 模块职责

全屏正在播放页的 UI 实现。包括当前歌曲、进度条、底部队列/合集/推荐抽屉、歌词页、MV 全屏、收藏夹选择器、UP 主合集视图。

## 入口与启动

- **文件**: `NowPlayingView.swift`（主入口）、`PlayerControlViews.swift`（控制子视图）、`PlayerSheetViews.swift`（歌词/合集/收藏等 sheet）
- 由 `RootView` 的 LNPopupUI `.floatingCompact + .automatic` 容器承载。
- 迷你播放器、主播放器开合、跟手下滑和安全区停靠由 vendored LNPopupController 统一管理；播放页不再维护第二套纵向转场状态机。

## 对外接口

### NowPlayingView


### 页面组成

| 子视图 | 用途 |
|--------|------|
| 播放器模式选择器 | 音乐/MV 切换 |
| 封面/视频 | 16:9 封面或 AVPlayer 视频播放器 |
| 曲目信息 | 标题、歌手、错误信息 |
| PlayerProgressBar | 进度条（独立子视图限制 currentTime 订阅范围） |
| 控制按钮 | 上一曲、播放/暂停、下一曲 |
| 操作栏 | 收藏（短按/长按）、下载、音乐/MV 切换、更多 |
| 底部抽屉 | 当前列表 / 合集 / 推荐，支持 collapsed → split → full 两段式展开 |
| 歌词页 | LyricSheetView（滚动高亮、自动居中） |
| MV 全屏 | MVFullscreenView（全屏视频播放） |

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
| 2026-08-14 | 收紧播放器纵向节奏；collapsed 显示下一首标题，split 在固定可视高度内开放完整队列滚动。 |
| 2026-08-14 | 融合 LNPopup 性能架构与底部三段式抽屉；移除已由框架取代的自制开合手势和逐帧 frame 监听。 |
| 2026-07-27 | 全项目 review 修复 + 文档同步：播放器子视图拆分并补充列表与手势回归；UI 层行为由 `BiliMusicUITests/PlayerChromeUITests` 以 fixture 覆盖。 |
| 2026-06-24 | 初始文档创建。 |
