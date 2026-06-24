[根目录](../../../CLAUDE.md) > [Features](../) > **Home**

## 模块职责

首页推荐页面。用 RecommendationEngine 从收藏夹种子生成推荐列表，3 小时内不重复推荐同一曲目。

## 入口与启动

- **文件**: `HomeView.swift`, `RecentHomeFeedStore.swift`
- 页面出现时自动触发推荐加载。

## 对外接口

### HomeView

- 点击「换一批」或下拉刷新重新加载。
- 未登录/无收藏夹时显示引导文案。
- 推荐结果的前 3 首会自动预加载。

### RecentHomeFeedStore

- `shared` 单例。
- `recentKeys()` — TTL 内仍算「最近推荐过」的 TrackKey 集合（用作排除集）。
- `record(_:)` — 记录本次展示的 bvid 列表。

## 关键依赖与配置

- `RecommendationEngine(.home)` — 推荐生成引擎。
- `RecentHomeFeedStore` — TTL 3 小时，上限 400 条，JSON 落盘到 `Documents/home-recent.json`。
- 推荐种子收藏夹从 `UserDefaults.integer(forKey: "recommendFolderId")` 读取。

## 数据模型

- 首页使用的是 `Track`（定义在 PlayerEngine 同文件）。
- `RecentHomeFeedStore` 内部：`[String: Date]`（bvid → 最近展示时间）。

## 相关文件清单

- `HomeView.swift`
- `RecentHomeFeedStore.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-06-24 | 初始文档创建。 |
