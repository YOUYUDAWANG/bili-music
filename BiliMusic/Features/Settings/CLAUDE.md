[根目录](../../../CLAUDE.md) > [Features](../) > **Settings**

## 模块职责

设置页面：账号登录/登出、首页音乐收藏夹、播放/下载音质、缓存策略、本机歌词模型、高精度歌词主机、MV 偏好和播放历史管理。

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
| 缓存 | 自动缓存开关（默认开） | `UserDefaults.autoCache` |
| 本机逐字歌词（已停用） | 显示已有 Qwen 模型占用，只允许删除，不再下载或运行 | `Library/Application Support/LocalModels/` |
| 高精度逐字歌词主机 | URL 覆盖与健康检查；令牌状态提示 | `UserDefaults.precisionLyricsHostURL` + 构建时由钥匙串生成的签名资源 |
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
- `OnDeviceLyricsAligner` — 仅查询和删除已有模型；真机 Metal SIGABRT 后不再从设置下载或从播放器运行。
- `PrecisionLyricsHostClient` — 测试 Windows 主机健康状态；生成入口仍在播放器菜单。
- `CIFilter.qrCodeGenerator()` — 二维码生成（CoreImage）。

## 相关文件清单

- `SettingsView.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-08-19 | 真机两次 MLX Metal SIGABRT 后停用本机生成与模型下载，只保留删除。 |
| 2026-08-19 | 增加 Windows 高精度歌词主机 URL 覆盖与连通性测试。 |
| 2026-08-19 | 本机歌词模型扩为 ASR 粗定位 + ForcedAligner 精修；两者顺序运行、不同时驻留，设置页显示合计占用。 |
| 2026-08-19 | 自动缓存默认开启。 |
| 2026-06-24 | 初始文档创建。 |
