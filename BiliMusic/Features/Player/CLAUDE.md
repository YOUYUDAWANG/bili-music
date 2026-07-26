[根目录](../../../CLAUDE.md) > [Features](../) > **NowPlaying (播放器 UI)**

## 模块职责

全屏正在播放页的 UI 实现。包括当前歌曲、进度条、底部队列/合集/推荐抽屉、歌词页、MV 全屏、收藏夹选择器、UP 主合集视图。

## 入口与启动

- **文件**: `NowPlayingView.swift`（主入口）、`PlayerControlViews.swift`（控制子视图）、`PlayerSheetViews.swift`（歌词/合集/收藏等 sheet）、`PlayerGesturePolicy.swift`（手势阈值与进度计算纯函数）、`PlayerListWindow.swift`（队列长列表窗口化纯函数）
- 由 `RootView` 通过 `.ignoresSafeArea()` 和 `.offset(y:)` 以浮层方式呈现。
- 迷你播放器由 `RootView` 的自定义 `GlassEffectContainer` 底部浮层呈现，和导航胶囊/搜索圆按钮组成 Apple Music 风格的内缩底部组。

## 对外接口

### NowPlayingView

- `onDismiss: (() -> Void)?` — 关闭回调（RootView 中使用）。

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

### PlayerGesturePolicy（static 枚举，纯函数）

- 集中定义手势阈值：mini bar 上滑展开（拖动区间 190pt、激活进度 0.38）、下滑关闭（位移 130pt / 预测 260pt，顶部 chrome 区 90pt / 180pt）、速度投影时间等。
- `miniOpenProgress` / `renderedMiniOpenProgress` 等把手势位移换算成展开进度，供 `BiliMusicTests/PlayerGesturePolicyTests` 验证。

### PlayerListWindow（static 枚举，纯函数）

- `items(tracks:current:maxRows:)` — 以当前曲目为中心取队列的可视窗口片段（长队列不整表渲染）。
- `positionText(tracks:current:)` — 「第 x / n 首」定位文案。

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
- `PlayerGesturePolicy.swift`
- `PlayerListWindow.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-07-27 | 全项目 review 修复 + 文档同步：模块拆分为 5 个文件，新增 PlayerGesturePolicy / PlayerListWindow 纯函数说明；UI 层行为由 `BiliMusicUITests/PlayerChromeUITests` 以 fixture 覆盖。 |
| 2026-06-24 | 初始文档创建。 |
