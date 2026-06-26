# Phase 01: playback-critical-path-and-responsiveness - Research

**Researched:** 2026-06-26  
**Domain:** SwiftUI iOS playback startup, search responsiveness, recommendation stability, image memory, XCTest instrumentation  
**Confidence:** MEDIUM

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

## Implementation Decisions

### First Playback Critical Path
- **D-01:** First playback may block only on the minimal path: set the current track state, use a local cache entry or prepared stream when available, resolve one necessary `cid`/`playurl` when needed, create the `AVPlayer` item, and request playback.
- **D-02:** Lyrics, artwork, MV probing, recommendation loading, queue/radio prefetch, auto-cache, and other enrichment cannot be awaited before the playback request.
- **D-03:** If a prepared remote stream appears expired or unauthorized, discard it and retry source resolution once. Only surface failure after the retry also fails.
- **D-04:** Tap-to-play diagnostics should expose timing checkpoints for tap, current-track assignment, source resolution, AVPlayer item creation, play request, and first observed playing state so regressions are measurable.

### Search Focus Experience
- **D-05:** Focusing the search field with an empty query should remain local and cheap.
- **D-06:** Empty focused search should show local search history, recent playback, and cached songs. Favorite-folder seed suggestions are intentionally excluded from Phase 1.
- **D-07:** Bilibili search requests may start only after explicit user submission, such as tapping keyboard search. Focus alone and normal typing must not perform network work.

### Recommendation and Background Work
- **D-08:** After sound starts, history, artwork, and lyrics may run as post-start work. Recommendation and MV work should wait until the user opens the relevant page or explicitly triggers it.
- **D-09:** Starting the first song after app launch must keep the existing Home recommendation list stable. It may be marked stale internally, but must not clear, auto-refresh, flash, or replace visible recommendations on the first playback path.
- **D-10:** Recommendation work should remain lower priority than direct playback startup and should not compete with first playback for network, main-actor time, or image decoding.

### Image and Memory Guardrails
- **D-11:** Image loading should prioritize first-screen visible images. Remaining images should be delayed, lower priority, or concurrency-capped.
- **D-12:** Scrolling and playback responsiveness outrank image completeness; images can appear late if needed to keep the app responsive.
- **D-13:** Decoded image memory should stay bounded, with a path to release reloadable image/media data on memory pressure or backgrounding without losing playback state.

### Completion Standard and Tests
- **D-14:** Phase 1 is complete only when behavior is observable through metrics/logging plus focused regression checks, not just by subjective feel.
- **D-15:** Regression coverage should include at least: search focus doing no network/expensive work, first playback not awaiting post-start enrichment, Home recommendations not resetting on first playback, and bounded image/memory behavior.

### the agent's Discretion

The agent may choose the exact instrumentation shape, log category names, internal helper boundaries, and test seams, as long as they preserve the existing SwiftUI app structure and avoid broad rewrites. Narrow collaborators or small protocols are acceptable when they directly make the first-play/search/recommendation/image behavior testable.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within Phase 1 scope. Discovery music-only ranking, search pagination, related-list behavior, player gestures/layout density, favorite-folder selection, collection queue context, MV/fullscreen polish, and broader API/auth/cache hardening remain in later roadmap phases unless a narrow dependency is required for Phase 1 stability.

</user_constraints>

## Summary

Phase 1 should be planned as a critical-path extraction and scheduling pass, not as a playback rewrite. `PlayerEngine.play(tracks:startAt:)` already centralizes all track starts, and `startCurrent` currently resolves cache/prepared/fresh streams, builds the `AVPlayerItem`, starts playback, records history, and schedules enrichment from one method. The planner should keep `PlayerEngine` as the owner but introduce small testable seams for diagnostics, source resolution/retry, and post-start work ordering. [VERIFIED: CodeGraph `PlayerEngine.play`, `startCurrent`, `startPlayback`, `schedulePostPlaybackWork`]

The biggest planning hazards are accidental network work on search typing, recommendation snapshot/favorite sync competing with first playback, and full-size image decode entering list scrolling. `SearchView` currently has a 450 ms debounced search path on query changes, `HomeView.load()` preloads recommendations after refresh, and `CachedAsyncImage` coalesces URL work but decodes with `UIImage(data:)`. Plan Phase 1 around removing those conflicts from focus/tap/background paths while preserving the existing app-wide `PlayerEngine`, `SearchStore`, `HomeView`, and shared image loader boundaries. [VERIFIED: CodeGraph `SearchView`, `HomeView`, `CachedAsyncImage`]

**Primary recommendation:** Split the plan into five implementation tracks: playback diagnostics/source retry, enrichment scheduling, submit-only search focus, Home recommendation stability, and shared image downsampling/cache release, with Wave 0 test seams before source changes. [VERIFIED: 01-CONTEXT.md]

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PLAY-01 | Current track becomes visible immediately before enrichment finishes. | `play(tracks:startAt:)` sets queue/index before `startCurrent`; plan should assert row accent/mini-player current state before stream/enrichment completion. [VERIFIED: CodeGraph `PlayerEngine.play`; VERIFIED: 01-UI-SPEC.md] |
| PLAY-02 | Startup resolves only cache, prepared stream, or one fresh stream before playback. | `startCurrent` already follows cache -> prepared -> `StreamResolver.prepareAudio`; plan should preserve that chain and prevent MV/recommendation/lyrics waits. [VERIFIED: CodeGraph `startCurrent`, `StreamResolver.prepareAudio`] |
| PLAY-03 | Timing checkpoints cover tap, source resolution, item creation, play request, first playback state. | Use one diagnostics seam around `play`, source resolver, `AVPlayerItem` creation, `playImmediately`, and `timeControlStatus`. [CITED: https://developer.apple.com/documentation/avfoundation/avplayer/timecontrolstatus-swift.enum; VERIFIED: CodeGraph `startPlayback`] |
| PLAY-04 | Expired or unauthorized prepared remote streams retry once. | `StreamResolver.invalidateAudio(for:)` exists; plan retry around prepared-stream playback item failure/status failure by invalidating and re-resolving once. [VERIFIED: CodeGraph `StreamResolver.invalidateAudio`; CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/status-swift.enum/failed] |
| PLAY-05 | Post-start enrichment cannot block first audible playback. | `schedulePostPlaybackWork` is already delayed utility work; plan should ensure history, cover, lyrics, MV, queue prefetch, and auto-cache are scheduled after playback request, with tests. [VERIFIED: CodeGraph `schedulePostPlaybackWork`] |
| SRCH-01 | Search focus and typing must not trigger Bilibili network or expensive local work. | `SearchView.onChange(of: query)` currently schedules `debouncedSearch`; plan should remove/disable that path and keep `.onSubmit(of: .search)` as the network trigger. [VERIFIED: CodeGraph `SearchView`] |
| SRCH-02 | Empty focused search shows local history/suggestions. | `SearchView` already has `searchSuggestions`, `PlaybackHistoryStore`, and `CacheStore`; plan should add cached-song and recent-playback local sections without network calls. [VERIFIED: CodeGraph `SearchView`, `PlaybackHistoryStore`, `CacheStore`; CITED: https://developer.apple.com/documentation/swiftui/view/searchable%28text:placement:prompt:suggestions:%29] |
| RECO-01 | First playback must not reset Home recommendations. | `HomeView` owns visible `tracks`; plan should keep them immutable during first playback and avoid playback-triggered Home `load()`. [VERIFIED: CodeGraph `HomeView`] |
| RECO-04 | Recommendation refresh stays bounded/lower priority than playback. | `RecommendationEngine` uses task groups and snapshot work; plan should gate recommendation work behind explicit surface load/manual refresh and avoid first playback competition. [VERIFIED: CodeGraph `RecommendationEngine`; VERIFIED: .planning/codebase/CONCERNS.md] |
| MEM-01 | Image-heavy scroll should not decode/retain full-size covers. | `CachedAsyncImage` currently decodes `UIImage(data:)`; plan should downsample to requested display size before cache insertion. [VERIFIED: CodeGraph `CachedAsyncImage`; CITED: https://developer.apple.com/documentation/uikit/uiimage/preparingthumbnail%28of:%29] |
| MEM-02 | Duplicate URL work coalesces and cache is bounded. | `ImageLoadCoordinator` already coalesces `inFlight` tasks and `ImageMemoryCache` has count/cost limits; plan should preserve this and add display-size-aware cache keys if needed. [VERIFIED: CodeGraph `ImageLoadCoordinator`, `ImageMemoryCache`; CITED: https://developer.apple.com/documentation/foundation/nscache] |
| MEM-03 | Memory pressure/background releases reloadable images without losing playback state. | `RootView` already handles background for cache/history/player; plan should add image cache release there and memory-warning notification handling without clearing `PlayerEngine.current`. [VERIFIED: CodeGraph `RootView`; CITED: https://developer.apple.com/documentation/uikit/uiapplication/didreceivememorywarningnotification] |

</phase_requirements>

## Project Constraints (from AGENTS.md)

| Directive | Planning Impact |
|-----------|-----------------|
| Read `.planning/PROJECT.md`, `.planning/STATE.md`, `.planning/ROADMAP.md`, and `.planning/REQUIREMENTS.md` before substantial work. [VERIFIED: AGENTS.md] | Planner should cite these files in Wave 0 and preserve requirement traceability. [VERIFIED: AGENTS.md] |
| Current focus is Phase 1: Playback Critical Path and Responsiveness. [VERIFIED: AGENTS.md] | Do not add Phase 2 discovery quality or Phase 3 player gesture/layout work unless needed for Phase 1 stability. [VERIFIED: AGENTS.md] |
| Playback startup takes priority over lyrics, recommendations, MV, artwork, cache work, and UI polish. [VERIFIED: AGENTS.md] | Every task touching async work should state whether it is on or off the first-play critical path. [VERIFIED: AGENTS.md] |
| Use CodeGraph before grep/find/raw source reads because `.codegraph/` is present. [VERIFIED: AGENTS.md] | Implementation agents should inspect symbols with CodeGraph before editing shared playback/search/image code. [VERIFIED: AGENTS.md] |
| Do not revert uncommitted user or prior-agent source changes. [VERIFIED: AGENTS.md] | Planner should avoid tasks that require broad rewrites or source reset; current source has uncommitted edits in player/root/search files. [VERIFIED: `git status --short`] |
| Keep planning-doc commits separate from source-code commits when possible. [VERIFIED: AGENTS.md] | This research artifact should be committed as docs only before implementation planning. [VERIFIED: AGENTS.md] |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Track tap/current-track feedback | Player Domain | Feature UI | `PlayerEngine.play` owns queue/current state; `TrackRow`/mini-player render `engine.current`. [VERIFIED: CodeGraph `PlayerEngine.play`, `TrackRow`] |
| Audio source resolution | Player Domain | API/Cache Boundary | `startCurrent` chooses cache, prepared audio, or `StreamResolver.prepareAudio`; Bilibili URL lookup stays behind `BiliClient`. [VERIFIED: CodeGraph `startCurrent`, `StreamResolver`, `BiliClient.audioStream`] |
| Prepared stream expiry/403 retry | Player Domain | AVFoundation Boundary | `StreamResolver` owns prepared stream invalidation; `AVPlayerItem` status/error should trigger one retry when the URL was prepared remote media. [VERIFIED: CodeGraph `StreamResolver.invalidateAudio`; CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/error] |
| Post-start enrichment | Player Domain | API/Persistence Boundary | `schedulePostPlaybackWork` already sequences cover, lyrics, MV preparation, queue prefetch, and auto-cache after start. [VERIFIED: CodeGraph `schedulePostPlaybackWork`] |
| Search focus/local suggestions | Feature UI/Search Store | Persistence Boundary | `SearchView` owns `.searchable` and suggestions; local history/cache/recent playback come from stores. [VERIFIED: CodeGraph `SearchView`; CITED: https://developer.apple.com/documentation/swiftui/view/searchcompletion%28_%3A%29] |
| Home recommendation stability | Feature UI/Home | Recommendation Engine | `HomeView` owns visible rows; `RecommendationEngine` should run only on explicit load/refresh paths. [VERIFIED: CodeGraph `HomeView`, `RecommendationEngine`] |
| Image downsampling/cache | Design System | Persistence Boundary | `CachedAsyncImage`, `ImageLoadCoordinator`, and `ImageMemoryCache` are shared design-system boundaries used by rows/player/root. [VERIFIED: CodeGraph `CachedAsyncImage`, `TrackRow`] |
| Memory-pressure/background cleanup | App Shell | Design System/Player Domain | `RootView` receives scene phase and already flushes stores/asks `PlayerEngine`; image cache cleanup belongs beside that without clearing playback state. [VERIFIED: CodeGraph `RootView`] |
| Diagnostics and regression checks | Player Domain/Test Targets | App Shell/UI Tests | Playback diagnostics should be generated in player code and asserted from XCTest/XCUITest fixture paths. [VERIFIED: .planning/codebase/TESTING.md; CITED: https://developer.apple.com/documentation/xctest/xctossignpostmetric] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS target 26.0; project Swift setting 5.10 | Native UI, `.searchable`, `scenePhase`, list rendering, environment-injected `PlayerEngine`. | Existing app stack; no web/component-library layer. [VERIFIED: project.yml; VERIFIED: CodeGraph `RootView`, `SearchView`] |
| AVFoundation | Apple platform framework from Xcode 26.3 SDK | `AVPlayer`, `AVPlayerItem`, `AVURLAsset`, audio session, playback state. | Existing playback engine and official Apple media framework. [VERIFIED: CodeGraph `PlayerEngine.startPlayback`; CITED: https://developer.apple.com/documentation/avfoundation/avplayer/timecontrolstatus-swift.enum] |
| OSLog | Apple platform framework | `Logger` and `OSSignposter` for tap-to-first-play checkpoints. | Existing code already uses `Logger`; signposts are the first-party performance interval mechanism. [VERIFIED: CodeGraph `BiliClient`, `StreamResolver`; CITED: https://developer.apple.com/documentation/os/ossignposter] |
| UIKit + ImageIO | Apple platform frameworks | Memory notifications, `UIImage`, thumbnail preparation, downsampling options. | Existing loader returns `UIImage`; Apple APIs avoid third-party image pipeline work. [VERIFIED: CodeGraph `CachedAsyncImage`; CITED: https://developer.apple.com/documentation/uikit/uiimage/preparingthumbnail%28of:%29] |
| XCTest + XCUITest | Xcode 26.3 | Unit and UI regression coverage. | Existing test targets and fixture-mode UI tests use XCTest/XCUITest. [VERIFIED: project.yml; VERIFIED: .planning/codebase/TESTING.md] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| XcodeGen | 2.45.4 | Regenerate `BiliMusic.xcodeproj` from `project.yml`. | Use after target/source-layout changes. [VERIFIED: `xcodegen --version`; VERIFIED: project.yml] |
| Foundation `NSCache`/`URLCache` | Apple platform framework | Bounded image memory/disk caching. | Continue in `ImageMemoryCache`/`ImageLoadCoordinator`; add explicit release hooks. [VERIFIED: CodeGraph `CachedAsyncImage`; CITED: https://developer.apple.com/documentation/foundation/nscache/removeallobjects%28%29] |
| Swift concurrency `Task`/`TaskPriority` | Apple Swift toolchain | Scheduling, cancellation, lower-priority enrichment/image work. | Use for post-start tasks, but do not rely on priority as the only guard; use cancellation/generation checks. [CITED: https://developer.apple.com/documentation/swift/taskpriority; CITED: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Existing `CachedAsyncImage` | A third-party image pipeline | Not recommended for Phase 1 because the approved UI spec forbids new registry/library work and the existing loader already coalesces URL work. [VERIFIED: 01-UI-SPEC.md; VERIFIED: CodeGraph `ImageLoadCoordinator`] |
| OSLog signposts | Plain `print`/`NSLog` timing | Not recommended because tests/Instruments can use signpost metrics and logs stay categorized. [CITED: https://developer.apple.com/documentation/os/logger; CITED: https://developer.apple.com/documentation/xctest/xctossignpostmetric] |
| Broad API/auth/cache rewrite | Narrow playback/search/image seams | Not recommended because v2 API/auth/cache hardening is deferred unless directly needed for Phase 1 stability. [VERIFIED: .planning/ROADMAP.md; VERIFIED: .planning/STATE.md] |

**Installation:**

```bash
xcodegen generate
```

**Version verification:** Standard stack versions were verified from `project.yml`, `xcodegen --version`, `xcodebuild -version`, and `swift --version`; no npm/PyPI/crates package versions apply. [VERIFIED: command output]

## Package Legitimacy Audit

No external packages are recommended or installed in this phase. [VERIFIED: 01-UI-SPEC.md]

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| None | N/A | N/A | N/A | N/A | OK | No install needed. [VERIFIED: 01-UI-SPEC.md] |

**Packages removed due to [SLOP] verdict:** none. [VERIFIED: no external package recommendations]  
**Packages flagged as suspicious [SUS]:** none. [VERIFIED: no external package recommendations]

## Architecture Patterns

### System Architecture Diagram

```text
Track tap / search row / home row
        |
        v
PlayerEngine.play(tracks:startAt:)
        |
        +--> Assign queue/index/current-visible state immediately
        |
        v
PlaybackDiagnostics checkpoint: tap/current
        |
        v
Resolve playable source
   | cache hit      | prepared remote stream       | fresh cid/playurl
   v                v                             v
 local file     prepared URL                StreamResolver.prepareAudio
        \              |                             /
         \             v                            /
          +--> AVURLAsset + AVPlayerItem creation <-+
                         |
                         v
              AVPlayer.playImmediately(atRate: 1)
                         |
                         +--> First timeControlStatus == .playing checkpoint
                         |
                         +--> Prepared remote failure?
                                  |
                                  +-- yes and retry unused:
                                  |       StreamResolver.invalidateAudio
                                  |       resolve fresh stream once
                                  |
                                  +-- no / retry used:
                                          surface failure

Post-start only:
  history save, cover, lyrics, MV probe, queue prefetch, auto-cache,
  Home/manual recommendation work, non-visible image loads
```

This flow keeps only source resolution and AVPlayer item creation before the play request, matching the locked Phase 1 critical path. [VERIFIED: 01-CONTEXT.md; VERIFIED: CodeGraph `startCurrent`, `startPlayback`]

### Recommended Project Structure

```text
BiliMusic/
├── Player/
│   ├── PlayerEngine.swift              # Keep public playback state and AVPlayer lifecycle
│   ├── StreamResolver.swift            # Prepared audio cache, invalidation, fresh stream resolution
│   └── PlaybackDiagnostics.swift       # Add small diagnostics/value-type seam for Phase 1
├── Features/
│   ├── Search/                         # Submit-only search and local suggestions
│   └── Home/                           # Stable visible recommendation list
├── Design/
│   └── CachedAsyncImage.swift          # Downsample, coalesce, bounded cache, memory release
└── Support/
    └── UITestFixtures.swift            # Existing fixture mode for deterministic UI checks

BiliMusicTests/
├── PlaybackCriticalPathTests.swift     # Wave 0 gap
├── SearchFocusTests.swift              # Wave 0 gap or extend SearchModelsTests.swift
└── ImageCacheTests.swift               # Wave 0 gap

BiliMusicUITests/
└── PlayerChromeUITests.swift           # Extend or add Home stability fixture tests
```

This structure follows existing folder boundaries and adds only small seams needed for testing. [VERIFIED: .planning/codebase/ARCHITECTURE.md; VERIFIED: CodeGraph]

### Pattern 1: Critical Path + Deferred Enrichment

**What:** The playback request path should record diagnostics, resolve one playable source, create the player item, and call playback before scheduling enrichments. [VERIFIED: 01-CONTEXT.md; VERIFIED: CodeGraph `startCurrent`]

**When to use:** Every track start, including Home, Search, Library, queue, and debug autoplay, because they all converge on `PlayerEngine.play`. [VERIFIED: CodeGraph `PlayerEngine.play` callers]

**Example:**

```swift
// Source: synthesized from PlayerEngine.startCurrent and OSLog guidance.
// [VERIFIED: CodeGraph `PlayerEngine.startCurrent`]
// [CITED: https://developer.apple.com/documentation/os/ossignposter]
@MainActor
private func startCurrent(resumeAt: Double = 0) async {
    let generation = UUID()
    playbackGeneration = generation
    diagnostics.mark(.currentAssigned, track: current)

    do {
        let source = try await audioSourceResolver.resolve(for: current)
        diagnostics.mark(.sourceResolved, track: current)
        startPlayback(url: source.url, isLocal: source.isLocal, resumeAt: resumeAt)
        diagnostics.mark(.playRequested, track: current)
        schedulePostPlaybackWork(for: source.track, generation: generation, isLocal: source.isLocal)
    } catch {
        diagnostics.mark(.failed, track: current)
        state = .failed(error.localizedDescription)
    }
}
```

### Pattern 2: One-Retry Prepared Stream Invalidation

**What:** Treat a prepared remote URL as an optimization, not durable truth; if AVPlayer reports item failure for a prepared URL, invalidate the prepared entry and resolve once fresh. [VERIFIED: 01-CONTEXT.md; VERIFIED: CodeGraph `StreamResolver.invalidateAudio`]

**When to use:** Only when the selected source came from `streamResolver.cachedAudio(for:)` and the retry has not already happened for that generation. [VERIFIED: CodeGraph `startCurrent`, `StreamResolver.cachedAudio`]

**Example:**

```swift
// Source: synthesized from AVPlayerItem status/error docs and StreamResolver.
// [CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/status-swift.enum/failed]
// [VERIFIED: CodeGraph `StreamResolver.invalidateAudio`]
statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
    Task { @MainActor in
        guard item.status == .failed else { return }
        await self?.retryPreparedStreamOnceIfNeeded(error: item.error)
    }
}
```

### Pattern 3: Submit-Only Search

**What:** Focus and typing update local UI state only; Bilibili network starts from `.onSubmit(of: .search)` or explicit retry/broaden/load-more actions. [VERIFIED: 01-CONTEXT.md; VERIFIED: CodeGraph `SearchView`]

**When to use:** Empty query focus, normal typing, and suggestions. [VERIFIED: 01-UI-SPEC.md]

**Example:**

```swift
// Source: SwiftUI searchable/searchCompletion docs plus current SearchView.
// [CITED: https://developer.apple.com/documentation/swiftui/view/searchable%28text:placement:prompt:suggestions:%29]
// [VERIFIED: CodeGraph `SearchView`]
.onChange(of: query) { _, newValue in
    store.queryDidChange(newValue)
    // No debounced network request here in Phase 1.
}
.onSubmit(of: .search) {
    submitSearch()
}
```

### Pattern 4: Target-Size Image Decode and Reloadable Cache Release

**What:** Decode list/player images to the size actually displayed before inserting into `NSCache`, then clear reloadable decoded images on memory warning/background. [VERIFIED: CodeGraph `CachedAsyncImage`; CITED: https://developer.apple.com/documentation/uikit/uiimage/preparingthumbnail%28of:%29]

**When to use:** `TrackRow` thumbnails, mini-player artwork, and full-player preview images. [VERIFIED: CodeGraph `TrackRow`, `RootView`]

**Example:**

```swift
// Source: UIKit thumbnail preparation and NSCache docs.
// [CITED: https://developer.apple.com/documentation/uikit/uiimage/preparingthumbnail%28of:%29]
// [CITED: https://developer.apple.com/documentation/foundation/nscache/removeallobjects%28%29]
private static func downsample(_ data: Data, targetSize: CGSize, scale: CGFloat) async -> UIImage? {
    await Task.detached(priority: .utility) {
        UIImage(data: data)?.preparingThumbnail(
            of: CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        )
    }.value
}

@MainActor
func removeReloadableImages() {
    cache.removeAllObjects()
}
```

### Anti-Patterns to Avoid

- **Awaiting enrichment before `playImmediately`:** This violates D-02 and would make lyrics/artwork/MV/recommendations part of first sound. [VERIFIED: 01-CONTEXT.md]
- **Retaining `debouncedSearch()` on query change:** This violates D-07 because normal typing can trigger Bilibili network requests. [VERIFIED: CodeGraph `SearchView`; VERIFIED: 01-CONTEXT.md]
- **Clearing Home `tracks` before a refresh succeeds:** This causes visible flashing/reset and violates RECO-01. [VERIFIED: 01-UI-SPEC.md; VERIFIED: CodeGraph `HomeView`]
- **Adding a second image loader:** This duplicates cache/coalescing behavior and makes memory limits inconsistent. [VERIFIED: CodeGraph `CachedAsyncImage`]
- **Persisting Bilibili playurl URLs:** Stream URLs are short-lived and must stay in memory only. [VERIFIED: .planning/PROJECT.md; VERIFIED: CodeGraph `StreamResolver`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Playback state detection | Polling timers or inferred state from button taps | `AVPlayer.timeControlStatus`, `AVPlayerItem.status`, item error/failure notifications | AVFoundation already exposes playback and failure state. [CITED: https://developer.apple.com/documentation/avfoundation/avplayer/timecontrolstatus-swift.enum; CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/error] |
| Performance timing | Ad hoc console timestamps only | `Logger` plus `OSSignposter`/structured diagnostics value | Signposts can be inspected and measured by tests/Instruments. [CITED: https://developer.apple.com/documentation/os/logger; CITED: https://developer.apple.com/documentation/os/ossignposter] |
| Image downsampling | Manual bitmap resizing after full decode | `UIImage.preparingThumbnail(of:)` or ImageIO thumbnail options | Avoids retaining full-size decoded images for small list thumbnails. [CITED: https://developer.apple.com/documentation/uikit/uiimage/preparingthumbnail%28of:%29; CITED: https://developer.apple.com/documentation/imageio/kcgimagesourcethumbnailmaxpixelsize] |
| Memory cache management | Custom global arrays/dictionaries of decoded images | Existing `NSCache` wrapper with count/cost limits and `removeAllObjects` | `NSCache` already supports bounded cost/count and eviction-friendly behavior. [VERIFIED: CodeGraph `ImageMemoryCache`; CITED: https://developer.apple.com/documentation/foundation/nscache] |
| UI test fixture bootstrapping | Live Bilibili network UI tests | Existing `BILIMUSIC_UITEST_FIXTURE`, launch arguments, accessibility identifiers | Existing tests already use deterministic fixtures and stable identifiers. [VERIFIED: .planning/codebase/TESTING.md; CITED: https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/launchenvironment] |

**Key insight:** Phase 1 failures come from scheduling and ownership, not missing libraries; the plan should constrain when existing services run rather than introduce new infrastructure. [VERIFIED: .planning/codebase/CONCERNS.md]

## Common Pitfalls

### Pitfall 1: Current Track Feedback Still Waits on `startCurrent`

**What goes wrong:** The UI keeps showing a spinner/preparing state until stream resolution finishes. [VERIFIED: CodeGraph `SearchView.play`, `PlayerEngine.play`]  
**Why it happens:** `play(tracks:startAt:)` awaits `startCurrent`, and some callers clear local preparing state only after `engine.play` returns. [VERIFIED: CodeGraph `SearchView.play`]  
**How to avoid:** Plan an immediate current assignment/diagnostic checkpoint before awaiting source resolution, then test row accent/current state separately from audible playback. [VERIFIED: 01-CONTEXT.md]  
**Warning signs:** Tests assert only final `.playing` state and miss the immediate visual current-track state. [VERIFIED: 01-CONTEXT.md]

### Pitfall 2: Prepared Stream Retry Happens at the Wrong Layer

**What goes wrong:** A stale prepared URL fails inside AVPlayer, but `StreamResolver.prepareAudio` never sees an HTTP 403 because no fresh API request was made. [VERIFIED: CodeGraph `startPlayback`, `StreamResolver.cachedAudio`]  
**Why it happens:** Prepared stream reuse passes URL directly into `AVURLAsset`; retry must observe playback item failure and then invalidate resolver state. [VERIFIED: CodeGraph `startPlayback`; CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/failedtoplaytoendtimenotification]  
**How to avoid:** Track source provenance (`cache`, `preparedRemote`, `freshRemote`) and retry only `preparedRemote` once per generation. [VERIFIED: 01-CONTEXT.md]  
**Warning signs:** Retry code catches only `prepareAudio` errors but not `AVPlayerItem.status == .failed`. [CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/status-swift.enum/failed]

### Pitfall 3: Search Focus Path Looks Local but Typing Still Searches

**What goes wrong:** Focusing is cheap, but typing the first character schedules network work and can reintroduce keyboard freeze. [VERIFIED: CodeGraph `SearchView.onChange`]  
**Why it happens:** Current `SearchView` schedules `debouncedSearch()` after 450 ms when query text is non-empty. [VERIFIED: CodeGraph `SearchView`]  
**How to avoid:** Remove typing-driven search for Phase 1; preserve `onSubmit`, retry, broaden, and pagination as explicit network paths. [VERIFIED: 01-CONTEXT.md]  
**Warning signs:** A `BiliClient.search` test spy sees calls before `.onSubmit(of: .search)`. [VERIFIED: CodeGraph `BiliClient.search`]

### Pitfall 4: Home Stability Breaks Through Background Preload

**What goes wrong:** Home rows visually reset or image/network work competes with first playback even if playback tap does not call `HomeView.load()`. [VERIFIED: CodeGraph `HomeView.load`, `engine.preload`]  
**Why it happens:** Home loading/preloading and recommendation snapshots can run near app launch and use network/main-actor resources. [VERIFIED: CodeGraph `HomeView`, `RecommendationEngine.makeSnapshot`]  
**How to avoid:** Keep visible `tracks` until refresh succeeds, avoid playback-triggered refresh, and make recommendation/image preload cancellable/lower priority. [VERIFIED: 01-UI-SPEC.md]  
**Warning signs:** First playback changes `homeTrackRow0` identity or clears `homeList` in fixture UI tests. [VERIFIED: .planning/codebase/TESTING.md]

### Pitfall 5: `NSCache` Limits Do Not Prevent Full-Size Decode Cost

**What goes wrong:** Memory spikes during list scroll before cache eviction can help because full-size images are decoded first. [VERIFIED: CodeGraph `CachedAsyncImage`]  
**Why it happens:** `UIImage(data:)` creates a decoded image without target-size constraints. [VERIFIED: CodeGraph `ImageLoadCoordinator.image`]  
**How to avoid:** Downsample/prep thumbnails before inserting into `ImageMemoryCache`, and clear reloadable images on memory warning/background. [CITED: https://developer.apple.com/documentation/uikit/uiimage/preparingthumbnail%28of:%29; CITED: https://developer.apple.com/documentation/uikit/uiapplication/didenterbackgroundnotification]  
**Warning signs:** Cache cost limit exists, but tests cannot prove target image cost is near rendered size. [VERIFIED: CodeGraph `ImageMemoryCache.memoryCost`]

## Code Examples

Verified patterns from project code and official sources:

### Playback Checkpoint Shape

```swift
// Source: project Logger pattern + OSSignposter docs.
// [VERIFIED: CodeGraph `StreamResolver` Logger usage]
// [CITED: https://developer.apple.com/documentation/os/ossignposter]
enum PlaybackCheckpoint: String, Equatable {
    case tap
    case currentAssigned
    case sourceResolved
    case itemCreated
    case playRequested
    case firstPlaying
    case failed
}

struct PlaybackDiagnosticEvent: Equatable {
    let checkpoint: PlaybackCheckpoint
    let bvid: String?
    let generation: UUID
    let millisecondsSinceTap: Double
}
```

### Prepared Remote Retry Guard

```swift
// Source: AVPlayerItem failure docs + current StreamResolver invalidation.
// [CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/error]
// [VERIFIED: CodeGraph `StreamResolver.invalidateAudio`]
private struct PlaybackSource {
    enum Kind { case localCache, preparedRemote, freshRemote }
    let kind: Kind
    let url: URL
    let track: Track
}

@MainActor
private func handleItemFailure(source: PlaybackSource, generation: UUID) async {
    guard source.kind == .preparedRemote,
          playbackGeneration == generation,
          !retriedPreparedStreamGenerations.contains(generation) else {
        state = .failed(player?.currentItem?.error?.localizedDescription ?? "播放失败")
        return
    }
    retriedPreparedStreamGenerations.insert(generation)
    streamResolver.invalidateAudio(for: source.track)
    await startCurrent()
}
```

### Search Focus Test Spy

```swift
// Source: XCTest async/MainActor pattern from existing tests.
// [VERIFIED: BiliMusicTests/SearchModelsTests.swift]
@MainActor
func testQueryChangeDoesNotSubmitSearch() {
    let store = SearchStore()

    store.queryDidChange("晴")

    XCTAssertFalse(store.searching)
    XCTAssertTrue(store.results.isEmpty)
}
```

### Image Cache Memory Release Hook

```swift
// Source: UIKit memory-warning and NSCache docs.
// [CITED: https://developer.apple.com/documentation/uikit/uiapplication/didreceivememorywarningnotification]
// [CITED: https://developer.apple.com/documentation/foundation/nscache/removeallobjects%28%29]
.onReceive(NotificationCenter.default.publisher(
    for: UIApplication.didReceiveMemoryWarningNotification
)) { _ in
    ImageMemoryCache.shared.removeReloadableImages()
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Console-only timing | `Logger` + `OSSignposter` + optional `XCTOSSignpostMetric` | Apple OSLog/XCTest APIs are available in current SDK docs. [CITED: https://developer.apple.com/documentation/os/ossignposter; CITED: https://developer.apple.com/documentation/xctest/xctossignpostmetric] | Planner can require measurable tap-to-play checkpoints, not subjective feel. |
| Full-size `UIImage(data:)` decode | Target-size `UIImage.preparingThumbnail(of:)` or ImageIO thumbnail options | UIKit/ImageIO docs expose thumbnail preparation APIs. [CITED: https://developer.apple.com/documentation/uikit/uiimage/preparingthumbnail%28of:%29; CITED: https://developer.apple.com/documentation/imageio/kcgimagesourcethumbnailfromimagealways] | Planner can bound decoded image cost for list/player thumbnails. |
| Network search during typing | Explicit `.onSubmit(of: .search)` search | SwiftUI `.searchable` supports suggestions and completions separate from submit behavior. [CITED: https://developer.apple.com/documentation/swiftui/view/searchable%28text:placement:prompt:suggestions:%29] | Planner can satisfy SRCH-01/SRCH-02 without new UI components. |
| Hidden AVPlayer failures | Observe `AVPlayerItem.status`, `error`, and failure notifications | AVFoundation docs expose item status/error and failure notification. [CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/status-swift.enum; CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/failedtoplaytoendtimenotification] | Planner can place prepared-stream retry where failures actually surface. |

**Deprecated/outdated:**
- **Persisted remote playurl:** Treat as invalid for this app because Bilibili stream URLs are short-lived and current code keeps them memory-only. [VERIFIED: .planning/PROJECT.md; VERIFIED: CodeGraph `StreamResolver`]
- **Live-network UI tests for Phase 1 regressions:** Avoid because existing test architecture uses fixture mode and launch environment for deterministic UI behavior. [VERIFIED: .planning/codebase/TESTING.md]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | AVPlayer prepared-stream expiry will surface through item failure/status/error paths often enough to trigger one retry. [ASSUMED] | Phase Requirements, Pattern 2, Pitfall 2 | If Bilibili CDN expiry instead stalls without failure, planner must add timeout/access-log based stale detection in addition to item failure observers. |
| A2 | Phase 1 can add small protocols/collaborators around `PlayerEngine` without a broad dependency-injection rewrite. [ASSUMED] | Summary, Recommended Project Structure | If current uncommitted source makes injection difficult, planner should create narrower test-only hooks instead of refactoring `PlayerEngine` broadly. |

## Open Questions

1. **What exact tap-to-first-play threshold should become the regression budget?**
   - What we know: Phase 1 requires checkpoints and fast first sound, but no numeric SLA is locked. [VERIFIED: 01-CONTEXT.md]
   - What's unclear: The acceptable baseline on the user's real iPhone and Bilibili network is not documented. [ASSUMED]
   - Recommendation: Plan a baseline measurement task before enforcing a numeric threshold; initially assert ordering rather than milliseconds. [VERIFIED: 01-CONTEXT.md]

2. **Will expired prepared URLs fail synchronously enough for item-status retry?**
   - What we know: `AVPlayerItem.status.failed`, `error`, and failure notification exist; prepared URL reuse bypasses `BiliClient.audioStream`. [CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/status-swift.enum/failed; VERIFIED: CodeGraph `startCurrent`]
   - What's unclear: Bilibili CDN behavior for an expired prepared URL may be failure, stall, or access-log error depending on CDN response. [ASSUMED]
   - Recommendation: Plan one manual/autoplay verification using a deliberately invalidated prepared URL or forced stale fixture. [VERIFIED: .planning/codebase/TESTING.md]

3. **Should Home initial load be deferred during first app launch?**
   - What we know: `HomeView.task` loads recommendations when `tracks` is empty, and Phase 1 forbids recommendation work competing with first playback. [VERIFIED: CodeGraph `HomeView.load`; VERIFIED: 01-CONTEXT.md]
   - What's unclear: Whether app launch should show cached/stale Home rows before async refresh is not locked. [ASSUMED]
   - Recommendation: Plan the narrowest stable behavior: never clear visible rows, and do not auto-refresh as a side effect of first playback; defer broader Home startup policy to Phase 2 if needed. [VERIFIED: 01-UI-SPEC.md]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Xcode / `xcodebuild` | Build, XCTest, XCUITest | yes | Xcode 26.3, build 17C529 | None for iOS build. [VERIFIED: `xcodebuild -version`] |
| Swift toolchain | Compile app/tests | yes | Apple Swift 6.2.4; project setting Swift 5.10 | Use project setting through Xcode build. [VERIFIED: `swift --version`; VERIFIED: project.yml] |
| XcodeGen | Regenerate project | yes | 2.45.4 | Existing `.xcodeproj` can build if project.yml unchanged. [VERIFIED: `xcodegen --version`] |
| iOS Simulator | UI tests | yes | iPhone 17 booted; iPhone 16e available | Update destination from documented `iPhone 16` to installed simulator if needed. [VERIFIED: `xcrun simctl list devices available`] |
| Python 3 | Manual Bilibili verification scripts | yes | 3.12.7 | Skip scripts for pure unit/UI work. [VERIFIED: `python3 --version`] |
| CodeGraph | Source inspection | yes | CLI 1.0.1; `.codegraph/` present | Use raw reads only if CodeGraph reports stale/missing data. [VERIFIED: `codegraph --version`; VERIFIED: AGENTS.md] |
| fast-context MCP | Semantic source search | no | Missing Windsurf API key | CodeGraph was used as fallback. [VERIFIED: `mcp__fast_context__fast_context_search` error] |

**Missing dependencies with no fallback:**
- None for research/planning. [VERIFIED: environment audit]

**Missing dependencies with fallback:**
- fast-context MCP is unavailable because `WINDSURF_API_KEY` is not configured; CodeGraph provided source context. [VERIFIED: fast-context tool error; VERIFIED: CodeGraph queries]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest + XCUITest from Xcode 26.3. [VERIFIED: .planning/codebase/TESTING.md; VERIFIED: `xcodebuild -version`] |
| Config file | `project.yml`; generated `BiliMusic.xcodeproj`. [VERIFIED: project.yml] |
| Quick run command | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -target BiliMusicTests -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO` [VERIFIED: .planning/codebase/TESTING.md] |
| Full suite command | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO` [VERIFIED: installed simulator audit; VERIFIED: .planning/codebase/TESTING.md] |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| PLAY-01 | Current track visible immediately after tap/current assignment. | unit + UI fixture | Quick unit target plus UI fixture row assertion. | ❌ Wave 0 `PlaybackCriticalPathTests.swift`; extend `PlayerChromeUITests.swift`. [VERIFIED: test file audit] |
| PLAY-02 | Source resolution blocks only on cache/prepared/fresh audio. | unit | Quick unit target. | ❌ Wave 0 `PlaybackCriticalPathTests.swift`. [VERIFIED: test file audit] |
| PLAY-03 | Diagnostics include ordered checkpoints. | unit/performance | Quick unit target; optional `XCTOSSignpostMetric`. | ❌ Wave 0 `PlaybackDiagnosticsTests.swift`. [CITED: https://developer.apple.com/documentation/xctest/xctossignpostmetric] |
| PLAY-04 | Prepared stream invalidates and retries once on failure. | unit with fake resolver/player item seam | Quick unit target. | ❌ Wave 0 `PreparedStreamRetryTests.swift`. [VERIFIED: CodeGraph `StreamResolver`] |
| PLAY-05 | Enrichment not awaited before playback request. | unit | Quick unit target. | ❌ Wave 0 `PlaybackCriticalPathTests.swift`. [VERIFIED: CodeGraph `schedulePostPlaybackWork`] |
| SRCH-01 | Focus/typing do not call Bilibili search. | unit | Quick unit target. | ⚠️ Existing `SearchModelsTests.swift`; add focused tests. [VERIFIED: BiliMusicTests/SearchModelsTests.swift] |
| SRCH-02 | Empty focus shows history/recent/cache local suggestions. | unit + UI fixture | Quick unit target; UI fixture search tab. | ❌ Wave 0 `SearchFocusTests.swift`; extend `PlayerChromeUITests.swift`. [VERIFIED: CodeGraph `SearchView`] |
| RECO-01 | First playback does not clear/replace Home rows. | XCUITest fixture | Full suite command with fixture mode. | ⚠️ Existing `PlayerChromeUITests.swift`; add Home stability test. [VERIFIED: .planning/codebase/TESTING.md] |
| RECO-04 | Recommendation work is explicit/lower priority and bounded. | unit | Quick unit target with fake recommendation worker. | ❌ Wave 0 `RecommendationSchedulingTests.swift`. [VERIFIED: CodeGraph `RecommendationEngine`] |
| MEM-01 | Images are downsampled before cache insertion. | unit | Quick unit target. | ❌ Wave 0 `ImageCacheTests.swift`. [VERIFIED: CodeGraph `CachedAsyncImage`] |
| MEM-02 | Duplicate URL work coalesces and cache stays bounded. | unit | Quick unit target. | ❌ Wave 0 `ImageCacheTests.swift`. [VERIFIED: CodeGraph `ImageLoadCoordinator`] |
| MEM-03 | Memory warning/background clears reloadable images but keeps playback state. | unit + UI smoke | Quick unit target; fixture UI smoke. | ❌ Wave 0 `ImageCacheTests.swift`. [CITED: https://developer.apple.com/documentation/uikit/uiapplication/didreceivememorywarningnotification] |

### Sampling Rate

- **Per task commit:** Run the quick unit command. [VERIFIED: .planning/codebase/TESTING.md]
- **Per wave merge:** Run the full suite command with an installed simulator destination. [VERIFIED: simulator audit]
- **Phase gate:** Full suite green, plus manual/autoplay playback verification for real Bilibili stream behavior. [VERIFIED: .planning/codebase/TESTING.md]

### Wave 0 Gaps

- [ ] `BiliMusicTests/PlaybackCriticalPathTests.swift` — covers PLAY-01, PLAY-02, PLAY-05. [VERIFIED: test file audit]
- [ ] `BiliMusicTests/PlaybackDiagnosticsTests.swift` — covers PLAY-03. [VERIFIED: test file audit]
- [ ] `BiliMusicTests/PreparedStreamRetryTests.swift` — covers PLAY-04. [VERIFIED: test file audit]
- [ ] `BiliMusicTests/SearchFocusTests.swift` or focused additions to `SearchModelsTests.swift` — covers SRCH-01, SRCH-02. [VERIFIED: test file audit]
- [ ] `BiliMusicTests/ImageCacheTests.swift` — covers MEM-01, MEM-02, MEM-03. [VERIFIED: test file audit]
- [ ] `BiliMusicUITests/PlayerChromeUITests.swift` extension — covers RECO-01 fixture Home stability. [VERIFIED: BiliMusicUITests/PlayerChromeUITests.swift]
- [ ] Test seams for `PlayerEngine` source resolution, diagnostics sink, and image cache cleanup; existing singleton-coupled code limits direct unit tests. [VERIFIED: .planning/codebase/CONCERNS.md]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | Limited | Do not expand cookie/auth handling in Phase 1; never log Cookie or auth headers in diagnostics. [VERIFIED: .planning/STATE.md; VERIFIED: .planning/codebase/CONCERNS.md] |
| V3 Session Management | Limited | Preserve Keychain-backed Cookie boundary; prepared stream retry should not persist auth-bearing URLs. [VERIFIED: .planning/PROJECT.md; VERIFIED: CodeGraph `CookieStore`, `StreamResolver`] |
| V4 Access Control | No | Phase 1 has no multi-user authorization model. [VERIFIED: .planning/PROJECT.md] |
| V5 Input Validation | Yes | Keep Bilibili network requests behind `BiliClient`; validate URL construction and avoid search network on focus/typing. [VERIFIED: CodeGraph `BiliClient`, `SearchView`] |
| V6 Cryptography | No | Do not hand-roll crypto; WBI signing stays in existing `WBISigner` boundary and is not broadened in Phase 1. [VERIFIED: .planning/codebase/ARCHITECTURE.md] |

### Known Threat Patterns for SwiftUI/AVFoundation/Bilibili Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Cookie or private stream URL leakage in diagnostics | Information Disclosure | Redact headers and URLs; log bvid/cid/source kind/checkpoint only. [VERIFIED: .planning/codebase/CONCERNS.md] |
| Persisting short-lived media URLs | Tampering/DoS | Persist only bvid/cid/cache files; keep playurl memory-only. [VERIFIED: .planning/PROJECT.md; VERIFIED: CodeGraph `StreamResolver`] |
| API-returned URL with privileged headers | Information Disclosure | Do not expand header/cookie forwarding in Phase 1; keep image/media request headers scoped to existing `BiliClient.headers` behavior. [VERIFIED: .planning/codebase/CONCERNS.md; VERIFIED: CodeGraph `CachedAsyncImage`] |
| Search focus causing unintended network calls | Privacy/Information Disclosure | Network starts only on explicit submit/retry/broaden/load-more. [VERIFIED: 01-CONTEXT.md; VERIFIED: CodeGraph `SearchView`] |

## Sources

### Primary (Project-Local Verification)

- `AGENTS.md` - project constraints, CodeGraph rule, Phase 1 focus. [VERIFIED: AGENTS.md]
- `.planning/phases/01-playback-critical-path-and-responsiveness/01-CONTEXT.md` - locked implementation decisions. [VERIFIED: 01-CONTEXT.md]
- `.planning/phases/01-playback-critical-path-and-responsiveness/01-UI-SPEC.md` - approved UI-visible constraints. [VERIFIED: 01-UI-SPEC.md]
- `.planning/PROJECT.md`, `.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md` - scope, phase requirements, and deferred boundaries. [VERIFIED: planning docs]
- `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/CONCERNS.md`, `.planning/codebase/TESTING.md` - architecture map, risks, and test patterns. [VERIFIED: codebase docs]
- CodeGraph queries for `PlayerEngine`, `StreamResolver`, `SearchView`, `HomeView`, `RecommendationEngine`, `CachedAsyncImage`, `PlaybackHistoryStore`, and tests. [VERIFIED: CodeGraph]

### Official Documentation (MEDIUM confidence via websearch verification)

- Apple AVFoundation `AVPlayer.timeControlStatus` - playback state observation. [CITED: https://developer.apple.com/documentation/avfoundation/avplayer/timecontrolstatus-swift.enum]
- Apple AVFoundation `AVPlayerItem.status`, `.failed`, `error`, and failed-to-play notification - item failure/retry detection. [CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/status-swift.enum; CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/status-swift.enum/failed; CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/error; CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/failedtoplaytoendtimenotification]
- Apple OSLog `Logger` and `OSSignposter`; XCTest `XCTOSSignpostMetric`. [CITED: https://developer.apple.com/documentation/os/logger; CITED: https://developer.apple.com/documentation/os/ossignposter; CITED: https://developer.apple.com/documentation/xctest/xctossignpostmetric]
- Apple SwiftUI `.searchable`, `.searchCompletion`, and `.searchScopes`. [CITED: https://developer.apple.com/documentation/swiftui/view/searchable%28text:placement:prompt:suggestions:%29; CITED: https://developer.apple.com/documentation/swiftui/view/searchcompletion%28_%3A%29; CITED: https://developer.apple.com/documentation/swiftui/view/searchscopes%28_:activation:_%3A%29]
- Apple UIKit/ImageIO/Foundation image and cache APIs. [CITED: https://developer.apple.com/documentation/uikit/uiimage/preparingthumbnail%28of:%29; CITED: https://developer.apple.com/documentation/imageio/kcgimagesourcecreatethumbnailfromimagealways; CITED: https://developer.apple.com/documentation/imageio/kcgimagesourcethumbnailmaxpixelsize; CITED: https://developer.apple.com/documentation/foundation/nscache]
- Apple UIKit/SwiftUI app lifecycle notifications and scene phase. [CITED: https://developer.apple.com/documentation/uikit/uiapplication/didreceivememorywarningnotification; CITED: https://developer.apple.com/documentation/uikit/uiapplication/didenterbackgroundnotification; CITED: https://developer.apple.com/documentation/swiftui/scenephase]
- Apple XCUITest and SwiftUI accessibility docs. [CITED: https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/launchenvironment; CITED: https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/launcharguments; CITED: https://developer.apple.com/documentation/xcuiautomation/xcuielement/waitforexistence(timeout:); CITED: https://developer.apple.com/documentation/swiftui/view/accessibilityidentifier%28_%3A%29]
- Swift concurrency docs and TaskPriority. [CITED: https://developer.apple.com/documentation/swift/taskpriority; CITED: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/]

### Tertiary (LOW confidence)

- Context7 Apple Developer Documentation query returned noisy/non-actionable AVFoundation results; not used for final technical claims. [VERIFIED: Context7 query output]
- Assumptions A1-A2 are marked explicitly in the Assumptions Log. [ASSUMED]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - verified from project config, local tools, and official Apple docs; no new packages. [VERIFIED: project.yml; VERIFIED: command output]
- Architecture: HIGH - verified from CodeGraph current on-disk source and project codebase docs. [VERIFIED: CodeGraph; VERIFIED: .planning/codebase/ARCHITECTURE.md]
- Pitfalls: MEDIUM - codebase risks are verified, but AVPlayer expired-CDN failure shape still needs manual/fixture confirmation. [VERIFIED: CodeGraph; ASSUMED]

**Research date:** 2026-06-26  
**Valid until:** 2026-07-26 for project-local architecture; 2026-07-03 for Apple API details and simulator/tooling assumptions. [ASSUMED]
