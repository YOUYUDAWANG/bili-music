[根目录](../../CLAUDE.md) > **Design**

## 模块职责

全局主题定义、图片加载基础设施和跨页面复用的 UI 组件（曲目行、触感反馈、小控件）。Apple Music 式的克制层级 + B 站蓝青品牌强调色。

## 入口与启动

- **文件**: `AppTheme.swift`, `CachedAsyncImage.swift`, `Haptics.swift`, `TrackRow.swift`, `UIComponents.swift`
- `AppTheme` 是 enum，品牌色 + 系统语义色值。
- `CachedAsyncImage` 是通用图片加载 View，自动使用。

## 对外接口

### AppTheme

| 属性 | 值 |
|------|-----|
| `brand` | B 站蓝青 `Color(red: 0, green: 0.631, blue: 0.839)` |
| `brandSoft` | 品牌色柔和背景（正在播放行高亮等）。动态色：浅色模式近白浅青，深色模式低亮度品牌色调，保证 `.secondary` 文字可读 |
| `accent` | `= brand` |
| `background` | `UIColor.systemBackground` |
| `groupedBackground` | `UIColor.systemGroupedBackground` |
| `secondaryBackground` | `UIColor.secondarySystemGroupedBackground` |
| `separator` | `UIColor.separator` |
| `label` | `UIColor.label` |
| `error` / `success` | `Color.red` / `Color.green` |
| `playerCoverRadius` | `14` |

`playerGradient` 已删除。播放器背景改用 **`PlayerArtworkPalette`**：`from(_ image:)` 取封面 12×12 降采样平均色，经饱和度/亮度钳制派生 top/middle/bottom 三色，暴露 `gradient`（线性渐变）与 `glow`（径向光晕）；无封面时用 `fallback`。

### CachedAsyncImage

```swift
CachedAsyncImage(url: coverURL) { image in
    image.resizable().aspectRatio(contentMode: .fill)
} placeholder: {
    AppTheme.secondaryBackground
}
```

### ImageMemoryCache

- `@MainActor` 单例。NSCache 缓存解码后的 UIImage。
- 上限: 240 张，总成本 48MB。

### ImageLoadCoordinator

- actor 单例。URLSession + URLCache（32MB 内存 / 128MB 磁盘）的图片网络加载。
- 同 URL 去重（inFlight 字典）。
- 自动携带 `BiliClient.headers`。

## 关键约束

- 封面缩略图 URL 处理：所有 hdslb.com 的 URL 追加 `@widthw_heighth_1c.webp` 参数，以获取指定尺寸的 WebP 缩略图。
- 播放器封面（PlayerEngine 内）：追加 `@600w_600h_1c.webp`。
- 列表封面（TrackRow、RootView 底部 mini 播放器）：追加 `@160w_160h_1c.webp` 或 `@160w_90h_1c.webp`。
- 全屏播放器封面（NowPlayingView）：追加 `@960w_540h_1c.webp`。

## 相关文件清单

- `AppTheme.swift`
- `CachedAsyncImage.swift`
- `Haptics.swift`
- `TrackRow.swift`
- `UIComponents.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-07-27 | 全项目 review 修复 + 文档同步：品牌色改 B 站蓝青（`brand`/`brandSoft` 动态色），删除 `playerGradient` 改 `PlayerArtworkPalette`，补 Haptics/TrackRow/UIComponents。 |
| 2026-06-24 | 初始文档创建。 |
