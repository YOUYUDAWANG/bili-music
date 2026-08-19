[根目录](../../CLAUDE.md) > **Design**

## 模块职责

全局主题定义、图片加载基础设施和跨页面复用的 UI 组件（曲目行、触感反馈、小控件）。工具页使用克制的 B 站蓝青强调色；沉浸式内容由真实封面派生颜色。

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
| `playerCoverRadius` | `8` |

`playerGradient` 已删除。播放器背景改用 **`PlayerArtworkPalette`**：`from(_ image:)` 取封面 12×12 降采样平均色，经饱和度/亮度钳制派生 top/middle/bottom 三色；当前播放器只取 top/bottom 形成干净双色光场，不使用封面模糊或 glow。无封面时使用中性 `fallback`。

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

- 系统 Liquid Glass 只用于原生 Tab/LNPopup 与必要系统浮层；首页和播放器内容层不新增材质卡或玻璃胶囊。
- 高饱和生成撞色不能代替真实封面；沉浸页的颜色来自封面，搜索/缓存/设置仍由 `AppTheme.accent` 提供稳定工具色。
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
| 2026-08-19 | 新增 `PlayerSurface` token、`HapticIntent.transportImpact`；`CachedAsyncImage` 0.15s 淡入。 |
| 2026-08-14 | 明确“系统玻璃外壳 + 横版影像内容”分层；播放器收敛为封面双色光场，不使用高饱和生成撞色。 |
| 2026-07-27 | 全项目 review 修复 + 文档同步：品牌色改 B 站蓝青（`brand`/`brandSoft` 动态色），删除 `playerGradient` 改 `PlayerArtworkPalette`，补 Haptics/TrackRow/UIComponents。 |
| 2026-06-24 | 初始文档创建。 |
