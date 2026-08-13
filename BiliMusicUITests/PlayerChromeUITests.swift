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
            let miniPlayer = element("miniPlayer")
            XCTAssertTrue(miniPlayer.waitForExistence(timeout: 3), "Mini player should be visible before opening on round \(iteration).")
            XCTAssertTrue(
                miniPlayer.descendants(matching: .staticText)["Fixture Song One"].waitForExistence(timeout: 3),
                "The standard popup bar should expose the current title before opening on round \(iteration)."
            )
            XCTAssertTrue(
                miniPlayer.descendants(matching: .image).firstMatch.waitForExistence(timeout: 3),
                "The standard popup bar should expose artwork before opening on round \(iteration)."
            )

            try openFullPlayerFromMini()
            let nowPlaying = element("nowPlayingView")
            XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should open on round \(iteration).")

            let fullTitle = metadataElement(timeout: 3)
            XCTAssertTrue(fullTitle.waitForExistence(timeout: 3), "Full title should be visible after opening on round \(iteration).")
            XCTAssertEqual(fullTitle.label, "Fixture Song One", "Full title should keep the raw fixture title after opening on round \(iteration).")
            XCTAssertTrue(element("nowPlayingArtwork").waitForExistence(timeout: 3), "Full artwork should be visible after opening on round \(iteration).")

            centerPlayerCoverArea().dragDownToDismiss()

            XCTAssertTrue(nowPlaying.waitForNonExistence(timeout: 3), "Full player should close on round \(iteration).")
            XCTAssertTrue(miniPlayer.waitForExistence(timeout: 3), "Mini player should be visible again after closing on round \(iteration).")
            XCTAssertTrue(
                miniPlayer.descendants(matching: .staticText)["Fixture Song One"].waitForExistence(timeout: 3),
                "The current title should survive closing on round \(iteration)."
            )
            XCTAssertTrue(
                miniPlayer.descendants(matching: .image).firstMatch.waitForExistence(timeout: 3),
                "Artwork should survive closing on round \(iteration)."
            )
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
    func testBottomContextUsesYouTubeMusicStyleQueueStates() throws {
        try openFullPlayerFromMini()

        let collapsedDrawer = element("playerBottomContextCollapsed")
        XCTAssertTrue(collapsedDrawer.waitForExistence(timeout: 2), "Bottom queue context should start as a collapsed Up Next surface.")
        let nextTitle = element("playerCollapsedNextTrackTitle")
        XCTAssertTrue(nextTitle.waitForExistence(timeout: 2), "Collapsed queue context should preview the next song.")
        XCTAssertEqual(nextTitle.label, "Fixture Song Two", "Collapsed queue context should show the actual next queue item.")
        XCTAssertFalse(element("playerBottomQueuePanel").exists, "The queue list should not be expanded by default.")

        let start = collapsedDrawer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        let end = start.withOffset(CGVector(dx: 0, dy: -92))
        start.press(forDuration: 0.05, thenDragTo: end)

        let splitHeader = element("playerQueueSplitHeader")
        XCTAssertTrue(splitHeader.waitForExistence(timeout: 2), "First upward drag should reveal the split Up Next state.")
        XCTAssertTrue(element("playerBottomQueuePanel").waitForExistence(timeout: 2), "Split state should show the queue list.")

        let splitStart = splitHeader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let splitEnd = splitStart.withOffset(CGVector(dx: 0, dy: -116))
        splitStart.press(forDuration: 0.05, thenDragTo: splitEnd)

        XCTAssertTrue(element("playerQueueFullHeader").waitForExistence(timeout: 2), "Second upward drag should promote the queue into the full queue state.")
        let fullQueueDrawer = element("playerBottomContextDrawer")
        XCTAssertTrue(fullQueueDrawer.waitForExistence(timeout: 2), "Full queue should keep the bottom context drawer visible.")
        let fullQueuePanel = element("playerBottomQueuePanel")
        XCTAssertTrue(fullQueuePanel.waitForExistence(timeout: 2), "Full queue should keep the queue panel visible.")
        XCTAssertLessThan(fullQueueDrawer.frame.minY, app.frame.height * 0.30, "Full queue drawer should start near the upper player area like a queue sheet, not near the bottom.")
        XCTAssertGreaterThan(fullQueuePanel.frame.height, app.frame.height * 0.55, "Full queue should allocate a queue-dominant area instead of a small bottom drawer.")
        XCTAssertTrue(element("nowPlayingView").waitForExistence(timeout: 1), "Promoting the queue context should not close the player.")
    }

    @MainActor
    func testDraggingDownInsideFullQueueListDoesNotDismissPlayer() throws {
        try openFullPlayerFromMini()
        try expandBottomContextToFullQueue()

        let fullQueuePanel = element("playerBottomQueuePanel")
        XCTAssertTrue(fullQueuePanel.waitForExistence(timeout: 2), "Full queue panel should be visible before testing list drag ownership.")

        let dragStart = fullQueuePanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        let dragEnd = fullQueuePanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)

        XCTAssertTrue(element("nowPlayingView").waitForExistence(timeout: 1), "Dragging down inside the full queue list should scroll or bounce the list, not minimize the player.")
        XCTAssertTrue(element("playerQueueFullHeader").waitForExistence(timeout: 1), "Dragging down inside the list body should keep the full queue state.")
    }

    @MainActor
    func testDraggingDownInsideSplitQueueListDoesNotDismissPlayer() throws {
        try openFullPlayerFromMini()
        try expandBottomContextToSplit()

        let splitQueuePanel = element("playerBottomQueuePanel")
        XCTAssertTrue(splitQueuePanel.waitForExistence(timeout: 2), "Split queue panel should be visible before testing list drag ownership.")

        let dragStart = splitQueuePanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        let dragEnd = splitQueuePanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)

        XCTAssertTrue(element("nowPlayingView").waitForExistence(timeout: 1), "Dragging down inside the split queue list should scroll or bounce the list, not minimize the player.")
        XCTAssertTrue(element("playerQueueSplitHeader").waitForExistence(timeout: 1), "Dragging down inside the split list body should keep the split queue state.")
    }

    @MainActor
    func testSplitQueueCanScrollBeyondItsInitiallyVisibleRows() throws {
        try openFullPlayerFromMini()
        try expandBottomContextToSplit()

        let splitQueuePanel = element("playerBottomQueuePanel")
        XCTAssertTrue(splitQueuePanel.waitForExistence(timeout: 2), "Split queue panel should be visible before testing its full data source.")

        let tenthSong = staticText(containing: "Fixture Song Ten")
        for _ in 0..<5 where !tenthSong.exists {
            let dragStart = splitQueuePanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
            let dragEnd = splitQueuePanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        }

        XCTAssertTrue(tenthSong.waitForExistence(timeout: 2), "The first expanded queue state should scroll through the complete queue, not a four-row slice.")
        XCTAssertTrue(element("playerQueueSplitHeader").waitForExistence(timeout: 1), "Scrolling the split queue should not promote, collapse, or dismiss the drawer.")
        XCTAssertEqual(nowPlayingTitleLabel(), "Fixture Song One", "Scrolling the split queue should not start another track.")
    }

    @MainActor
    func testCenterBodyDragDoesNotDismissWhileSplitQueueIsOpen() throws {
        try openFullPlayerFromMini()
        try expandBottomContextToSplit()

        centerPlayerCoverArea().dragDownToDismiss()

        XCTAssertTrue(element("nowPlayingView").waitForExistence(timeout: 1), "The center dismiss gesture should not minimize the player while the split queue owns vertical gestures.")
        XCTAssertTrue(element("playerQueueSplitHeader").waitForExistence(timeout: 1), "The split queue should remain open after a center-body downward drag.")
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
        try expandBottomContextToFullQueue()

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should stay open before testing queue-list drag.")
        let queuePanel = element("playerBottomQueuePanel")
        XCTAssertTrue(queuePanel.waitForExistence(timeout: 2), "Bottom queue panel should be visible before testing list drag.")

        let dragStart = queuePanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        let dragEnd = queuePanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)

        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 1), "Dragging inside the queue list body should not minimize the full player.")
    }

    @MainActor
    func testBottomQueueListScrollsVertically() throws {
        try openFullPlayerFromMini()
        try expandBottomContextToFullQueue()

        let queuePanel = element("playerBottomQueuePanel")
        XCTAssertTrue(queuePanel.waitForExistence(timeout: 2), "Bottom queue panel should be visible before testing vertical scrolling.")

        let tenthSong = staticText(containing: "Fixture Song Ten")
        for _ in 0..<3 where !tenthSong.exists {
            let dragStart = queuePanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            let dragEnd = queuePanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24))
            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        }

        XCTAssertTrue(tenthSong.waitForExistence(timeout: 2), "Bottom queue should expose later rows in the expanded list.")
        XCTAssertTrue(element("nowPlayingView").waitForExistence(timeout: 1), "Vertical queue scrolling should not minimize the full player.")
        XCTAssertEqual(nowPlayingTitleLabel(), "Fixture Song One", "Vertical queue scrolling should not change the current track.")
    }

    @MainActor
    func testDraggingRecommendationListBodyDoesNotDismissFullPlayer() throws {
        try openFullPlayerFromMini()
        try expandBottomContextToFullQueue()
        selectBottomContextTab("recommendations")

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should stay open before testing recommendation-list drag.")
        let recommendationsPanel = element("playerBottomRecommendationsPanel")
        XCTAssertTrue(recommendationsPanel.waitForExistence(timeout: 5), "Bottom recommendations panel should be visible before testing list drag.")

        let dragStart = recommendationsPanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        let dragEnd = recommendationsPanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)

        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 1), "Dragging inside the recommendation list body should not minimize the full player.")
    }

    @MainActor
    func testBottomRecommendationListScrollsVerticallyWithoutChangingTrack() throws {
        try openFullPlayerFromMini()
        try expandBottomContextToFullQueue()
        selectBottomContextTab("recommendations")

        let recommendationsPanel = element("playerBottomRecommendationsPanel")
        XCTAssertTrue(recommendationsPanel.waitForExistence(timeout: 5), "Bottom recommendations panel should be visible before testing vertical scrolling.")

        let tenthSong = staticText(containing: "Fixture Song Ten")
        for _ in 0..<3 where !tenthSong.exists {
            let dragStart = recommendationsPanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            let dragEnd = recommendationsPanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24))
            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        }

        XCTAssertTrue(tenthSong.waitForExistence(timeout: 2), "Bottom recommendations should expose later rows in the expanded list.")
        XCTAssertTrue(element("nowPlayingView").waitForExistence(timeout: 1), "Vertical recommendation scrolling should not minimize the full player.")
        XCTAssertEqual(nowPlayingTitleLabel(), "Fixture Song One", "Vertical recommendation scrolling should not change the current track.")
    }

    @MainActor
    func testProgressScrubDoesNotDismissPlayer() throws {
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
        XCTAssertFalse(element("playerBottomQueuePanel").isHittable, "Scrubbing progress should not open the queue panel.")
        XCTAssertFalse(element("playerBottomRecommendationsPanel").isHittable, "Scrubbing progress should not open recommendations.")
    }

    @MainActor
    func testHorizontalLeftSwipeDoesNotChangeSinglePlayerPageOrDismiss() throws {
        try openFullPlayerFromMini()

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should be open before testing horizontal gesture ownership.")
        let titleBefore = nowPlayingTitleLabel()

        centerPlayerCoverArea().leftSwipe()

        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 1), "Horizontal swipe should not minimize the single-page player.")
        XCTAssertTrue(waitForSingleNowPlayingSurface(), "The player should remain on the single now-playing surface.")
        XCTAssertEqual(nowPlayingTitleLabel(), titleBefore, "Horizontal swipe should not change the current track.")
    }

    @MainActor
    func testHorizontalRightSwipeDoesNotChangeSinglePlayerPageOrDismiss() throws {
        try openFullPlayerFromMini()

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should be open before testing horizontal gesture ownership.")
        let titleBefore = nowPlayingTitleLabel()

        centerPlayerCoverArea().rightSwipe()

        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 1), "Horizontal swipe should not minimize the single-page player.")
        XCTAssertTrue(waitForSingleNowPlayingSurface(), "The player should remain on the single now-playing surface.")
        XCTAssertEqual(nowPlayingTitleLabel(), titleBefore, "Horizontal swipe should not change the current track.")
    }

    @MainActor
    func testHorizontalDragOnQueueRowDoesNotJumpTrack() throws {
        try openFullPlayerFromMini()
        XCTAssertEqual(nowPlayingTitleLabel(), "Fixture Song One")

        try expandBottomContextToFullQueue()

        let queuePanel = element("playerBottomQueuePanel")
        XCTAssertTrue(queuePanel.waitForExistence(timeout: 2), "Bottom queue should be visible before dragging a queue row.")
        let secondRowTitle = queuePanel.descendants(matching: .staticText)
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
            XCTAssertTrue(metadata.waitForExistence(timeout: 2), "The center metadata should remain visible after a horizontal row drag.")
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

    private func staticText(containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func assertDensePlayerLayout() throws {
        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should be open before dense layout verification.")

        let topChrome = element("playerTopChrome")
        let metadata = metadataElement()
        let progress = element("nowPlayingProgress")
        let transport = element("playerTransportControls")
        let toolbar = element("playerToolbar")
        let bottomContext = element("playerBottomContextCollapsed")

        let elements = [topChrome, metadata, progress, transport, toolbar, bottomContext]
        for element in elements {
            XCTAssertTrue(element.waitForExistence(timeout: 2), "Dense player layout element should exist: \(element)")
            XCTAssertFalse(element.frame.isEmpty, "Dense player layout element should have a measurable frame: \(element)")
        }

        let coverArea = centerPlayerCoverArea()
        XCTAssertGreaterThanOrEqual(coverArea.screenPoint.y, topChrome.frame.maxY + 36, "Cover area should stay below the top chrome.")
        XCTAssertLessThanOrEqual(coverArea.screenPoint.y, metadata.frame.minY - 24, "Cover area should stay above title metadata.")
        XCTAssertGreaterThanOrEqual(metadata.frame.minY - topChrome.frame.maxY, 178, "Dense player layout should preserve room for visible cover art.")
        assertVerticalOrder(metadata, progress, "Title metadata should stay above progress.")
        assertVerticalOrder(progress, transport, "Progress should stay above transport controls.")
        assertVerticalOrder(transport, toolbar, "Transport controls should stay above the player toolbar.")
        assertVerticalOrder(toolbar, bottomContext, "The bottom queue drawer should sit below the player toolbar.")

        let layoutElements = [metadata, progress, transport, toolbar]
        for firstIndex in 0..<layoutElements.count {
            for secondIndex in (firstIndex + 1)..<layoutElements.count {
                assertNoFrameOverlap(layoutElements[firstIndex], layoutElements[secondIndex])
            }
        }

        let maxToolbarToDrawerGap: CGFloat = app.frame.height <= 700 ? 60 : 84
        let toolbarToDrawerGap = bottomContext.frame.minY - toolbar.frame.maxY
        XCTAssertLessThanOrEqual(toolbarToDrawerGap, maxToolbarToDrawerGap, "Collapsed queue should sit under the toolbar instead of leaving a large empty lower half.")
        XCTAssertGreaterThanOrEqual(toolbarToDrawerGap, 12, "Collapsed queue should keep enough breathing room below the toolbar.")
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

    @MainActor
    private func expandBottomContextToSplit() throws {
        let collapsedDrawer = element("playerBottomContextCollapsed")
        XCTAssertTrue(collapsedDrawer.waitForExistence(timeout: 2), "Bottom queue context should start collapsed before expanding.")

        let start = collapsedDrawer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        let end = start.withOffset(CGVector(dx: 0, dy: -92))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(element("playerQueueSplitHeader").waitForExistence(timeout: 2), "First upward drag should reveal the split queue state.")
    }

    @MainActor
    private func expandBottomContextToFullQueue() throws {
        try expandBottomContextToSplit()

        let splitHeader = element("playerQueueSplitHeader")
        let splitStart = splitHeader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let splitEnd = splitStart.withOffset(CGVector(dx: 0, dy: -116))
        splitStart.press(forDuration: 0.05, thenDragTo: splitEnd)

        XCTAssertTrue(element("playerQueueFullHeader").waitForExistence(timeout: 2), "Second upward drag should reveal the full queue state.")
    }

    @MainActor
    private func selectBottomContextTab(_ rawValue: String) {
        let tab = element("playerBottomTab-\(rawValue)")
        XCTAssertTrue(tab.waitForExistence(timeout: 2), "Bottom context tab should exist: \(rawValue)")
        tab.tap()
    }

    @MainActor
    private func centerPlayerCoverArea() -> CoverArea {
        let nowPlaying = element("nowPlayingView")
        let artwork = element("nowPlayingArtwork")
        let topChrome = element("playerTopChrome")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 2), "Full player should exist before deriving the cover area.")
        if artwork.waitForExistence(timeout: 2), !artwork.frame.isEmpty {
            return CoverArea(app: app, screenPoint: CGPoint(x: artwork.frame.midX, y: artwork.frame.midY))
        }

        XCTAssertTrue(topChrome.waitForExistence(timeout: 2), "Top chrome should exist before deriving the cover area.")

        let top = max(topChrome.frame.maxY, nowPlaying.frame.minY + 96)
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
    private func waitForSingleNowPlayingSurface(timeout: TimeInterval = 2) -> Bool {
        let nowPlaying = element("nowPlayingView")
        guard nowPlaying.waitForExistence(timeout: timeout) else { return false }

        let topChrome = element("playerTopChrome")
        guard topChrome.waitForExistence(timeout: timeout) else { return false }

        return true
    }

}
