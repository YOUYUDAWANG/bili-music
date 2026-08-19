[根目录](../../CLAUDE.md) > **Auth**

## 模块职责

B 站登录会话。Cookie 仍只放在 Keychain；运行时解析为 `BiliSession`，并保存资料、WBI 与过期态。

## 入口与启动

- **文件**: `CookieStore.swift`、`BiliSession.swift`、`BiliSessionStore.swift`
- `CookieStore` 继续负责钥匙串读写；写入后同步 `BiliSessionStore`。
- App 启动时 `RootView` 调用 `BiliSessionStore.shared.refreshFromNav()`。

## 对外接口

| 属性/方法 | 用途 |
|----------|------|
| `CookieStore.cookie` | 完整 Cookie 字符串（读写 Keychain） |
| `CookieStore.isLoggedIn` | 有 Cookie 且尚未被标记失效 |
| `CookieStore.isExpired` | nav / 401 / -101 判定登录失效 |
| `CookieStore.mid` / `csrf` | 从 Cookie 解析 DedeUserID / bili_jct |
| `BiliSessionStore.session` | 解析后的会话对象 |
| `BiliSessionStore.adopt(cookie:refreshToken:buvid3:)` | 扫码成功后补 refresh token / buvid3 |
| `BiliSessionStore.refreshFromNav()` | 启动时确认 Cookie，并补齐用户名和 WBI |
| `BiliSessionStore.markExpired()` | 受保护接口返回 401/-101 时调用 |

## 关键依赖与配置

- Keychain service name: `com.fubuki.BiliMusic.cookie`
- Cookie 格式: `"SESSDATA=..; bili_jct=..; DedeUserID=.."`
- 会话资料 JSON：`Documents/bili-session.json`（不含 Cookie 明文优先；Cookie 仍以钥匙串为准）
- `NSLock` 保护内存缓存的并发读写。

## 数据模型

- `BiliSession` — cookie 解析字段、refreshToken、uname/face、WBI、buvid3、isExpired
- `BiliNavProfile` — `/x/web-interface/nav` 的登录态与资料

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-08-19 | 增加 `BiliSession` / `BiliSessionStore`；401/-101 进入共享过期态。 |
| 2026-06-24 | 初始文档创建。 |
