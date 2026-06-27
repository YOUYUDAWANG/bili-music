import XCTest

final class PlayerChromeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-searchHistory", "[]"]
        app.launchEnvironment["BILIMUSIC_UITEST_FIXTURE"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
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
    func testQueueSideListScrollsVertically() throws {
        try openFullPlayerFromMini()
        try swipeToPlayerPage(direction: .right)

        let queuePage = element("playerQueuePage")
        XCTAssertTrue(queuePage.waitForExistence(timeout: 2), "Queue page should be visible before testing vertical scrolling.")

        for _ in 0..<3 where !app.staticTexts["Fixture Song Ten"].exists {
            let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
            let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        }

        XCTAssertTrue(app.staticTexts["Fixture Song Ten"].waitForExistence(timeout: 2), "Queue side page should allow vertical scrolling to later rows.")
        XCTAssertTrue(element("nowPlayingView").waitForExistence(timeout: 1), "Vertical queue scrolling should not minimize the full player.")
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
    func testProgressScrubDoesNotDismissOrChangePlayerPage() throws {
        try openFullPlayerFromMini()

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should be open before testing progress scrub ownership.")
        XCTAssertTrue(centerPlayerCoverArea().screenPoint.y > nowPlaying.frame.minY, "The center player cover area should be measurable before scrubbing.")

        let progress = element("nowPlayingProgress")
        XCTAssertTrue(progress.waitForExistence(timeout: 2), "The progress bar should be visible before scrubbing.")
        let start = progress.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.5))
        let end = progress.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 1), "Scrubbing progress should not minimize the full player.")
        XCTAssertFalse(element("playerQueuePage").isHittable, "Scrubbing progress should not swipe to the queue page.")
        XCTAssertFalse(element("playerRecommendationsPage").isHittable, "Scrubbing progress should not swipe to the recommendations page.")
    }

    @MainActor
    func testHorizontalPageSwipeChangesPageWithoutDismissing() throws {
        try openFullPlayerFromMini()

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should be open before testing horizontal page ownership.")

        try swipeToPlayerPage(direction: .left)

        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 1), "Horizontal page swipe should not minimize the full player.")
        XCTAssertTrue(element("playerRecommendationsPage").exists, "Horizontal page swipe should land on the recommendations page.")
    }

    @MainActor
    func testHorizontalDragOnQueueRowDoesNotJumpTrack() throws {
        try openFullPlayerFromMini()
        XCTAssertEqual(metadataElement().label, "Fixture Song One")

        try swipeToPlayerPage(direction: .right)

        let queuePage = element("playerQueuePage")
        XCTAssertTrue(queuePage.waitForExistence(timeout: 2), "Queue page should be visible before dragging a queue row.")
        let secondRowTitle = queuePage.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@", "Fixture Song Two"))
            .firstMatch
        XCTAssertTrue(secondRowTitle.waitForExistence(timeout: 2), "Queue should expose the second fixture row before dragging.")

        let start = secondRowTitle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
        let end = secondRowTitle.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        start.press(forDuration: 0.08, thenDragTo: end)

        let currentRow = element("playerQueueCurrentRow")
        if currentRow.waitForExistence(timeout: 1) {
            XCTAssertTrue(currentRow.label.contains("Fixture Song One"), "A horizontal row drag should not be treated as tapping the second queue item.")
        } else {
            let metadata = element("nowPlayingMetadata")
            XCTAssertTrue(metadata.waitForExistence(timeout: 2), "If the horizontal row drag changes player pages, the center metadata should be visible.")
            XCTAssertEqual(metadata.label, "Fixture Song One", "A horizontal row drag should not be treated as tapping the second queue item.")
        }
    }

    @MainActor
    func testDensePlayerLayoutKeepsKeyElementsOrderedAndBottomGapBounded() throws {
        try openFullPlayerFromMini()
        try assertDensePlayerLayout()
    }

    @MainActor
    func testLandscapePlayerKeepsCoreChromeVisible() throws {
        try openFullPlayerFromMini()

        XCUIDevice.shared.orientation = .landscapeLeft

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should stay open after rotating landscape.")

        let metadata = metadataElement()
        let progress = element("nowPlayingProgress")
        let transport = element("playerTransportControls")
        let toolbar = element("playerToolbar")

        for element in [metadata, progress, transport, toolbar] {
            XCTAssertTrue(element.waitForExistence(timeout: 2), "Landscape player element should exist: \(element)")
            XCTAssertFalse(element.frame.isEmpty, "Landscape player element should have a measurable frame: \(element)")
            XCTAssertGreaterThanOrEqual(element.frame.minY, app.frame.minY - 1, "Landscape player element should not be clipped above the screen: \(element)")
            XCTAssertLessThanOrEqual(element.frame.maxY, app.frame.maxY + 1, "Landscape player element should not be clipped below the screen: \(element)")
        }
    }

    @MainActor
    func testTappingRecommendationKeepsHomeListStable() throws {
        try assertFixtureHomeRowStableWhileStartingPlayback()
    }

    @MainActor
    func testSearchTabUsesFocusedHistoryWithoutModeScopes() throws {
        app.tabBars.buttons["搜索"].tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3), "Search tab should expose the system search field.")
        searchField.tap()
        searchField.typeText("a")

        XCTAssertFalse(element("searchScope_music").exists, "Search should no longer expose a Music mode scope.")
        XCTAssertFalse(element("searchScope_expanded").exists, "Search should no longer expose an expanded-results mode scope.")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func assertDensePlayerLayout() throws {
        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should be open before dense layout verification.")

        let pageHint = element("playerPageHint")
        let metadata = metadataElement()
        let progress = element("nowPlayingProgress")
        let transport = element("playerTransportControls")
        let toolbar = element("playerToolbar")

        let elements = [pageHint, metadata, progress, transport, toolbar]
        for element in elements {
            XCTAssertTrue(element.waitForExistence(timeout: 2), "Dense player layout element should exist: \(element)")
            XCTAssertFalse(element.frame.isEmpty, "Dense player layout element should have a measurable frame: \(element)")
        }

        let coverArea = centerPlayerCoverArea()
        XCTAssertGreaterThanOrEqual(coverArea.screenPoint.y, pageHint.frame.maxY + 80, "Cover area should stay below the page hint.")
        XCTAssertLessThanOrEqual(coverArea.screenPoint.y, metadata.frame.minY - 24, "Cover area should stay above title metadata.")
        XCTAssertGreaterThanOrEqual(metadata.frame.minY - pageHint.frame.maxY, 210, "Dense player layout should preserve room for visible cover art.")
        assertVerticalOrder(metadata, progress, "Title metadata should stay above progress.")
        assertVerticalOrder(progress, transport, "Progress should stay above transport controls.")
        assertVerticalOrder(transport, toolbar, "Transport controls should stay above the player toolbar.")

        let layoutElements = [metadata, progress, transport, toolbar]
        for firstIndex in 0..<layoutElements.count {
            for secondIndex in (firstIndex + 1)..<layoutElements.count {
                assertNoFrameOverlap(layoutElements[firstIndex], layoutElements[secondIndex])
            }
        }

        let maxBottomGap: CGFloat = app.frame.height <= 700 ? 96 : 128
        let bottomGap = app.frame.maxY - toolbar.frame.maxY
        XCTAssertLessThanOrEqual(bottomGap, maxBottomGap, "Dense player layout should not leave excessive empty space below the toolbar.")
    }

    private func assertVerticalOrder(_ upper: XCUIElement, _ lower: XCUIElement, _ message: String) {
        XCTAssertLessThanOrEqual(upper.frame.maxY, lower.frame.minY + 1, message)
    }

    private func assertNoFrameOverlap(_ first: XCUIElement, _ second: XCUIElement) {
        XCTAssertFalse(first.frame.intersects(second.frame), "Dense player key elements should not overlap: \(first) and \(second)")
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
        let coverArea = centerPlayerCoverArea()
        XCTAssertTrue(coverArea.screenPoint.y > nowPlaying.frame.minY, "The center player cover area should be measurable before swiping pages.")

        let expectedPage = direction == .left ? "推荐" : "队列"
        if direction == .left {
            coverArea.leftSwipe()
        } else {
            coverArea.rightSwipe()
        }

        XCTAssertTrue(waitForPlayerPage(expectedPage), "Horizontal swipe should switch the player page to \(expectedPage).")
    }

    @MainActor
    private func centerPlayerCoverArea() -> CoverArea {
        let pageHint = element("playerPageHint")
        let metadata = metadataElement()
        XCTAssertTrue(pageHint.waitForExistence(timeout: 2), "Page hint should exist before deriving the cover area.")
        XCTAssertTrue(metadata.waitForExistence(timeout: 2), "Metadata should exist before deriving the cover area.")

        let top = pageHint.frame.maxY
        let bottom = metadata.frame.minY
        let y = min(max((top + bottom) / 2, app.frame.minY + 120), app.frame.maxY - 120)
        return CoverArea(app: app, screenPoint: CGPoint(x: app.frame.midX, y: y))
    }

    @MainActor
    private func metadataElement(timeout: TimeInterval = 2) -> XCUIElement {
        let identified = element("nowPlayingMetadata")
        if identified.waitForExistence(timeout: 0.4) {
            return identified
        }

        let fixtureTitle = app.staticTexts
            .matching(NSPredicate(format: "label == %@", "Fixture Song One"))
            .firstMatch
        if fixtureTitle.waitForExistence(timeout: timeout) {
            return fixtureTitle
        }

        return identified
    }

    private struct CoverArea {
        let app: XCUIApplication
        let screenPoint: CGPoint

        func leftSwipe() {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                .withOffset(CGVector(dx: app.frame.width * 0.74, dy: screenPoint.y))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                .withOffset(CGVector(dx: app.frame.width * 0.22, dy: screenPoint.y))
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        func rightSwipe() {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                .withOffset(CGVector(dx: app.frame.width * 0.22, dy: screenPoint.y))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                .withOffset(CGVector(dx: app.frame.width * 0.74, dy: screenPoint.y))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    @MainActor
    private func waitForPlayerPage(_ title: String, timeout: TimeInterval = 2) -> Bool {
        if title != "正在播放" {
            let expectedPageIdentifier = title == "队列" ? "playerQueuePage" : "playerRecommendationsPage"
            let expectedPage = element(expectedPageIdentifier)
            if expectedPage.waitForExistence(timeout: timeout), expectedPage.isHittable {
                return true
            }
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
