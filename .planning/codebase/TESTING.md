# Testing Patterns

**Analysis Date:** 2026-06-26

## Test Framework

**Runner:**
- XCTest through Xcode. Targets are declared in `project.yml`: `BiliMusicTests` for unit tests and `BiliMusicUITests` for UI tests.
- The generated Xcode project exposes the `BiliMusic` scheme in `BiliMusic.xcodeproj`; the scheme includes the app target and can run test targets configured by `project.yml`.
- Unit test config: `BiliMusicTests/SearchModelsTests.swift`.
- UI test config: `BiliMusicUITests/PlayerChromeUITests.swift`.

**Assertion Library:**
- XCTest assertions only. Use `XCTAssertEqual`, `XCTAssertTrue`, `XCTAssertFalse`, and `XCTAssertGreaterThan` as shown in `BiliMusicTests/SearchModelsTests.swift` and `BiliMusicUITests/PlayerChromeUITests.swift`.

**Run Commands:**
```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project BiliMusic.xcodeproj -target BiliMusic -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -target BiliMusicTests -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
python3 scripts/verify_audio.py <BV_ID>
python3 scripts/verify_search_rcmd.py "Jay Chou Qing Tian"
```

## Test File Organization

**Location:**
- Unit tests live in the top-level test target directory `BiliMusicTests/`.
- UI tests live in the top-level UI test target directory `BiliMusicUITests/`.
- Test-only runtime fixtures live in app source at `BiliMusic/Support/UITestFixtures.swift` so the app can install deterministic data when launched by XCUITest.

**Naming:**
- Test files use `*Tests.swift`: `BiliMusicTests/SearchModelsTests.swift`, `BiliMusicUITests/PlayerChromeUITests.swift`.
- Test classes are `final class ...: XCTestCase`: `SearchModelsTests` in `BiliMusicTests/SearchModelsTests.swift`, `PlayerChromeUITests` in `BiliMusicUITests/PlayerChromeUITests.swift`.
- Test methods start with `test` and describe behavior, such as `testCacheKeyNormalizesWhitespaceAndCase` in `BiliMusicTests/SearchModelsTests.swift` and `testMiniPlayerSlowDragOpensRespectsSafeAreaAndClosesFromTopChrome` in `BiliMusicUITests/PlayerChromeUITests.swift`.

**Structure:**
```text
BiliMusicTests/
└── SearchModelsTests.swift          # XCTest unit tests for search models/store logic
BiliMusicUITests/
└── PlayerChromeUITests.swift        # XCUITest coverage for player chrome and search tab UI
BiliMusic/Support/
└── UITestFixtures.swift             # Deterministic fixture data enabled by environment variable
scripts/
├── verify_audio.py                  # Manual API/audio-chain verification
└── verify_search_rcmd.py            # Manual search/recommendation API verification
```

## Test Structure

**Suite Organization:**
```swift
// `BiliMusicTests/SearchModelsTests.swift`
final class SearchModelsTests: XCTestCase {
    func testSectionsPromoteFirstResultAndSplitMV() {
        let best = Track(typeID: 3, bvid: "BV1", title: "Best", artist: "Artist",
                         coverURL: nil, duration: 269)

        let sections = SearchResultSections.make(from: [best])

        XCTAssertEqual(sections.bestMatch?.bvid, "BV1")
    }
}
```

```swift
// `BiliMusicUITests/PlayerChromeUITests.swift`
final class PlayerChromeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-searchHistory", "[]"]
        app.launchEnvironment["BILIMUSIC_UITEST_FIXTURE"] = "1"
        app.launch()
    }
}
```

**Patterns:**
- Unit tests construct simple domain values inline with `Track(...)` and assert pure model behavior in `BiliMusicTests/SearchModelsTests.swift`.
- Tests that touch `@MainActor` observable state mark methods with `@MainActor`, as in `testSearchStoreRestoresCachedSnapshot` in `BiliMusicTests/SearchModelsTests.swift`.
- UI tests use a shared `XCUIApplication` field, `setUpWithError()`, and `tearDownWithError()` in `BiliMusicUITests/PlayerChromeUITests.swift`.
- UI tests prefer stable accessibility identifiers over coordinate-only lookup when available: `miniPlayer`, `nowPlayingView`, `homeTrackRow0`, `searchScope_music`, and `searchScope_expanded` are asserted in `BiliMusicUITests/PlayerChromeUITests.swift` and defined in `BiliMusic/Features/RootView.swift`, `BiliMusic/Features/Home/HomeView.swift`, `BiliMusic/Features/Search/SearchView.swift`, and `BiliMusic/Features/Player/NowPlayingView.swift`.
- Coordinate gestures are used only for player drag behavior that cannot be expressed as a button tap; examples are `openFullPlayerFromMini()` and close-drag tests in `BiliMusicUITests/PlayerChromeUITests.swift`.

## Mocking

**Framework:** No mocking framework is configured. Tests use inline values, app launch arguments, and app launch environment.

**Patterns:**
```swift
// `BiliMusicUITests/PlayerChromeUITests.swift`
app.launchArguments = ["-searchHistory", "[]"]
app.launchEnvironment["BILIMUSIC_UITEST_FIXTURE"] = "1"
```

```swift
// `BiliMusic/Support/UITestFixtures.swift`
enum UITestFixtures {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["BILIMUSIC_UITEST_FIXTURE"] == "1"
    }
}
```

**What to Mock:**
- Prefer pure inline fixtures for model logic, as in `BiliMusicTests/SearchModelsTests.swift`.
- Use `BILIMUSIC_UITEST_FIXTURE` for UI tests that need deterministic player/home data through `BiliMusic/Support/UITestFixtures.swift`.
- Use test-only insertion helpers for in-memory stores, such as `storeCachedSnapshotForTesting(query:mode:snapshot:)` in `BiliMusic/Features/Search/SearchStore.swift`.

**What NOT to Mock:**
- Do not introduce network-dependent unit tests in `BiliMusicTests/SearchModelsTests.swift`; keep Bilibili API verification in `scripts/verify_audio.py` and `scripts/verify_search_rcmd.py`.
- Do not mock `AVPlayer` inside existing search unit tests. Player behavior belongs in focused player tests or UI fixture flows because `PlayerEngine` in `BiliMusic/Player/PlayerEngine.swift` coordinates playback, queue state, and system media APIs.
- Do not persist real cookies or secrets in tests. Scripts accept optional `--cookie` arguments in `scripts/verify_audio.py` and `scripts/verify_search_rcmd.py`; keep secret values out of source and docs.

## Fixtures and Factories

**Test Data:**
```swift
// `BiliMusicTests/SearchModelsTests.swift`
let track = Track(typeID: 3, bvid: "BV1", title: "Song", artist: "Artist",
                  coverURL: nil, duration: 269)
```

```swift
// `BiliMusic/Support/UITestFixtures.swift`
static let homeTracks: [Track] = [
    Track(typeID: 3, bvid: "BVUITEST001", cid: 1001, title: "Fixture Song One",
          artist: "UI Test", coverURL: nil, duration: 211)
]
```

**Location:**
- Unit fixture values are local to the test methods in `BiliMusicTests/SearchModelsTests.swift`.
- Shared UI fixture values live in `BiliMusic/Support/UITestFixtures.swift`.
- UI accessibility hooks are in production views: `BiliMusic/Features/RootView.swift`, `BiliMusic/Features/Home/HomeView.swift`, `BiliMusic/Features/Search/SearchView.swift`, and `BiliMusic/Features/Player/NowPlayingView.swift`.

## Coverage

**Requirements:** No coverage threshold or coverage configuration is enforced in `project.yml`, `BiliMusic.xcodeproj`, or repository-level config files.

**View Coverage:**
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' -enableCodeCoverage YES CODE_SIGNING_ALLOWED=NO
```

## Test Types

**Unit Tests:**
- `BiliMusicTests/SearchModelsTests.swift` covers `SearchCacheKey`, `SearchResultMode`, `SearchResultSections`, `MusicFilter`, and focused `SearchStore` transitions.
- Unit tests use `@testable import BiliMusic` to reach internal app symbols from `BiliMusicTests/SearchModelsTests.swift`.
- Unit tests avoid UIKit, network, keychain, and file-system dependencies; examples use inline `Track` instances and in-memory `SearchCachedSnapshot` values.

**Integration Tests:**
- No XCTest integration suite is present. API and stream verification are handled by scripts: `scripts/verify_audio.py` for BV-to-audio-chain checks and `scripts/verify_search_rcmd.py` for WBI search, home recommendations, and related-video sources.
- App launch smoke behavior is exercised through debug environment variables in `BiliMusic/Features/RootView.swift`: `AUTOPLAY_BV` and `AUTOPLAY_TEST_NEXT`.

**E2E Tests:**
- `BiliMusicUITests/PlayerChromeUITests.swift` provides XCUITest coverage for mini-player opening/closing, safe-area player chrome, recommendation-list stability, and native search chrome.
- UI tests rely on `BILIMUSIC_UITEST_FIXTURE` and production accessibility identifiers to avoid live network data in `BiliMusicUITests/PlayerChromeUITests.swift`.
- Manual real-device verification remains necessary for playback, AltStore signing, background audio, and Bilibili network behavior described by `CLAUDE.md` and implemented in `BiliMusic/Player/PlayerEngine.swift`.

## Common Patterns

**Async Testing:**
```swift
// `BiliMusicTests/SearchModelsTests.swift`
@MainActor
func testSearchStoreRestoresCachedSnapshot() {
    let store = SearchStore()
    store.storeCachedSnapshotForTesting(query: "song", mode: .music, snapshot: snapshot)

    let restored = store.restoreCachedResultsIfAvailable(for: " song ")

    XCTAssertTrue(restored)
}
```

**Error Testing:**
```swift
// `BiliMusicTests/SearchModelsTests.swift`
func testExpandedSearchRejectsObviousNonMusic() {
    let gameplay = Track(typeID: 17, bvid: "BV9", title: "Gameplay",
                         artist: "Game", coverURL: nil, duration: 320)

    XCTAssertFalse(MusicFilter.isSearchResult(gameplay, query: "game", mode: .expanded))
}
```

**UI Waiting:**
```swift
// `BiliMusicUITests/PlayerChromeUITests.swift`
let nowPlaying = element("nowPlayingView")
XCTAssertTrue(nowPlaying.waitForExistence(timeout: 3),
              "Full player should be open for chrome layout verification.")
```

**Verification Scripts:**
```bash
python3 scripts/verify_audio.py <BV_ID>
python3 scripts/verify_search_rcmd.py "Jay Chou Qing Tian"
```

---

*Testing analysis: 2026-06-26*
