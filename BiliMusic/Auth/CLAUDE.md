[根目录](../../CLAUDE.md) > **Auth**

## 模块职责

B 站登录 Cookie 的 Keychain 存取。管理登录态的生命周期。

## 入口与启动

- **文件**: `CookieStore.swift`
- `CookieStore` 是 enum，所有属性和方法都是 static 的。调用时自动读取 Keychain。

## 对外接口

| 属性/方法 | 用途 |
|----------|------|
| `cookie` | 完整 Cookie 字符串（读写 Keychain，lazy load + 内存缓存） |
| `isLoggedIn` | 是否有已保存的登录态 |
| `mid` | DedeUserID（收藏夹等接口需要） |
| `csrf` | bili_jct（收藏/取消收藏等写操作需要 CSRF token） |

## 关键依赖与配置

- Keychain service name: `com.fubuki.BiliMusic.cookie`
- Cookie 格式: `"SESSDATA=..; bili_jct=..; DedeUserID=.."`
- `NSLock` 保护内存缓存的并发读写。

## 数据模型

无自定义数据模型。Cookie 存储为纯字符串。

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-06-24 | 初始文档创建。 |
