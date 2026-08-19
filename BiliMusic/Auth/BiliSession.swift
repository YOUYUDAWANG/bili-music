import Foundation

/// 运行时会话。Cookie 仍由钥匙串保管；这里保存解析后的字段、资料和过期态。
struct BiliSession: Equatable, Codable, Sendable {
    var cookie: String
    var sessData: String
    var biliJct: String
    var dedeUserId: String
    var refreshToken: String
    var mid: Int?
    var uname: String?
    var face: String?
    var imgKey: String?
    var subKey: String?
    var buvid3: String?
    var isExpired: Bool
    var updatedAt: Date

    static let empty = BiliSession(
        cookie: "",
        sessData: "",
        biliJct: "",
        dedeUserId: "",
        refreshToken: "",
        mid: nil,
        uname: nil,
        face: nil,
        imgKey: nil,
        subKey: nil,
        buvid3: nil,
        isExpired: false,
        updatedAt: Date(timeIntervalSince1970: 0))

    var hasCookie: Bool { !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var isLoggedIn: Bool {
        !isExpired
            && !sessData.isEmpty
            && !biliJct.isEmpty
            && !dedeUserId.isEmpty
    }

    var hasProfile: Bool {
        mid != nil || (uname?.isEmpty == false)
    }

    var hasWbiKeys: Bool {
        (imgKey?.isEmpty == false) && (subKey?.isEmpty == false)
    }

    var isReady: Bool { isLoggedIn && hasProfile }

    func clearAuth() -> BiliSession {
        var next = self
        next.cookie = ""
        next.sessData = ""
        next.biliJct = ""
        next.dedeUserId = ""
        next.refreshToken = ""
        next.mid = nil
        next.uname = nil
        next.face = nil
        next.isExpired = false
        next.updatedAt = Date()
        return next
    }

    static func parsingCookie(_ cookie: String, existing: BiliSession = .empty) -> BiliSession {
        let values = cookieValues(in: cookie)
        var next = existing
        next.cookie = cookie
        next.sessData = values["SESSDATA"] ?? ""
        next.biliJct = values["bili_jct"] ?? ""
        next.dedeUserId = values["DedeUserID"] ?? ""
        if let mid = Int(next.dedeUserId) {
            next.mid = mid
        }
        if let buvid3 = values["buvid3"], !buvid3.isEmpty {
            next.buvid3 = buvid3
        }
        next.isExpired = false
        next.updatedAt = Date()
        return next
    }

    static func cookieValues(in cookie: String) -> [String: String] {
        var values: [String: String] = [:]
        for part in cookie.split(separator: ";") {
            let pair = part.trimmingCharacters(in: .whitespaces)
            guard let equals = pair.firstIndex(of: "=") else { continue }
            let name = String(pair[..<equals])
            let value = String(pair[pair.index(after: equals)...])
            guard !name.isEmpty else { continue }
            values[name] = value
        }
        return values
    }
}

struct BiliNavProfile: Equatable, Sendable {
    var isLogin: Bool
    var mid: Int?
    var uname: String?
    var face: String?
    var imgKey: String?
    var subKey: String?
}

enum BiliAuthenticationError: LocalizedError {
    case expired

    var errorDescription: String? {
        switch self {
        case .expired:
            return "登录已失效，请重新扫码登录"
        }
    }
}

extension BiliClient.APIError {
    var isAuthenticationFailure: Bool {
        code == 401 || code == -101
    }
}
