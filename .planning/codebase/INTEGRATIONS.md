# External Integrations

**Analysis Date:** 2026-06-26

## APIs & External Services

**Bilibili Public/Web APIs:**
- Bilibili video metadata - video details and page lists for playback setup.
  - SDK/Client: custom `BiliClient` in `BiliMusic/API/BiliClient.swift`
  - Auth: optional Cookie from `BiliMusic/Auth/CookieStore.swift`
  - Endpoints: `https://api.bilibili.com/x/web-interface/view`, `https://api.bilibili.com/x/player/pagelist`
- Bilibili playback URLs - DASH audio, FLAC where available, and MP4 MV streams.
  - SDK/Client: custom `BiliClient` in `BiliMusic/API/BiliClient.swift`
  - Auth: optional Cookie from `BiliMusic/Auth/CookieStore.swift`
  - Endpoints: `https://api.bilibili.com/x/player/playurl`
  - Consumers: `BiliMusic/Player/StreamResolver.swift`, `BiliMusic/Player/PlayerEngine.swift`, and `BiliMusic/Cache/DownloadManager.swift`
- Bilibili WBI search and feed recommendations - signed search and personalized home feed.
  - SDK/Client: `BiliMusic/API/BiliClient.swift` with signing from `BiliMusic/API/WBISigner.swift`
  - Auth: optional Cookie from `BiliMusic/Auth/CookieStore.swift`
  - Endpoints: `https://api.bilibili.com/x/web-interface/wbi/search/type`, `https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd`, `https://api.bilibili.com/x/web-interface/nav`
- Bilibili related videos - radio/autoplay recommendation source.
  - SDK/Client: custom `BiliClient` in `BiliMusic/API/BiliClient.swift`
  - Auth: optional Cookie from `BiliMusic/Auth/CookieStore.swift`
  - Endpoint: `https://api.bilibili.com/x/web-interface/archive/related`
- Bilibili subtitles - subtitle metadata and subtitle file download.
  - SDK/Client: custom `BiliClient` in `BiliMusic/API/BiliClient.swift`
  - Auth: optional Cookie from `BiliMusic/Auth/CookieStore.swift`
  - Endpoint: `https://api.bilibili.com/x/player/v2`
- Bilibili QR login - QR generation and polling.
  - SDK/Client: custom `BiliClient` in `BiliMusic/API/BiliClient.swift`
  - Auth: QR login callback values stored as Cookie by `BiliMusic/Auth/CookieStore.swift`
  - Endpoints: `https://passport.bilibili.com/x/passport-login/web/qrcode/generate`, `https://passport.bilibili.com/x/passport-login/web/qrcode/poll`
- Bilibili favorites and playlists - favorite folders, favorite item IDs, favorite mutation, and UP playlists.
  - SDK/Client: custom `BiliClient` in `BiliMusic/API/BiliClient.swift`
  - Auth: Cookie and CSRF token from `BiliMusic/Auth/CookieStore.swift`
  - Endpoints: `https://api.bilibili.com/x/v3/fav/folder/created/list-all`, `https://api.bilibili.com/x/v3/fav/resource/list`, `https://api.bilibili.com/x/v3/fav/resource/ids`, `https://api.bilibili.com/x/v3/fav/resource/deal`, `https://api.bilibili.com/x/polymer/web-space/seasons_series_list`, `https://api.bilibili.com/x/polymer/web-space/seasons_archives_list`

**Lyrics:**
- LRCLIB - synchronized lyrics search and LRC parsing.
  - SDK/Client: custom `LyricsClient` in `BiliMusic/API/LyricsClient.swift`
  - Auth: Not detected
  - Endpoint: `https://lrclib.net/api/search`

**Media/CDN Assets:**
- Bilibili CDN URLs - audio/video stream URLs returned by Bilibili `playurl` responses and image/subtitle URLs returned by Bilibili metadata.
  - SDK/Client: `URLSession`, `AVURLAsset`, and `AVPlayer` in `BiliMusic/Player/PlayerEngine.swift`; image loading in `BiliMusic/Design/CachedAsyncImage.swift`
  - Auth: Bilibili-style request headers from `BiliMusic/API/BiliClient.swift`; Cookie is added where API methods require it.

## Data Storage

**Databases:**
- Not detected. The code comments in `BiliMusic/Cache/CacheStore.swift` explicitly keep the single-table audio cache out of SwiftData.

**File Storage:**
- App Documents directory - audio files in `Documents/audio/` and cache index `Documents/cache_index.json` managed by `BiliMusic/Cache/CacheStore.swift`.
- Playback history - `Documents/playback-history.json` managed by `BiliMusic/Player/PlaybackHistoryStore.swift`.
- Recent home feed suppression - `Documents/home-recent.json` managed by `BiliMusic/Features/Home/RecentHomeFeedStore.swift`.
- URLCache image disk cache - disk path `BiliMusicImages` configured in `BiliMusic/Design/CachedAsyncImage.swift`.
- Verification output - `scripts/verify_audio.py` writes downloaded `.m4a` files under `scripts/`.

**Caching:**
- In-memory stream URL cache - 90-minute TTL in `BiliMusic/Player/StreamResolver.swift`.
- In-memory recommendation candidate cache - 8-minute TTL in `BiliMusic/Player/RecommendationEngine.swift`.
- In-memory image cache - `NSCache` with count and cost limits in `BiliMusic/Design/CachedAsyncImage.swift`.
- URLCache image cache - 32 MB memory and 128 MB disk in `BiliMusic/Design/CachedAsyncImage.swift`.
- Local offline audio cache - persistent files and JSON index in `BiliMusic/Cache/CacheStore.swift`.

## Authentication & Identity

**Auth Provider:**
- Bilibili QR login and Cookie-based session.
  - Implementation: `QRLoginView` in `BiliMusic/Features/Settings/SettingsView.swift` requests a QR code, polls Bilibili, and stores the returned Cookie.
  - Storage: Apple Keychain through `BiliMusic/Auth/CookieStore.swift`.
  - Cookie fields used: `SESSDATA`, `bili_jct`, and `DedeUserID`.
  - CSRF: `bili_jct` from `CookieStore.csrf` is required by favorite write operations in `BiliMusic/API/BiliClient.swift`.

## Monitoring & Observability

**Error Tracking:**
- None detected. No Sentry, Firebase Crashlytics, analytics, or external telemetry SDK is declared.

**Logs:**
- Apple OSLog via `Logger` in `BiliMusic/API/BiliClient.swift`, `BiliMusic/API/LyricsClient.swift`, `BiliMusic/Cache/CacheStore.swift`, `BiliMusic/Cache/DownloadManager.swift`, `BiliMusic/Player/PlaybackHistoryStore.swift`, `BiliMusic/Player/PlayerEngine.swift`, `BiliMusic/Player/RecommendationEngine.swift`, and `BiliMusic/Player/StreamResolver.swift`.
- Python verification scripts print status to stdout in `scripts/verify_audio.py` and `scripts/verify_search_rcmd.py`.

## CI/CD & Deployment

**Hosting:**
- GitHub Actions CI is configured in `.github/workflows/build.yml`.
- App deployment/distribution automation is not detected.

**CI Pipeline:**
- `.github/workflows/build.yml` runs on pull requests and pushes to `main` for selected paths.
- Pipeline steps: checkout, `brew install xcodegen`, `xcodegen generate`, and `xcodebuild` against `BiliMusic.xcodeproj`.
- CI build target: `BiliMusic` on `iphonesimulator` with `CODE_SIGNING_ALLOWED=NO`.

## Environment Configuration

**Required env vars:**
- Not detected. Build settings are in `project.yml`; runtime credentials are acquired through Bilibili QR login and persisted in Keychain by `BiliMusic/Auth/CookieStore.swift`.

**Secrets location:**
- No `.env` or checked-in secret files detected at the scanned repo depth.
- Runtime Bilibili session Cookie is stored in Apple Keychain service `com.fubuki.BiliMusic.cookie` by `BiliMusic/Auth/CookieStore.swift`.
- GitHub Actions workflow `.github/workflows/build.yml` does not reference repository secrets.

## Webhooks & Callbacks

**Incoming:**
- None detected. The app has no server endpoint or webhook receiver.

**Outgoing:**
- None detected. The app performs direct HTTPS requests to Bilibili and LRCLIB; no webhook publisher is present.

---

*Integration audit: 2026-06-26*
