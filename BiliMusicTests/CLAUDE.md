[根目录](../../CLAUDE.md) > **BiliMusicTests**

## 模块职责

单元测试 target（`BiliMusicTests`）+ UI 测试 target（`BiliMusicUITests`）。单元测试覆盖播放引擎关键路径、队列/过滤/手势等纯函数策略、搜索状态管理与缓存投影，不依赖网络（PlayerEngine 通过注入 `AudioStreamResolving` fixture 与 `startupTestHooks` 驱动）。

## 运行方式

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project BiliMusic.xcodeproj -scheme BiliMusic \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO -only-testing:BiliMusicTests
```

- 机型不存在时用 `xcrun simctl list devices available` 找可用机型替换。
- UI 测试（`-only-testing:BiliMusicUITests`）较慢，日常迭代只跑单元测试套件。
- **新增测试文件后必须 `xcodegen generate`** —— `.xcodeproj` 是生成的，不重新生成 Xcode 找不到新文件。

## 测试文件与覆盖范围

| 文件 | 覆盖内容 |
|------|---------|
| `AudioCDNSelectorTests.swift` | 音频 CDN 候选去重、host 健康度排序、PlayInfo backup URL 驼峰/下划线解码 |
| `ImageCacheTests.swift` | `ImageMemoryCache` 缓存/清理、当前封面保护 |
| `MusicFilterTests.swift` | `isMusic`/`isStrictMusic` 时长边界（59/60/720/721、74/75/540/541）；≤4 字符纯 ASCII 提示词的词边界匹配正反例（"Official MV" 命中、"explained"/"livehouse"/"amv"/"using" 不命中）；非音乐词否决与强音乐信号豁免 |
| `PlaybackCriticalPathTests.swift` | PlayerEngine 起播关键路径：current/封面先行赋值、单次取流、首帧后调度、自动缓存出声后调度、`playbackHeaders`、电台 advance 竞态（pause/play/previous/换模式）、队列末尾收尾、seek 边界、stale scrub、`VersionedAtomicFileWriter` 版本拒绝、`PlaybackHistoryStore` 注入合并；repeatOne 手动/自动 nextIndex 语义 |
| `PlaybackPersistenceTests.swift` | 队列窗口裁剪、冷启动恢复暂停队列与进度、电台恢复为顺序、`FavItem` first_cid、封面快照补 cid、按 bvid 去重优先 cid |
| `CacheStoreTests.swift` | 旧索引缺 `accessedAt` 仍可解码、超出 120 首 LRU 淘汰、保护正在播放的 key |
| `PlaybackDiagnosticsTests.swift` | 起播链路诊断事件（checkpoint 顺序与来源标注） |
| `PlayerControlLogicTests.swift` | 原生 `Slider` 提交给播放器前的进度时间边界 clamp |
| `PreparedStreamRetryTests.swift` | prepared 流失效后 invalidate + 单次 fresh 重试、重复失败回调共享一次恢复、pause 不吞失败、坏本地缓存回退 freshRemote 并移除缓存条目 |
| `QueueControllerTests.swift` | `nextIndex` 全模式边界（空队列、队尾、shuffle 越界/去重、radio、repeatOne 自动重复 vs 手动队尾回绕到 0）；`appendUnique` 按 `TrackKey.matches` 去重（cid 未解析时按 bvid 松匹配、不同分 P 视为不同曲目） |
| `RecommendationSchedulingTests.swift` | 推荐调度策略（`RecommendationSchedulingPolicy` / `RecommendationPanelRefreshPolicy` / `RecommendationVisibleLoadPolicy`）、cid enrichment 判定、推荐展示过滤；含少量读源码的结构断言 |
| `SearchFocusTests.swift` | 输入首字符保持本地 idle、`SearchLocalContent` 投影（历史上限 8、recent/cached 去重合并、空态）；含少量读源码断言（无 debounce 提交路径） |
| `SearchModelsTests.swift` | 搜索模型，以及歌词平台路由、候选一致性排序、LRC/翻译/逐字解析和 `LyricsStore` 偏移持久化 |
| `SearchStoreTests.swift` | `loadLocalContent`/`refreshLocalContent` 投影与 contentRevision 增量语义、空查询不清结果、分页部分失败保留成功页、首次搜索先展示第一页、缓存 `entry(for:)` 分 P 精确匹配 |

### UI 测试（`BiliMusicUITests/`）

| 文件 | 覆盖内容 |
|------|---------|
| `PlayerChromeUITests.swift` | mini/full 播放器开合、手势/布局，以及歌词页逐字、翻译和偏移控件 |

## 共享单例隔离约定（重要）

跑完测试后**宿主的真实数据必须完好**。约定优先级从高到低：

1. **注入实例 + 临时目录**（首选）：`CacheStore(indexURLForTesting:audioDirForTesting:)`（`#if DEBUG`）与 `PlaybackHistoryStore(fileURLForTesting:)`，全部落在 `FileManager.temporaryDirectory` 下的独立子目录，tearDown 删除整个目录。`SearchStoreTests` 全量采用此方式。
2. **快照 + 恢复**（测试链路必须经过 `.shared` 时退而求其次，如 PlayerEngine 内部硬引用 `CacheStore.shared`）：setUp/测试开头快照真实索引 JSON，`addTeardownBlock` 中先 `flush()` 落定防抖写盘、清理测试产物、再恢复快照。`PreparedStreamRetryTests.testBrokenLocalCacheFallsBackToFreshRemoteStream` 是范例。
3. **UserDefaults**：setUp 捕获初始值，tearDown 恢复（nil 则 remove），不要无条件 `removeObject`。

CacheStore 新行为注意事项：

- `loadIfNeeded()` 会**删除 audioDir 中不在磁盘索引里的孤儿文件** —— 测试要写音频文件必须在 `await loadIfNeeded()` 完成之后。
- `remove()` 走 1s 防抖写盘 —— 断言磁盘状态前先 `flush()`。
- `flush()` 在未加载时会先触发完整 load。

## 测试 fixture 机制

- **PlayerEngine 注入**：`PlayerEngine(streamResolver:startupTestHooks:radioTrackProvider:)`。`startupTestHooks.record` 收集 `PlaybackStartupTestEvent` 事件序列；`startPlaybackOverride` 跳过真实 AVPlayer；`reportFirstPlayingImmediately` 模拟首帧。fixture resolver 返回的流 **cid 必须与请求曲目一致**（生产 resolver 语义如此）——固定 cid 会触发 PlayerEngine 的分 P 身份守卫拒流。
- **有界等待**：等待 fixture 状态用有界循环（yield 上限 + 超时 `XCTFail`），禁止无界 `while … { await Task.yield() }`（行为回归时会挂死测试进程）。
- **UI 测试 fixture**：`BILIMUSIC_UITEST_FIXTURE=1` 环境变量（`BiliMusic/Support/UITestFixtures.swift`）。App 启动时注入固定曲目队列，`PlayerEngine.installUITestFixture(tracks:startAt:)` 不建真实流；`BILIMUSIC_UITEST_LYRICS=1` 额外注入逐字与翻译歌词。
- **调试环境变量**：`AUTOPLAY_BV`（模拟器自动播放）、`AUTOPLAY_TEST_NEXT`（测切歌）。

## 关键约束

- 只做单元测试 + 编译验证；交互体验最终在真机 iPhone 上验证（AltStore 签名）。
- 自动化测试不发真实网络请求；`MetingLyricsClient` 的纯路由、排序与解析逻辑有单元测试，真实 BM/歌词平台响应另做有界冒烟验证。
- 避免「读生产源码断言精确缩进子串」的脆弱写法；行为已有策略函数（如 `RecommendationPanelRefreshPolicy`）时优先断言策略函数行为。
- WBISigner 未测试：`sign` 依赖网络获取的 mixin key，无注入点；纯逻辑部分（encode/重排）均为 private。

## 覆盖率缺口

- 无 API 层测试（依赖网络）；API 响应结构靠 `scripts/verify_audio.py`、`scripts/verify_search_rcmd.py` 验证。
- 无 Feature 视图快照测试（纯 SwiftUI，真机验证）。
- BiliMusicUITests 存在硬编码归一化坐标（P3，待重构为可访问性驱动）。

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-08-19 | 新增 PlaybackPersistenceTests、CacheStoreTests；SearchStoreTests 覆盖第一页增量展示。 |
| 2026-07-27 | 全面同步生产行为变化：SearchStoreTests 迁移到注入 store；PreparedStreamRetryTests 快照恢复真实索引；busy-wait 改有界等待；fixture resolver cid 对齐；新增 QueueControllerTests / MusicFilterTests / ProgressScrubMath.shouldBeginScrub 覆盖；重写本文档。 |
| 2026-06-24 | 初始文档创建。 |
