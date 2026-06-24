[根目录](../../../CLAUDE.md) > [Features](../) > **Search**

## 模块职责

B 站视频搜索，默认限定音乐分区，支持分页、模式切换（音乐/更多）、搜索历史和结果缓存。

## 入口与启动

- **文件**: `SearchView.swift`, `SearchStore.swift`, `SearchModels.swift`
- `SearchView` 在 RootView 的 tab bar 中展示。
- 启动时自动加载搜索历史（UserDefaults）和播放历史/缓存供 landing 页面展示。

## 对外接口

### SearchStore（`@Observable`）

核心属性：
- `results` — `[Track]` 搜索结果
- `searchHistory` — `[String]` 搜索历史
- `searching` / `loadingMore` — 加载状态
- `mode` — `.music`（默认）或 `.expanded`
- `hasMoreResults` — 是否有更多分页

核心方法：
| 方法 | 用途 |
|------|------|
| `loadHistory()` | 从 UserDefaults 加载搜索历史 |
| `submitSearch(_:preload:)` | 提交搜索（自动缓存恢复命中时跳过网络） |
| `loadMore(preload:)` | 加载更多结果 |
| `setMode(_:query:)` | 切换搜索模式（music/expanded） |
| `retryCurrentSearch(preload:)` | 重试当前搜索 |
| `broadenCurrentSearch(preload:)` | 切换到 expanded 模式重搜 |
| `queryDidChange(_:)` | 查询词变化时重置状态 |

## 关键依赖与配置

- `BiliClient.search(keyword:page:musicOnly:)` — 调用 WBI 签名搜索。
- `MusicFilter.isSearchResult(_:query:mode:)` — 搜索结果的音乐内容过滤。
- 搜索历史：UserDefaults key `searchHistory`，上限 20 条，JSON 编码。
- 结果缓存：内存 `[SearchCacheKey: SearchCachedSnapshot]`。
- 分页逻辑：最多 30 页；自动跳过因过滤导致无结果的分页（最多跳过 3 批）。
- 关键词策略：含空格的英文/数字查询同时搜索 compact 和原始版本。

## 数据模型（SearchModels.swift）

- `SearchResultMode` — music / expanded（是否用 B 站音乐分区限定搜索）
- `SearchCacheKey` — 归一化（lowercase + fold + trim）的 query + mode 组合作为缓存 key
- `SearchCachedSnapshot` — 搜索结果缓存快照（tracks, nextPage, activeKeywords, hasMoreResults）
- `SearchResultSections` — 三段式（bestMatch / songs / mvs）

## 测试

`BiliMusicTests/SearchModelsTests.swift` 覆盖：
- SearchCacheKey 归一化
- SearchResultMode 值
- SearchResultSections 三段拆分
- MusicFilter 搜索过滤逻辑
- SearchStore 缓存恢复、模式切换

## 相关文件清单

- `SearchView.swift`
- `SearchStore.swift`
- `SearchModels.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-06-24 | 初始文档创建。 |
