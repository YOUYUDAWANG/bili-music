[根目录](../../../CLAUDE.md) > [Features](../) > **Settings**

## 模块职责

设置页面：账号登录/登出、首页音乐收藏夹、播放/下载音质、缓存策略、MV 偏好和播放历史管理。

## 入口与启动

- **文件**: `SettingsView.swift`
- 在 RootView tab bar 中展示。
- 包含内嵌视图：`PlaybackHistoryView`、`QRLoginView`。

## 对外接口

### SettingsView

设置选项：

| 区段 | 选项 | 存储 |
|------|------|------|
| 账号 | 扫码登录 / 退出登录 | Keychain (CookieStore) |
| 音乐资料库 | 首页音乐收藏夹选择器 | `UserDefaults.recommendFolderId` |
| 音质 | 播放音质、下载音质 | `UserDefaults.playbackQuality` / `downloadQuality` |
| 缓存 | 自动缓存开关 | `UserDefaults.autoCache` |
| 播放 | Wi-Fi 优先 MV、播放历史入口 | `UserDefaults.preferMVOnWiFi` |

### QRLoginView

- 生成 B 站登录二维码（CIFilter.qrCodeGenerator）。
- 2 秒轮询扫码结果。
- 成功后将 Cookie 存入 Keychain 并回调 `onSuccess`。

### PlaybackHistoryView

- 播放历史列表（显示次数）。
- 点击重播、context menu 电台播放、清空历史。

## 关键依赖与配置

- `CookieStore` — 登录态管理。
- `BiliClient.qrCodeGenerate()` / `qrCodePoll(key:)` — 扫码登录接口。
- `BiliClient.myInfo()` — 登录后获取用户名。
- `BiliClient.favFolders()` — 首页音乐收藏夹列表。
- `UserDefaults` — 各偏好设置的持久化存储。
- `CIFilter.qrCodeGenerator()` — 二维码生成（CoreImage）。

## 相关文件清单

- `SettingsView.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-06-24 | 初始文档创建。 |
