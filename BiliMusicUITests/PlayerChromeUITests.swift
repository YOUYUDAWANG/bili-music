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
        if name.contains("Lyrics") || name.contains("StageV5") {
            app.launchEnvironment["BILIMUSIC_UITEST_LYRICS"] = "1"
        }
        if name.contains("KaraokeSweep") {
            app.launchEnvironment["BILIMUSIC_UITEST_PLAYBACK_TIME"] = "0.175"
        }
        if name.contains("StagePrototype") {
            app.launchEnvironment["BILIMUSIC_LYRIC_STAGE_PROTOTYPE"] = "1"
        }
        if name.contains("StageV5") {
            app.launchEnvironment["BILIMUSIC_LYRIC_STAGE_V5"] = "1"
        }
        if name.contains("StageV51") {
            app.launchEnvironment["BILIMUSIC_UITEST_LYRICS"] = "1"
            app.launchEnvironment["BILIMUSIC_LYRIC_STAGE_V51"] = "1"
        }
        if name.contains("StageV52") {
            app.launchEnvironment["BILIMUSIC_UITEST_LYRICS"] = "1"
            app.launchEnvironment["BILIMUSIC_UITEST_YOU_AIZU"] = "1"
            app.launchEnvironment["BILIMUSIC_LYRIC_STAGE_V52"] = "1"
        }
        if name.contains("StageV53") {
            app.launchEnvironment["BILIMUSIC_UITEST_LYRICS"] = "1"
            app.launchEnvironment["BILIMUSIC_UITEST_YOU_AIZU"] = "1"
            app.launchEnvironment["BILIMUSIC_LYRIC_STAGE_V53"] = "1"
        }
        if name.contains("StageRecipeV4Performance") {
            app.launchEnvironment["BILIMUSIC_UITEST_LYRICS"] = "1"
            app.launchEnvironment["BILIMUSIC_UITEST_YOU_AIZU"] = "1"
            app.launchEnvironment["BILIMUSIC_LYRIC_STAGE_V53"] = "1"
            app.launchEnvironment["BILIMUSIC_UITEST_STAGE_V4_PERF"] = "1"
            app.launchEnvironment["BILIMUSIC_UITEST_PLAYING"] = "1"
            app.launchEnvironment["BILIMUSIC_UITEST_PLAYBACK_TIME"] = "60.9"
            app.launchEnvironment["BILIMUSIC_V53_PERF_SIGNPOSTS"] = "1"
            app.launchEnvironment["BILIMUSIC_UITEST_OPEN_FULL_PLAYER"] = "1"
        }
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
        XCTAssertTrue(element("playerUtilityBar").waitForExistence(timeout: 0.8), "Player actions should appear promptly after opening.")
    }

    @MainActor
    func testStagePrototypeRendersInsideArtworkPlayerCanvas() throws {
        try openFullPlayerFromMini()

        let prototype = element("lyricStagePrototype")
        XCTAssertTrue(prototype.waitForExistence(timeout: 3), "The local v5 motion study should replace only the inline lyric canvas.")
        XCTAssertTrue(element("nowPlayingArtwork").exists, "The prototype must preserve the existing artwork layout.")
        XCTAssertTrue(element("nowPlayingProgress").exists, "The prototype must not replace playback controls.")
        XCTAssertTrue(element("playerUtilityBar").exists, "The prototype must keep the Apple Music utility bar.")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Lyric Stage Prototype"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testStageV5RendersRealTimedLyricsInsideArtworkCanvas() throws {
        try openFullPlayerFromMini()

        let stage = element("lyricStageView")
        XCTAssertTrue(stage.waitForExistence(timeout: 3), "The v5 stage should compile the fixture's real timed lyrics locally.")
        XCTAssertTrue(element("nowPlayingArtwork").exists)
        XCTAssertTrue(element("nowPlayingProgress").exists)
        XCTAssertTrue(element("playerUtilityBar").exists)
        XCTAssertFalse(element("lyricStagePrototype").exists, "The real lyric stage and hard-coded study must be mutually exclusive.")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Lyric Stage V5 Real Lyrics"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testStageV51RendersEventCanvasInsideArtworkCanvas() throws {
        try openFullPlayerFromMini()

        let stage = element("lyricStageCanvasView")
        XCTAssertTrue(stage.waitForExistence(timeout: 3), "The V5.1 canvas should replace only the inline lyric canvas.")
        XCTAssertTrue(element("nowPlayingArtwork").exists)
        XCTAssertTrue(element("nowPlayingProgress").exists)
        XCTAssertTrue(element("playerUtilityBar").exists)
        XCTAssertFalse(element("lyricStagePrototype").exists)
        XCTAssertFalse(element("lyricStageView").exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Lyric Stage V5.1 Events"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testStageV52RendersYouAizuGoldenStudyInsideArtworkCanvas() throws {
        let samples: [(String, Double)] = [
            ("00-intro", 8.0),
            ("01-wake", 19.5),
            ("02-tuning", 31.8),
            ("01-step", 39.2),
            ("02-blink", 45.9),
            ("03-promise", 51.6),
            ("04-converge", 56.4),
            ("08-hook-final", 66.5),
            ("09-drive", 75.4),
            ("10-conduct", 84.9),
            ("11-sunday", 100.2),
            ("12-reprise", 126.7),
            ("13-final", 156.2),
            ("14-outro", 170.0),
        ]
        for sample in samples {
            app.terminate()
            app.launchEnvironment["BILIMUSIC_UITEST_PLAYBACK_TIME"] = String(sample.1)
            app.launch()
            try openFullPlayerFromMini()

            let stage = element("youAizuGoldenStage")
            XCTAssertTrue(stage.waitForExistence(timeout: 3))
            XCTAssertTrue(element("nowPlayingArtwork").exists)
            XCTAssertTrue(element("nowPlayingProgress").exists)
            XCTAssertTrue(element("playerUtilityBar").exists)
            XCTAssertFalse(element("lyricStageCanvasView").exists)
            XCTAssertFalse(element("lyricStagePrototype").exists)

            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "You and Aizu V5.2 \(sample.0)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testStageV53RendersGenericFullSongChoreographyAcrossYouAizu() throws {
        let samples: [(String, Double)] = [
            ("00-intro", 8.0),
            ("01-verse", 19.5),
            ("02-dialogue", 45.9),
            ("03-hook-call", 58.4),
            ("04-hook-echo", 61.0),
            ("05-hook-converge", 63.7),
            ("06-hook-lock", 66.3),
            ("07-middle", 100.2),
            ("08-reprise", 126.7),
            ("09-final", 156.2),
        ]
        for sample in samples {
            app.terminate()
            app.launchEnvironment["BILIMUSIC_UITEST_PLAYBACK_TIME"] = String(sample.1)
            app.launch()
            try openFullPlayerFromMini()

            let stage = element("lyricStageV53")
            XCTAssertTrue(stage.waitForExistence(timeout: 3))
            XCTAssertTrue(element("nowPlayingArtwork").exists)
            XCTAssertTrue(element("nowPlayingProgress").exists)
            XCTAssertTrue(element("playerUtilityBar").exists)
            XCTAssertFalse(element("youAizuGoldenStage").exists)
            XCTAssertFalse(element("lyricStageCanvasView").exists)

            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Generic V5.3 You and Aizu \(sample.0)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testStageRecipeV4PerformanceRecordsDoubleResidueHookBaseline() throws {
        let stage = element("lyricStageV53")
        XCTAssertTrue(stage.waitForExistence(timeout: 4))
        XCTAssertEqual(stage.value as? String, "v4:chorusMemory")
        XCTAssertTrue(element("nowPlayingView").exists)
        XCTAssertTrue(element("nowPlayingProgress").exists)
        Thread.sleep(forTimeInterval: 5.5)
        XCTAssertTrue(stage.exists)
    }

    @MainActor
    func testQueueButtonOpensDedicatedQueuePage() throws {
        try openFullPlayerFromMini()
        try openAppleMusicQueuePage()

        let queuePage = element("playerAppleMusicQueue")
        XCTAssertTrue(queuePage.waitForExistence(timeout: 2), "The current queue should use the dedicated queue page.")
        XCTAssertTrue(staticText(containing: "Fixture Song Two").waitForExistence(timeout: 2), "The queue page should expose the next queue item.")
        XCTAssertTrue(staticText(containing: "自动播放").waitForExistence(timeout: 2), "The queue page should keep AutoPlay recommendations in the same scroll surface.")
        XCTAssertFalse(element("playerBottomContextDrawer").exists, "The retired three-state drawer should not be part of the active player route.")
        XCTAssertTrue(element("nowPlayingView").waitForExistence(timeout: 1), "Opening the queue page should keep the player presented.")
    }

    @MainActor
    func testLyricsSheetShowsSyncedTranslationAndOffsetControls() throws {
        try openFullPlayerFromMini()

        let lyricsButton = app.buttons["歌词"]
        XCTAssertTrue(lyricsButton.waitForExistence(timeout: 3), "Loaded lyrics should expose the lyrics action.")
        lyricsButton.tap()

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 2), "Lyrics should stay inside the now-playing surface.")
        let lyricsPage = element("playerLyricsPage")
        XCTAssertTrue(lyricsPage.waitForExistence(timeout: 3), "Lyrics action should stay on the now-playing surface.")
        XCTAssertTrue(element("nowPlayingProgress").waitForNonExistence(timeout: 2), "Lyrics mode should not keep the playback progress control.")
        XCTAssertTrue(element("playerTransportControls").waitForNonExistence(timeout: 2), "Lyrics mode should not keep play/skip controls.")
        XCTAssertTrue(element("playerUtilityBar").waitForExistence(timeout: 2), "Lyrics mode should keep the bottom lyrics/queue switcher.")
        XCTAssertTrue(element("playerLyricsButton").isSelected, "The lyrics button should stay selected while lyrics are shown.")
        XCTAssertTrue(staticText(containing: "Electric night begins").waitForExistence(timeout: 2), "The page should render synchronized lyrics.")
        XCTAssertTrue(staticText(containing: "电光之夜开始").waitForExistence(timeout: 2), "The page should render the aligned translation.")

        let more = element("lyricsMoreMenu")
        XCTAssertTrue(more.waitForExistence(timeout: 2), "Lyrics controls should live in the more menu.")
        more.tap()
        let calibration = app.buttons["歌词校准"]
        XCTAssertTrue(calibration.waitForExistence(timeout: 2), "The more menu should expose lyrics calibration.")
        calibration.tap()
        XCTAssertTrue(element("lyricsOffsetSheet").waitForExistence(timeout: 2), "Calibration should open a sheet.")
        XCTAssertTrue(app.sliders["lyricsOffsetControl"].waitForExistence(timeout: 2), "Calibration should offer an offset slider.")
        XCTAssertTrue(app.buttons["重置"].waitForExistence(timeout: 2), "Calibration should offer a reset action.")
        XCTAssertTrue(app.buttons["lyricsAutoAlignButton"].waitForExistence(timeout: 2), "Calibration should offer auto-align.")
        XCTAssertTrue(app.staticTexts["已对齐"].waitForExistence(timeout: 2), "The slider should show the current offset.")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Lyrics page"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLyricsButtonTogglesNowPlayingPage() throws {
        try openFullPlayerFromMini()

        let lyricsButton = element("playerLyricsButton")
        XCTAssertTrue(lyricsButton.waitForExistence(timeout: 3), "The now-playing screen should expose a persistent lyrics switch.")
        lyricsButton.tap()

        let lyricsPage = element("playerLyricsPage")
        XCTAssertTrue(lyricsPage.waitForExistence(timeout: 3), "The first tap should open lyrics in place.")
        XCTAssertTrue(lyricsButton.isSelected, "The lyrics switch should stay on while the lyrics page is visible.")
        XCTAssertTrue(element("playerUtilityBar").exists, "The lyrics switcher should remain reachable on the lyrics page.")

        lyricsButton.tap()
        XCTAssertTrue(lyricsPage.waitForNonExistence(timeout: 2), "A second tap should turn lyrics off.")
        XCTAssertTrue(element("nowPlayingArtwork").waitForExistence(timeout: 2), "Turning lyrics off should restore the artwork page.")
        XCTAssertFalse(lyricsButton.isSelected, "The lyrics switch should clear its selected state after turning off.")
    }

    @MainActor
    func testLyricsKaraokeSweepUsesTheWordProgressRenderer() throws {
        try openFullPlayerFromMini()

        let lyricsButton = element("playerLyricsButton")
        XCTAssertTrue(lyricsButton.waitForExistence(timeout: 3))
        lyricsButton.tap()

        let karaokeLine = element("lyricsKaraokeWordLine")
        XCTAssertTrue(karaokeLine.waitForExistence(timeout: 3), "A word-timed line should use the progressive karaoke renderer.")
        XCTAssertTrue(karaokeLine.label.contains("Electric night begins"))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Lyrics karaoke sweep at half of first word"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testInlineLyricsPreviewOpensLyricsPage() throws {
        try openFullPlayerFromMini()

        let preview = element("nowPlayingLyricStageView")
        let previewExists = preview.waitForExistence(timeout: 3)
        let initialScreenshot = XCTAttachment(screenshot: app.screenshot())
        initialScreenshot.name = "Inline lyrics preview before assertion"
        initialScreenshot.lifetime = .keepAlways
        add(initialScreenshot)
        XCTAssertTrue(previewExists, "Synchronized lyrics should fill the flexible space on the artwork page.")
        XCTAssertTrue(
            preview.label.contains("Electric night begins while every signal crosses the skyline without losing a single word"),
            "The inline stage must expose the complete long lyric instead of an ellipsis."
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Inline lyrics preview"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        preview.tap()

        XCTAssertTrue(element("playerLyricsPage").waitForExistence(timeout: 3), "Tapping the inline preview should open the complete lyrics mode.")
        XCTAssertTrue(element("playerLyricsButton").isSelected, "Opening lyrics from the preview should select the persistent lyrics switch.")
    }

    @MainActor
    func testLunaLyricDirectorIsExposedAsAnExplicitDevelopmentAction() throws {
        try openFullPlayerFromMini()

        let moreMenu = element("playerMoreMenu")
        XCTAssertTrue(moreMenu.waitForExistence(timeout: 3), "The player should expose its more menu.")
        moreMenu.tap()

        let director = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Luna'")).firstMatch
        XCTAssertTrue(director.waitForExistence(timeout: 2), "Luna direction should be an explicit development action, not an automatic playback request.")
        XCTAssertTrue(element("nowPlayingView").exists, "Opening the director menu must not replace or dismiss the player.")
    }

    @MainActor
    func testLyricsPrecisionHostActionIsEnabledAndUnsafeOnDeviceActionIsHidden() throws {
        try openFullPlayerFromMini()

        let moreMenu = element("playerMoreMenu")
        XCTAssertTrue(moreMenu.waitForExistence(timeout: 3))
        moreMenu.tap()

        let hostAction = app.buttons.matching(NSPredicate(format: "label CONTAINS '高精度主机'")).firstMatch
        XCTAssertTrue(hostAction.waitForExistence(timeout: 2), "Line-synced lyrics should expose the precision host action.")
        XCTAssertTrue(hostAction.isEnabled, "A missing runtime host configuration must surface as a tap error, not a grey button.")
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label CONTAINS '本机生成'")).firstMatch.exists,
            "The MLX action must stay hidden after real-device Metal SIGABRT failures."
        )
    }

    @MainActor
    func testLyricsModeHidesPlaybackControls() throws {
        try openFullPlayerFromMini()

        let lyricsButton = element("playerLyricsButton")
        XCTAssertTrue(lyricsButton.waitForExistence(timeout: 3), "The lyrics switch should be available.")
        XCTAssertTrue(element("nowPlayingProgress").waitForExistence(timeout: 2), "Artwork mode should show playback progress.")
        lyricsButton.tap()

        XCTAssertTrue(element("playerLyricsPage").waitForExistence(timeout: 3), "Lyrics should stay inside the now-playing surface.")
        XCTAssertTrue(element("nowPlayingProgress").waitForNonExistence(timeout: 2), "Progress should be gone in lyrics mode, not delayed-hidden.")
        XCTAssertTrue(element("playerTransportControls").waitForNonExistence(timeout: 2), "Play/skip controls should be gone in lyrics mode.")
        XCTAssertTrue(element("playerUtilityBar").exists, "The lyrics/AirPlay/queue switcher should stay on the same surface.")
        XCTAssertTrue(lyricsButton.isSelected, "The lyrics switch should stay selected.")

        lyricsButton.tap()
        XCTAssertTrue(element("nowPlayingProgress").waitForExistence(timeout: 2), "Turning lyrics off should restore playback progress.")
        XCTAssertTrue(element("playerTransportControls").waitForExistence(timeout: 2), "Turning lyrics off should restore play/skip controls.")
    }

    @MainActor
    func testFullPlayerChromeStaysBelowStatusBar() throws {
        try openFullPlayerFromMini()

        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should be open for chrome layout verification.")

        let utilityBar = element("playerUtilityBar")
        XCTAssertTrue(utilityBar.waitForExistence(timeout: 2), "The player utility bar should be visible.")
        XCTAssertGreaterThan(utilityBar.frame.minY, 80, "The player chrome should stay below the status bar.")
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
    func testMiniPlayerAndTabBarFollowNativeScrollMinimization() throws {
        let homeList = element("homeList")
        let tabBar = app.tabBars.firstMatch
        let miniPlayer = element("miniPlayer")

        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5), "Fixture playback should expose the LNPopup mini player.")
        XCTAssertTrue(tabBar.waitForExistence(timeout: 2), "The native system tab bar should be visible before scrolling.")
        let expandedTabFrame = tabBar.frame
        let expandedMiniFrame = miniPlayer.frame

        homeList.swipeUp()

        XCTAssertTrue(
            waitForNativeBottomBarCompaction(
                tabBar: tabBar,
                miniPlayer: miniPlayer,
                expandedTabFrame: expandedTabFrame,
                expandedMiniFrame: expandedMiniFrame,
                timeout: 2
            ),
            "Scrolling should let iOS 27 compact the Tab Bar and move the LNPopup mini player into its native inline geometry."
        )
        XCTAssertTrue(miniPlayer.exists, "The mini player should remain available in the compact native bottom-bar state.")
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
    private func waitForNativeBottomBarCompaction(
        tabBar: XCUIElement,
        miniPlayer: XCUIElement,
        expandedTabFrame: CGRect,
        expandedMiniFrame: CGRect,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let compactTabFrame = tabBar.frame
            let compactMiniFrame = miniPlayer.frame
            if compactTabFrame.height < expandedTabFrame.height - 2 ||
                compactTabFrame.minY > expandedTabFrame.minY + 2 ||
                compactMiniFrame.minY > expandedMiniFrame.minY + 2 ||
                compactMiniFrame.width < expandedMiniFrame.width - 2 {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return false
    }

    @MainActor
    private func assertDensePlayerLayout() throws {
        let nowPlaying = element("nowPlayingView")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Full player should be open before dense layout verification.")

        let topChrome = element("playerTopChrome")
        let artwork = element("nowPlayingArtwork")
        let metadata = metadataElement()
        let progress = element("nowPlayingProgress")
        let transport = element("playerTransportControls")
        let utilityBar = element("playerUtilityBar")

        let elements = [topChrome, artwork, metadata, progress, transport, utilityBar]
        for element in elements {
            XCTAssertTrue(element.waitForExistence(timeout: 2), "Dense player layout element should exist: \(element)")
            XCTAssertFalse(element.frame.isEmpty, "Dense player layout element should have a measurable frame: \(element)")
        }

        let coverArea = centerPlayerCoverArea()
        let compactHeight = app.frame.height <= 700
        XCTAssertGreaterThanOrEqual(coverArea.screenPoint.y, topChrome.frame.maxY + 36, "Cover area should stay below the top chrome.")
        XCTAssertLessThanOrEqual(coverArea.screenPoint.y, metadata.frame.minY - 24, "Cover area should stay above title metadata.")
        XCTAssertGreaterThanOrEqual(artwork.frame.minY, app.frame.minY - 1, "Artwork should remain within the visible screen bounds.")
        let artworkMetadataGap = metadata.frame.minY - artwork.frame.maxY
        XCTAssertGreaterThanOrEqual(
            artworkMetadataGap,
            10,
            "Artwork and metadata should keep a visible fixed gap."
        )
        XCTAssertLessThanOrEqual(
            artworkMetadataGap,
            18,
            "Artwork and metadata should stay grouped instead of gaining elastic space."
        )
        assertVerticalOrder(metadata, progress, "Title metadata should stay above progress.")
        assertVerticalOrder(progress, transport, "Progress should stay above transport controls.")
        assertVerticalOrder(transport, utilityBar, "Transport controls should stay above the utility bar.")

        XCTAssertLessThanOrEqual(
            transport.frame.minY - progress.frame.maxY,
            compactHeight ? 22 : 28,
            "Progress and transport should remain one fixed-rhythm control cluster."
        )
        XCTAssertLessThanOrEqual(
            utilityBar.frame.minY - transport.frame.maxY,
            compactHeight ? 32 : 38,
            "Only a bounded secondary gap should separate transport from utility controls."
        )

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
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3), "Tapping a cover should open the shared LNPopup full player.")

        let miniPlayer = element("miniPlayer")
        XCTAssertFalse(element("coverPlayerCloseButton").exists, "Home should not create a second custom player or close target.")

        centerPlayerCoverArea().dragDownToDismiss()

        XCTAssertTrue(nowPlaying.waitForNonExistence(timeout: 3), "LNPopup should minimize back to its standard bar.")
        let homeList = element("homeList")
        XCTAssertTrue(homeList.waitForExistence(timeout: 1), "The cover wall should remain mounted under LNPopup.")
        XCTAssertTrue(homeList.isHittable, "The cover wall should be draggable after LNPopup minimizes.")
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 3), "The same LNPopup lifecycle should expose its mini player after minimizing.")
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
