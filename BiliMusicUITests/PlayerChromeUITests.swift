import XCTest

final class PlayerChromeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = [
            "-searchHistory", "[]",
            "-cleanListTitles", "false"
        ]
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
    func testMiniPlayerArtworkAndFullArtworkSurviveTwoOpenCloseTransitions() throws {
        for iteration in 1...2 {
            let miniTitle = element("miniPlayerTitle")
            XCTAssertTrue(miniTitle.waitForExistence(timeout: 3), "Mini title should be visible before opening on round \(iteration).")
            XCTAssertEqual(miniTitle.label, "Fixture Song One", "Mini title should keep the raw fixture title before opening on round \(iteration).")
            XCTAssertTrue(element("miniPlayerArtwork").waitForExistence(timeout: 3), "Mini artwork should be visible before opening on round \(iteration).")

            try openFullPlayerFromMini()
            let nowPlaying = element("nowPlayingView")
            XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should open on round \(iteration).")

            let fullTitle = metadataElement(timeout: 3)
            XCTAssertTrue(fullTitle.waitForExistence(timeout: 3), "Full title should be visible after opening on round \(iteration).")
            XCTAssertEqual(fullTitle.label, "Fixture Song One", "Full title should keep the raw fixture title after opening on round \(iteration).")
            XCTAssertTrue(element("nowPlayingArtwork").waitForExistence(timeout: 3), "Full artwork should be visible after opening on round \(iteration).")

            centerPlayerCoverArea().dragDownToDismiss()

            XCTAssertTrue(nowPlaying.waitForNonExistence(timeout: 3), "Full player should close on round \(iteration).")
            XCTAssertTrue(miniTitle.waitForExistence(timeout: 3), "Mini title should be visible again after closing on round \(iteration).")
            XCTAssertEqual(miniTitle.label, "Fixture Song One", "Mini title should keep the raw fixture title after closing on round \(iteration).")
            XCTAssertTrue(element("miniPlayerArtwork").waitForExistence(timeout: 3), "Mini artwork should be visible again after closing on round \(iteration).")
        }
    }

    @MainActor
    func testFullPlayerContentAppearsPromptlyAfterOpenTransition() throws {
        let miniPlayer = element("miniPlayer")
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5), "Fixture mini player should be visible.")

        let openStart = miniPlayer.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.5))
        let openEnd = openStart.withOffset(CGVector(dx: 0, dy: -160))
        openStart.press(forDuration: 0.35, thenDragTo: openEnd)

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 1), "Full player shell should mount as the open transition starts.")
        XCTAssertTrue(element("nowPlayingArtwork").exists, "Artwork may participate in the mini-to-full transition.")
        XCTAssertTrue(element("nowPlayingMetadata").waitForExistence(timeout: 0.8), "Metadata should appear promptly after opening.")
        XCTAssertTrue(element("nowPlayingProgress").waitForExistence(timeout: 0.8), "Progress should appear promptly after opening.")
        XCTAssertTrue(element("playerToolbar").waitForExistence(timeout: 0.8), "Player actions should appear promptly after opening.")
    }

    @MainActor
    func testBottomContextDrawerStartsCollapsedAndExpandsWithUpwardDrag() throws {
        try openFullPlayerFromMini()

        let collapsedDrawer = element("playerBottomContextCollapsed")
        XCTAssertTrue(collapsedDrawer.waitForExistence(timeout: 2), "Bottom queue context should start collapsed.")
        XCTAssertFalse(element("playerBottomQueuePanel").exists, "The queue list should not be expanded by default.")

        let start = collapsedDrawer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        let end = start.withOffset(CGVector(dx: 0, dy: -92))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(element("playerBottomQueuePanel").waitForExistence(timeout: 2), "Dragging upward on the collapsed queue context should expand the list.")
        XCTAssertTrue(element("nowPlayingView").waitForExistence(timeout: 1), "Expanding the bottom queue context should not close the player.")
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

        centerPlayerCoverArea().dragDownToDismiss()

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
        XCTAssertEqual(nowPlayingTitleLabel(), "Fixture Song One", "Vertical queue scrolling should not change the current track.")
        XCTAssertTrue(waitForPlayerPage("队列"), "Vertical queue scrolling should keep the queue page selected.")
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
    func testRecommendationSideListScrollsVerticallyWithoutChangingPageOrTrack() throws {
        try openFullPlayerFromMini()
        try swipeToPlayerPage(direction: .left)

        let recommendationsPage = element("playerRecommendationsPage")
        XCTAssertTrue(recommendationsPage.waitForExistence(timeout: 2), "Recommendations page should be visible before testing vertical scrolling.")

        for _ in 0..<3 where !app.staticTexts["Fixture Song Ten"].exists {
            let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
            let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        }

        XCTAssertTrue(app.staticTexts["Fixture Song Ten"].waitForExistence(timeout: 2), "Recommendation side page should allow vertical scrolling to later rows.")
        XCTAssertTrue(element("nowPlayingView").waitForExistence(timeout: 1), "Vertical recommendation scrolling should not minimize the full player.")
        XCTAssertEqual(nowPlayingTitleLabel(), "Fixture Song One", "Vertical recommendation scrolling should not change the current track.")
        XCTAssertTrue(waitForPlayerPage("推荐"), "Vertical recommendation scrolling should keep the recommendations page selected.")
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
        XCTAssertTrue(waitForPlayerPage("推荐"), "A left swipe from the center page should land on recommendations.")

        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 1), "Horizontal page swipe should not minimize the full player.")
        XCTAssertTrue(element("playerRecommendationsPage").exists, "Horizontal page swipe should expose the recommendations page.")
    }

    @MainActor
    func testHorizontalRightSwipeFromCenterShowsQueueWithoutDismissing() throws {
        try openFullPlayerFromMini()

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should be open before testing horizontal page ownership.")

        try swipeToPlayerPage(direction: .right)
        XCTAssertTrue(waitForPlayerPage("队列"), "A right swipe from the center page should land on the queue.")

        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 1), "Horizontal page swipe should not minimize the full player.")
        XCTAssertTrue(element("playerQueuePage").exists, "Horizontal page swipe should expose the queue page.")
    }

    @MainActor
    func testHorizontalDragOnQueueRowDoesNotJumpTrack() throws {
        try openFullPlayerFromMini()
        XCTAssertEqual(nowPlayingTitleLabel(), "Fixture Song One")

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

    private func elements(_ identifier: String) -> [XCUIElement] {
        app.descendants(matching: .any).matching(identifier: identifier).allElementsBoundByIndex
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
        let currentTitle = currentPlayerPageTitle(timeout: 1) ?? "正在播放"
        let expectedPage = expectedPageTitle(afterSwiping: direction, from: currentTitle)

        let coverArea = centerPlayerCoverArea()
        performPagerSwipe(direction: direction, in: coverArea)
        if !waitForPlayerPage(expectedPage, timeout: 1.2) {
            performPagerSwipe(direction: direction, in: coverArea)
        }

        XCTAssertTrue(waitForPlayerPage(expectedPage), "Horizontal swipe should switch the player page to \(expectedPage).")
    }

    @MainActor
    private func performPagerSwipe(direction: PlayerPageSwipeDirection, in coverArea: CoverArea) {
        switch direction {
        case .left:
            coverArea.leftSwipe()
        case .right:
            coverArea.rightSwipe()
        }
    }

    @MainActor
    private func currentPlayerPageTitle(timeout: TimeInterval = 2) -> String? {
        let hint = element("playerPageHint")
        guard hint.waitForExistence(timeout: timeout) else { return nil }
        return hint.value as? String
    }

    private func expectedPageTitle(afterSwiping direction: PlayerPageSwipeDirection, from currentTitle: String) -> String {
        let pages = ["队列", "正在播放", "推荐"]
        guard let currentIndex = pages.firstIndex(of: currentTitle) else {
            return direction == .left ? "推荐" : "队列"
        }

        switch direction {
        case .left:
            return pages[min(pages.count - 1, currentIndex + 1)]
        case .right:
            return pages[max(0, currentIndex - 1)]
        }
    }

    @MainActor
    private func centerPlayerCoverArea() -> CoverArea {
        let nowPlaying = element("nowPlayingView")
        let artwork = element("nowPlayingArtwork")
        let pageHint = element("playerPageHint")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 2), "Full player should exist before deriving the cover area.")
        if artwork.waitForExistence(timeout: 2), !artwork.frame.isEmpty {
            return CoverArea(app: app, screenPoint: CGPoint(x: artwork.frame.midX, y: artwork.frame.midY))
        }

        XCTAssertTrue(pageHint.waitForExistence(timeout: 2), "Page hint should exist before deriving the cover area.")

        let top = max(pageHint.frame.maxY, nowPlaying.frame.minY + 96)
        let y = min(max(top + 170, app.frame.minY + 160), app.frame.maxY * 0.54)
        return CoverArea(app: app, screenPoint: CGPoint(x: app.frame.midX, y: y))
    }

    @MainActor
    private func metadataElement(timeout: TimeInterval = 2) -> XCUIElement {
        if let title = stableTitleElement(timeout: timeout) {
            return title
        }

        if let identified = stableMetadataElement(timeout: timeout) {
            return identified
        }

        if let fixtureTitle = fixtureTitleElement(timeout: timeout) {
            return fixtureTitle
        }

        return element("nowPlayingMetadata")
    }

    @MainActor
    private func nowPlayingTitleLabel(timeout: TimeInterval = 2) -> String {
        if let title = stableTitleElement(timeout: timeout) {
            return title.label
        }
        if let fixtureTitle = fixtureTitleElement(timeout: timeout) {
            return fixtureTitle.label
        }
        return metadataElement(timeout: timeout).label
    }

    @MainActor
    private func stableMetadataElement(timeout: TimeInterval) -> XCUIElement? {
        let nowPlaying = element("nowPlayingView")
        _ = nowPlaying.waitForExistence(timeout: timeout)

        let progress = element("nowPlayingProgress")
        _ = progress.waitForExistence(timeout: 0.4)
        let progressFrame = progress.exists ? progress.frame : .null

        if let fixtureTitle = fixtureTitleElement(timeout: 0.5) {
            return fixtureTitle
        }

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let title = bestMetadataCandidate(
                in: elements("nowPlayingTitle"),
                playerFrame: nowPlaying.frame,
                progressFrame: progressFrame
            ) {
                return title
            }

            if let metadata = bestMetadataCandidate(
                in: elements("nowPlayingMetadata").filter { $0.elementType != .staticText },
                playerFrame: nowPlaying.frame,
                progressFrame: progress.frame
            ) {
                return titleElement(in: metadata) ?? metadata
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return nil
    }

    @MainActor
    private func stableTitleElement(timeout: TimeInterval) -> XCUIElement? {
        let nowPlaying = element("nowPlayingView")
        _ = nowPlaying.waitForExistence(timeout: timeout)

        let progress = element("nowPlayingProgress")
        _ = progress.waitForExistence(timeout: 0.4)
        let progressFrame = progress.exists ? progress.frame : .null

        if let fixtureTitle = fixtureTitleElement(timeout: 0.5) {
            return fixtureTitle
        }

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let title = bestMetadataCandidate(
                in: elements("nowPlayingTitle"),
                playerFrame: nowPlaying.frame,
                progressFrame: progressFrame
            ) {
                return title
            }

            if let metadata = bestMetadataCandidate(
                in: elements("nowPlayingMetadata").filter { $0.elementType != .staticText },
                playerFrame: nowPlaying.frame,
                progressFrame: progressFrame
            ), let title = titleElement(in: metadata) {
                return title
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return nil
    }

    @MainActor
    private func fixtureTitleElement(timeout: TimeInterval) -> XCUIElement? {
        let nowPlaying = element("nowPlayingView")
        _ = nowPlaying.waitForExistence(timeout: timeout)

        let progress = element("nowPlayingProgress")
        _ = progress.waitForExistence(timeout: 0.4)
        let progressFrame = progress.exists ? progress.frame : .null
        let fixtureTitles = app.staticTexts.matching(NSPredicate(format: "label == %@", "Fixture Song One"))

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let candidates = fixtureTitles.allElementsBoundByIndex.filter { candidate in
                candidate.exists &&
                !candidate.frame.isEmpty &&
                candidate.frame.intersects(nowPlaying.frame) &&
                (progressFrame.isNull || progressFrame.isEmpty || candidate.frame.maxY <= progressFrame.minY + 1)
            }

            if let title = candidates.sorted(by: titleSort).first {
                return title
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return nil
    }

    private func bestMetadataCandidate(
        in candidates: [XCUIElement],
        playerFrame: CGRect,
        progressFrame: CGRect
    ) -> XCUIElement? {
        let visible = candidates.filter { candidate in
            candidate.exists &&
            !candidate.frame.isEmpty &&
            candidate.frame.intersects(playerFrame)
        }

        let ordered = visible.sorted { lhs, rhs in
            if abs(lhs.frame.minY - rhs.frame.minY) > 1 {
                return lhs.frame.minY < rhs.frame.minY
            }
            return lhs.frame.minX < rhs.frame.minX
        }

        if !progressFrame.isEmpty,
           let aboveProgress = ordered.first(where: { $0.frame.maxY <= progressFrame.minY + 1 }) {
            return aboveProgress
        }

        return ordered.first
    }

    private func titleElement(in metadata: XCUIElement) -> XCUIElement? {
        let titles = metadata.descendants(matching: .staticText).allElementsBoundByIndex
            .filter { $0.exists && !$0.frame.isEmpty }
            .sorted(by: titleSort)

        return titles.first(where: { isFixtureTitleLabel($0.label) }) ?? titles.first
    }

    private func isFixtureTitleLabel(_ label: String) -> Bool {
        label.hasPrefix("Fixture Song")
    }

    private func titleSort(_ lhs: XCUIElement, _ rhs: XCUIElement) -> Bool {
        if abs(lhs.frame.minY - rhs.frame.minY) > 1 {
            return lhs.frame.minY < rhs.frame.minY
        }
        return lhs.frame.minX < rhs.frame.minX
    }

    private struct CoverArea {
        let app: XCUIApplication
        let screenPoint: CGPoint

        private func absoluteCoordinate(x: CGFloat) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                .withOffset(CGVector(dx: x, dy: screenPoint.y))
        }

        func leftSwipe() {
            let start = absoluteCoordinate(x: app.frame.width * 0.88)
            let end = absoluteCoordinate(x: app.frame.width * 0.08)
            start.press(forDuration: 0.02, thenDragTo: end)
        }

        func rightSwipe() {
            let start = absoluteCoordinate(x: app.frame.width * 0.12)
            let end = absoluteCoordinate(x: app.frame.width * 0.92)
            start.press(forDuration: 0.02, thenDragTo: end)
        }

        func dragDownToDismiss() {
            let start = absoluteCoordinate(x: screenPoint.x)
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                .withOffset(CGVector(dx: screenPoint.x, dy: app.frame.height * 0.76))
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
