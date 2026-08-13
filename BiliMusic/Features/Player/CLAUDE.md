[根目录](../../../CLAUDE.md) > [Features](../) > **NowPlaying (播放器 UI)**

## 模块职责

全屏正在播放页的 UI 实现。包括当前播放页、进度条、歌词页、MV 全屏、收藏夹选择器、UP 主合集视图。

## 入口与启动

- **文件**: `NowPlayingView.swift`
- 由 `RootView` 通过 `.ignoresSafeArea()` 和 `.offset(y:)` 以浮层方式呈现。
- 迷你播放器由 `RootView` 的自定义 `GlassEffectContainer` 底部浮层呈现，和导航胶囊/搜索圆按钮组成 Apple Music 风格的内缩底部组。

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
| 操作栏 | 收藏（短按/长按）、下载、歌词、播放模式、音质、合集 |
| 底部面板 | 合集列表 / 队列预览 |
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
- `PlayerPage` — 推荐/队列辅助状态枚举（不再驱动顶部滑动分页 UI）

## 相关文件清单

- `NowPlayingView.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-06-24 | 初始文档创建。 |
