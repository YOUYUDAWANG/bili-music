# Phase 3: Player Interaction and Regression Coverage - Context

**Gathered:** 2026-06-27
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase makes the daily player feel like a native Apple Music-style music player: a denser full-screen Now Playing layout, a finger-tracked mini-player expansion, deliberate full-player minimization, left/right player pages for queue and recommendations, and regression checks for the critical gestures and behavior added in v1.

The phase does not add new music-library capabilities, rewrite Bilibili API/auth/cache layers, or pull v2 player-feature work into scope except where a narrow control or layout decision is required for the player interaction surface.

</domain>

<decisions>
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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Scope

- `.planning/PROJECT.md` — Product identity, core value, Apple Music direction, active requirements, and boundaries.
- `.planning/REQUIREMENTS.md` — Phase 3 requirement IDs: `PLYR-01`, `PLYR-02`, `PLYR-03`, `PLYR-04`, `PLYR-05`, `TEST-02`, and `TEST-05`.
- `.planning/ROADMAP.md` — Phase 3 goal, success criteria, and v2 boundary.
- `.planning/STATE.md` — Current phase and accumulated Phase 1/2 decisions.

### Prior Phase Context

- `.planning/phases/01-playback-critical-path-and-responsiveness/01-CONTEXT.md` — Playback-first guardrails, post-start enrichment constraints, image/memory responsiveness decisions.
- `.planning/phases/02-discovery-reliability-and-music-only-results/02-CONTEXT.md` — Recommendation-list stability, music-only recommendation behavior, and deferred player layout decisions.

### Codebase Maps

- `.planning/codebase/CONVENTIONS.md` — SwiftUI, `@Observable`, gesture helper, UI metric, and test-hook conventions.
- `.planning/codebase/STRUCTURE.md` — Feature/player/design/test file ownership and where to add new player UI code.
- `.planning/codebase/STACK.md` — SwiftUI, AVKit, Observation, XCTest/XCUITest, and iOS deployment constraints.
- `.planning/codebase/TESTING.md` — Existing unit/UI test commands and fixture patterns.

### Source Areas

- `BiliMusic/Features/RootView.swift` — Mini-player, full-player presentation, pull-up progress, and top-level player transition.
- `BiliMusic/Features/Player/NowPlayingView.swift` — Full-screen player layout, page model, gestures, toolbar actions, lyrics/MV/favorite/cache controls.
- `BiliMusic/Features/Player/PlayerControlViews.swift` — Existing player controls that can be reused or reshaped.
- `BiliMusic/Features/Player/PlayerSheetViews.swift` — Existing lyrics/MV/playlist/favorite/download sheets and support UI.
- `BiliMusic/Player/PlayerEngine.swift` — Playback state, queue state, play mode, MV/music mode, and user actions exposed to player UI.
- `BiliMusic/Player/QueueController.swift` — Pure queue behavior for queue-page regression coverage.
- `BiliMusicUITests/PlayerChromeUITests.swift` — Existing fixture-driven UI tests for mini-player/full-player chrome and gesture guardrails.
- `BiliMusicTests/*` — Unit-test target for pure gesture/layout policy helpers and playback/recommendation regression seams.

### External Design References

- Apple Human Interface Guidelines: Motion — use motion to clarify hierarchy, respect motion sensitivity, and avoid unnecessary animation.
- Apple Human Interface Guidelines: Gestures — gestures should feel like direct manipulation and must not conflict with core scrolling.
- Apple Human Interface Guidelines: Layout — keep controls reachable, readable, and adaptive across iPhone sizes.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `RootView` already presents `NowPlayingView` as an overlay and drives `fullPlayerOpenProgress`, `fullPlayerOffset`, opacity, and scale. This is the right seam for finger-tracked mini-player expansion.
- `SystemMiniPlayer` already has a drag gesture, `MiniOpenDragSample`, matched cover geometry, opacity/scale fading, and haptic-safe controls. Extend this rather than replacing it with a new mini-player architecture.
- `PlayerGesturePolicy` already holds deterministic gesture thresholds and should remain the place for pure gesture decisions that need unit tests.
- `NowPlayingView` already has page state for queue, center Now Playing, and recommendations. Phase 3 should reshape the presentation rather than introducing a separate page model.
- `CachedAsyncImage` and `ImageMemoryCache` already support target-size image loading and cleanup, which should be used for enlarged cover art without regressing memory behavior.
- Existing player sheets and managers cover lyrics, favorites, cache/download, quality, MV, and playlists. The toolbar should wire into these existing actions instead of creating duplicate state.

### Established Patterns

- UI constants belong in private nested metric enums such as `Layout`, `Metrics`, or `Motion`.
- Gesture behavior that affects tests should be extracted into pure policy helpers.
- SwiftUI animation should be state-driven with `withAnimation` and should respect `@Environment(\.accessibilityReduceMotion)`.
- Feature-specific view decomposition should stay under `BiliMusic/Features/Player/` unless a component is genuinely cross-feature and belongs in `BiliMusic/Design/`.
- Playback startup and `PlayerEngine` core behavior should not be reorganized for visual polish. Player UI changes should call existing engine actions.

### Integration Points

- Mini-player expansion attaches to `SystemMiniPlayer.miniOpenDragGesture`, `RootView.handleMiniOpenDragChanged`, `RootView.handleMiniOpenDragEnded`, and `RootView.fullPlayerOffset`.
- Full-player minimization attaches to `NowPlayingView.dismissDrag`, `onDismiss`, and page/list gesture boundaries.
- Three-page player layout attaches to `NowPlayingView.playerPages` and related queue/recommendation page helpers.
- Toolbar changes attach to existing lyrics, favorite, cache, quality, and MV controls in `NowPlayingView` and `PlayerSheetViews`.
- Regression coverage should extend `PlayerChromeUITests` for visible gesture behavior and add/extend unit tests for pure gesture thresholds, page policy, and layout policy where possible.

</code_context>

<specifics>
## Specific Ideas

- The user explicitly wants the player to look and feel closer to Apple Music than YouTube Music, while retaining the YouTube Music-style music/MV toggle behavior.
- The player should no longer feel like a temporary overlay/status sheet. It should feel like the main music playback surface.
- The bottom of the center player should not feel empty; cover, metadata, progress, controls, and toolbar should use the screen more evenly.
- Queue is the left page, recommendations are the right page, and the center page stays focused on playback.
- Page indicators should be light and subtle, not a heavy segmented control.
- Visual polish is important, but performance and stable playback remain higher priority than pixel-perfect Apple Music recreation.

</specifics>

<deferred>
## Deferred Ideas

- Favorite-folder long-press selection, collection queue context, typed auth errors, cache index repair, and broad API/cache hardening remain v2 unless a narrow UI hook is already available.
- Pixel-level Apple Music reproduction is explicitly not required in Phase 3.

</deferred>

---

*Phase: 3-Player Interaction and Regression Coverage*
*Context gathered: 2026-06-27*
