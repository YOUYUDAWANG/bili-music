import CryptoKit
import Foundation

/// WBI 参数签名,算法来自 bilibili-API-collect。
/// nav 接口取 img/sub key → 重排表混淆出 mixin key → 参数排序 + wts + MD5。
@MainActor
enum WBISigner {
    private static let mixinKeyTable = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5,
        49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24,
        55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63,
        57, 62, 11, 36, 20, 34, 44, 52,
    ]

    private static var cachedKey: (key: String, fetchedAt: Date)?

    /// 对参数签名,返回完整 query string(含 wts 和 w_rid)。
    static func sign(_ params: [String: String]) async throws -> String {
        let mixinKey = try await self.mixinKey()
        var all = params
        all["wts"] = String(Int(Date().timeIntervalSince1970))
        let query = all.sorted { $0.key < $1.key }
            .map { "\(encode($0.key))=\(encode($0.value))" }
            .joined(separator: "&")
        let digest = Insecure.MD5.hash(data: Data((query + mixinKey).utf8))
        let wRid = digest.map { String(format: "%02x", $0) }.joined()
        return query + "&w_rid=" + wRid
    }

    static func prewarm() async {
        _ = try? await mixinKey()
    }

    private static func mixinKey() async throws -> String {
        if let cached = cachedKey, Date().timeIntervalSince(cached.fetchedAt) < 12 * 3600 {
            return cached.key
        }
        // nav 接口未登录时 code=-101,但 data.wbi_img 仍有效,所以不走统一信封校验
        struct Nav: Decodable {
            struct D: Decodable {
                struct Wbi: Decodable { let img_url: String; let sub_url: String }
                let wbi_img: Wbi
            }
            let data: D
        }
        var req = URLRequest(url: URL(string: "https://api.bilibili.com/x/web-interface/nav")!)
        BiliClient.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if let cookie = CookieStore.cookie { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let (data, _) = try await URLSession.shared.data(for: req)
        let nav = try JSONDecoder().decode(Nav.self, from: data)
        let raw = keyPart(nav.data.wbi_img.img_url) + keyPart(nav.data.wbi_img.sub_url)
        let chars = Array(raw)
        let key = String(mixinKeyTable.compactMap { $0 < chars.count ? chars[$0] : nil }.prefix(32))
        cachedKey = (key, Date())
        return key
    }

    private static func keyPart(_ url: String) -> String {
        url.split(separator: "/").last.map { $0.split(separator: ".").first.map(String.init) ?? "" } ?? ""
    }

    /// 与 Python urlencode 一致的编码:RFC3986 unreserved 之外全部百分号编码,空格转 +
    private static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        return encoded.replacingOccurrences(of: "%20", with: "+")
    }
}
