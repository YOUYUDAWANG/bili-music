# Roadmap: Bilibili Music

## Overview

v1 is a vertical MVP stabilization pass for the existing brownfield SwiftUI app. It follows the daily music path from tapping a track to hearing audio, then makes discovery trustworthy, then hardens the player interaction surface with regression coverage. Broader API/auth/cache hardening stays in v2 unless it is directly required to keep v1 playback, search, recommendations, or image memory behavior stable.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Playback Critical Path and Responsiveness** - First sound, first-play stability, search focus, and memory/image guardrails stop blocking the music path. Automated verification passed; human UAT pending. (completed 2026-06-26)
- [ ] **Phase 2: Discovery Reliability and Music-Only Results** - Search and recommendations stay scoped, stable, paginated, and music-only.
- [ ] **Phase 3: Player Interaction and Regression Coverage** - Player gestures, layout density, and targeted regression checks protect the daily playback experience.

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

**Plans**: TBD
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

**Plans**: TBD
**UI hint**: yes

## Coverage Validation

- v1 requirements mapped: 28/28
- Orphaned requirements: 0
- Duplicate phase mappings: 0
- v2 boundary: API/auth/cache broad hardening remains deferred unless a v1 stability fix directly needs a narrow change.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Playback Critical Path and Responsiveness | 5/5 | Complete    | 2026-06-26 |
| 2. Discovery Reliability and Music-Only Results | 0/TBD | Not started | - |
| 3. Player Interaction and Regression Coverage | 0/TBD | Not started | - |
