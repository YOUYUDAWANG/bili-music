# Phase 03: Player Interaction and Regression Coverage - Pattern Map

**Mapped:** 2026-06-27
**Files analyzed:** 13
**Analogs found:** 13 / 13
**Project skills:** no local `.codex/skills/` or `.agents/skills/` directories found

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `BiliMusic/Features/RootView.swift` | component/shell | event-driven | `BiliMusic/Features/RootView.swift` | exact |
| `BiliMusic/Features/Player/NowPlayingView.swift` | component/screen | event-driven | `BiliMusic/Features/Player/NowPlayingView.swift` | exact |
| `BiliMusic/Features/Player/PlayerControlViews.swift` | component/control | event-driven | `BiliMusic/Features/Player/PlayerControlViews.swift` | exact |
| `BiliMusic/Features/Player/PlayerGesturePolicy.swift` | utility | transform | `BiliMusic/Features/Player/PlayerGesturePolicy.swift` | exact |
| `BiliMusic/Features/Player/PlayerLayoutPolicy.swift` (optional if extracted) | utility | transform | `BiliMusic/Features/Player/PlayerGesturePolicy.swift` | role-match |
| `BiliMusic/Features/Player/PlayerSheetViews.swift` | component/sheet | request-response | `BiliMusic/Features/Player/PlayerSheetViews.swift` | reuse |
| `BiliMusicUITests/PlayerChromeUITests.swift` | test | event-driven | `BiliMusicUITests/PlayerChromeUITests.swift` | exact |
| `BiliMusicTests/PlayerGesturePolicyTests.swift` | test | transform | `BiliMusicTests/PlayerGesturePolicyTests.swift` | exact |
| `BiliMusicTests/PlayerLayoutPolicyTests.swift` (optional if helper added) | test | transform | `BiliMusicTests/PlayerGesturePolicyTests.swift` | role-match |
| `BiliMusicTests/RecommendationSchedulingTests.swift` | test | event-driven/transform | `BiliMusicTests/RecommendationSchedulingTests.swift` | exact |
| `BiliMusicTests/PlaybackCriticalPathTests.swift` | test | async request-response | `BiliMusicTests/PlaybackCriticalPathTests.swift` | exact |
| `BiliMusicTests/ImageCacheTests.swift` | test | file-I/O/cache | `BiliMusicTests/ImageCacheTests.swift` | exact |
| `BiliMusicTests/SearchModelsTests.swift` | test | CRUD/transform | `BiliMusicTests/SearchModelsTests.swift` | guardrail |

## Pattern Assignments

### `BiliMusic/Features/RootView.swift` (component/shell, event-driven)

**Analog:** `BiliMusic/Features/RootView.swift`

Use this file for mini-player upward drag, full-player overlay offset/opacity/scale, matched cover transition, and reduced-motion open/close animation. Do not move playback startup logic into this layer.

**State and motion pattern** (lines 9-20, 119-133):
```swift
@State private var showFullPlayer = false
@State private var fullPlayerOpenProgress: CGFloat = 0
@State private var miniOpenDragTranslation: CGFloat?
@State private var isTrackingMiniOpenDrag = false
@Namespace private var playerTransition

private enum Motion {
    static let open = Animation.smooth(duration: 0.52, extraBounce: 0.055)
    static let close = Animation.smooth(duration: 0.38, extraBounce: 0.015)
    static let cancel = Animation.smooth(duration: 0.24, extraBounce: 0)
}

private var openAnimation: Animation {
    reduceMotion ? .easeOut(duration: 0.12) : Motion.open
}
```

**Full-player progress pattern** (lines 163-203):
```swift
private func fullPlayerOffset(height: CGFloat, safeAreaInsets: EdgeInsets) -> CGFloat {
    guard showFullPlayer || isMiniOpening || fullPlayerOpenProgress > 0 else {
        return height
    }
    let offscreenOffset = height + safeAreaInsets.bottom + 24
    return offscreenOffset * (1 - renderedPlayerOpenProgress)
}

private var renderedPlayerOpenProgress: CGFloat {
    PlayerGesturePolicy.renderedMiniOpenProgress(
        rawProgress: playerOpenProgress,
        isMiniOpening: isMiniOpening,
        isFullPlayerPresented: showFullPlayer)
}

private var fullPlayerOpacity: Double {
    let progress = Double(renderedPlayerOpenProgress)
    guard !reduceMotion else { return progress }
    return min(1, 0.72 + progress * 0.28)
}
```

**Open/cancel/close pattern** (lines 205-243):
```swift
private func openFullPlayer(startProgress explicitStartProgress: CGFloat? = nil) {
    let startProgress = max(explicitStartProgress ?? playerOpenProgress, 0.04)
    var transaction = Transaction()
    transaction.animation = nil
    withTransaction(transaction) {
        showFullPlayer = true
        miniOpenDragTranslation = nil
        isTrackingMiniOpenDrag = false
        fullPlayerOpenProgress = min(1, startProgress)
    }

    withAnimation(openAnimation) {
        fullPlayerOpenProgress = 1
    }
}

private func closeFullPlayer() {
    withAnimation(closeAnimation) {
        miniOpenDragTranslation = nil
        isTrackingMiniOpenDrag = false
        fullPlayerOpenProgress = 0
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + closeRemovalDelay) {
        guard fullPlayerOpenProgress <= 0.01 else { return }
        showFullPlayer = false
    }
}
```

**Mini drag event pattern** (lines 267-304):
```swift
private func handleMiniOpenDragChanged(_ sample: MiniOpenDragSample) {
    guard engine.current != nil, !showFullPlayer else {
        isTrackingMiniOpenDrag = false
        return
    }

    if !isTrackingMiniOpenDrag {
        guard shouldBeginMiniOpenDrag(sample) else { return }
        isTrackingMiniOpenDrag = true
    }

    miniOpenDragTranslation = sample.translation.height
    if PlayerGesturePolicy.shouldOpenMiniPlayerLive(
        translationY: sample.translation.height,
        velocityY: sample.velocity.height
    ) {
        isTrackingMiniOpenDrag = false
        miniOpenDragTranslation = nil
        openFullPlayer(startProgress: PlayerGesturePolicy.initialMiniOpenProgress(
            for: sample.translation.height))
        return
    }
}
```

**Mini-player direct manipulation pattern** (lines 350-415, 492-513):
```swift
let accessoryProgress = isFullPlayerPresented || miniOpenDragTranslation != nil
    ? transitionProgress(openProgress)
    : 0

HStack(spacing: lerp(7, 9, layoutProgress)) {
    // title, artwork, and controls
}
.highPriorityGesture(miniOpenDragGesture, including: .all)
.opacity(Double(max(0, 1 - max(0, (accessoryProgress - 0.14) / 0.86))))
.scaleEffect(1 - accessoryProgress * 0.03, anchor: .bottom)
.accessibilityIdentifier("miniPlayer")

private var miniOpenDragGesture: some Gesture {
    DragGesture(minimumDistance: 8, coordinateSpace: .local)
        .onChanged { value in
            onOpenDragChanged(miniOpenDragSample(from: value))
        }
        .onEnded { value in
            onOpenDragEnded(miniOpenDragSample(from: value))
        }
}
```

### `BiliMusic/Features/Player/NowPlayingView.swift` (component/screen, event-driven)

**Analog:** `BiliMusic/Features/Player/NowPlayingView.swift`

Use this file for the full-screen three-page player, center Now Playing layout, queue/recommendation lists, toolbar actions, progress-scrub/page-swipe conflict handling, and full-player dismiss regions.

**Imports and state pattern** (lines 1-12, 31-85):
```swift
import AVKit
import SwiftUI

struct NowPlayingView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onDismiss: (() -> Void)? = nil
    var namespace: Namespace.ID
    var safeAreaTop: CGFloat = 0
    private enum PlayerPage: Int {
        case queue = 0
        case nowPlaying = 1
        case recommendations = 2
    }

    @State private var selectedPage = PlayerPage.nowPlaying.rawValue
    @State private var recommendedTracks: [Track] = []
    @State private var recommendationsLoading = false
    @State private var recommendationsError: String?
    @State private var suppressNextRecommendationRefresh = false
    @State private var recommendationsStale = false
    @State private var showLyrics = false
    @State private var showMVFullscreen = false
    @State private var switchingMode = false
    @GestureState private var dismissDragOffset: CGFloat = 0
    @State private var suppressPageSwipeForScrub = false
}
```

**Three-page pattern** (lines 222-258):
```swift
private func playerPages(coverSize: CGFloat, width: CGFloat, safeAreaTop: CGFloat) -> some View {
    TabView(selection: $selectedPage) {
        horizontalListPage {
            queueList
        }
        .tag(PlayerPage.queue.rawValue)

        ScrollView(showsIndicators: false) {
            nowPlayingPage(coverSize: coverSize)
                .padding(.top, Layout.contentTopInset)
        }
        .tag(PlayerPage.nowPlaying.rawValue)

        horizontalListPage {
            recommendationsList
        }
        .tag(PlayerPage.recommendations.rawValue)
    }
    .tabViewStyle(.page(indexDisplayMode: .never))
    .indexViewStyle(.page(backgroundDisplayMode: .never))
    .scrollDisabled(suppressPageSwipeForScrub)
    .simultaneousGesture(pageSwipeGesture(width: width), including: .gesture)
    .safeAreaInset(edge: .top, spacing: 0) {
        playerTopModeSwitcher(safeAreaTop: safeAreaTop)
    }
}
```

**Center layout pattern to reshape** (lines 178-220):
```swift
private func nowPlayingPage(coverSize: CGFloat) -> some View {
    VStack(spacing: 15) {
        mediaView(coverSize: coverSize)
            .padding(.top, 6)

        VStack(spacing: 5) {
            Text(engine.current?.title ?? "")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(engine.current?.artist ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        progressView
        transportControls
        actionRow

        bottomContextPanel
        Spacer(minLength: 0)
    }
    .padding(.bottom, 12)
}
```

Phase 3 should preserve the data wiring above but replace `bottomContextPanel` on the center page with the approved Apple Music-like toolbar/page model.

**Cover/image pattern** (lines 312-330):
```swift
let coverURL = thumbnailURL(engine.current?.coverURL, width: 960, height: 540)
if let coverURL {
    CachedAsyncImage(
        url: coverURL,
        targetSize: CGSize(width: coverSize, height: coverSize * 9 / 16)
    ) { image in
        image.resizable().aspectRatio(contentMode: .fill)
    } placeholder: {
        artworkPlaceholder(cornerRadius: AppTheme.playerCoverRadius)
    }
}
.matchedGeometryEffect(id: "playerCover", in: namespace)
.frame(width: coverSize, height: coverSize * 9 / 16)
.clipShape(RoundedRectangle(cornerRadius: AppTheme.playerCoverRadius))
```

**Toolbar action wiring pattern** (lines 396-536):
```swift
private var actionRow: some View {
    HStack(spacing: 12) {
        favoriteButton
        downloadIconButton
        if !engine.lyrics.isEmpty {
            lyricsButton
        }
        queueModeMenu
        moreMenu
    }
}

private var favoriteButton: some View {
    ActionSymbolButton(
        title: favorites.isFavorite(track) ? "已收藏" : "收藏",
        systemName: favorites.isFavorite(track) ? "heart.fill" : "heart"
    ) {
        guard !favorites.busyBVIDs.contains(track.bvid) else { return }
        Task { await favorites.toggle(track: track) }
    }
}

private var lyricsButton: some View {
    ActionSymbolButton(title: "歌词", systemName: "quote.bubble") {
        showLyrics = true
    }
}

private var downloadIconButton: some View {
    let downloads = DownloadManager.shared
    if CacheStore.shared.entry(for: track) != nil {
        ActionSymbolButton(title: "已缓存", systemName: "arrow.down.circle.fill") {}
            .foregroundStyle(AppTheme.success)
    } else {
        ActionSymbolButton(title: "缓存", systemName: "arrow.down.circle") {
            Task { await downloads.download(track: track) }
        }
    }
}
```

Use the same manager/engine calls. Change presentation to five persistent toolbar actions: lyrics, favorite, cache/download, audio quality, MV switch. Lyrics unavailable should remain aligned and disabled instead of disappearing.

**Queue/recommendation list pattern** (lines 573-643):
```swift
private func horizontalListPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 12) {
            content()
                .padding(.horizontal, 20)
            Spacer(minLength: 32)
        }
        .padding(.top, Layout.contentTopInset)
        .padding(.bottom, 28)
    }
}

private var queueList: some View {
    ForEach(Array(engine.queue.enumerated()), id: \.element.id) { index, track in
        Button {
            Task { await engine.jump(to: index) }
        } label: {
            TrackRow(track: track, isPlaying: index == engine.queueIndex)
        }
        .buttonStyle(.plain)
    }
}

private var recommendationsList: some View {
    ForEach(Array(recommendedTracks.prefix(12).enumerated()), id: \.element.id) { index, track in
        Button {
            suppressNextRecommendationRefresh = true
            Task { await engine.play(tracks: recommendedTracks, startAt: index, queueMode: .radio) }
        } label: {
            TrackRow(track: track, isPlaying: engine.current.map { track.key.matches($0) } ?? false)
        }
        .buttonStyle(.plain)
    }
}
```

**Dismiss/page/scrub conflict pattern** (lines 1004-1100):
```swift
private var dismissDrag: some Gesture {
    DragGesture(minimumDistance: 18, coordinateSpace: .global)
        .updating($dismissDragOffset) { value, state, _ in
            guard let offset = PlayerGesturePolicy.dismissDragOffset(
                translation: value.translation,
                startY: value.startLocation.y,
                dismissGrabZoneHeight: Layout.dismissGrabZoneHeight
            ) else { return }
            state = offset
        }
        .onEnded { value in
            if PlayerGesturePolicy.shouldDismissFullPlayer(
                translation: value.translation,
                predictedEndTranslation: value.predictedEndTranslation,
                startY: value.startLocation.y,
                dismissGrabZoneHeight: Layout.dismissGrabZoneHeight
            ) {
                closePlayer()
            }
        }
}

private func pageSwipeGesture(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 12, coordinateSpace: .local)
        .onEnded { value in
            guard !suppressPageSwipeForScrub else { return }
            let horizontalThreshold = max(28, width * 0.07)
            guard abs(horizontalIntent) > horizontalThreshold,
                  abs(horizontalIntent) > abs(verticalIntent) * 0.82 else { return }
        }
}

private func setProgressScrubbing(_ scrubbing: Bool) {
    progressScrubGeneration += 1
    isProgressScrubbing = scrubbing
    suppressPageSwipeForScrub = true
}
```

### `BiliMusic/Features/Player/PlayerControlViews.swift` (component/control, event-driven)

**Analog:** `BiliMusic/Features/Player/PlayerControlViews.swift`

Use this file for reusable control primitives and the progress scrubber. Add toolbar button variants here only if they are reusable player controls; otherwise keep feature-specific composition in `NowPlayingView`.

**Button import/hit-target pattern** (lines 1-37):
```swift
import SwiftUI

struct PlayerIconButton: View {
    let systemName: String
    let size: CGFloat
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 56, height: 56)
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ActionSymbolButton: View {
    let title: String
    let systemName: String
    let action: () -> Void
}
```

**Progress scrub pattern** (lines 57-148):
```swift
struct PlayerProgressBar: View {
    @Environment(PlayerEngine.self) private var engine
    var onScrubChanged: (Bool) -> Void = { _ in }
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var trackWidth: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.quaternary)
                .frame(height: 3)
            Circle()
                .fill(AppTheme.label)
                .frame(width: 12, height: 12)
        }
        .frame(height: 44)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isScrubbing {
                        scrubValue = min(engine.currentTime, engine.duration)
                        isScrubbing = true
                        engine.beginScrub()
                        onScrubChanged(true)
                    }
                    let progress = max(0, min(1, value.location.x / max(trackWidth, 1)))
                    scrubValue = progress * engine.duration
                }
                .onEnded { _ in
                    engine.endScrub(to: scrubValue)
                    isScrubbing = false
                    onScrubChanged(false)
                },
            including: .all
        )
    }
}
```

### `BiliMusic/Features/Player/PlayerGesturePolicy.swift` (utility, transform)

**Analog:** `BiliMusic/Features/Player/PlayerGesturePolicy.swift`

Put deterministic drag thresholds, axis checks, region checks, and velocity projections here. Keep SwiftUI `@State`, `GestureState`, and animation in views.

**Imports/constants pattern** (lines 1-15):
```swift
import CoreGraphics

enum PlayerGesturePolicy {
    static let miniOpeningDragRange: CGFloat = 190
    static let miniOpeningActivationProgress: CGFloat = 0.10
    static let miniLiveOpeningActivationProgress: CGFloat = 0.07
    static let miniPredictedOpeningMinimumProgress: CGFloat = 0.10
    static let miniOpeningPredictedActivationProgress: CGFloat = 0.38
    static let velocityProjectionTime: CGFloat = 0.22
    static let dismissGrabZoneHeight: CGFloat = 150
    static let dismissTranslationThreshold: CGFloat = 130
    static let dismissPredictedThreshold: CGFloat = 260
}
```

**Mini-open policy pattern** (lines 16-57):
```swift
static func miniOpenProgress(for translationY: CGFloat) -> CGFloat {
    clamp(-translationY / miniOpeningDragRange)
}

static func shouldBeginMiniOpenDrag(translation: CGSize) -> Bool {
    let isVertical = abs(translation.height) > abs(translation.width) * 1.2
    return translation.height < -18 && isVertical
}

static func shouldFinishMiniOpenDrag(translationY: CGFloat, velocityY: CGFloat) -> Bool {
    let progress = miniOpenProgress(for: translationY)
    let predictedProgress = miniOpenProgress(for: predictedTranslationY(
        translationY: translationY,
        velocityY: velocityY))

    return progress > miniOpeningActivationProgress ||
        (progress > miniPredictedOpeningMinimumProgress &&
         predictedProgress > miniOpeningPredictedActivationProgress)
}
```

**Dismiss policy pattern** (lines 63-122):
```swift
static func dismissDragOffset(
    translation: CGSize,
    startY: CGFloat,
    dismissGrabZoneHeight: CGFloat = Self.dismissGrabZoneHeight
) -> CGFloat? {
    guard shouldTrackDismissDrag(
        translation: translation,
        startY: startY,
        dismissGrabZoneHeight: dismissGrabZoneHeight
    ) else { return nil }
    return min(340, max(0, translation.height))
}

static func shouldDismissFullPlayer(
    translation: CGSize,
    predictedEndTranslation: CGSize,
    startY: CGFloat,
    dismissGrabZoneHeight: CGFloat = Self.dismissGrabZoneHeight
) -> Bool {
    guard shouldTrackDismissDrag(
        translation: translation,
        startY: startY,
        dismissGrabZoneHeight: dismissGrabZoneHeight
    ) else { return false }
    return translation.height > dismissTranslationThreshold ||
        predictedEndTranslation.height > dismissPredictedThreshold
}

private static func shouldTrackTopChromeDismissDrag(translation: CGSize) -> Bool {
    let isDownward = translation.height > 0
    let isVertical = abs(translation.height) > abs(translation.width) * 1.08
    return isDownward && isVertical
}
```

### `BiliMusic/Features/Player/PlayerLayoutPolicy.swift` (optional utility, transform)

**Analog:** `BiliMusic/Features/Player/PlayerGesturePolicy.swift`

Only add this file if layout-density calculations or drag-region decisions become hard to test inside `NowPlayingView`. Copy the stateless enum style from `PlayerGesturePolicy`: `import CoreGraphics`, `enum PlayerLayoutPolicy`, static constants/functions, no SwiftUI state, no `PlayerEngine`.

**Pattern to copy** (lines 1-18):
```swift
import CoreGraphics

enum PlayerGesturePolicy {
    static let miniOpeningDragRange: CGFloat = 190
    static let miniOpeningActivationProgress: CGFloat = 0.10

    static func miniOpenProgress(for translationY: CGFloat) -> CGFloat {
        clamp(-translationY / miniOpeningDragRange)
    }
}
```

### `BiliMusic/Features/Player/PlayerSheetViews.swift` (component/sheet, request-response)

**Analog:** `BiliMusic/Features/Player/PlayerSheetViews.swift`

Use existing sheet components for lyrics and MV. Do not duplicate sheet state in toolbar controls.

**Imports and lyrics sheet pattern** (lines 1-52):
```swift
import AVKit
import SwiftUI

struct LyricsSheetView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let active = currentLyricIndex
        return NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(engine.lyrics.enumerated()), id: \.element.id) { index, line in
                            Text(line.text)
                                .font(index == active ? .title3.weight(.semibold) : .title3.weight(.regular))
                                .foregroundStyle(index == active ? AppTheme.label : .secondary)
                        }
                    }
                }
                .navigationTitle("歌词")
                .toolbar {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
```

**MV fullscreen pattern** (lines 56-85):
```swift
struct MVFullscreenView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player = engine.avPlayer {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .frame(width: 42, height: 42)
            }
        }
        .task {
            await engine.upgradeMVForFullscreen()
        }
    }
}
```

### `BiliMusicUITests/PlayerChromeUITests.swift` (test, event-driven)

**Analog:** `BiliMusicUITests/PlayerChromeUITests.swift`

Add visible gesture regressions here: mini-player pull-up, center-page downward minimize, queue/recommendation scroll non-dismissal, progress scrub/page swipe conflict, dense layout identifiers. Use fixtures and accessibility identifiers first; use coordinates only for drag behavior.

**Fixture launch pattern** (lines 1-12):
```swift
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
}
```

**Gesture UI test pattern** (lines 18-35, 121-129):
```swift
@MainActor
func testMiniPlayerSlowDragOpensRespectsSafeAreaAndClosesFromTopChrome() throws {
    try openFullPlayerFromMini()

    let nowPlaying = element("nowPlayingView")
    XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3))

    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.11))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
    start.press(forDuration: 0.05, thenDragTo: end)

    let miniPlayer = element("miniPlayer")
    XCTAssertTrue(miniPlayer.waitForExistence(timeout: 3))
    XCTAssertTrue(nowPlaying.waitForNonExistence(timeout: 3))
}

@MainActor
private func openFullPlayerFromMini() throws {
    let miniPlayer = element("miniPlayer")
    XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5))

    let openStart = miniPlayer.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.5))
    let openEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.42))
    openStart.press(forDuration: 0.35, thenDragTo: openEnd)
}
```

**Recommendation stability UI pattern** (lines 107-119):
```swift
@MainActor
private func assertFixtureHomeRowStableWhileStartingPlayback(rowIdentifier: String = "homeTrackRow0") throws {
    let firstRow = app.buttons[rowIdentifier]
    XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
    let frameBefore = firstRow.frame

    firstRow.tap()

    let miniPlayer = element("miniPlayer")
    XCTAssertTrue(miniPlayer.waitForExistence(timeout: 3))
    XCTAssertTrue(firstRow.waitForExistence(timeout: 2))
    XCTAssertEqual(firstRow.frame.minY, frameBefore.minY, accuracy: 12)
}
```

### `BiliMusicTests/PlayerGesturePolicyTests.swift` (test, transform)

**Analog:** `BiliMusicTests/PlayerGesturePolicyTests.swift`

Extend this file for pure gesture policy changes. Add a new layout policy test file only if an optional `PlayerLayoutPolicy` is created.

**Imports/class pattern** (lines 1-5):
```swift
import CoreGraphics
import XCTest
@testable import BiliMusic

final class PlayerGesturePolicyTests: XCTestCase {
```

**Mini-open assertions pattern** (lines 6-37):
```swift
func testMiniPlayerOpenProgressTracksUpwardDragMonotonically() {
    let small = PlayerGesturePolicy.miniOpenProgress(for: -24)
    let medium = PlayerGesturePolicy.miniOpenProgress(for: -72)
    let full = PlayerGesturePolicy.miniOpenProgress(for: -260)

    XCTAssertGreaterThan(small, 0)
    XCTAssertLessThan(small, medium)
    XCTAssertLessThan(medium, full)
    XCTAssertEqual(full, 1)
}

func testMiniPlayerOpenRequiresIntentionalVerticalUpwardDrag() {
    XCTAssertFalse(PlayerGesturePolicy.shouldBeginMiniOpenDrag(
        translation: CGSize(width: 0, height: -16)))
    XCTAssertFalse(PlayerGesturePolicy.shouldBeginMiniOpenDrag(
        translation: CGSize(width: 30, height: -24)))

    XCTAssertTrue(PlayerGesturePolicy.shouldBeginMiniOpenDrag(
        translation: CGSize(width: 8, height: -24)))
}
```

**Dismiss assertions pattern** (lines 39-80):
```swift
func testFullPlayerDismissIgnoresListAreaAndHorizontalDrags() {
    XCTAssertFalse(PlayerGesturePolicy.shouldDismissFullPlayer(
        translation: CGSize(width: 0, height: 180),
        predictedEndTranslation: CGSize(width: 0, height: 220),
        startY: 260))

    XCTAssertFalse(PlayerGesturePolicy.shouldDismissFullPlayer(
        translation: CGSize(width: 220, height: 150),
        predictedEndTranslation: CGSize(width: 260, height: 180),
        startY: 80))
}

func testTopChromeDismissUsesLowerThresholdThanContentDrag() {
    XCTAssertTrue(PlayerGesturePolicy.shouldDismissFromTopChrome(
        translation: CGSize(width: 0, height: 95),
        predictedEndTranslation: CGSize(width: 0, height: 120)))
}
```

### `BiliMusicTests/PlayerLayoutPolicyTests.swift` (optional test, transform)

**Analog:** `BiliMusicTests/PlayerGesturePolicyTests.swift`

If a pure layout helper is added, copy the same test style: `CoreGraphics`, `XCTest`, `@testable import BiliMusic`, inline `CGSize`/numeric fixtures, direct assertions, no SwiftUI rendering.

### `BiliMusicTests/RecommendationSchedulingTests.swift` (test, event-driven/transform)

**Analog:** `BiliMusicTests/RecommendationSchedulingTests.swift`

Keep recommendation-panel stability covered when changing the recommendations page or tap behavior.

**Policy test pattern** (lines 32-57):
```swift
func testRecommendationTapMarksPanelStaleWithoutImmediateRefresh() {
    let policy = RecommendationPanelRefreshPolicy.currentTrackChanged(
        suppressImmediateRefresh: true,
        recommendationPanelVisible: true)

    XCTAssertFalse(policy.shouldLoadImmediately)
    XCTAssertTrue(policy.shouldMarkStale)
}

func testVisibleExternalTrackChangeLoadsRecommendationsImmediately() {
    let policy = RecommendationPanelRefreshPolicy.currentTrackChanged(
        suppressImmediateRefresh: false,
        recommendationPanelVisible: true)

    XCTAssertTrue(policy.shouldLoadImmediately)
    XCTAssertFalse(policy.shouldMarkStale)
}
```

**Source-separation guard pattern** (lines 83-98):
```swift
func testHomeAndNowPlayingRecommendationStateStaySeparate() throws {
    let home = try Self.sourceFile("BiliMusic/Features/Home/HomeView.swift")
    let nowPlaying = try Self.sourceFile("BiliMusic/Features/Player/NowPlayingView.swift")

    XCTAssertTrue(home.contains("@State private var tracks: [Track] = []"))
    XCTAssertTrue(nowPlaying.contains("@State private var recommendedTracks: [Track] = []"))
    XCTAssertTrue(nowPlaying.contains("RecommendationPanelRefreshPolicy.currentTrackChanged"))
    XCTAssertFalse(home.contains("recommendedTracks"))
}
```

### `BiliMusicTests/PlaybackCriticalPathTests.swift` (test, async request-response)

**Analog:** `BiliMusicTests/PlaybackCriticalPathTests.swift`

Use this as a guardrail when UI actions or recommendations call playback. Phase 3 should not add awaited enrichment before the playback request.

**Async test harness pattern** (lines 1-30):
```swift
import XCTest
@testable import BiliMusic

@MainActor
final class PlaybackCriticalPathTests: XCTestCase {
    func testPlayAssignsCurrentBeforeAwaitedSourceResolutionCompletes() async {
        let track = Self.track()
        let resolver = CriticalPathAudioResolver(
            prepared: Self.stream(
                url: URL(string: "https://example.invalid/prepared.m4a")!,
                cid: 1001,
                duration: 211,
                quality: 30280,
                bandwidth: 192_000))
        var currentDuringResolution: Track?
        resolver.onPrepare = { (engine: PlayerEngine) in
            currentDuringResolution = engine.current
        }
        let engine = PlayerEngine(
            streamResolver: resolver,
            startupTestHooks: .init(
                startPlaybackOverride: { _, _, _ in },
                reportFirstPlayingImmediately: false))

        await engine.play(tracks: [track], startAt: 0)

        XCTAssertEqual(currentDuringResolution?.bvid, track.bvid)
        XCTAssertEqual(engine.current?.bvid, track.bvid)
    }
}
```

**Event ordering pattern** (lines 41-58):
```swift
var events: [PlayerEngine.PlaybackStartupTestEvent] = []
let engine = PlayerEngine(
    streamResolver: resolver,
    startupTestHooks: .init(
        record: { events.append($0) },
        startPlaybackOverride: { _, _, _ in },
        reportFirstPlayingImmediately: false))

await engine.play(tracks: [track], startAt: 0)

XCTAssertEqual(events, [
    .currentAssigned,
    .sourceResolutionStarted,
    .sourceResolved(.freshRemote),
    .playerItemCreated(.freshRemote),
    .playRequested(.freshRemote)
])
```

### `BiliMusicTests/ImageCacheTests.swift` (test, file-I/O/cache)

**Analog:** `BiliMusicTests/ImageCacheTests.swift`

Keep image memory and target-size regressions covered if cover art sizing changes.

**Setup/cleanup pattern** (lines 1-19):
```swift
import UIKit
import XCTest
@testable import BiliMusic

final class ImageCacheTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            ImageMemoryCache.shared.removeAll()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            ImageMemoryCache.shared.removeAll()
        }
        CountingImageURLProtocol.reset()
        try await super.tearDown()
    }
}
```

**Target-size/cache cleanup pattern** (lines 44-72, 106-134):
```swift
@MainActor
func testImageCacheSeparatesSameURLByTargetPixelSize() {
    let url = URL(string: "https://example.com/shared-cover.jpg")!
    let smallTarget = CGSize(width: 64, height: 36)
    let largeTarget = CGSize(width: 320, height: 180)

    ImageMemoryCache.shared.insert(smallImage, for: url, targetPixelSize: smallTarget)
    ImageMemoryCache.shared.insert(largeImage, for: url, targetPixelSize: largeTarget)

    XCTAssertEqual(ImageMemoryCache.shared.image(for: url, targetPixelSize: smallTarget)?.pixelSize, smallTarget)
    XCTAssertEqual(ImageMemoryCache.shared.image(for: url, targetPixelSize: largeTarget)?.pixelSize, largeTarget)
}

@MainActor
func testBackgroundCleanupReleasesImagesWithoutClearingPlaybackState() async {
    ImageMemoryCache.shared.insert(image, for: url, targetPixelSize: image.pixelSize)

    await AppResourceCleanup.handleBackgrounding(engine: engine)

    XCTAssertNil(ImageMemoryCache.shared.image(for: url, targetPixelSize: image.pixelSize))
    XCTAssertEqual(engine.current?.bvid, tracks[1].bvid)
    XCTAssertEqual(engine.queue.map(\.bvid), tracks.map(\.bvid))
}
```

### `BiliMusicTests/SearchModelsTests.swift` (test, CRUD/transform)

**Analog:** `BiliMusicTests/SearchModelsTests.swift`

This is a preserved guardrail, not a primary Phase 3 edit target. Reuse its style if player UI changes affect search chrome or stable fixture playback.

**Inline model fixture pattern** (lines 18-45):
```swift
func testSectionsPromoteFirstResultAndSplitMV() {
    let best = Track(typeID: 3, bvid: "BV1", title: "晴天", artist: "周杰伦",
                     coverURL: nil, duration: 269)
    let song = Track(typeID: 3, bvid: "BV2", title: "七里香", artist: "周杰伦",
                     coverURL: nil, duration: 295)
    let mv = Track(typeID: 193, bvid: "BV3", title: "稻香 MV", artist: "周杰伦",
                   coverURL: nil, duration: 260)

    let sections = SearchResultSections.make(from: [best, song, mv])

    XCTAssertEqual(sections.bestMatch?.bvid, "BV1")
    XCTAssertEqual(sections.songs.map(\.bvid), ["BV2"])
    XCTAssertEqual(sections.mvs.map(\.bvid), ["BV3"])
}
```

**Async stale-result pattern** (lines 88-108):
```swift
@MainActor
func testStaleSearchResultsCannotReplaceActiveQuery() async throws {
    let oldTrack = makeTrack(bvid: "BVOLD", title: "旧歌 Live")
    let newTrack = makeTrack(bvid: "BVNEW", title: "新歌 Live")
    let store = SearchStore(searchPageForTesting: { keyword, _, _ in
        if keyword == "旧歌" {
            try? await Task.sleep(nanoseconds: 150_000_000)
            return [oldTrack]
        }
        return [newTrack]
    })

    store.submitSearch("旧歌") { _ in }
    try await Task.sleep(nanoseconds: 20_000_000)
    store.submitSearch("新歌") { _ in }
    try await Task.sleep(nanoseconds: 250_000_000)

    XCTAssertEqual(store.resultsQuery, "新歌")
    XCTAssertEqual(store.results.map { $0.bvid }, ["BVNEW"])
    XCTAssertFalse(store.searching)
}
```

## Shared Patterns

### No Auth Guard

**Source:** player UI files
**Apply to:** all Phase 3 player UI files

There is no authentication middleware or controller guard pattern in this native SwiftUI surface. The relevant guard pattern is local precondition gating:

```swift
guard engine.current != nil, !showFullPlayer else { return }
guard !suppressPageSwipeForScrub else { return }
guard mode == .music || engine.videoAvailable else { return }
```

### Theme And Color

**Source:** `BiliMusic/Design/AppTheme.swift` lines 1-39
**Apply to:** `NowPlayingView`, `PlayerControlViews`, optional player toolbar components

```swift
import SwiftUI

enum AppTheme {
    static let accent = Color(uiColor: .systemRed)
    static let background = Color(uiColor: .systemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let secondaryBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let separator = Color(uiColor: .separator)
    static let label = Color(uiColor: .label)
    static let secondaryLabel = Color(uiColor: .secondaryLabel)
    static let error = Color.red
    static let success = Color.green
    static let playerCoverRadius: CGFloat = 14
    static let playerGradient = LinearGradient(
        colors: [
            Color(uiColor: .secondarySystemBackground),
            Color(uiColor: .systemBackground),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}
```

### Image Target Sizing

**Source:** `BiliMusic/Design/CachedAsyncImage.swift` lines 49-62, 182-227
**Apply to:** full-player cover art, mini-player artwork, image regression tests

```swift
static func targetPixelSize(for displaySize: CGSize?, scale: CGFloat) -> CGSize? {
    guard let displaySize,
          displaySize.width.isFinite,
          displaySize.height.isFinite,
          displaySize.width > 0,
          displaySize.height > 0,
          scale.isFinite,
          scale > 0 else {
        return nil
    }
    return CGSize(
        width: ceil(displaySize.width * scale),
        height: ceil(displaySize.height * scale))
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var targetSize: CGSize?

    @MainActor
    private func load() async {
        let scale = max(displayScale, 1)
        let targetPixelSize = ImageMemoryCache.targetPixelSize(for: targetSize, scale: scale)
        if let cached = ImageMemoryCache.shared.image(for: url, targetPixelSize: targetPixelSize) {
            image = cached
            return
        }
        guard let decoded = await ImageLoadCoordinator.shared.image(
            for: url,
            targetPixelSize: targetPixelSize,
            headers: headers,
            scale: scale), !Task.isCancelled else {
            return
        }
        ImageMemoryCache.shared.insert(decoded, for: url, targetPixelSize: targetPixelSize)
        image = decoded
    }
}
```

### UI Test Fixtures

**Source:** `BiliMusic/Support/UITestFixtures.swift` lines 3-19
**Apply to:** `PlayerChromeUITests`

```swift
enum UITestFixtures {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["BILIMUSIC_UITEST_FIXTURE"] == "1"
    }

    static let homeTracks: [Track] = [
        Track(typeID: 3, bvid: "BVUITEST001", cid: 1001, title: "Fixture Song One", artist: "UI Test", coverURL: nil, duration: 211),
        Track(typeID: 3, bvid: "BVUITEST002", cid: 1002, title: "Fixture Song Two", artist: "UI Test", coverURL: nil, duration: 197),
        Track(typeID: 193, bvid: "BVUITEST003", cid: 1003, title: "Fixture MV Three", artist: "UI Test", coverURL: nil, duration: 243)
    ]
}
```

### SwiftUI Motion

**Source:** `RootView.swift` lines 119-133; `NowPlayingView.swift` lines 1102-1111
**Apply to:** mini-player expansion, full-player minimization, page hints, toolbar state

```swift
private var dismissDragAnimation: Animation {
    reduceMotion ? .easeOut(duration: 0.12) : .interactiveSpring(response: 0.26, dampingFraction: 0.9)
}

private func animate(_ animation: Animation, _ updates: @escaping () -> Void) {
    if reduceMotion {
        updates()
    } else {
        withAnimation(animation, updates)
    }
}
```

### XcodeGen Gate

**Source:** `.planning/codebase/CONVENTIONS.md` and `.planning/codebase/TESTING.md`
**Apply to:** any optional new Swift file

If `PlayerLayoutPolicy.swift` or `PlayerLayoutPolicyTests.swift` is created, regenerate the project before build/test:

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -target BiliMusicTests -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO
```

## No Analog Found

No Phase 3 file lacks an analog. Optional layout policy helpers should copy the `PlayerGesturePolicy` stateless enum and `PlayerGesturePolicyTests` direct assertion style.

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| none | - | - | Existing player UI, gesture policy, image cache, and test harnesses cover the required patterns. |

## Metadata

**Analog search scope:** `BiliMusic/Features/RootView.swift`, `BiliMusic/Features/Player/*.swift`, `BiliMusic/Design/*.swift`, `BiliMusic/Support/*.swift`, `BiliMusicTests/*.swift`, `BiliMusicUITests/*.swift`
**Files scanned:** 14 source/test files plus required phase and codebase planning docs
**Pattern extraction date:** 2026-06-27
**Source discovery:** CodeGraph first; targeted `rg`/shell reads only after CodeGraph when locating one non-indexed computed property range and non-overlapping line snippets
