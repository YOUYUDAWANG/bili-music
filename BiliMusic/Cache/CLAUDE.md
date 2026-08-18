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
| `loadIfNeeded()` | 从磁盘异步加载缓存索引；加载后做孤儿音频清理（删除 audioDir 里不在索引中的文件；索引解码失败时跳过清理，避免误删有效音频） |
| `entry(for:)` | 按 Track 查缓存（精确到 cid，多分 P 避免误匹配） |
| `addPersisting(_:)` | 添加缓存条目（立即写盘）；超出 120 首时 LRU 淘汰，不删正在播放/下载的文件 |
| `touch(_:)` | 本地命中时更新访问时间并置顶 |
| `enforceRetentionLimit()` | 冷启动恢复队列后裁到 120 首 |
| `remove(_:)` | 删除缓存 + 文件（防抖写盘）
| `removeAll()` | 清空全部 |
| `totalSize` | 缓存总字节数 |
| `flush()` | 立即写盘（用于 scene phase 切换） |

### DownloadManager

| 方法/属性 | 用途 |
|----------|------|
| `progress` | `[TrackKey: Double]` 下载进度字典 |
| `isDownloading(_:)` | 按 Track 检查是否正在下载 |
| `progress(for:)` | 按 Track 查询进度 |
| `download(track:)` | 下载整曲（先 `CacheStore.loadIfNeeded()` → 补全 cid → 取流 → 下载 → 写索引） |

## 关键依赖与配置

- 音频目录: `Documents/audio/`
- 索引文件: `Documents/cache_index.json`
- 文件名格式: `{bvid}_{cid}.m4a`
- 下载音质从 `UserDefaults.integer(forKey: "downloadQuality")` 读取。
- 下载请求使用 `BiliClient.playbackHeaders`。
- 自动缓存默认开启；出声约 1.5s 后由 `PlayerEngine` 调用 `download(track:)`。
- 防抖写盘（1s 延迟）/ 立即写盘（`immediate: true`）。
- 后台 decode/encode（`Task.detached(priority: .background)`）。
- `ProgressWatcher` —— URLSessionDownloadTask 的进度回调适配器。
- `CacheStore` 另有 `init(indexURLForTesting:audioDirForTesting:)` 测试注入构造器（不触碰真实 Documents）。

## 数据模型

- `CachedEntry` —— codable，含 bvid, cid, title, artist, coverURL, duration, fileName, fileSize, downloadedAt, quality, accessedAt
- 音频目录最多保留 120 首；`touch` 更新访问时间，淘汰时跳过正在播放和正在下载的 key

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-08-19 | 本地音频 LRU 上限 120；命中缓存会 touch；不淘汰正在播放/下载的文件。 |
| 2026-08-19 | 下载请求改用 `playbackHeaders`；自动缓存默认开启。 |
| 2026-07-27 | 全项目 review 修复 + 文档同步：孤儿音频清理、`remove` 防抖写盘、测试注入 init、下载前 `loadIfNeeded`。 |
| 2026-06-24 | 初始文档创建。 |
