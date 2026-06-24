[根目录](../../CLAUDE.md) > **Cache**

## 模块职责

离线音频缓存管理。包含缓存索引（JSON）管理和下载管理器。

## 入口与启动

- **文件**: `CacheStore.swift`, `DownloadManager.swift`
- 均为 `@Observable` 单例：`CacheStore.shared`、`DownloadManager.shared`

## 对外接口

### CacheStore

| 方法/属性 | 用途 |
|----------|------|
| `loadIfNeeded()` | 从磁盘异步加载缓存索引 |
| `entry(for:)` | 按 Track 查缓存（精确到 cid，多分 P 避免误匹配） |
| `entry(key:)` | 按 TrackKey 查缓存 |
| `entry(bvid:)` | 兼容旧调用：只在 BV 唯一缓存时返回 |
| `localURL(for:)` | 取缓存文件本地路径 |
| `add(_:)` | 添加缓存条目（立即写盘） |
| `remove(_:)` | 删除缓存 + 文件 |
| `removeAll()` | 清空全部 |
| `totalSize` | 缓存总字节数 |
| `flush()` | 立即写盘（用于 scene phase 切换） |

### DownloadManager

| 方法/属性 | 用途 |
|----------|------|
| `progress` | `[TrackKey: Double]` 下载进度字典 |
| `isDownloading(_:)` | 按 bvid 或 Track 检查是否正在下载 |
| `progress(for:)` | 按 Track 查询进度 |
| `download(track:)` | 下载整曲（补全 cid → 取流 → 下载 → 写索引） |

## 关键依赖与配置

- 音频目录: `Documents/audio/`
- 索引文件: `Documents/cache_index.json`
- 文件名格式: `{bvid}_{cid}.m4a`
- 下载音质从 `UserDefaults.integer(forKey: "downloadQuality")` 读取。
- 防抖写盘（1s 延迟）/ 立即写盘（`immediate: true`）。
- 后台 decode/encode（`Task.detached(priority: .background)`）。
- `ProgressWatcher` —— URLSessionDownloadTask 的进度回调适配器。

## 数据模型

- `CachedEntry` —— codable，含 bvid, cid, title, artist, coverURL, duration, fileName, fileSize, downloadedAt, quality

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-06-24 | 初始文档创建。 |
