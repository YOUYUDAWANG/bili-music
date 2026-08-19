import Foundation
import OSLog

private let sessionLog = Logger(subsystem: "com.fubuki.BiliMusic", category: "session")

/// 会话资料（用户名、WBI、refresh token、过期态）。Cookie 本体仍只在 Keychain。
final class BiliSessionStore: @unchecked Sendable {
    static let shared = BiliSessionStore()

    private let lock = NSLock()
    private let fileURL: URL
    private let fileWriter = VersionedAtomicFileWriter()
    private var current = BiliSession.empty
    private var writeRevision = 0
    private var hasLoadedProfile = false

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bili-session.json")
        current = Self.readProfile(from: fileURL)
        hasLoadedProfile = true
        if let cookie = CookieStore.cookie, !cookie.isEmpty {
            current = BiliSession.parsingCookie(cookie, existing: current)
        } else {
            current = current.clearAuth()
        }
    }

#if DEBUG
    init(fileURLForTesting: URL) {
        fileURL = fileURLForTesting
        current = Self.readProfile(from: fileURLForTesting)
        hasLoadedProfile = true
    }
#endif

    var session: BiliSession {
        lock.withLock { current }
    }

    var isExpired: Bool {
        lock.withLock { current.isExpired && current.hasCookie }
    }

    var isLoggedIn: Bool {
        lock.withLock { current.isLoggedIn }
    }

    /// Cookie 刚写入或清除后同步解析字段。不回写 Keychain。
    func handleCookieChange(_ cookie: String?) {
        let snapshot: BiliSession = lock.withLock {
            if let cookie, !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                current = BiliSession.parsingCookie(cookie, existing: current)
            } else {
                current = current.clearAuth()
            }
            writeRevision += 1
            return current
        }
        persist(snapshot)
    }

    func adopt(
        cookie: String,
        refreshToken: String? = nil,
        buvid3: String? = nil
    ) {
        let snapshot: BiliSession = lock.withLock {
            current = BiliSession.parsingCookie(cookie, existing: current)
            if let refreshToken {
                let trimmed = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    current.refreshToken = trimmed
                }
            }
            if let buvid3 {
                let trimmed = buvid3.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    current.buvid3 = trimmed
                }
            }
            writeRevision += 1
            return current
        }
        persist(snapshot)
    }

    func apply(profile: BiliNavProfile) {
        let snapshot: BiliSession = lock.withLock {
            if !profile.isLogin {
                current.isExpired = current.hasCookie
                current.updatedAt = Date()
            } else {
                current.isExpired = false
                current.mid = profile.mid ?? current.mid
                current.uname = Self.normalized(profile.uname) ?? current.uname
                current.face = Self.normalized(profile.face) ?? current.face
                current.imgKey = Self.normalized(profile.imgKey) ?? current.imgKey
                current.subKey = Self.normalized(profile.subKey) ?? current.subKey
                current.updatedAt = Date()
            }
            writeRevision += 1
            return current
        }
        persist(snapshot)
        if snapshot.isExpired {
            postAuthenticationDidChange()
        }
    }

    func markExpired() {
        let shouldNotify: Bool = lock.withLock {
            guard current.hasCookie, !current.isExpired else { return false }
            current.isExpired = true
            current.updatedAt = Date()
            writeRevision += 1
            persistLockedSnapshot()
            return true
        }
        if shouldNotify {
            postAuthenticationDidChange()
        }
    }

    /// 启动时用 nav 确认 Cookie 是否仍有效，并补齐用户名 / WBI。
    func refreshFromNav() async {
        guard CookieStore.cookie != nil else { return }
        do {
            let profile = try await BiliClient().navProfile()
            apply(profile: profile)
            if !profile.isLogin {
                sessionLog.info("nav reported logged-out session")
            }
        } catch let error as BiliClient.APIError where error.isAuthenticationFailure {
            markExpired()
        } catch {
            sessionLog.info("session nav refresh skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

#if DEBUG
    func resetForTesting() {
        lock.withLock {
            current = .empty
            writeRevision += 1
        }
        try? FileManager.default.removeItem(at: fileURL)
    }
#endif

    private func persist(_ snapshot: BiliSession) {
        let revision: Int = lock.withLock {
            writeRevision
        }
        Task(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try await fileWriter.write(data, revision: revision, to: fileURL)
            } catch {
                sessionLog.error("session persist failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func persistLockedSnapshot() {
        let snapshot = current
        let revision = writeRevision
        Task(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try await fileWriter.write(data, revision: revision, to: fileURL)
            } catch {
                sessionLog.error("session persist failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func postAuthenticationDidChange() {
        let post = {
            NotificationCenter.default.post(name: .biliAuthenticationDidChange, object: nil)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func readProfile(from url: URL) -> BiliSession {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(BiliSession.self, from: data) else {
            return .empty
        }
        return decoded
    }
}
