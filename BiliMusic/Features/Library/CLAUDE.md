[根目录](../../../CLAUDE.md) > [Features](../) > **Library**

## 模块职责

已缓存音频的本地管理页面。支持离线播放、搜索过滤、多维度排序和缓存管理。

## 入口与启动

- **文件**: `LibraryView.swift`
- 在 RootView tab bar 中展示。
- 页面出现时自动调用 `CacheStore.shared.loadIfNeeded()`。

## 对外接口

### LibraryView

- 搜索：通过 `.searchable` 按标题/UP主/bvid 过滤。
- 排序：5 种排序方式（最近缓存、标题、UP主、文件大小、音质）。
- 点击播放（支持本地文件离线播放）。
- 滑动删除 / 清空全部。
- context menu：电台播放、随机播放。

### CacheSortOrder（private enum）

`recentlyCached` / `title` / `artist` / `size` / `quality`

## 关键依赖与配置

- `CacheStore.shared` — 读取缓存索引，无网络请求。
- `PlayerEngine.play(tracks:startAt:)` — 点击曲目播放。
- 缓存统计（数量 + 字节数）通过 `ByteCountFormatter` 格式化。

## 数据模型

- `CachedEntry` — 见 Cache 模块定义（bvid, cid, title, artist, coverURL, duration, fileName, fileSize, downloadedAt, quality）

## 相关文件清单

- `LibraryView.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-06-24 | 初始文档创建。 |
