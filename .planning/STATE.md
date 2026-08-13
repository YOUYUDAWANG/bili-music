---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 4
current_phase_name: Interface Cohesion and Search Polish
status: complete
stopped_at: Completed 04-01-PLAN.md
last_updated: "2026-07-25T00:00:00Z"
last_activity: 2026-07-25
last_activity_desc: Completed post-milestone deep stability review and P1 hardening
progress:
  total_phases: 4
  completed_phases: 4
  total_plans: 10
  completed_plans: 10
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-27)

**Core value:** 让音乐尽快、稳定地响起来；当功能冲突时，播放启动速度和不中断播放优先于推荐、歌词、MV、UI 动效和其他增强体验。
**Current focus:** Post-milestone stabilization audit — preserve first sound and playback correctness

## Current Position

Phase: 4 — Interface Cohesion and Search Polish
Plan: 1 of 1 — 04-01
Status: Complete
Last activity: 2026-07-25 — Completed post-milestone deep stability review and P1 hardening

Progress: [##########] 100%

## Post-Milestone Deep Review — 2026-07-25

The review kept the shipped interaction model intact and concentrated on state races, stale async work,
track identity, persistence ordering, and memory bounds.

### P1 risks closed

- Explicit track selection invalidates pending direct-play and radio requests before they can write back.
- Radio lookup, pause/resume, previous-track, mode changes, and late recommendation responses preserve the
  latest transport intent instead of restarting an ended player item.
- Automatic queue advancement inherits a late pause, so an end notification cannot unexpectedly resume audio.
- AVPlayer time/status/buffer/end/failure callbacks validate playback generation plus player/item identity.
- Slow-start CDN fallback and item-failure recovery no longer replace the same playback source concurrently.
- A corrupt local cache invalidates the matching prepared stream before retrying a fresh remote URL.
- Progress scrubbing is bound to the track that began the gesture; a stale release cannot seek a new song.
- Cache, playback history, and recent-home persistence use revisioned atomic writes and merge mutations made
  during their initial disk load.
- Search, favorites, Home recommendations, related recommendations, and playlist lookup reject stale responses.
- Track, stream, cache, history, queue, and prefetch identity is exact to `bvid + cid` once cid is known.
- Shared row haptics are attached once per screen rather than once per visible row.

### Remaining P2 work

- Split `PlayerEngine`, `NowPlayingView`, and `BiliClient` only in a dedicated phase with real-device gates.
- Add versioned persistence envelopes, corrupt-file quarantine, cache orphan repair, disk quota, and LRU eviction.
- Add a shared authentication-expiry state instead of waiting for a protected request to reveal stale cookies.
- Replace broad ATS allowance after real Bilibili CDN host/scheme capture.
- Make initial search results incremental instead of waiting for all first-batch pages.
- Resolve Swift 6 strict-concurrency warnings before changing the project language mode.
- Validate Dolby response schema and full-screen DASH MV support against real API samples before exposing them
  as guaranteed quality paths.

### Verification

- Generic iOS device `xcodebuild` completed successfully with code signing disabled.
- The app target and all test sources passed direct Swift typechecking; no simulator or real-device UI run was
  performed during this audit.

## Performance Metrics

**Velocity:**

- Total plans completed: 12
- Average duration: 13 min
- Total execution time: 1.30 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Playback Critical Path and Responsiveness | 5 | 65 min | 13 min |
| 2. Discovery Reliability and Music-Only Results | 1 | 13 min | 13 min |
| 3. Player Interaction and Regression Coverage | 3 planned | - | - |
| 4. Interface Cohesion and Search Polish | 1 | 30 min | 30 min |
| 01 | 5 | - | - |

**Recent Trend:**

- Last 5 plans: 01-02, 01-03, 01-04, 01-05, 02-01
- Trend: Playback, search focus, Home recommendation stability, image memory guardrails, and discovery reliability complete

*Updated after each plan completion*
| Phase 03-player-interaction-and-regression-coverage P01 | 35min | 3 tasks | 5 files |
| Phase 03-player-interaction-and-regression-coverage P02 | 10min | 3 tasks | 3 files |
| Phase 03-player-interaction-and-regression-coverage P03 | 30min | 3 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v1]: Project mode is MVP; phases are vertical stabilization slices rather than broad subsystem rewrites.
- [v1]: Phase 1 prioritizes first sound, first-play recommendation stability, search focus responsiveness, and memory/image guardrails.
- [v1]: Broader API/auth/cache hardening stays in v2 unless a narrow change is required for v1 stability.
- [01-02]: First playback now assigns current before awaited source resolution and reaches AVPlayer through cache, prepared audio, or one fresh stream only.
- [01-02]: Prepared remote audio failure invalidates matching/fallback resolver entries and retries one fresh stream without a second user tap.
- [01-03]: Search focus and typing stay local; Bilibili search starts from explicit submit, retry, broaden, or pagination only.
- [01-03]: Empty search can render local history suggestions, recent playback, and cached songs without remote work.
- [01-04]: Home recommendation work now starts from explicit Home load/manual refresh triggers with bounded seed/request limits.
- [01-04]: Home recommendation scoring and fan-out run at utility priority while radio and related-panel recommendations keep interactive priority.
- [01-05]: Image cache and in-flight image loading are keyed by URL plus target pixel size and downsample remote bytes before decoded images enter memory.
- [01-05]: Backgrounding and memory warnings release reloadable decoded images through AppResourceCleanup without clearing PlayerEngine current track or queue.
- [01-06]: Historical custom player gesture thresholds were covered by unit and player chrome UI tests before LNPopup replaced that transition path.
- [02-01]: Search result application is scoped by request identity, query, and mode; stale first-page or pagination work cannot replace the active visible list.
- [02-01]: Search pagination preserves existing results on later-page failure, keeps retry state available, rebuilds sections after append, and applies music-only filtering per page.
- [02-01]: Now Playing recommendation taps keep the visible recommendation list stable, mark it stale, and defer refresh until the panel is reopened unless an external visible-track change requires immediate refresh.
- [02-01]: Recommendation candidate pools apply music-only display filtering before scoring and final presentation.
- [Phase 03-01]: Mini-player pull-up completion uses deterministic policy thresholds, including distance and projected velocity, rather than view-local ad hoc gesture checks.
- [Phase 03-01]: The full-player overlay tracks rendered open progress for offset, opacity, and scale while Reduced Motion keeps scale disabled through existing guards.
- [Phase 03-01]: The UI fixture uses mini-player-relative drag coordinates to avoid simulator-global coordinate drift while preserving deliberate-open and shallow-cancel coverage.
- [Current player model]: Queue, playlist context, and current-track recommendations live in one bottom drawer; the earlier horizontal side-page navigation was removed to avoid gesture conflicts.
- [Current player model]: MV/music switching remains in the persistent toolbar and does not block initial audio playback.
- [Phase 03-player-interaction-and-regression-coverage]: Recommendation tap stability is protected by a regression assertion that suppression is assigned before related playback starts.
- [Current player model]: LNPopup owns mini/full vertical presentation; queue, playlist, and recommendation list bodies keep their own scrolling inside the bottom drawer.
- [Phase 03-03]: Progress scrub owns the full progress block, including label hit targets, so page swipes cannot steal scrub gestures.
- [Phase 03-03]: Compact and modern player chrome UI suites plus preserved search/playback/recommendation/image regressions form the v1 stabilization gate.
- [Phase 04-01]: Daily UI polish uses the calmer Bilibili blue-cyan accent instead of pink while keeping Apple Music-style structure.
- [Phase 04-01]: Search focus shows only local history or an empty-history state; visible search scopes and separate MV search mode are removed from the search chrome.
- [Phase 04-01]: Display title cleaning is conservative and only applies high-confidence structured parses; broader parsing remains available for lyrics matching.
- [Phase 04-01]: Player toolbar actions sit in one compact grouped control with a text music/MV toggle and layout spacing protected by the modern bottom-gap UI test.

### Pending Todos

- [Phase 01 UAT] Confirm real expired or unauthorized Bilibili prepared-stream retry if a reproducible CDN failure is available.

### Blockers/Concerns

- Brownfield risk: PlayerEngine and NowPlayingView are large; phase planning should keep playback-path changes scoped and regression-backed.
- Private Bilibili APIs and WBI behavior are fragile; avoid broad API restructuring during v1 unless required for a specific stability fix.
- Image decoding and unbounded request fan-out were bounded in Phase 1; keep watching this risk in Phase 2 discovery surfaces as result volume grows.
- Phase 01 automated verification passed and real iPhone first-audible playback UAT passed at approximately 1-2 seconds. The real expired/unauthorized Bilibili prepared-stream retry check is recorded in `01-UAT.md` as accepted residual risk because no reproducible live CDN failure was available. DEBUG builds mirror recent sanitized playback checkpoints into `AUTOPLAY_DIAGNOSTIC` console lines for easier real-device UAT.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260627-36w | 设置里支持音频 CDN 测速并选择默认线路 | 2026-06-26 | bff89cd | [260627-36w-cdn](./quick/260627-36w-cdn/) |

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| API/Auth | Typed status handling, cookie expiry routing, WBI fixture coverage, and API-domain client split | v2 | v1 roadmap creation |
| Cache | Cache index repair, quota/free-space policy, orphan cleanup, and download failure UX | v2 | v1 roadmap creation |
| Player/Music | Favorites folder selection, collection queue context, MV/music source switching polish, quality display, and full play-mode polish | v2 | v1 roadmap creation |

## Session Continuity

Last session: 2026-06-27T10:30:00.000Z
Stopped at: Completed 04-01-PLAN.md
Resume file: .planning/phases/04-interface-cohesion-and-search-polish/04-01-SUMMARY.md
