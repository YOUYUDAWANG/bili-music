import Foundation
import Security

/// 登录 Cookie 的 Keychain 存取。Cookie 形如 "SESSDATA=..; bili_jct=..; DedeUserID=.."
enum CookieStore {
    private static let service = "com.fubuki.BiliMusic.cookie"

    static var cookie: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnData as String: true,
            ]
            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
            ]
            SecItemDelete(base as CFDictionary)
            guard let newValue, let data = newValue.data(using: .utf8) else { return }
            var add = base
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

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
