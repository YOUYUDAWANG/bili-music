[根目录](../../CLAUDE.md) > **BiliMusicTests**

## 模块职责

纯逻辑单元测试。当前只有一个测试文件，覆盖 SearchModels 和 SearchStore 的核心逻辑。不依赖网络或 UIKit。

## 入口与启动

- **文件**: `SearchModelsTests.swift`
- 在 `project.yml` 中定义为 `BiliMusicTests` target，依赖 `BiliMusic` target。
- 运行方式：`xcodebuild test -project BiliMusic.xcodeproj -target BiliMusicTests -sdk iphonesimulator`

## 测试覆盖

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testCacheKeyNormalizesWhitespaceAndCase` | SearchCacheKey 归一化（空格/大小写） |
| `testModeControlsBiliMusicOnlySearch` | SearchResultMode 枚举值 |
| `testSectionsPromoteFirstResultAndSplitMV` | SearchResultSections 三段拆分 |
| `testExpandedSearchRejectsObviousNonMusic` | MusicFilter 过滤明显非音乐内容 |
| `testMusicModeAcceptsMVSignalAsResultSection` | MusicFilter 接受 MV 信号 |
| `testSearchStoreRestoresCachedSnapshot` | SearchStore 缓存恢复 |
| `testChangingModeClearsTransientResultsForSameQuery` | SearchStore 模式切换 |
| `testChangingQueryAfterMoreResultsReturnsToMusicMode` | SearchStore 查询变化时回到 music 模式 |

## 关键约束

- 不做 UI 交互测试（无 XCUITest）。
- 所有验证在真机 iPhone 上完成（AltStore，免费开发者账号）。

## 覆盖率缺口

- 无 PlayerEngine 测试（依赖 AVPlayer 和网络）。
- 无 API 层测试（依赖网络）。
- 无 Feature 视图测试（纯 SwiftUI，需真机验证）。

## 相关文件清单

- `SearchModelsTests.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-06-24 | 初始文档创建。 |
