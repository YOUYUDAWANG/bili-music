import Foundation
import Security

/// 登录 Cookie 的 Keychain 存取。Cookie 形如 "SESSDATA=..; bili_jct=..; DedeUserID=.."
enum CookieStore {
    private static let service = "com.fubuki.BiliMusic.cookie"
    private static let lock = NSLock()
    private static var cachedCookie: String?
    private static var loadedFromKeychain = false

    /// Keychain 里的完整 Cookie 串。读写都走钥匙串；set 为 nil 即登出并清除。
    static var cookie: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            if loadedFromKeychain {
                return cachedCookie
            }
            switch readFromKeychain() {
            case .found(let value, let needsMigration):
                cachedCookie = value
                loadedFromKeychain = true
                if needsMigration {
                    migrateAccessibility(value)
                }
                return value
            case .missing:
                // 只有确认「条目不存在」才缓存未登录结论
                cachedCookie = nil
                loadedFromKeychain = true
                return nil
            case .failure:
                // 瞬时失败（设备锁定 errSecInteractionNotAllowed 等）不缓存,下次访问重试
                return nil
            }
        }
        set {
            _ = save(newValue)
        }
    }

    @discardableResult
    static func save(_ newValue: String?) -> Bool {
        lock.lock()
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status: OSStatus
        if let newValue, let data = newValue.data(using: .utf8) {
            // delete + re-add 而非 update：kSecAttrAccessible 无法靠 SecItemUpdate 可靠追加,
            // 重建条目保证锁屏后台音频也能读到（AfterFirstUnlockThisDeviceOnly）
            SecItemDelete(base as CFDictionary)
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        } else {
            let deleteStatus = SecItemDelete(base as CFDictionary)
            status = deleteStatus == errSecItemNotFound ? errSecSuccess : deleteStatus
        }
        guard status == errSecSuccess else {
            lock.unlock()
            return false
        }

        cachedCookie = newValue
        loadedFromKeychain = true
        lock.unlock()
        postAuthenticationDidChange()
        return true
    }

    private static func postAuthenticationDidChange() {
        let post = {
            NotificationCenter.default.post(name: .biliAuthenticationDidChange, object: nil)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    /// Keychain 读取结果:区分「确实不存在」和「瞬时失败」,后者不应缓存为未登录。
    private enum KeychainReadResult {
        case found(value: String, needsMigration: Bool)
        case missing
        case failure(OSStatus)
    }

    private static func readFromKeychain() -> KeychainReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let dict = result as? [String: Any],
                  let data = dict[kSecValueData as String] as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                return .missing // 数据损坏视为不存在
            }
            // 存量条目缺 AfterFirstUnlockThisDeviceOnly 时惰性迁移
            let accessible = dict[kSecAttrAccessible as String] as? String
            let wanted = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
            return .found(value: value, needsMigration: accessible != wanted)
        case errSecItemNotFound:
            return .missing
        default:
            return .failure(status)
        }
    }

    /// 存量条目补写 kSecAttrAccessible:delete + re-add（调用方需已持有 lock）。
    private static func migrateAccessibility(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(add as CFDictionary, nil) != errSecSuccess {
            // 迁移失败则按原样写回,避免丢失登录态
            var restore = base
            restore[kSecValueData as String] = data
            SecItemAdd(restore as CFDictionary, nil)
        }
    }

    /// 是否存在已保存的登录态。
    static var isLoggedIn: Bool { cookie != nil }

    /// Cookie 里的 DedeUserID,收藏夹等接口需要
    static var mid: String? {
        cookie?.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("DedeUserID=") }
            .map { String($0.dropFirst("DedeUserID=".count)) }
    }

    /// Cookie 里的 CSRF Token,收藏/取消收藏等写操作需要
    static var csrf: String? {
        cookie?.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("bili_jct=") }
            .map { String($0.dropFirst("bili_jct=".count)) }
    }
}

extension Notification.Name {
    static let biliAuthenticationDidChange = Notification.Name("BiliMusic.authenticationDidChange")
}
