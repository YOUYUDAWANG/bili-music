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

        let utilityBar = element("playerUtilityBar")
        XCTAssertTrue(utilityBar.waitForExistence(timeout: 2), "The Apple Music utility bar should be visible after opening.")

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
                miniPlayerExposesTitle("Fixture Song One", in: miniPlayer, timeout: 3),
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
                miniPlayerExposesTitle("Fixture Song One", in: miniPlayer, timeout: 3),
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
    func testQueueButtonOpensDedicatedQueuePage() throws {
        try openFullPlayerFromMini()
        try openAppleMusicQueuePage()

        let queuePage = element("playerAppleMusicQueue")
        XCTAssertTrue(queuePage.waitForExistence(timeout: 2), "The current queue should use the dedicated queue page.")
        XCTAssertTrue(staticText(containing: "Fixture Song Two").waitForExistence(timeout: 2), "The queue page should expose the next queue item.")
        XCTAssertTrue(staticText(containing: "AutoPlay").waitForExistence(timeout: 2), "The queue page should keep AutoPlay recommendations in the same scroll surface.")
        XCTAssertFalse(element("playerBottomContextDrawer").exists, "The retired three-state drawer should not be part of the active player route.")
        XCTAssertTrue(element("nowPlayingView").waitForExistence(timeout: 1), "Opening the queue page should keep the player presented.")
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
        try openAppleMusicQueuePage()

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should stay open before testing queue-list drag.")
        let queuePanel = element("playerAppleMusicQueue")
        XCTAssertTrue(queuePanel.waitForExistence(timeout: 2), "The active queue page should be visible before testing list drag.")

        let dragStart = queuePanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        let dragEnd = queuePanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)

        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 1), "Dragging inside the queue list body should not minimize the full player.")
    }

    @MainActor
    func testBottomQueueListScrollsVertically() throws {
        try openFullPlayerFromMini()
        try openAppleMusicQueuePage()

        let queuePanel = element("playerAppleMusicQueue")
        XCTAssertTrue(queuePanel.waitForExistence(timeout: 2), "The active queue page should be visible before testing vertical scrolling.")

        let tenthSong = element("playerTrackRow-BVUITEST010#1010")
        for _ in 0..<3 where !tenthSong.exists {
            let dragStart = queuePanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            let dragEnd = queuePanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24))
            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        }

        XCTAssertTrue(tenthSong.waitForExistence(timeout: 2), "The queue page should expose later rows after vertical scrolling.")
        XCTAssertTrue(element("nowPlayingView").waitForExistence(timeout: 1), "Vertical queue scrolling should not minimize the full player.")
        XCTAssertEqual(nowPlayingTitleLabel(), "Fixture Song One", "Vertical queue scrolling should not change the current track.")
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
        XCTAssertFalse(element("playerAppleMusicQueue").isHittable, "Scrubbing progress should not open the queue page.")
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

        try openAppleMusicQueuePage()

        let queuePanel = element("playerAppleMusicQueue")
        XCTAssertTrue(queuePanel.waitForExistence(timeout: 2), "The queue page should be visible before dragging a queue row.")
        let secondRowTitle = element("playerTrackRow-BVUITEST002#1002")
        XCTAssertTrue(secondRowTitle.waitForExistence(timeout: 2), "Queue should expose the second fixture row before dragging.")

        let start = secondRowTitle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
        let end = secondRowTitle.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        start.press(forDuration: 0.08, thenDragTo: end)

        let queueButton = element("playerQueueButton")
        XCTAssertTrue(queueButton.waitForExistence(timeout: 2), "The queue page should keep its close control available.")
        queueButton.tap()
        XCTAssertEqual(nowPlayingTitleLabel(), "Fixture Song One", "A horizontal row drag should not be treated as tapping the second queue item.")
    }

    @MainActor
    func testQueueRowTapStillChangesTrack() throws {
        try openFullPlayerFromMini()
        try openAppleMusicQueuePage()

        let queuePanel = element("playerAppleMusicQueue")
        let secondRow = element("playerTrackRow-BVUITEST002#1002")
        XCTAssertTrue(secondRow.waitForExistence(timeout: 2), "The queue page should expose the second fixture row before tapping.")
        secondRow.tap()

        let queueButton = element("playerQueueButton")
        XCTAssertTrue(queueButton.waitForExistence(timeout: 2), "The queue page should keep its close control available after a row tap.")
        queueButton.tap()
        XCTAssertEqual(nowPlayingTitleLabel(), "Fixture Song Two", "A deliberate queue-row tap should still change the current track.")
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
    func testTappingCoverKeepsMusicLibraryStable() throws {
        try assertFixtureHomeRowStableWhileStartingPlayback()
    }

    @MainActor
    func testMiniPlayerKeepsTabBarVisibleWhileHomeScrolls() throws {
        let homeList = element("homeList")
        let musicTab = app.tabBars.buttons["音乐"]
        let favoritesTab = app.tabBars.buttons["收藏夹"]
        let searchTab = app.tabBars.buttons["搜索"]

        XCTAssertTrue(element("miniPlayer").waitForExistence(timeout: 5), "Fixture playback should expose the mini player.")
        for tab in [musicTab, favoritesTab, searchTab] {
            XCTAssertTrue(tab.waitForExistence(timeout: 2), "The system tab bar should be visible before scrolling.")
        }

        homeList.swipeUp()

        for tab in [musicTab, favoritesTab, searchTab] {
            XCTAssertTrue(tab.waitForExistence(timeout: 1), "The system tab bar should remain visible while a mini player exists.")
            XCTAssertTrue(tab.isHittable, "The system tab bar should remain interactive after scrolling the cover wall.")
        }
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
        let utilityBar = element("playerUtilityBar")

        let elements = [topChrome, metadata, progress, transport, utilityBar]
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
        assertVerticalOrder(transport, utilityBar, "Transport controls should stay above the utility bar.")

        let layoutElements = [metadata, progress, transport, utilityBar]
        for firstIndex in 0..<layoutElements.count {
            for secondIndex in (firstIndex + 1)..<layoutElements.count {
                assertNoFrameOverlap(layoutElements[firstIndex], layoutElements[secondIndex])
            }
        }

        let utilityBarBottomGap = app.frame.maxY - utilityBar.frame.maxY
        let maximumBottomGap: CGFloat = app.frame.height <= 700 ? 40 : 72
        XCTAssertGreaterThanOrEqual(utilityBarBottomGap, 8, "The utility bar should remain clear of the screen bottom edge.")
        XCTAssertLessThanOrEqual(utilityBarBottomGap, maximumBottomGap, "The utility bar should finish the portrait layout without excessive bottom void.")
    }

    private func assertVerticalOrder(_ upper: XCUIElement, _ lower: XCUIElement, _ message: String) {
        XCTAssertLessThanOrEqual(upper.frame.maxY, lower.frame.minY + 1, message)
    }

    private func assertNoFrameOverlap(_ first: XCUIElement, _ second: XCUIElement) {
        XCTAssertFalse(first.frame.intersects(second.frame), "Dense player key elements should not overlap: \(first) and \(second)")
    }

    @MainActor
    private func miniPlayerExposesTitle(
        _ title: String,
        in miniPlayer: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let titlePredicate = NSPredicate(format: "label CONTAINS %@", title)
        let descendantText = miniPlayer.descendants(matching: .staticText)
            .matching(titlePredicate)
            .firstMatch
        let descendantButton = miniPlayer.descendants(matching: .button)
            .matching(titlePredicate)
            .firstMatch
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if descendantText.exists || descendantButton.exists || miniPlayer.label.contains(title) {
                return true
            }
            if String(describing: miniPlayer.value).contains(title) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return false
    }

    @MainActor
    private func assertFixtureHomeRowStableWhileStartingPlayback(rowIdentifier: String = "homeTrackRow0") throws {
        let firstRow = app.buttons[rowIdentifier]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "Fixture cover should be visible.")
        let frameBefore = firstRow.frame

        firstRow.tap()

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Tapping a cover should open the full player from that cover.")

        let miniPlayer = element("miniPlayer")
        XCTAssertFalse(miniPlayer.exists, "The popup bar should stay hidden during the direct cover-to-player presentation.")

        let closeButton = element("coverPlayerCloseButton")
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2), "The direct cover player should expose a stable close target.")
        closeButton.tap()

        XCTAssertTrue(nowPlaying.waitForNonExistence(timeout: 3), "Closing should return to the cover wall.")
        let homeList = element("homeList")
        XCTAssertTrue(homeList.waitForExistence(timeout: 1), "Closing should immediately return gesture ownership to the cover wall.")
        XCTAssertTrue(homeList.isHittable, "The cover wall should be draggable as soon as the direct player closes.")
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 3), "The standard mini player should resume after the cover transition finishes.")
        XCTAssertTrue(firstRow.waitForExistence(timeout: 2), "The cover library should reappear after closing the player.")
        XCTAssertEqual(firstRow.frame.minY, frameBefore.minY, accuracy: 12, "The cover library should not jump after tapping a song.")
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
    private func openAppleMusicQueuePage() throws {
        let queueButton = element("playerQueueButton")
        XCTAssertTrue(queueButton.waitForExistence(timeout: 3), "The full player should expose its queue button.")
        queueButton.tap()
        XCTAssertTrue(element("playerAppleMusicQueue").waitForExistence(timeout: 3), "Tapping the queue button should reveal the active queue page.")
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
