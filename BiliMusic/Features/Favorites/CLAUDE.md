[根目录](../../../CLAUDE.md) > [Features](../) > **Favorites**

## 模块职责

B 站收藏夹的浏览和管理。将 B 站收藏夹当歌单使用，支持分页加载、过滤失效稿件、电台播放和随机播放。

## 入口与启动

- **文件**: `FavoritesView.swift`, `FavoriteManager.swift`
- `FavoritesView` 在 RootView tab bar 中展示。
- 需要扫码登录后才能使用。

## 对外接口

### FavoritesView

- 收藏夹列表，点击进入详情。
- 恢复上次打开的收藏夹（通过 `FavoriteManager.lastFolderId`）。

### FavFolderDetailView

- 收藏夹内容分页加载。
- 过滤已失效的稿件（`attr != 0`）。
- `MusicFilter.isMusic` 过滤非音乐内容。
- 支持单击播放、context menu 电台/随机播放。

### FavoriteManager（`@Observable` 单例）

| 方法/属性 | 用途 |
|----------|------|
| `favoriteBVIDs` | 已收藏 bvid 全集 |
| `folders` | 收藏夹列表 |
| `busyBVIDs` | 正在操作中的 bvid 集合 |
| `lastFolderId` | 上次使用的收藏夹 id（UserDefaults） |
| `isFavorite(_:)` | 检查是否已收藏 |
| `toggle(track:)` | 切换到默认收藏夹 |
| `toggle(track:folder:)` | 切换到指定收藏夹 |
| `loadFolders()` | 拉取收藏夹列表 |
| `syncAllFavoriteIDs(force:)` | 同步全部收藏 bvid（供推荐去重，10 分钟缓存） |
| `markLoaded(folderId:title:tracks:)` | 加载收藏夹后记录 |

## 关键依赖与配置

- `BiliClient.favFolders()` / `favItems(folderId:page:)` / `setFavorite(aid:folderId:add:)`
- `CookieStore.isLoggedIn` / `CookieStore.csrf` — 需要登录和 CSRF token。
- `lastFavoriteFolderId` 持久化在 `UserDefaults`。
- 错误码 401 时引导用户重新登录。

## 数据模型

- `BiliClient.FavFolder` — 收藏夹（id, title, media_count）
- `BiliClient.FavItem` — 收藏内容（bvid, title, cover, duration, upper, attr）

## 相关文件清单

- `FavoritesView.swift`
- `FavoriteManager.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-06-24 | 初始文档创建。 |
