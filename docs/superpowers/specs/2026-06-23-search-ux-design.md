# Search UX Redesign

## Goal

Improve the search page from a raw result list into a clear music-search flow. The work should make the page feel faster, explain what is happening, and make it obvious how to play, load more, or broaden results.

The implementation will happen in two steps:

1. Phase A: low-risk interaction fixes on the current page.
2. Phase B: Apple Music-style result organization once the main flow feels stable.

## Non-Goals

- Do not add BV/link parsing back into the search bar.
- Do not replace the Bilibili search API.
- Do not introduce a database or third-party search library.
- Do not overhaul the global player UI as part of this work.

## Current Problems

- The page has only coarse states: history, spinner, results, empty. There is no useful intermediate state while typing or updating.
- Search results are a single undifferentiated list, so the best match is not obvious.
- The trailing ellipsis in `TrackRow` looks actionable but currently does nothing on the search page.
- Infinite auto-load near the bottom makes filtered search feel jumpy and hard to understand.
- Strict music filtering can produce few results, but the UI does not explain that results were narrowed.
- Repeating the same query does not show cached results first, so the page feels slower than it needs to.
- Tapping a result does not give immediate row-level feedback while playback is preparing.

## Phase A Design

Phase A keeps the existing `SearchView`, `SearchStore`, `BiliClient.search`, and `MusicFilter` shape. It changes the interaction model and state presentation without replacing the core search pipeline.

### Search States

The search page should distinguish:

- Idle: show search history plus quick entries from recent playback or cache if available.
- Typing: show matching history suggestions and a subtle prompt to submit search.
- Searching first page: keep the search field stable and show a compact loading row, not a full blank page.
- Showing results: keep results visible while loading more or refreshing.
- Empty filtered result: explain that only music results are shown and offer to broaden search.
- Error: show a retry action near the failed state.

### Result Rows

Rows should keep the existing compact `TrackRow` visual language, with two changes:

- Replace the inactive trailing ellipsis with a real menu or remove it on pages where no menu exists.
- When the user taps a result, immediately mark that row as preparing or selected until `PlayerEngine.current` updates.

The first visible result can be labeled as the best match in Phase A if it does not require a layout restructure.

### Loading More

Replace automatic bottom-triggered pagination with an explicit `加载更多` button. The button should:

- Disable while loading.
- Show inline progress.
- Append results without moving the scroll position unexpectedly.
- Offer `扩大搜索` when strict filtering returns too few items.

### Query Result Cache

Add a lightweight in-memory cache inside `SearchStore`:

- Keyed by normalized query and filter mode.
- Stores tracks, next page, active keywords, and `hasMoreResults`.
- Repeated queries should restore cached results immediately, then refresh in the background only if needed.

This cache is not persisted across app launches.

### Filter Controls

Default mode remains music-only. Phase A adds a compact filter control near the results header:

- `音乐`: default strict music search.
- `MV`: prioritize MV-like results and music video category.
- `扩大`: loosen local filtering while still avoiding obvious non-music content.

The control should not expose Bilibili implementation details such as `typeid` or `tids`.

## Phase B Design

Phase B moves toward an Apple Music-style structure after Phase A stabilizes.

### Result Organization

Search results should be organized as:

- Best Match: one prominent row for the top candidate.
- Songs: compact list of music/audio-oriented results.
- MV: compact list of music-video-oriented results.
- More from UP: optional section when several results share the same uploader.

The page should still use the same `Track` model and playback APIs. Classification can initially be heuristic and local.

### Landing Page

When the search field is empty, the page should become a useful entry point:

- Recent searches.
- Recently played songs.
- Cached songs.

This avoids an empty utility screen and makes search feel integrated with the personal library.

## Component Boundaries

- `SearchView`: renders the page and handles focus, row taps, and filter controls.
- `SearchStore`: owns query state, result cache, pagination state, and filter mode.
- `SearchResultMode`: small enum for `music`, `mv`, and `expanded`.
- `SearchResultSections`: derived grouping for Phase B. It should be computed from tracks rather than persisted.
- `TrackRow`: should either support an optional trailing action or use page-specific trailing views, so search does not display fake affordances.

## Data Flow

1. User edits query.
2. `SearchStore.queryDidChange` updates transient UI state without starting network work.
3. User submits search or taps a history suggestion.
4. `SearchStore` checks in-memory cache.
5. Cached results render immediately if present.
6. Network search runs with current mode.
7. Results are filtered, deduped, cached, and displayed.
8. Tapping a row marks it as preparing and calls `PlayerEngine.play`.
9. When `engine.current` matches the row, normal playing state takes over.

## Error Handling

- Network/API failure shows a small error block with retry.
- Empty strict results show an empty state with `扩大搜索`.
- Loading-more failure does not clear existing results; it shows an inline retry.
- If a row fails to play, keep the existing player error state, but clear the row-level preparing marker.

## Verification

Manual checks:

- First focus of search field should not freeze the UI.
- Typing a query should not clear useful suggestions into a blank page.
- Searching should preserve layout while loading.
- Result tap should show immediate feedback.
- Repeating a previous query should show cached results immediately.
- `加载更多` should append without jumping.
- Strict empty result should offer broadened search.

Build check:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

## Implementation Order

1. Phase A state model and result cache in `SearchStore`.
2. Phase A UI states and explicit load-more button in `SearchView`.
3. Row tap feedback and trailing menu cleanup.
4. Filter mode control and broadened-result fallback.
5. Phase B section derivation and best-match layout.
6. Phase B landing page additions from history/cache.
