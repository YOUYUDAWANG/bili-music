# Requirements: Bilibili Music

**Defined:** 2026-06-26  
**Core Value:** 让音乐尽快、稳定地响起来；当功能冲突时，播放启动速度和不中断播放优先于推荐、歌词、MV、UI 动效和其他增强体验。

## v1 Requirements

v1 聚焦当前用户已经反复遇到的卡顿和稳定性问题。目标不是重写整个 app，而是让日常使用路径变得快、稳、可验证。

### Playback Performance

- [x] **PLAY-01**: User can tap a track and see the selected track become current immediately, before lyrics, recommendations, MV probing, artwork loading, auto-cache, or history flush finishes.
- [x] **PLAY-02**: User can start playback through a protected critical path that resolves only cached audio, a prepared stream, or one fresh audio stream before calling AVPlayer playback.
- [x] **PLAY-03**: Playback startup records timing checkpoints for tap, source resolution, AVPlayer item creation, play request, and first observed playback state so regressions are measurable.
- [x] **PLAY-04**: Prepared remote audio streams are invalidated and retried once when they appear expired or unauthorized instead of making the user manually tap again.
- [x] **PLAY-05**: Post-start enrichment work such as lyrics, artwork, MV availability, related recommendations, queue/radio prefetch, history persistence, and auto-cache cannot block first audible playback.

### Search Responsiveness

- [x] **SRCH-01**: User can enter the Search screen and focus the search field without triggering Bilibili network requests or expensive local work on the focus path.
- [x] **SRCH-02**: User sees local search history and suggestions when the search field is focused with an empty query.
- [ ] **SRCH-03**: User can submit a search and results are scoped to the active query and search mode; stale results from older queries cannot appear in the current result list.
- [ ] **SRCH-04**: User can load more search results through pagination without losing existing results when a later page fails.
- [ ] **SRCH-05**: Search results apply music-only filtering on every page and do not mix general Bilibili videos into the default song result surface.

### Recommendation Stability

- [x] **RECO-01**: User can start the first song after app launch without causing the Home recommendation list to flash, reset, or auto-refresh.
- [ ] **RECO-02**: User can tap a track from the player recommendation list without immediately refreshing or scrambling that visible recommendation list.
- [ ] **RECO-03**: Home recommendations and Now Playing related recommendations maintain separate refresh state and do not cancel, clear, or reset each other.
- [x] **RECO-04**: Recommendation refresh work is bounded and lower priority than direct playback startup.
- [ ] **RECO-05**: Recommendation sources apply the same music-only filtering principles as Search.

### Memory and Images

- [x] **MEM-01**: User can scroll image-heavy search, recommendation, and player surfaces without full-size cover images being decoded and retained unnecessarily.
- [x] **MEM-02**: Image loading coalesces duplicate URL work and applies a bounded cache policy so repeated list scrolling does not continually grow memory.
- [x] **MEM-03**: App responds to memory pressure or backgrounding by releasing reloadable image/media data without losing playback state.

### Player Interaction

- [ ] **PLYR-01**: User can expand the mini-player with an upward drag that visually tracks the finger and feels like the full player is being pulled up from the bottom.
- [ ] **PLYR-02**: User can minimize the full player with a deliberate downward gesture outside scrollable queue/recommendation lists.
- [ ] **PLYR-03**: User can scroll queue and recommendation lists without accidentally triggering player minimize.
- [ ] **PLYR-04**: User can scrub the progress bar and swipe between player pages without those gestures fighting the minimize gesture.
- [ ] **PLYR-05**: Full player layout uses denser Apple Music-like spacing with no excessive bottom void on supported iPhone sizes.

### Regression Coverage

- [ ] **TEST-01**: Search store tests cover query identity, mode identity, pagination, stale-result rejection, and music-only filtering.
- [ ] **TEST-02**: Playback tests or instrumentation verify post-start enrichment is not awaited before the playback request.
- [ ] **TEST-03**: Recommendation tests or UI tests verify first playback does not reset Home recommendations and tapping a related track does not immediately refresh the related list.
- [ ] **TEST-04**: Player chrome UI tests cover mini-player expansion, full-player minimization, and list scrolling without accidental dismissal.
- [ ] **TEST-05**: Image/cache behavior has at least one regression check for bounded image work or memory-pressure cleanup.

## v2 Requirements

Deferred items are important, but they should not block v1 stabilization.

### API and Auth Hardening

- **API-01**: App classifies HTTP status codes before JSON decoding and surfaces typed Bilibili/API/auth/rate-limit/decode errors.
- **API-02**: App detects expired Bilibili cookies and routes the user to re-login instead of showing generic 401 interface errors.
- **API-03**: Private Bilibili API response models have fixture decode tests and WBI signing regression coverage.
- **API-04**: `BiliClient` is split into smaller API-domain clients behind one shared transport/header/cookie layer.

### Cache Reliability

- **CACH-01**: Cache index uses versioned, atomically written metadata with backup-on-corruption.
- **CACH-02**: Cache library can repair or report orphaned audio files in `Documents/audio`.
- **CACH-03**: User can view and enforce cache quota/free-space policy.
- **CACH-04**: Download failures expose actionable reasons and retry state.

### Player and Music Features

- **MUSC-01**: User can choose a default favorite folder and long-press favorite to choose another folder with clear auth-expired handling.
- **MUSC-02**: User can start a song from a Bilibili collection and see that collection as the active queue context, with the current song positioned correctly.
- **MUSC-03**: User can switch between Music and MV while preserving playback time and ensuring only one playback source is active.
- **MUSC-04**: User can view current audio quality and bitrate from the player quality control.
- **MUSC-05**: User can use play modes including sequence, shuffle, repeat queue, and repeat one with clear player state.

### Visual Polish

- **UI-01**: Full player, mini-player, search, library, favorites, and settings share a cohesive Apple Music-like visual language.
- **UI-02**: Lyrics unavailable, MV unavailable/loading, favorite, cache, download failure, and auth-expired states have distinct UI affordances.
- **UI-03**: Queue and related recommendation pages are polished as left/right player pages with stable empty/loading/error states.

## Out of Scope

| Feature | Reason |
|---------|--------|
| App Store release | This is a personal sideload app; public distribution is not part of the current project. |
| Full Bilibili client | Comments, danmaku, social feed, profiles, uploads, live, and community features are outside the music-first product. |
| Backend service | Current product should remain a local iOS app without operational backend cost. |
| Cross-platform clients | Android, macOS, Web, and CarPlay are not part of the current roadmap. |
| Social playlist sharing | Reuse Bilibili folders/collections and local queue/cache before adding any social model. |
| Bypassing Bilibili access limits | The app may use what the user's account can access, but will not promise to bypass membership, region, or rights restrictions. |
| Heavy onboarding or marketing UI | App should open into usable music surfaces, not a landing page. |

## Traceability

Roadmap mapping is filled during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| PLAY-01 | Phase 1 | Complete |
| PLAY-02 | Phase 1 | Complete |
| PLAY-03 | Phase 1 | Complete |
| PLAY-04 | Phase 1 | Complete |
| PLAY-05 | Phase 1 | Complete |
| SRCH-01 | Phase 1 | Complete |
| SRCH-02 | Phase 1 | Complete |
| SRCH-03 | Phase 2 | Pending |
| SRCH-04 | Phase 2 | Pending |
| SRCH-05 | Phase 2 | Pending |
| RECO-01 | Phase 1 | Complete |
| RECO-02 | Phase 2 | Pending |
| RECO-03 | Phase 2 | Pending |
| RECO-04 | Phase 1 | Complete |
| RECO-05 | Phase 2 | Pending |
| MEM-01 | Phase 1 | Complete |
| MEM-02 | Phase 1 | Complete |
| MEM-03 | Phase 1 | Complete |
| PLYR-01 | Phase 3 | Pending |
| PLYR-02 | Phase 3 | Pending |
| PLYR-03 | Phase 3 | Pending |
| PLYR-04 | Phase 3 | Pending |
| PLYR-05 | Phase 3 | Pending |
| TEST-01 | Phase 3 | Pending |
| TEST-02 | Phase 3 | Pending |
| TEST-03 | Phase 3 | Pending |
| TEST-04 | Phase 3 | Pending |
| TEST-05 | Phase 3 | Pending |

**Coverage:**

- v1 requirements: 28 total
- Mapped to phases: 28
- Unmapped: 0

---
*Requirements defined: 2026-06-26*
*Last updated: 2026-06-26 after Phase 01 Plan 05*
