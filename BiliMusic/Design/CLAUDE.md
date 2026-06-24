[根目录](../../CLAUDE.md) > **Design**

## 模块职责

全局主题定义和图片加载基础设施。Apple Music 风格的克制配色，不施加品牌主色。

## 入口与启动

- **文件**: `AppTheme.swift`, `CachedAsyncImage.swift`
- `AppTheme` 是 enum，直接使用 `Color.primary` 等系统语义色值。
- `CachedAsyncImage` 是通用图片加载 View，自动使用。

## 对外接口

### AppTheme

| 属性 | 值 |
|------|-----|
| `accent` | `Color.primary`（不自定品牌色） |
| `background` | `UIColor.systemBackground` |
| `groupedBackground` | `UIColor.systemGroupedBackground` |
| `secondaryBackground` | `UIColor.secondarySystemGroupedBackground` |
| `separator` | `UIColor.separator` |
| `label` | `UIColor.label` |
| `secondaryLabel` | `UIColor.secondaryLabel` |
| `playerGradient` | `secondarySystemBackground → systemBackground` 线性渐变 |

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
- 列表封面（TrackRow、MiniPlayerBar）：追加 `@160w_160h_1c.webp` 或 `@160w_90h_1c.webp`。
- 全屏播放器封面（NowPlayingView）：追加 `@960w_540h_1c.webp`。

## 相关文件清单

- `AppTheme.swift`
- `CachedAsyncImage.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-06-24 | 初始文档创建。 |
