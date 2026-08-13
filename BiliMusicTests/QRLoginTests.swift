import XCTest
@testable import BiliMusic

final class QRLoginTests: XCTestCase {
    func testLoginCookieCanComeEntirelyFromResponseHeaders() throws {
        let cookies = [
            makeCookie(name: "SESSDATA", value: "header-session"),
            makeCookie(name: "bili_jct", value: "header-csrf"),
            makeCookie(name: "DedeUserID", value: "123456"),
        ]

        let cookie = try BiliClient.qrLoginCookie(
            callbackURL: "https://passport.biligame.com/crossDomain",
            responseCookies: cookies)

        XCTAssertEqual(
            cookie,
            "SESSDATA=header-session; bili_jct=header-csrf; DedeUserID=123456")
    }

    func testResponseCookiesOverrideAndCompleteCallbackURL() throws {
        let callback = "https://passport.biligame.com/crossDomain?DedeUserID=111&SESSDATA=url%2Csession&bili_jct=url-csrf"
        let cookies = [
            makeCookie(name: "SESSDATA", value: "header-session"),
            makeCookie(name: "sid", value: "ignored"),
        ]

        let cookie = try BiliClient.qrLoginCookie(
            callbackURL: callback,
            responseCookies: cookies)

        XCTAssertEqual(
            cookie,
            "SESSDATA=header-session; bili_jct=url-csrf; DedeUserID=111")
    }

    func testEncodedCallbackCookieValueIsPreserved() throws {
        let callback = "https://passport.biligame.com/crossDomain?DedeUserID=111&SESSDATA=value%2Cwith%2Aencoding&bili_jct=csrf"

        let cookie = try BiliClient.qrLoginCookie(
            callbackURL: callback,
            responseCookies: [])

        XCTAssertEqual(
            cookie,
            "SESSDATA=value%2Cwith%2Aencoding; bili_jct=csrf; DedeUserID=111")
    }

    func testMissingCredentialProducesActionableError() {
        XCTAssertThrowsError(try BiliClient.qrLoginCookie(
            callbackURL: "https://passport.biligame.com/crossDomain?DedeUserID=111",
            responseCookies: [])) { error in
            XCTAssertTrue(error.localizedDescription.contains("SESSDATA"))
            XCTAssertTrue(error.localizedDescription.contains("bili_jct"))
        }
    }

    private func makeCookie(name: String, value: String) -> HTTPCookie {
        HTTPCookie(properties: [
            .domain: ".bilibili.com",
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE",
        ])!
    }
}
