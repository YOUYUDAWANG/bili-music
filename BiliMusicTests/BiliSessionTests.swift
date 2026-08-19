import XCTest
@testable import BiliMusic

final class BiliSessionTests: XCTestCase {
    func testParsingCookieExtractsIdentityFields() {
        let session = BiliSession.parsingCookie("SESSDATA=abc; bili_jct=csrf; DedeUserID=42; buvid3=xyz")

        XCTAssertEqual(session.sessData, "abc")
        XCTAssertEqual(session.biliJct, "csrf")
        XCTAssertEqual(session.dedeUserId, "42")
        XCTAssertEqual(session.mid, 42)
        XCTAssertEqual(session.buvid3, "xyz")
        XCTAssertTrue(session.isLoggedIn)
        XCTAssertFalse(session.isExpired)
    }

    func testClearAuthKeepsDeviceCookieMaterial() {
        var session = BiliSession.parsingCookie("SESSDATA=abc; bili_jct=csrf; DedeUserID=42; buvid3=xyz")
        session.imgKey = "img"
        session.subKey = "sub"
        session.uname = "user"

        let cleared = session.clearAuth()

        XCTAssertFalse(cleared.isLoggedIn)
        XCTAssertEqual(cleared.buvid3, "xyz")
        XCTAssertEqual(cleared.imgKey, "img")
        XCTAssertEqual(cleared.subKey, "sub")
        XCTAssertNil(cleared.uname)
        XCTAssertTrue(cleared.cookie.isEmpty)
    }

    func testSessionStoreMarksExpiryAndClearsItOnNewCookie() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bili-session-\(UUID().uuidString).json")
        let store = BiliSessionStore(fileURLForTesting: url)

        store.handleCookieChange("SESSDATA=abc; bili_jct=csrf; DedeUserID=42")
        XCTAssertTrue(store.session.isLoggedIn)
        XCTAssertFalse(store.isExpired)

        store.markExpired()
        XCTAssertTrue(store.isExpired)
        XCTAssertFalse(store.session.isLoggedIn)

        store.handleCookieChange("SESSDATA=new; bili_jct=csrf2; DedeUserID=42")
        XCTAssertFalse(store.isExpired)
        XCTAssertTrue(store.session.isLoggedIn)
    }

    func testAPIErrorRecognizesAuthenticationFailure() {
        XCTAssertTrue(BiliClient.APIError(code: -101, message: "账号未登录").isAuthenticationFailure)
        XCTAssertTrue(BiliClient.APIError(code: 401, message: "unauthorized").isAuthenticationFailure)
        XCTAssertFalse(BiliClient.APIError(code: -403, message: "wbi").isAuthenticationFailure)
    }
}
