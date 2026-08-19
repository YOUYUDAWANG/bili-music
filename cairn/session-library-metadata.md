---
type: project_topic
status: active
summary: "对照 AprDeci 后补齐的三块领域模型：音乐身份、登录会话、本地音乐库。"
tags: [metadata, session, library, favorites]
contains: [decision, current]
created: "2026-08-19"
updated: "2026-08-19"
related: ["cairn/lyrics-architecture.md", "BiliMusic/Auth/BiliSession.swift", "BiliMusic/Features/Favorites/LibraryStore.swift"]
authoring_mode: ai_generated
---
# 会话、本地库与音乐身份

## 当前真相

- `Track` 继续只表示 B 站播放物。清洗后的歌名/歌手、歌词和偏移是 `MusicMetadata`，由 `MusicMetadataController` 在出声后加载。
- 登录不再只是 Cookie 字符串。`CookieStore` 仍管 Keychain；`BiliSession` / `BiliSessionStore` 保存解析字段、refresh token、用户名、WBI 和过期态。401/-101 会把 `CookieStore.isLoggedIn` 变成 false。
- 收藏不再只是远程浏览。`LibraryStore` 有系统「我喜欢」（entry + membership），并缓存已打开的 B 站收藏夹。首页和收藏页优先读这份本地库。

## 行为

- 未登录点收藏：只切换「我喜欢」。
- 已登录点收藏：写入 B 站音乐收藏夹（设置里指定的，或标题像音乐的夹），没有音乐夹才退回默认收藏夹；同时写入本地「我喜欢」和该夹缓存。
- 登录失效：设置页和收藏页提示重新扫码；本地「我喜欢」和已缓存收藏夹仍可播放。
- 起播路径不变：元数据清洗和歌词仍在出声之后。
