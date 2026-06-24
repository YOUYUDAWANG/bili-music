[根目录](../../CLAUDE.md) > **App**

## 模块职责

BiliMusic 应用的入口模块。创建全局唯一的 `PlayerEngine` 并通过 SwiftUI Environment 注入整棵视图树。

## 入口与启动

- **文件**: `BiliMusicApp.swift`
- 使用 `@main` 属性标记，iOS 17+ `App` 协议入口。
- 在 `WindowGroup` 中创建 `RootView`，注入 `PlayerEngine`。
- 启动时自动完成：WBISigner.prewarm()、CacheStore 加载、PlaybackHistoryStore 加载。

## 对外接口

无公开 API。整个模块只有 `BiliMusicApp` 一个入口 struct。

## 关键依赖与配置

- `PlayerEngine` —— 通过 `@State private var engine = PlayerEngine()` 创建。
- `RootView` —— 根视图，包含 tab bar 和全屏播放器浮层。
- 无 Info.plist 修改需求。

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-06-24 | 初始文档创建。 |
