---
phase: 04-interface-cohesion-and-search-polish
plan: 01
subsystem: ui-polish
tags: [swiftui, search, player, theme, title-cleaning, xcuitest]

requires:
  - phase: 03-player-interaction-and-regression-coverage
    provides: Dense player layout and player chrome regression tests.
provides:
  - Calmer blue-cyan theme accent and shared row pressed/selected treatment.
  - Search focus history-only state with visible search scopes removed.
  - Combined music result presentation without a separate MV search section.
  - Conservative display-title cleaning backed by tests.
  - Rebalanced player toolbar spacing and modern layout verification.
affects: [theme, search, player, title-cleaning, ui-tests]

key-files:
  created:
    - .planning/phases/04-interface-cohesion-and-search-polish/04-01-PLAN.md
    - .planning/phases/04-interface-cohesion-and-search-polish/04-01-SUMMARY.md
  modified:
    - BiliMusic/Design/AppTheme.swift
    - BiliMusic/Design/UIComponents.swift
    - BiliMusic/Design/TrackRow.swift
    - BiliMusic/Features/Home/HomeView.swift
    - BiliMusic/Features/Search/SearchView.swift
    - BiliMusic/Features/Player/NowPlayingView.swift
    - BiliMusic/Features/Player/PlayerControlViews.swift
    - BiliMusic/API/LyricsClient.swift
    - BiliMusic/Features/Library/LibraryView.swift
    - BiliMusicTests/SearchModelsTests.swift
    - BiliMusicUITests/PlayerChromeUITests.swift

key-decisions:
  - "Use Bilibili blue-cyan, not pink, as the app accent because it is calmer for a daily music app."
  - "Focused search should show local history/suggestions only; remote search stays on explicit submit or pagination paths."
  - "Remove visible MV/expanded search scopes from the primary search UI; MV signals still merge into music results."
  - "Display title cleaning must be conservative and high-confidence; lyrics matching may remain broader."

requirements-completed:
  - SRCH-01
  - SRCH-02
  - SRCH-05
  - PLYR-05
requirements-partial:
  - UI-01

duration: 30min
completed: 2026-06-27
status: complete
---

# Phase 04-01: Interface Cohesion and Search Polish Summary

Phase 4 completed a narrow UI cohesion pass without touching the playback critical path.

## Accomplishments

- Replaced the previous pink accent tokens with `AppTheme.brand`, `brandPressed`, and `brandSoft` using Bilibili blue-cyan.
- Added shared row pressed feedback and made featured/track rows use consistent selected backgrounds and accent strokes.
- Removed visible `.searchScopes` from search and changed focused empty search to show history or an empty-history state.
- Combined search output into `最佳匹配` and `音乐结果`, removing the separate visible MV search section while keeping MV-like signals inside music results.
- Made search rows use the shared row button style and larger rectangular hit targets.
- Tightened `LyricsClient.ParsedSong.isDisplaySafe` so UI display only uses high-confidence structured parses.
- Added regression coverage for conservative display-title cleaning.
- Rebalanced player toolbar into one grouped action capsule and restored enough vertical spacing for the dense-player bottom-gap gate.

## Verification

- `xcodebuild clean test -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicTests/SearchModelsTests/testTrackTitleFormatterKeepsNoiseOnlyCleanupOutOfDisplay` - passed.
- `xcodebuild test -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicTests/SearchModelsTests -only-testing:BiliMusicTests/PlayerGesturePolicyTests` - passed, 34 tests.
- `xcodebuild test -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicUITests/PlayerChromeUITests/testDensePlayerLayoutKeepsKeyElementsOrderedAndBottomGapBounded` - passed.
- `xcodebuild test -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BiliMusicUITests/PlayerChromeUITests` - passed, 15 tests.
- `xcodebuild build -scheme BiliMusic -destination 'platform=iOS Simulator,name=iPhone 17'` - passed.
- `git diff --check` - passed.

## Residual Risk

- UI-01 is only partially complete: the daily surfaces now share a calmer accent and cleaner row/search/player treatment, but favorites/settings/cache still deserve a deeper future visual pass.
- Simulator UI tests cannot fully judge tactile polish on the user's real iPhone, so final daily-feel validation remains a human UAT concern.
