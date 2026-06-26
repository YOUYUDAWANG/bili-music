# Technology Stack

**Analysis Date:** 2026-06-26

## Languages

**Primary:**
- Swift 5.10 - iOS app source under `BiliMusic/`, configured in `project.yml`, and mirrored in `BiliMusic.xcodeproj/project.pbxproj`.

**Secondary:**
- Python 3 - standard-library verification scripts in `scripts/verify_audio.py` and `scripts/verify_search_rcmd.py`.
- YAML - XcodeGen project definition in `project.yml` and GitHub Actions workflow in `.github/workflows/build.yml`.

## Runtime

**Environment:**
- iOS 26.0 deployment target - set in `project.yml` under `options.deploymentTarget.iOS`.
- iPhone target family - `TARGETED_DEVICE_FAMILY: "1"` in `project.yml`.
- Apple SDK runtime - app code imports `SwiftUI`, `Observation`, `Foundation`, `AVFoundation`, `AVKit`, `MediaPlayer`, `Security`, `Network`, `CryptoKit`, `CoreImage.CIFilterBuiltins`, `UIKit`, and `OSLog`.

**Package Manager:**
- Homebrew is used only to install XcodeGen in `.github/workflows/build.yml` and per `README.md`.
- Lockfile: missing for Swift packages; no `Package.swift`, `Package.resolved`, `Podfile`, or `Cartfile` detected.

## Frameworks

**Core:**
- SwiftUI - app entry and UI layer, starting at `BiliMusic/App/BiliMusicApp.swift`.
- Observation - observable state objects such as `BiliMusic/Player/PlayerEngine.swift`, `BiliMusic/Cache/CacheStore.swift`, `BiliMusic/Cache/DownloadManager.swift`, and `BiliMusic/Features/Favorites/FavoriteManager.swift`.
- AVFoundation / AVKit / MediaPlayer - playback, MV display, background audio, and lock-screen integration in `BiliMusic/Player/PlayerEngine.swift`, `BiliMusic/Features/Player/NowPlayingView.swift`, and `BiliMusic/Features/Player/PlayerSheetViews.swift`.
- Security - Keychain-backed cookie storage in `BiliMusic/Auth/CookieStore.swift`.
- Network - Wi-Fi/network path monitoring in `BiliMusic/Player/NetworkMonitor.swift`.
- CryptoKit - WBI MD5 signing in `BiliMusic/API/WBISigner.swift`.
- CoreImage - QR code image generation in `BiliMusic/Features/Settings/SettingsView.swift`.

**Testing:**
- XCTest - unit tests in `BiliMusicTests/SearchModelsTests.swift` and UI tests in `BiliMusicUITests/PlayerChromeUITests.swift`.
- Xcode test bundles - configured by `project.yml` targets `BiliMusicTests` and `BiliMusicUITests`.

**Build/Dev:**
- XcodeGen - generates `BiliMusic.xcodeproj` from `project.yml`.
- xcodebuild - CI compile command in `.github/workflows/build.yml`.
- GitHub Actions - macOS simulator build gate in `.github/workflows/build.yml`.
- CodeGraph - local code index present under `.codegraph/` for repository navigation.

## Key Dependencies

**Critical:**
- Apple Foundation URLSession - direct HTTPS API access in `BiliMusic/API/BiliClient.swift`, `BiliMusic/API/LyricsClient.swift`, `BiliMusic/API/WBISigner.swift`, `BiliMusic/Cache/DownloadManager.swift`, and `BiliMusic/Design/CachedAsyncImage.swift`.
- Apple AVPlayer - audio/video playback engine in `BiliMusic/Player/PlayerEngine.swift`.
- Apple Keychain Services - secure Bilibili cookie persistence in `BiliMusic/Auth/CookieStore.swift`.
- Apple UserDefaults / AppStorage - user settings such as `autoCache`, `playbackQuality`, `downloadQuality`, `preferMVOnWiFi`, and `recommendFolderId` in `BiliMusic/Features/Settings/SettingsView.swift`.
- Local filesystem JSON/audio storage - offline cache and history in `BiliMusic/Cache/CacheStore.swift`, `BiliMusic/Player/PlaybackHistoryStore.swift`, and `BiliMusic/Features/Home/RecentHomeFeedStore.swift`.

**Infrastructure:**
- XcodeGen project model - `project.yml` is the source of target/platform/build settings.
- Generated Xcode project - `BiliMusic.xcodeproj/project.pbxproj` is present and contains build settings and source membership.
- Python standard library - `urllib`, `json`, `hashlib`, `time`, and `pathlib` in `scripts/verify_audio.py` and `scripts/verify_search_rcmd.py`.
- No declared third-party SDK packages - no SwiftPM, CocoaPods, Carthage, npm, Cargo, Go, or Python dependency manifest is present in the repo root.

## Configuration

**Environment:**
- No `.env` or secret environment files detected at the scanned repo depth.
- App identity and build configuration live in `project.yml`.
- Bundle identifier prefix is `com.fubuki` in `project.yml`; generated app bundle identifier is `com.fubuki.BiliMusic` in `BiliMusic.xcodeproj/project.pbxproj`.
- Development team is configured as `T28ATJ65TJ` in `project.yml`.
- Runtime user preferences are stored through `@AppStorage` and `UserDefaults` in `BiliMusic/Features/Settings/SettingsView.swift`, `BiliMusic/Player/PlayerEngine.swift`, `BiliMusic/Cache/DownloadManager.swift`, and `BiliMusic/Features/Favorites/FavoriteManager.swift`.
- Login cookies are stored in Keychain service `com.fubuki.BiliMusic.cookie` in `BiliMusic/Auth/CookieStore.swift`.

**Build:**
- `project.yml` defines app/test targets, iOS deployment target, Swift version, signing mode, Info.plist generation keys, and source exclusions.
- `BiliMusic/Info.plist` enables `UIBackgroundModes` audio and `NSAppTransportSecurity.NSAllowsArbitraryLoads`.
- `.github/workflows/build.yml` installs XcodeGen, runs `xcodegen generate`, and builds `BiliMusic` for `iphonesimulator` with code signing disabled.
- `README.md` documents local build steps: `brew install xcodegen`, `xcodegen generate`, and `open BiliMusic.xcodeproj`.

## Platform Requirements

**Development:**
- macOS with Xcode capable of Swift 5.10 and iOS 26.0 SDK.
- XcodeGen installed with Homebrew for regenerating `BiliMusic.xcodeproj` from `project.yml`.
- Python 3 for optional API verification scripts in `scripts/`.
- A Bilibili account is optional for anonymous playback/search but required for higher-quality streams, favorites, personalized recommendations, and QR-login flows.

**Production:**
- iOS application target `BiliMusic` built from `project.yml`.
- Background audio capability is configured through `BiliMusic/Info.plist`.
- Network access to Bilibili API/CDN hosts and `lrclib.net` is required for full functionality.
- Offline playback depends on files in the app Documents directory managed by `BiliMusic/Cache/CacheStore.swift`.

---

*Stack analysis: 2026-06-26*
