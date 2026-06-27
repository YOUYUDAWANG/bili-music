# Roadmap: Bilibili Music

## Overview

v1 is a vertical MVP stabilization pass for the existing brownfield SwiftUI app. It follows the daily music path from tapping a track to hearing audio, then makes discovery trustworthy, hardens the player interaction surface with regression coverage, and finishes with a narrow interface-cohesion polish pass. Broader API/auth/cache hardening stays in v2 unless it is directly required to keep v1 playback, search, recommendations, image memory, or daily UI responsiveness stable.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Playback Critical Path and Responsiveness** - First sound, first-play stability, search focus, and memory/image guardrails stop blocking the music path. Automated verification and real-device first-audible UAT passed; one CDN retry integration case is accepted residual risk. (completed 2026-06-26)
- [x] **Phase 2: Discovery Reliability and Music-Only Results** - Search and recommendations stay scoped, stable, paginated, and music-only. (completed 2026-06-27)
- [x] **Phase 3: Player Interaction and Regression Coverage** - Player gestures, layout density, and targeted regression checks protect the daily playback experience. (completed 2026-06-27)
- [x] **Phase 4: Interface Cohesion and Search Polish** - Daily UI surfaces use a calmer blue-cyan accent, search focuses into history/suggestions without mode clutter, rows are easier to tap, player toolbar spacing is rebalanced, and list-title cleaning is conservative. (completed 2026-06-27)

## Phase Details

### Phase 1: Playback Critical Path and Responsiveness

**Goal**: Users can tap a track and get responsive first playback without recommendation refreshes, search-focus freezes, or image memory work interfering with the music path.
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: PLAY-01, PLAY-02, PLAY-03, PLAY-04, PLAY-05, SRCH-01, SRCH-02, RECO-01, RECO-04, MEM-01, MEM-02, MEM-03, TEST-04
**Success Criteria** (what must be TRUE):

  1. User can tap a track after app launch and see it become current immediately, with playback requested after only cache, prepared stream, or one fresh audio stream is resolved.
  2. Tap-to-first-play diagnostics expose tap, source resolution, AVPlayer item creation, play request, and first observed playback state; expired or unauthorized prepared streams retry once without requiring another tap.
  3. User can start the first song after launch without Home recommendations flashing, resetting, or blocking first audible playback.
  4. User can enter Search and focus an empty search field with local history and suggestions appearing without network work or a keyboard freeze.
  5. User can scroll image-heavy search, recommendation, and player surfaces, then background the app, without unbounded image retention or memory cleanup interrupting playback state.
  6. Developer can run checks covering mini-player expansion, full-player minimization, and list-area drags that should not dismiss the player.

**Plans**: 5/5 plans executed
**Verification**: Automated simulator suite passed with player gesture guardrails; `01-UAT.md` tracks two real-device/CDN checks.

- [x] 01-01-PLAN.md
- [x] 01-02-PLAN.md
- [x] 01-03-PLAN.md
- [x] 01-04-PLAN.md
- [x] 01-05-PLAN.md

**UI hint**: yes

### Phase 2: Discovery Reliability and Music-Only Results

**Goal**: Users can search, paginate, and use Home or Now Playing recommendations without stale results, refresh collisions, or non-music content polluting the default music surfaces.
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: SRCH-03, SRCH-04, SRCH-05, RECO-02, RECO-03, RECO-05
**Success Criteria** (what must be TRUE):

  1. User can submit searches and only see results belonging to the active query and search mode; stale results from older work never appear in the current list.
  2. User can load more search results and keep existing results if a later page fails, while every appended page remains music-filtered.
  3. User can tap a track from the player recommendation list without the visible list immediately refreshing, scrambling, or clearing.
  4. Home recommendations and Now Playing related recommendations maintain separate refresh state and apply the same music-only filtering principles across their sources.

**Plans**: 1/1 plan executed
**Verification**: Search and recommendation focused unit tests passed; player chrome UI tests passed.

- [x] 02-01-PLAN.md

**UI hint**: yes

### Phase 3: Player Interaction and Regression Coverage

**Goal**: Users can interact with a denser Apple Music-like player confidently, while regression checks cover the critical playback, search, recommendation, gesture, and image-memory behavior added in v1.
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: PLYR-01, PLYR-02, PLYR-03, PLYR-04, PLYR-05, TEST-01, TEST-02, TEST-03, TEST-05
**Success Criteria** (what must be TRUE):

  1. User can expand the mini-player with an upward drag that tracks the finger and minimize the full player only with a deliberate downward gesture outside scrollable lists.
  2. User can scroll queue and recommendation lists, scrub progress, and swipe between player pages without accidental dismissal or gesture conflicts.
  3. User sees a denser Apple Music-like full-player layout on supported iPhone sizes, with no excessive bottom void around cover art, progress, controls, lyrics entry, queue, or recommendation pages.
  4. A developer can run regression checks that pass for search query identity, mode identity, pagination, stale-result rejection, music-only filtering, playback enrichment ordering, recommendation refresh stability, and player chrome gestures.
  5. A developer can run at least one regression check proving bounded image work or memory-pressure cleanup remains in place.

**Plans**: 3/3 plans executed
**Verification**: Compact and modern player chrome UI suites passed; preserved search, playback critical path, recommendation scheduling, image-cache, and gesture policy regressions passed.

- [x] 03-01-PLAN.md — Mini-player pull-up transition and guardrails
- [x] 03-02-PLAN.md — Dense Apple Music-like player layout, toolbar, and pages
- [x] 03-03-PLAN.md — Region-aware gesture conflicts and preserved regressions

**UI hint**: yes

### Phase 4: Interface Cohesion and Search Polish

**Goal**: Users see a more cohesive Apple Music-like daily interface without the previous pink accent, search-mode clutter, hard-to-tap search rows, or overly aggressive cleaned titles.
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: UI-01 partial, SRCH-01, SRCH-02, SRCH-05, PLYR-05
**Success Criteria** (what must be TRUE):

  1. Search focus shows local history/empty-history affordance and does not expose Music/MV/expanded scope chips.
  2. Search result rows combine best match and music results into a single tappable music surface, with larger row hit areas and no separate MV search mode.
  3. Shared row/card styling, selected states, and fallback player color use the calmer Bilibili blue-cyan accent rather than pink.
  4. Player toolbar keeps the compact Apple Music-like action group while preserving the dense-layout bottom-gap regression gate.
  5. List-title cleaning only changes display text for high-confidence structured titles, while lyrics matching can still use broader parsing internally.

**Plans**: 1/1 plan executed
**Verification**: Search/title unit tests, player gesture policy tests, full player chrome UI suite, hygiene checks, and simulator build passed.

- [x] 04-01-PLAN.md — Interface cohesion, search focus polish, toolbar spacing, and conservative display-title cleaning

**UI hint**: yes

## Coverage Validation

- v1 requirements mapped: 28/28
- Orphaned requirements: 0
- Duplicate phase mappings: 0
- v2 boundary: API/auth/cache broad hardening remains deferred unless a v1 stability fix directly needs a narrow change.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Playback Critical Path and Responsiveness | 5/5 | Complete    | 2026-06-26 |
| 2. Discovery Reliability and Music-Only Results | 1/1 | Complete    | 2026-06-27 |
| 3. Player Interaction and Regression Coverage | 3/3 | Complete    | 2026-06-27 |
| 4. Interface Cohesion and Search Polish | 1/1 | Complete    | 2026-06-27 |
