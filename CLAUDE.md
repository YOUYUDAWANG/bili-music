# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

The `.xcodeproj` is generated from `project.yml` and is not committed. Regenerate it whenever `project.yml` or new Swift files are added:

```bash
xcodegen generate
```

Compile check (no interactive tests — user verifies on real device):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project BiliMusic.xcodeproj -scheme BiliMusic \
  -destination 'generic/platform=iOS Simulator' build
```

No test targets exist. All verification is done on a physical iPhone via AltStore (free developer account, 7-day re-signing).

## Architecture

Single-module SwiftUI app, iOS 17+, `@Observable` MVVM. No third-party dependencies — URLSession + AVPlayer only.

### Global state

`PlayerEngine` is the sole `@Observable` class injected via `.environment(engine)` from `BiliMusicApp`. Views read it with `@Environment(PlayerEngine.self)`. `CacheStore.shared` and `FavoriteManager.shared` are singletons accessed directly.

### Data flow

```
BiliClient (URLSession) → Track struct → PlayerEngine (queue + AVPlayer)
                        ↘ CacheStore (JSON index + Documents/audio/)
```

`Track` is a plain `struct` (bvid, cid, title, artist, coverURL, duration). Audio/MV stream URLs are **ephemeral** (~2h TTL) — only bvid/cid are persisted. Every playback resolves a fresh URL via `BiliClient.audioStream(bvid:cid:preferredQuality:)` or `videoStream(bvid:cid:profile:)`.

### API layer (`BiliMusic/API/`)

- **`BiliClient`** — all B站 endpoints. Every request must include `BiliClient.headers` (Referer + browser UA) or CDN returns 403. Cookie (`CookieStore.cookie`) is appended when present.
- **`WBISigner`** — WBI signing required for search and home-feed endpoints. Uses nav-endpoint keys + 64-char rearrangement table → MD5. Keys are cached 24h. Call `WBISigner.prewarm()` on launch.
- **`LyricsClient`** — LRCLIB only. No B站 subtitle fallback (auto-CC produces "♪音乐♪" noise).
- Quality IDs: `30216`=64K, `30232`=132K, `30280`=192K, `30250`=Dolby, `30251`=Hi-Res. Canonical list is `BiliClient.qualityOptions` — reference this everywhere, don't re-define.

### Player (`BiliMusic/Player/`)

- **`PlayerEngine`** — `@Observable @MainActor`. Owns `AVPlayer`, queue (`[Track]`), `queueIndex`, playback state, lyrics, and MV/music mode. KVO on `timeControlStatus` keeps UI in sync with AVPlayer truth. `isScrubbing` flag prevents time-observer/gesture conflict during progress bar drag.
- **`QueueMode`**: `.sequential`, `.shuffle`, `.repeatOne`, `.radio`. Radio mode pre-fetches the next track via `RecommendationEngine` after current song starts.
- **`RecommendationEngine`** — stateless struct, `@MainActor`. Three modes: `.home`, `.radio`, `.relatedPanel`. Seeds candidates from favorites folder (random pages), related videos, history, and playlist neighbors; scores them deterministically + ±10 random dither; deduplicates by bvid within a call. Callers maintain cross-call exclusion sets (`shownBVIDs`) to avoid repeats across refreshes.
- **`MusicFilter`** — heuristics to detect music content: B站 music partition `typeID` set + title/duration rules.
- **`PlaybackHistoryStore.shared`** — JSON at `Documents/playback-history.json`, 300-entry cap.

### Auth (`BiliMusic/Auth/`)

- **`CookieStore`** — stores the full Cookie string in Keychain. Key fields: `SESSDATA`, `bili_jct`, `DedeUserID`. Check `CookieStore.isLoggedIn` before making authenticated requests.

### Cache (`BiliMusic/Cache/`)

- **`CacheStore.shared`** — `@Observable`. JSON index at `Documents/cache_index.json`; audio files at `Documents/audio/{bvid}_{cid}.m4a`.
- **`DownloadManager.shared`** — uses `URLSessionDownloadTask` (not `AsyncBytes`). Downloads with the same `BiliClient.headers`.

### Features

- **`RootView`** — tab bar + custom full-player overlay (not `.fullScreenCover`). The full player is a `NowPlayingView` applied as `.offset(y:).ignoresSafeArea()` so it slides up from the mini bar.
- **`NowPlayingView`** — three-page `TabView` (queue ← current song → recommendations). Dismissal via swipe-down gesture; threshold ~130pt or predicted ~260pt.
- **`HomeView`** — fires `RecommendationEngine(.home)` on appear; accumulates `shownBVIDs` across "换一批" taps to avoid repeats.

### Design

- **`AppTheme`** — `accent = Color.primary` (not B站 red). `playerGradient` is a neutral system gradient (no album-art blur — washes out content in light mode). All colors use system semantic values.

## Key Constraints

- **No simulator interaction tests** — only compile-verify; real-device testing done by user.
- **No forced red/brand accent** — `AppTheme.accent` stays `Color.primary`.
- **No album-art blur background** — use `AppTheme.playerGradient` (neutral).
- **Cover frames are 16:9** — B站 covers are 16:9; use `height: coverSize * 9/16`, not square.
- **New Swift files need `xcodegen generate`** — the `.xcodeproj` is generated; adding files without regenerating means Xcode won't find them.
- **Stream URLs must not be persisted** — only bvid/cid go to disk; URLs expire in ~2h.
