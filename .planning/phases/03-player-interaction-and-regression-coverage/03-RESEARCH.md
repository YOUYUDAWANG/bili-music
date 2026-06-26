# Phase 3: Player Interaction and Regression Coverage - Research

**Researched:** 2026-06-27
**Domain:** Native SwiftUI iOS player interaction, gesture conflict management, and XCTest/XCUITest regression coverage
**Confidence:** MEDIUM

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

## Implementation Decisions

### Apple Music Player Direction

- **D-01:** The full-screen main player should prioritize an Apple Music-like Now Playing screen rather than keeping the current temporary/status-like structure. The center page is the primary playback experience.
- **D-02:** The center page should emphasize a large cover image, title/UP owner metadata, progress, large playback controls, and a small set of unified tool icons. It should not stack multiple card-like panels below the controls.
- **D-03:** Use a high-similarity but conservative Apple Music recreation. Recreate the important feel, not pixel-level parity: mini-player pull-up, cover/player transition, background gradient, down-to-mini-player close, and horizontal pages. Avoid complex blur or physics that could hurt responsiveness.

### Main Player Toolbar

- **D-04:** The main player should use an Apple Music-style bottom toolbar for secondary actions instead of separate bulky action cards.
- **D-05:** The bottom toolbar's persistent actions are lyrics, favorite, cache/download, audio quality, and MV switch.
- **D-06:** Lyrics should behave like Apple Music: if lyrics are available, the lyrics control can be active/openable; if lyrics are unavailable, the control remains visually aligned but clearly disabled or inactive rather than leaving layout holes.
- **D-07:** MV switching should preserve the previously preferred YouTube Music-style music/MV toggle behavior, but visually fit into the Apple Music-like player.
- **D-08:** Playback mode can be placed near playback controls or in a secondary menu; it should not displace the five persistent toolbar actions unless implementation finds a clearer Apple Music-like placement.

### Mini-Player Expansion

- **D-09:** Mini-player upward drag should feel like pulling the full player up from the bottom. Full-player offset, opacity, and scale should track drag progress directly.
- **D-10:** Mini-player should fade/scale down as the full player emerges. Releasing the drag completes or cancels based on distance and velocity.
- **D-11:** Opening animation should use SwiftUI state-driven transitions and respect `accessibilityReduceMotion`. Reduced Motion should keep the transition clear but less animated.

### Full-Player Minimization

- **D-12:** On the center Now Playing page, users can minimize by dragging downward from blank/cover/player body areas.
- **D-13:** On queue and recommendation list pages, downward minimization is active only from the top chrome/grabber/title area. List scrolling must never trigger minimize.
- **D-14:** Minimize threshold should be deliberate enough to avoid accidental closes but not require dragging from the very top. Existing gesture threshold tests should be extended rather than discarded.

### Queue, Now Playing, and Recommendation Pages

- **D-15:** Full player uses a three-page horizontal model: left page is current queue, center page is Now Playing, right page is current-song recommendations.
- **D-16:** The center Now Playing page is the default when opening the player.
- **D-17:** Page hints should be lightweight: small page dots or a thin indicator plus fading page title when on queue/recommendation pages. Avoid the current heavy segmented-control feel.
- **D-18:** Queue and recommendation pages should keep stable empty/loading/error states and must preserve Phase 2's recommendation-list stability: tapping a recommendation plays it without immediately scrambling the visible list.

### Performance and Regression Standard

- **D-19:** Player interaction polish must not regress the project core value: first sound and stable playback outrank visual fidelity.
- **D-20:** Animations should move only the key surfaces needed to communicate hierarchy. Avoid animating every control or adding expensive background effects.
- **D-21:** Phase 3 is complete only when focused checks cover mini-player expansion, full-player minimization, scroll/list gesture non-interference, progress scrubbing/page-swipe conflict handling, denser layout, and previously added search/recommendation/image guardrails.

### the agent's Discretion

The agent may choose exact SwiftUI animation curves, layout constants, page indicator shape, and internal view extraction boundaries as long as the decisions above hold. Prefer small pure gesture/layout policy helpers and existing test seams over broad rewrites of `PlayerEngine`.

### Deferred Ideas (OUT OF SCOPE)

## Deferred Ideas

- Favorite-folder long-press selection, collection queue context, typed auth errors, cache index repair, and broad API/cache hardening remain v2 unless a narrow UI hook is already available.
- Pixel-level Apple Music reproduction is explicitly not required in Phase 3.
</user_constraints>

## Summary

Phase 3 should be planned as a native SwiftUI interaction and regression-hardening pass, not as a playback engine, API, auth, or cache rewrite. The codebase already has the main seams: `RootView` owns mini-player to full-player presentation state; `SystemMiniPlayer` owns the mini-player drag gesture; `PlayerGesturePolicy` owns deterministic thresholds; `NowPlayingView` already has the three-page queue / now playing / recommendations model; `PlayerProgressBar` already suppresses page swipes during scrubbing; and existing XCTest/XCUITest files cover prior playback, search, recommendation, gesture, and image-memory guardrails. [VERIFIED: CodeGraph]

The planning focus should be: reshape `NowPlayingView` to match the approved UI-SPEC, move bulky bottom context content into the left/right pages, keep a compact center Now Playing page, preserve the existing `PlayerEngine` action surface, and expand pure policy/UI fixture tests around gesture conflicts and layout density. SwiftUI official docs support the current primitives: `DragGesture` reports drag sequences; `highPriorityGesture` can give local controls precedence; `simultaneousGesture` can observe without replacing existing gestures; and `TabViewStyle.page` is the standard paged horizontal container. [CITED: developer.apple.com/documentation/swiftui/draggesture] [CITED: developer.apple.com/documentation/swiftui/view/highprioritygesture%28_%3Aincluding%3A%29] [CITED: developer.apple.com/documentation/swiftui/view/simultaneousgesture%28_%3Aname%3Aisenabled%3A%29] [CITED: developer.apple.com/documentation/swiftui/tabviewstyle/page]

**Primary recommendation:** Plan one player-UI implementation slice plus one regression-coverage slice; do not merge visual polish with `PlayerEngine` startup behavior except where existing UI actions need to call existing engine methods. [VERIFIED: 03-CONTEXT.md] [VERIFIED: CodeGraph]

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PLYR-01 | Mini-player upward drag visually tracks finger and pulls full player from bottom. | `RootView.fullPlayerOffset`, `renderedPlayerOpenProgress`, and `SystemMiniPlayer.miniOpenDragGesture` are the implementation seam; `PlayerGesturePolicy` has mini-open progress/finish thresholds. [VERIFIED: CodeGraph] |
| PLYR-02 | Full player minimizes with deliberate downward gesture outside scrollable lists. | Current global `dismissDrag` starts only in a grab zone; Phase 3 needs center-page allowed-region expansion plus list-page top-chrome restriction. [VERIFIED: CodeGraph] |
| PLYR-03 | Queue/recommendation list scrolling does not trigger minimize. | `horizontalListPage` contains queue/recommendation `ScrollView`s; top chrome already has a separate high-priority dismiss gesture. [VERIFIED: CodeGraph] |
| PLYR-04 | Progress scrub and page swipe do not fight minimize gesture. | `PlayerProgressBar` uses a high-priority drag and calls `setProgressScrubbing`; `NowPlayingView` disables page swiping while scrubbing. [VERIFIED: CodeGraph] |
| PLYR-05 | Full player layout uses denser Apple Music-like spacing without bottom void. | UI-SPEC defines the dense center-page order, spacing, toolbar, and responsive cover range. [VERIFIED: 03-UI-SPEC.md] |
| TEST-01 | Search store tests cover identity, pagination, stale rejection, and music filtering. | `SearchModelsTests` already covers cache/mode/results, stale queries, pagination failure preservation, page filtering, and bounded empty-page skip. [VERIFIED: CodeGraph] |
| TEST-02 | Playback test/instrumentation verifies post-start enrichment is not awaited before playback request. | `PlaybackCriticalPathTests` already asserts current assignment before source await, one fresh resolution, play request event order, and post-sound scheduling boundaries. [VERIFIED: CodeGraph] |
| TEST-03 | Recommendation tests/UI tests verify first playback and related taps keep lists stable. | `RecommendationSchedulingTests` covers recommendation policies; `PlayerChromeUITests` covers Home-row stability when starting playback. [VERIFIED: CodeGraph] |
| TEST-05 | Image/cache behavior has at least one regression check for bounded image work or memory cleanup. | `ImageCacheTests` covers target-size cache separation, downsampling, in-flight coalescing, `releaseReloadableImages`, background cleanup, and memory-warning cleanup. [VERIFIED: CodeGraph] |
</phase_requirements>

## Project Constraints (from AGENTS.md)

- Read `.planning/PROJECT.md`, `.planning/STATE.md`, `.planning/ROADMAP.md`, and `.planning/REQUIREMENTS.md` before planning substantial work. [VERIFIED: AGENTS.md]
- Current stabilization priority is first sound and stable playback; playback startup outranks lyrics, recommendations, MV, artwork, cache work, and UI polish. [VERIFIED: AGENTS.md]
- `.codegraph/` is present; use CodeGraph before grep/find/raw source reads when locating or understanding source code. [VERIFIED: AGENTS.md]
- GSD planning docs live in `.planning/`; preserve requirements traceability when scope changes. [VERIFIED: AGENTS.md]
- Keep v1 focused on stabilization and do not pull v2 API/auth/cache rewrites into Phase 3 unless a narrow change is required for v1 stability. [VERIFIED: AGENTS.md]
- Do not revert uncommitted user or prior-agent source changes; stage only relevant files if a later phase commits. [VERIFIED: AGENTS.md]
- Keep planning-doc commits separate from source-code commits when commits are requested. [VERIFIED: AGENTS.md]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Mini-player pull-up transition | iOS Client / SwiftUI shell (`RootView`) | Gesture policy helper | The overlay progress, opacity, scale, and offset already live in `RootView`; thresholds belong in `PlayerGesturePolicy` for tests. [VERIFIED: CodeGraph] |
| Full-player minimization | iOS Client / SwiftUI player (`NowPlayingView`) | Gesture policy helper | Region ownership depends on page and gesture location; threshold math should remain deterministic. [VERIFIED: CodeGraph] |
| Queue and recommendation pages | iOS Client / SwiftUI player (`NowPlayingView`) | Player domain for queue/play actions | The pages are presentation surfaces; queue jumps and recommendation taps should call existing `PlayerEngine` methods. [VERIFIED: CodeGraph] |
| Progress scrubbing | Player control UI (`PlayerProgressBar`) | Player domain (`PlayerEngine.beginScrub/endScrub`) | The control owns touch handling; `PlayerEngine` owns playback time mutation. [VERIFIED: CodeGraph] |
| Layout density and toolbar | Player feature UI | Existing sheets/managers | UI-SPEC requires toolbar actions to reuse lyrics/favorite/cache/quality/MV behavior rather than duplicate state. [VERIFIED: 03-UI-SPEC.md] |
| Regression coverage | Unit and UI test targets | Debug UI fixture support | Pure logic belongs in `BiliMusicTests`; observable gesture flows belong in `BiliMusicUITests` with `BILIMUSIC_UITEST_FIXTURE`. [VERIFIED: .planning/codebase/TESTING.md] |
| Image-memory regression | Design/cache support | App cleanup hook | Image cache and cleanup already live in `CachedAsyncImage.swift` and `AppResourceCleanup`. [VERIFIED: CodeGraph] |

## Standard Stack

### Core

| Library / Framework | Version | Purpose | Why Standard |
|---------------------|---------|---------|--------------|
| SwiftUI | Apple SDK in Xcode 26.3; project Swift version 5.10 | Full player layout, gestures, `TabView` pages, animation, safe areas | Existing app is SwiftUI, and Apple docs provide standard `DragGesture`, gesture composition, and paged `TabView` APIs. [VERIFIED: local `xcodebuild -version`] [VERIFIED: .planning/codebase/STACK.md] [CITED: developer.apple.com/documentation/swiftui/draggesture] |
| XCTest / XCUITest | Bundled with Xcode 26.3 | Unit tests, UI tests, coordinate drag tests, wait assertions | Existing tests use XCTest/XCUITest; official UI automation APIs support stable identifiers, waiting, and drag gestures. [VERIFIED: local `xcodebuild -version`] [VERIFIED: .planning/codebase/TESTING.md] [CITED: developer.apple.com/documentation/xctest/xcuielement/waitforexistence(timeout:)] |
| AVFoundation / AVKit / MediaPlayer | Apple SDK in Xcode 26.3 | Existing playback engine and MV display | Phase 3 must reuse `PlayerEngine` and not replace playback infrastructure. [VERIFIED: .planning/codebase/STACK.md] [VERIFIED: CodeGraph] |
| Observation | Apple SDK in Xcode 26.3 | Existing `@Observable` app-wide and feature stores | `PlayerEngine`, stores, and shared managers already follow the app's Observation pattern. [VERIFIED: .planning/codebase/STACK.md] |

### Supporting

| Library / Tool | Version | Purpose | When to Use |
|----------------|---------|---------|-------------|
| XcodeGen | 2.45.4 | Regenerate `BiliMusic.xcodeproj` after adding Swift files | Use only if Phase 3 adds or moves Swift files. [VERIFIED: local `xcodegen --version`] [VERIFIED: .planning/codebase/CONVENTIONS.md] |
| CodeGraph | 1.0.1 | Source seam discovery and line references | Use before source exploration or blast-radius checks. [VERIFIED: local `codegraph --version`] [VERIFIED: AGENTS.md] |
| Python 3 | 3.12.7 | Existing optional API verification scripts | Not required for Phase 3 UI tests unless a planner includes manual API script checks. [VERIFIED: local `python3 --version`] [VERIFIED: .planning/codebase/TESTING.md] |
| App-local `PlayerGesturePolicy` | repo current | Pure gesture threshold rules | Extend for new page/region/scrub conflict decisions. [VERIFIED: CodeGraph] |
| App-local `CachedAsyncImage` / `ImageMemoryCache` | repo current | Target-size cover loading and memory cleanup | Reuse for full-player cover art and TEST-05 regression checks. [VERIFIED: CodeGraph] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftUI `TabView` page style | Custom pager | Custom paging increases gesture conflict risk and is unnecessary because the existing player already uses `TabView` pages. [VERIFIED: CodeGraph] [CITED: developer.apple.com/documentation/swiftui/tabviewstyle/page] |
| State-driven `DragGesture` + policy helpers | Custom physics engine | UI-SPEC explicitly rejects complex physics that could hurt responsiveness. [VERIFIED: 03-UI-SPEC.md] |
| Existing XCTest/XCUITest | Third-party test framework | The project has no third-party dependency manifests and already uses XCTest/XCUITest. [VERIFIED: .planning/codebase/STACK.md] [VERIFIED: .planning/codebase/TESTING.md] |
| Existing `PlayerEngine` calls | Playback engine rewrite | Phase boundary forbids broad player/API/cache rewrites for visual polish. [VERIFIED: 03-CONTEXT.md] |

**Installation:**

```bash
# No external package install is recommended for Phase 3.
# If new Swift files are added:
xcodegen generate
```

**Version verification:** Xcode 26.3, XcodeGen 2.45.4, Python 3.12.7, CodeGraph 1.0.1, and an available iOS 26.3 iPhone simulator were verified locally. [VERIFIED: local command]

## Package Legitimacy Audit

No external SwiftPM, CocoaPods, Carthage, npm, PyPI, or crates packages are recommended for this phase. The package legitimacy gate is not applicable unless the plan introduces a new dependency, which this research recommends against. [VERIFIED: .planning/codebase/STACK.md]

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| none | — | — | — | — | OK | No install needed |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```text
Mini-player tap/drag
  -> SystemMiniPlayer (RootView)
  -> MiniOpenDragSample
  -> PlayerGesturePolicy mini-open progress / threshold
  -> RootView fullPlayerOpenProgress, offset, opacity, scale
  -> NowPlayingView overlay opens on center page
      -> Center Now Playing page: cover, metadata, progress, controls, toolbar
      -> Left page: queue list -> PlayerEngine.jump/remove
      -> Right page: recommendations -> PlayerEngine.play(..., queueMode: .radio)
      -> Progress scrub -> PlayerProgressBar -> PlayerEngine.beginScrub/endScrub
      -> Downward dismiss -> allowed region policy -> RootView closeFullPlayer

Regression checks
  -> Unit tests: PlayerGesturePolicy, PlaybackCriticalPath, SearchModels, RecommendationScheduling, ImageCache
  -> UI tests: PlayerChromeUITests with BILIMUSIC_UITEST_FIXTURE
```

This reflects current data/control flow discovered in source and should be preserved during planning. [VERIFIED: CodeGraph]

### Recommended Project Structure

```text
BiliMusic/
├── Features/
│   ├── RootView.swift                  # Mini-player/full-player overlay transition seam
│   └── Player/
│       ├── NowPlayingView.swift        # Three-page player layout and dismiss/page gestures
│       ├── PlayerControlViews.swift    # Progress bar, icon buttons, reusable player controls
│       ├── PlayerGesturePolicy.swift   # Pure gesture thresholds and intent checks
│       └── PlayerSheetViews.swift      # Existing lyrics/MV/favorite/download/quality sheets
├── Design/
│   └── CachedAsyncImage.swift          # Target-size image loading and memory cache
└── Player/
    └── PlayerEngine.swift              # Existing playback/queue/user-action surface only

BiliMusicTests/
├── PlayerGesturePolicyTests.swift
├── PlaybackCriticalPathTests.swift
├── SearchModelsTests.swift
├── RecommendationSchedulingTests.swift
└── ImageCacheTests.swift

BiliMusicUITests/
└── PlayerChromeUITests.swift
```

The structure matches existing source ownership and should not be broadened without a concrete testability reason. [VERIFIED: .planning/codebase/STRUCTURE.md] [VERIFIED: CodeGraph]

### Pattern 1: Keep Gesture Math Pure

**What:** Keep distance, velocity, region, and axis decisions in `PlayerGesturePolicy`; keep SwiftUI `@State` and animation in `RootView` / `NowPlayingView`. [VERIFIED: CodeGraph]

**When to use:** Any change that affects whether a drag opens, cancels, dismisses, pages, or is ignored. [VERIFIED: CodeGraph]

**Example:**

```swift
// Source: BiliMusic/Features/Player/PlayerGesturePolicy.swift
let canDismiss = PlayerGesturePolicy.shouldDismissFullPlayer(
    translation: value.translation,
    predictedEndTranslation: value.predictedEndTranslation,
    startY: value.startLocation.y,
    dismissGrabZoneHeight: Layout.dismissGrabZoneHeight
)
```

### Pattern 2: Compose SwiftUI Gestures by Ownership

**What:** Use high-priority gestures only for controls that must own a drag, such as the mini-player and progress bar; use simultaneous gestures for page/dismiss observation only after intent checks. [VERIFIED: CodeGraph] [CITED: developer.apple.com/documentation/swiftui/view/highprioritygesture%28_%3Aincluding%3A%29] [CITED: developer.apple.com/documentation/swiftui/view/simultaneousgesture%28_%3Aname%3Aisenabled%3A%29]

**When to use:** Mini-player pull-up, scrubber drag, page swipe, top-chrome dismiss, and center-page body dismiss. [VERIFIED: 03-UI-SPEC.md]

**Example:**

```swift
// Source: BiliMusic/Features/Player/PlayerControlViews.swift
.highPriorityGesture(
    DragGesture(minimumDistance: 0)
        .onChanged { _ in onScrubChanged(true) }
        .onEnded { _ in onScrubChanged(false) },
    including: .all
)
```

### Pattern 3: Use Existing Paged Player Model

**What:** Keep the left queue, center Now Playing, right recommendations model in `NowPlayingView` and customize page hints outside the default index display. [VERIFIED: CodeGraph] [CITED: developer.apple.com/documentation/swiftui/tabviewstyle/page]

**When to use:** Any Phase 3 planning that touches queue/recommendation presentation or page indicators. [VERIFIED: 03-UI-SPEC.md]

**Example:**

```swift
// Source: BiliMusic/Features/Player/NowPlayingView.swift
TabView(selection: $selectedPage) {
    horizontalListPage { queueList }.tag(PlayerPage.queue.rawValue)
    ScrollView { nowPlayingPage(coverSize: coverSize) }.tag(PlayerPage.nowPlaying.rawValue)
    horizontalListPage { recommendationsList }.tag(PlayerPage.recommendations.rawValue)
}
.tabViewStyle(.page(indexDisplayMode: .never))
```

### Pattern 4: Preserve Playback-First Boundaries

**What:** UI actions should call existing `PlayerEngine` methods and avoid adding awaited enrichment or recommendation work to first playback. [VERIFIED: CodeGraph] [VERIFIED: 01-CONTEXT.md]

**When to use:** Toolbar actions, recommendation taps, queue taps, progress scrubs, and playback mode toggles. [VERIFIED: CodeGraph]

**Example:**

```swift
// Source: BiliMusic/Features/Player/NowPlayingView.swift
suppressNextRecommendationRefresh = true
Task { await engine.play(tracks: recommendedTracks, startAt: index, queueMode: .radio) }
```

### Anti-Patterns to Avoid

- **Replacing `PlayerEngine` to support layout polish:** Phase 3 should call existing actions and keep first-sound tests green. [VERIFIED: 03-CONTEXT.md] [VERIFIED: CodeGraph]
- **Putting all gesture decisions in view closures:** Untested closures make drag conflicts hard to protect; use pure policy helpers. [VERIFIED: .planning/codebase/CONVENTIONS.md]
- **Making list pages share the same dismiss region as center page:** UI-SPEC says list scrolling must never dismiss the player. [VERIFIED: 03-UI-SPEC.md]
- **Hiding unavailable lyrics/MV actions:** UI-SPEC requires aligned disabled states instead of toolbar holes. [VERIFIED: 03-UI-SPEC.md]
- **Adding expensive blur/physics/background animation:** HIG motion guidance favors brief, precise, useful motion, and UI-SPEC rejects effects that hurt responsiveness. [CITED: developer.apple.com/design/human-interface-guidelines/motion] [VERIFIED: 03-UI-SPEC.md]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Horizontal queue/now/recommendation paging | Custom pager/physics engine | SwiftUI `TabView` with `.page` plus custom lightweight hints | Existing implementation already uses this standard primitive. [VERIFIED: CodeGraph] [CITED: developer.apple.com/documentation/swiftui/tabviewstyle/page] |
| Gesture threshold decisions | Ad hoc view-local math | `PlayerGesturePolicy` | Existing unit tests already cover mini-open and dismiss thresholds. [VERIFIED: CodeGraph] |
| Progress scrub conflict handling | Separate overlay recognizer | `PlayerProgressBar` high-priority drag and `setProgressScrubbing` suppression | Existing seam already prevents page swipe while scrubbing. [VERIFIED: CodeGraph] |
| Image memory cleanup | New image loader/cache | `CachedAsyncImage`, `ImageMemoryCache`, `AppResourceCleanup` | Existing tests cover target-size cache, downsampling, coalescing, and cleanup. [VERIFIED: CodeGraph] |
| Playback or recommendation state | New player state in UI | Existing `PlayerEngine`, `RecommendationPanelRefreshPolicy`, and managers | Phase 2 stability depends on current recommendation-list behavior. [VERIFIED: CodeGraph] |
| UI automation harness | Third-party UI test framework | XCUITest with fixture mode | Existing UI tests already use `BILIMUSIC_UITEST_FIXTURE`. [VERIFIED: .planning/codebase/TESTING.md] |

**Key insight:** Phase 3's complexity is gesture ownership and regression preservation, not missing infrastructure. The plan should isolate interaction policy and layout changes while leaving playback, search, recommendation, and image systems in place. [VERIFIED: CodeGraph]

## Common Pitfalls

### Pitfall 1: A Global Dismiss Drag Eats List Scrolling
**What goes wrong:** Queue or recommendation vertical scrolling closes the player. [VERIFIED: 03-UI-SPEC.md]
**Why it happens:** A broad simultaneous/global drag observes the whole player instead of allowed regions. [VERIFIED: CodeGraph]
**How to avoid:** Add region-aware policy: center body can dismiss; list pages dismiss only from top chrome/grabber/title. [VERIFIED: 03-UI-SPEC.md]
**Warning signs:** A UI test can drag inside `queue`/`recommendations` and `nowPlayingView` disappears. [VERIFIED: .planning/codebase/TESTING.md]

### Pitfall 2: Scrubbing Triggers Page Swipe or Minimize
**What goes wrong:** Progress drag changes pages or minimizes the player. [VERIFIED: 03-UI-SPEC.md]
**Why it happens:** Multiple `DragGesture`s compete without an explicit scrub-active suppression window. [VERIFIED: CodeGraph]
**How to avoid:** Preserve `PlayerProgressBar` high-priority gesture and expand tests around `setProgressScrubbing`. [VERIFIED: CodeGraph]
**Warning signs:** A scrub UI test changes `selectedPage` or closes the overlay. [VERIFIED: CodeGraph]

### Pitfall 3: Dense Layout Reintroduces Bottom Cards
**What goes wrong:** The center page still feels like a status sheet because queue/playlist panels remain stacked under controls. [VERIFIED: 03-CONTEXT.md]
**Why it happens:** Existing `bottomContextPanel` occupies center-page vertical space. [VERIFIED: CodeGraph]
**How to avoid:** Move queue/recommendation content to left/right pages and keep the center page to cover, metadata, progress, controls, and toolbar. [VERIFIED: 03-UI-SPEC.md]
**Warning signs:** Center page shows multiple material panels below controls or a large empty bottom void. [VERIFIED: 03-UI-SPEC.md]

### Pitfall 4: Visual Animation Work Competes with First Sound
**What goes wrong:** Player polish causes startup or tap-to-play regressions. [VERIFIED: PROJECT.md]
**Why it happens:** UI polish adds async enrichment, image work, or recommendation refreshes to playback actions. [VERIFIED: 01-CONTEXT.md]
**How to avoid:** Keep UI actions thin, do not await lyrics/recommendations/images before playback requests, and run playback critical path tests per wave. [VERIFIED: CodeGraph]
**Warning signs:** `PlaybackCriticalPathTests` event order changes or `RecommendationSchedulingTests` finds Home refresh references in direct playback. [VERIFIED: CodeGraph]

### Pitfall 5: Image Regression Hidden by Larger Cover Art
**What goes wrong:** Denser/larger cover art decodes or retains oversized images. [VERIFIED: 01-CONTEXT.md]
**Why it happens:** Full-player cover uses a larger target without passing a bounded target size. [VERIFIED: BiliMusic/Design/CLAUDE.md]
**How to avoid:** Continue `CachedAsyncImage` target-size loading and keep `ImageCacheTests` green. [VERIFIED: CodeGraph]
**Warning signs:** `ImageCacheTests` target-size/downsample/coalescing cleanup tests fail. [VERIFIED: CodeGraph]

## Code Examples

### Direct Mini-Player Progress

```swift
// Source: BiliMusic/Features/RootView.swift
private func fullPlayerOffset(height: CGFloat, safeAreaInsets: EdgeInsets) -> CGFloat {
    let offscreenOffset = height + safeAreaInsets.bottom + 24
    return offscreenOffset * (1 - renderedPlayerOpenProgress)
}
```

Use this seam for PLYR-01; avoid a separate transition engine. [VERIFIED: CodeGraph]

### Reduced-Motion Branch

```swift
// Source: BiliMusic/Features/RootView.swift
private var fullPlayerScaleX: CGFloat {
    guard !reduceMotion else { return 1 }
    return 0.985 + renderedPlayerOpenProgress * 0.015
}
```

Keep `@Environment(\.accessibilityReduceMotion)` branches in any new transition or page-hint animation. [VERIFIED: CodeGraph] [CITED: developer.apple.com/design/human-interface-guidelines/accessibility]

### Memory Cleanup Regression

```swift
// Source: BiliMusic/Features/RootView.swift
static func handleMemoryWarning(_ notification: Notification) {
    guard notification.name == UIApplication.didReceiveMemoryWarningNotification else { return }
    ImageMemoryCache.shared.releaseReloadableImages()
}
```

UIKit low-memory guidance supports releasing recreateable cached data on memory warning. [VERIFIED: CodeGraph] [CITED: developer.apple.com/documentation/uikit/uiapplication/didreceivememorywarningnotification]

## State of the Art

| Old Approach | Current Approach | When Changed / Verified | Impact |
|--------------|------------------|--------------------------|--------|
| Heavy segmented/player status surface | Three-page player with lightweight hints and dense center page | Approved in Phase 3 UI-SPEC on 2026-06-27 | Planner should remove the heavy segmented feel while preserving the three-page model. [VERIFIED: 03-UI-SPEC.md] |
| Playback-side recommendation refresh | Visible related list stays stable after recommendation tap | Phase 2 completed 2026-06-27 | Player UI changes must preserve `suppressNextRecommendationRefresh` behavior. [VERIFIED: STATE.md] [VERIFIED: CodeGraph] |
| Full-size decoded image retention | URL + target-size cache keys, downsampling, cleanup | Phase 1 completed 2026-06-26 | Larger cover art must keep target-size image requests and cleanup tests. [VERIFIED: STATE.md] [VERIFIED: CodeGraph] |
| Gesture tests only by feel | Pure policy tests plus XCUITest fixture drags | Phase 1 completed 2026-06-26 | Add conflict cases for page/list/scrub/minimize rather than manual-only validation. [VERIFIED: STATE.md] [VERIFIED: CodeGraph] |

**Deprecated/outdated:**
- Center-page bottom context panels as primary queue/recommendation UI: replace with left/right pages per UI-SPEC, while preserving stable states. [VERIFIED: 03-UI-SPEC.md] [VERIFIED: CodeGraph]
- Broad API/auth/cache hardening in v1: keep deferred unless a narrow Phase 3 UI hook requires it. [VERIFIED: ROADMAP.md]

## Assumptions Log

All claims in this research were verified from local project artifacts, CodeGraph source inspection, local commands, or official Apple/OWASP documentation. No `[ASSUMED]` claims are used.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| — | — | — | — |

## Open Questions

1. **Which simulator/device sizes should gate PLYR-05?**
   - What we know: UI-SPEC requires compact 375pt-wide class and a modern iPhone size. [VERIFIED: 03-UI-SPEC.md]
   - What's unclear: The local simulator list has iPhone 17 booted and no iPhone 16 shown in the first available-device page. [VERIFIED: local `xcrun simctl list devices available`]
   - Recommendation: Plan responsive layout tests on the available modern iPhone simulator plus one compact destination if installed; include real-device UAT for final gesture feel. [VERIFIED: .planning/codebase/TESTING.md]

2. **How much of layout density should be automated?**
   - What we know: Existing UI tests use accessibility identifiers and coordinate checks. [VERIFIED: CodeGraph]
   - What's unclear: Pixel-perfect Apple Music parity is out of scope, so exact void measurements need a pragmatic threshold. [VERIFIED: 03-CONTEXT.md]
   - Recommendation: Add stable identifiers for cover/progress/toolbar/page hints and assert existence/non-overlap plus coarse vertical placement; rely on UAT for subjective density. [VERIFIED: 03-UI-SPEC.md]

3. **Should Phase 3 update outdated module CLAUDE test docs?**
   - What we know: `BiliMusicTests/CLAUDE.md` says only one test file exists, but CodeGraph found many current test files. [VERIFIED: BiliMusicTests/CLAUDE.md] [VERIFIED: CodeGraph]
   - What's unclear: The phase output request is research-only and source/docs updates beyond RESEARCH are not requested. [VERIFIED: user request]
   - Recommendation: Planner may add a small docs cleanup task only if it helps execution; it is not required for Phase 3 behavior. [VERIFIED: user request]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Xcode / xcodebuild | Build and XCTest/XCUITest | yes | Xcode 26.3, build 17C529 | None for simulator tests. [VERIFIED: local `xcodebuild -version`] |
| XcodeGen | Project regeneration after new Swift files | yes | 2.45.4 | Avoid adding files or install via Homebrew if missing. [VERIFIED: local `xcodegen --version`] |
| iOS Simulator | UI regression tests | yes | iOS 26.3 devices available; iPhone 17 booted | Use any available iPhone destination if named iPhone 16 is absent. [VERIFIED: local `xcrun simctl list devices available`] |
| CodeGraph | Source seam discovery | yes | 1.0.1 | Shell `codegraph` or MCP tool; no fallback needed in this repo. [VERIFIED: local `codegraph --version`] |
| Python 3 | Optional existing API scripts | yes | 3.12.7 | Not needed for Phase 3 UI/test plan unless scripts are invoked. [VERIFIED: local `python3 --version`] |
| Network/Bilibili APIs | Not required for automated Phase 3 tests | not required | — | Use `BILIMUSIC_UITEST_FIXTURE` for UI tests. [VERIFIED: .planning/codebase/TESTING.md] |

**Missing dependencies with no fallback:**
- None found for research/planning. [VERIFIED: local command]

**Missing dependencies with fallback:**
- Exact `iPhone 16` simulator destination was not shown in the sampled available-device output; use an available iPhone simulator or install that runtime/device before execution if the plan hardcodes it. [VERIFIED: local `xcrun simctl list devices available`]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest/XCUITest bundled with Xcode 26.3. [VERIFIED: local `xcodebuild -version`] |
| Config file | `project.yml`; no separate XCTest config file. [VERIFIED: .planning/codebase/TESTING.md] |
| Quick run command | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -target BiliMusicTests -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO` |
| Full suite command | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| PLYR-01 | Mini-player upward drag tracks and completes/cancels by policy | unit + UI | Unit target plus `-only-testing:BiliMusicUITests/PlayerChromeUITests/testMiniPlayerSlowDragOpensRespectsSafeAreaAndClosesFromTopChrome` | Exists; extend for finger-tracking/progress if feasible. [VERIFIED: CodeGraph] |
| PLYR-02 | Deliberate full-player downward minimize from allowed center regions | unit + UI | Unit target plus PlayerChrome UI test extension | Exists; add center-body allowed-region cases. [VERIFIED: CodeGraph] |
| PLYR-03 | Queue/recommendation list scroll does not minimize | unit + UI | PlayerChrome UI test dragging inside queue/recommendation list pages | Partial; existing content-drag test exists, page-specific cases needed. [VERIFIED: CodeGraph] |
| PLYR-04 | Scrub, page swipe, and vertical minimize do not fight | unit + UI | Add policy tests and UI tests using progress/accessibility identifiers | Gap; `PlayerProgressBar` seam exists but direct conflict tests need adding. [VERIFIED: CodeGraph] |
| PLYR-05 | Dense layout has no excessive bottom void | UI + manual UAT | UI test with identifiers/coarse frame assertions; manual real-device check | Gap; no current layout-density test. [VERIFIED: CodeGraph] |
| TEST-01 | Search query/mode/pagination/stale/filtering guardrails | unit | Unit target, `SearchModelsTests` | Exists. [VERIFIED: CodeGraph] |
| TEST-02 | Playback request before post-start enrichment | unit | Unit target, `PlaybackCriticalPathTests` | Exists; keep in phase gate. [VERIFIED: CodeGraph] |
| TEST-03 | Recommendation list stability | unit + UI | Unit target, `RecommendationSchedulingTests`; UI `testTappingRecommendationKeepsHomeListStable` | Exists. [VERIFIED: CodeGraph] |
| TEST-05 | Bounded image work / memory cleanup | unit | Unit target, `ImageCacheTests` | Exists. [VERIFIED: CodeGraph] |

### Sampling Rate

- **Per task commit:** Run focused unit tests for touched seams, especially `PlayerGesturePolicyTests`, `PlaybackCriticalPathTests`, and `ImageCacheTests`. [VERIFIED: .planning/codebase/TESTING.md]
- **Per wave merge:** Run full unit target and relevant `PlayerChromeUITests`. [VERIFIED: .planning/codebase/TESTING.md]
- **Phase gate:** Full simulator suite green before `$gsd-verify-work`, plus real-device/manual gesture UAT for density and touch feel. [VERIFIED: .planning/codebase/TESTING.md] [VERIFIED: 03-UI-SPEC.md]

### Wave 0 Gaps

- [ ] `BiliMusicTests/PlayerGesturePolicyTests.swift` — add policy coverage for center-body dismiss allowance, list-page top-chrome-only dismiss, horizontal page-intent gating, and scrub suppression where pure logic can express it. [VERIFIED: CodeGraph]
- [ ] `BiliMusicUITests/PlayerChromeUITests.swift` — add fixture checks for queue page scroll, recommendation page scroll, progress scrub not paging/dismissing, page swipe not minimizing, and dense layout identifiers. [VERIFIED: CodeGraph]
- [ ] `BiliMusic/Features/Player/NowPlayingView.swift` — likely needs accessibility identifiers for page hints, queue/recommendation pages, cover, progress, and toolbar to make UI checks stable. [VERIFIED: CodeGraph]
- [ ] `project.yml` regeneration only if new Swift files are introduced. [VERIFIED: .planning/codebase/CONVENTIONS.md]

## Security Domain

Security enforcement is enabled because `.planning/config.json` does not set `security_enforcement: false`. [VERIFIED: .planning/config.json]

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no direct change | Do not touch cookie login/auth lifecycle in Phase 3; broad auth hardening remains v2. [VERIFIED: ROADMAP.md] [CITED: owasp.org/www-project-application-security-verification-standard/] |
| V3 Session Management | no direct change | Do not introduce new session state; player UI should call existing engine/managers only. [VERIFIED: 03-CONTEXT.md] |
| V4 Access Control | no direct change | No new privileged server/API operations are in scope. [VERIFIED: REQUIREMENTS.md] |
| V5 Input Validation | yes, local UI input | Validate gesture intent by axis, velocity, distance, page, and region in `PlayerGesturePolicy`; keep list scroll and scrub ownership explicit. [VERIFIED: CodeGraph] |
| V6 Cryptography | no direct change | Do not modify Keychain/cookie storage, WBI signing, or crypto behavior in Phase 3. [VERIFIED: ROADMAP.md] |

### Known Threat Patterns for Native Player UI

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Accidental destructive or disruptive gesture | Denial of Service | Region-gated dismiss policy and UI tests proving list/scrub/page gestures do not close the player. [VERIFIED: 03-UI-SPEC.md] |
| Memory pressure from full-player artwork | Denial of Service | Target-size image requests, downsampling, `NSCache`, and memory/background cleanup tests. [VERIFIED: CodeGraph] [CITED: developer.apple.com/documentation/uikit/uiapplication/didreceivememorywarningnotification] |
| State confusion after recommendation tap | Tampering | Preserve Phase 2 `suppressNextRecommendationRefresh` and visible-list stability tests. [VERIFIED: CodeGraph] |
| Accessibility-unreachable disabled actions | Usability/Security Adjacent | Keep disabled lyrics/MV controls aligned and labeled; do not encode state by color alone. [VERIFIED: 03-UI-SPEC.md] |

## Sources

### Primary (Local Verified)

- `AGENTS.md` - project constraints, CodeGraph requirement, playback-first priority. [VERIFIED: AGENTS.md]
- `.planning/PROJECT.md`, `.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md` - v1 scope, Phase 3 requirements, deferred v2 boundaries, prior phase state. [VERIFIED: local docs]
- `.planning/phases/03-player-interaction-and-regression-coverage/03-CONTEXT.md` - locked user decisions and phase boundary. [VERIFIED: local docs]
- `.planning/phases/03-player-interaction-and-regression-coverage/03-UI-SPEC.md` - approved player layout, interaction, accessibility, and verification contract. [VERIFIED: local docs]
- `.planning/codebase/CONVENTIONS.md`, `STRUCTURE.md`, `STACK.md`, `TESTING.md` - code organization, stack, and test commands. [VERIFIED: local docs]
- CodeGraph on `RootView.swift`, `NowPlayingView.swift`, `PlayerControlViews.swift`, `PlayerGesturePolicy.swift`, `PlayerChromeUITests.swift`, `PlaybackCriticalPathTests.swift`, `SearchModelsTests.swift`, `RecommendationSchedulingTests.swift`, and `ImageCacheTests.swift`. [VERIFIED: CodeGraph]

### Secondary (Official Docs)

- `/websites/developer_apple_swiftui` via Context7 - `DragGesture`, `highPriorityGesture`, `simultaneousGesture`, `TabViewStyle.page`, `PageTabViewStyle`. [CITED: developer.apple.com/documentation/swiftui]
- `/websites/developer_apple_uikit` via Context7 - `UIApplication.didReceiveMemoryWarningNotification`, memory warning handling. [CITED: developer.apple.com/documentation/uikit/uiapplication/didreceivememorywarningnotification]
- `/websites/developer_apple_design_human-interface-guidelines` via Context7 - gestures, motion, accessibility/reduced motion, toolbar guidance. [CITED: developer.apple.com/design/human-interface-guidelines]
- Apple XCTest/XCUITest developer docs - UI element waits, coordinate drags, accessibility identifiers. [CITED: developer.apple.com/documentation/xctest]
- OWASP ASVS project - ASVS category framing for security-domain checklist. [CITED: owasp.org/www-project-application-security-verification-standard/]

### Tertiary (LOW confidence)

- None used for recommendations. The GSD seam classified websearch as MEDIUM when verified, Context7 as MEDIUM, and no unverified web-only claims were carried into decisions. [VERIFIED: local `gsd-tools classify-confidence`]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH for local stack and environment availability because project docs and local commands agree; MEDIUM for external framework behavior because Context7 classified official docs as MEDIUM. [VERIFIED: .planning/codebase/STACK.md] [VERIFIED: local command] [CITED: developer.apple.com/documentation/swiftui]
- Architecture: MEDIUM because CodeGraph verified source seams, but no source changes or test execution were performed during research. [VERIFIED: CodeGraph]
- Pitfalls: MEDIUM because they are derived from existing code seams, UI-SPEC decisions, and prior regression tests. [VERIFIED: CodeGraph] [VERIFIED: 03-UI-SPEC.md]
- Validation: MEDIUM because test files and commands are verified, but the Phase 3-specific tests do not yet exist. [VERIFIED: .planning/codebase/TESTING.md] [VERIFIED: CodeGraph]

**Research date:** 2026-06-27
**Valid until:** 2026-07-04 for Apple SDK/Xcode-specific details; local codebase findings remain valid until the touched files change.
