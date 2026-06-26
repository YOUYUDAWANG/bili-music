import XCTest

final class PlayerChromeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-searchHistory", "[]"]
        app.launchEnvironment["BILIMUSIC_UITEST_FIXTURE"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testMiniPlayerSlowDragOpensRespectsSafeAreaAndClosesFromTopChrome() throws {
        try openFullPlayerFromMini()

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Slow upward drag from the mini player should open the full player.")

        let switcher = element("playerModeSwitchButton")
        XCTAssertTrue(switcher.waitForExistence(timeout: 2), "The toolbar music/MV switcher should be visible.")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.11))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        start.press(forDuration: 0.05, thenDragTo: end)

        let miniPlayer = element("miniPlayer")
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 3), "Dragging down from the top player chrome should close the full player.")
        XCTAssertTrue(nowPlaying.waitForNonExistence(timeout: 3), "Full player should be removed after closing.")
    }

    @MainActor
    func testFullPlayerChromeStaysBelowStatusBar() throws {
        try openFullPlayerFromMini()

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should be open for chrome layout verification.")

        let switcher = element("playerModeSwitchButton")
        XCTAssertTrue(switcher.waitForExistence(timeout: 2), "The toolbar music/MV switcher should be visible.")
        XCTAssertGreaterThan(switcher.frame.minY, 80, "The player toolbar should stay below the status bar.")
    }

    @MainActor
    func testTinyMiniPlayerDragDoesNotOpenFullPlayer() throws {
        let miniPlayer = element("miniPlayer")
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5), "Fixture mini player should be visible.")

        let start = miniPlayer.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: -16))
        start.press(forDuration: 0.25, thenDragTo: end)

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForNonExistence(timeout: 1), "A small upward adjustment on the mini player should not open the full player.")
        XCTAssertTrue(miniPlayer.exists, "The mini player should remain visible after a tiny drag.")
    }

    @MainActor
    func testShallowMiniPlayerDragCancelsAndKeepsMiniPlayerVisible() throws {
        let miniPlayer = element("miniPlayer")
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5), "Fixture mini player should be visible.")

        let start = miniPlayer.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: -20))
        start.press(forDuration: 0.30, thenDragTo: end)

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForNonExistence(timeout: 1), "A shallow upward drag should cancel instead of opening the full player.")
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 2), "The mini player should remain visible after a shallow canceled drag.")
    }

    @MainActor
    func testDraggingCenterPlayerBodyDismissesFullPlayer() throws {
        try openFullPlayerFromMini()

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should be open before testing center-page dismiss.")

        let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)

        XCTAssertTrue(nowPlaying.waitForNonExistence(timeout: 3), "Dragging down on the center player body should minimize the full player.")
        XCTAssertTrue(element("miniPlayer").waitForExistence(timeout: 3), "The mini player should reappear after center-page minimize.")
    }

    @MainActor
    func testDraggingQueueListBodyDoesNotDismissFullPlayer() throws {
        try openFullPlayerFromMini()
        try swipeToPlayerPage(direction: .right)

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should stay open before testing queue-list drag.")

        let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
        let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)

        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 1), "Dragging inside the queue list body should not minimize the full player.")
    }

    @MainActor
    func testDraggingRecommendationListBodyDoesNotDismissFullPlayer() throws {
        try openFullPlayerFromMini()
        try swipeToPlayerPage(direction: .left)

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should stay open before testing recommendation-list drag.")

        let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
        let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)

        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 1), "Dragging inside the recommendation list body should not minimize the full player.")
    }

    @MainActor
    func testTappingRecommendationKeepsHomeListStable() throws {
        try assertFixtureHomeRowStableWhileStartingPlayback()
    }

    @MainActor
    func testSearchTabUsesSystemSearchChrome() throws {
        app.tabBars.buttons["搜索"].tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3), "Search tab should expose the system search field.")
        searchField.tap()
        searchField.typeText("a")

        let musicScopeVisible = element("searchScope_music").waitForExistence(timeout: 3)
            || app.buttons["音乐"].exists
            || app.staticTexts["音乐"].exists
        let expandedScopeVisible = element("searchScope_expanded").waitForExistence(timeout: 3)
            || app.buttons["更多"].exists
            || app.staticTexts["更多"].exists
        XCTAssertTrue(musicScopeVisible, "Search should expose a native Music scope.")
        XCTAssertTrue(expandedScopeVisible, "Search should expose a native expanded-results scope.")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func assertFixtureHomeRowStableWhileStartingPlayback(rowIdentifier: String = "homeTrackRow0") throws {
        let firstRow = app.buttons[rowIdentifier]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "Fixture recommendation row should be visible.")
        let frameBefore = firstRow.frame

        firstRow.tap()

        let miniPlayer = element("miniPlayer")
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 3), "Tapping a recommendation should start the fixture player.")
        XCTAssertTrue(firstRow.waitForExistence(timeout: 2), "The recommendation list should not disappear after tapping a song.")
        XCTAssertEqual(firstRow.frame.minY, frameBefore.minY, accuracy: 12, "The recommendation list should not jump after tapping a song.")
    }

    @MainActor
    private func openFullPlayerFromMini() throws {
        let miniPlayer = element("miniPlayer")
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5), "Fixture mini player should be visible.")

        let openStart = miniPlayer.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.5))
        let openEnd = openStart.withOffset(CGVector(dx: 0, dy: -160))
        openStart.press(forDuration: 0.35, thenDragTo: openEnd)
    }

    private enum PlayerPageSwipeDirection {
        case left
        case right
    }

    @MainActor
    private func swipeToPlayerPage(direction: PlayerPageSwipeDirection) throws {
        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should be open before swiping pages.")
        let cover = element("nowPlayingCover")
        XCTAssertTrue(cover.waitForExistence(timeout: 2), "The center player cover should be visible before swiping pages.")

        let expectedPage = direction == .left ? "推荐" : "队列"
        if direction == .left {
            cover.swipeLeft()
        } else {
            cover.swipeRight()
        }

        XCTAssertTrue(waitForPlayerPage(expectedPage), "Horizontal swipe should switch the player page to \(expectedPage).")
    }

    @MainActor
    private func waitForPlayerPage(_ title: String, timeout: TimeInterval = 2) -> Bool {
        let expectedPageIdentifier = title == "队列" ? "playerQueuePage" : "playerRecommendationsPage"
        let expectedPage = element(expectedPageIdentifier)
        if expectedPage.waitForExistence(timeout: timeout), expectedPage.isHittable {
            return true
        }

        let hint = element("playerPageHint")
        guard hint.waitForExistence(timeout: timeout) else { return false }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if hint.value as? String == title {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return hint.value as? String == title
    }
}
