---
type: project_topic
status: active
summary: "记录歌曲列表当前播放态的克制视觉规则。"
tags: [ui, list, player, theme]
contains: [decision]
created: "2026-08-14"
updated: "2026-08-14"
related: ["BiliMusic/Design/TrackRow.swift", "BiliMusic/Design/UIComponents.swift"]
authoring_mode: ai_generated
---
# 歌曲列表播放态

## 当前结论

- 当前播放歌曲只将标题文字改为 `AppTheme.accent`，不为整行添加主题色背景或描边。
- 波形和扬声器图标可继续使用主题色作为播放状态提示，但不能形成新的框状选中面。
- 该规则同时适用于通用 `TrackRow` 和首页、搜索结果使用的 `MusicTrackRow`，保证收藏、缓存、队列、首页与搜索一致。

## 决策记录

- 用户明确要求歌曲播放态只高亮文字，去掉此前整行圆角浅色背景；点击区域与行内菜单保持不变。
