---
phase: 05
slug: native-feel-and-lyrics
status: executed
created: 2026-08-19
expanded: 2026-08-19
executed: 2026-08-19
---

# Phase 05 — 原生风格统一与歌词重构 · 实施规格书

> 状态：**已执行**（2026-08-19）。真机确认见 §10。
> 本文档是唯一实施依据。目标读者是接手的执行模型：**所有审美决策已在本文档拍死，执行时不允许自由发挥。**

---

## 0. 执行者硬规则（先读，违反即返工）

1. **只允许使用 §3 定义的颜色、字号、间距、圆角、图标、触感。** 发现规格没覆盖的场景，停下来问用户，不许自己发明新值。
2. **不许改动本文档未列出的页面、组件或行为。** 觉得别处"也可以顺手优化"时，记录下来交给用户，不做。
3. **不许触碰播放热路径**：`PlayerEngine`、`BiliClient`、`StreamResolver`、`CacheStore`、`DownloadManager` 的内部逻辑一律不改；只允许改它们的视图调用点。
4. 玻璃与材质只用系统 API（`.glass`、系统 material、LNPopup/TabView 默认外观），禁止自绘或包装 `UIBlurEffect`/`UIGlassEffect`（iOS 27 合规红线，见 §1）。
4. 每新增/删除 Swift 文件，必须执行 `xcodegen generate` 再编译（`.xcodeproj` 是生成物）。
5. 每个切片完成后必须跑 §9 该片对应的验证命令，全部通过才能进入下一片。
6. 行号只是定位锚点，会随编辑漂移；**一律按符号名定位**。
7. 完成每个切片后，在 `cairn/LOG.md` 顶部加一条 ≤8 行的摘要与指针；稳定结论更新到对应模块 `CLAUDE.md` 的变更记录表。
8. 现有 UI 测试标识符（`accessibilityIdentifier`）不许改名；新增标识符只能用 §5/§9 列出的名字。

## 1. 目标与基准定义

用户目标：整个 App 像原生音乐应用一样精致、风格统一；歌词对齐 Apple Music 方案。基准系统：**iOS 27**（Liquid Glass 2.0，WWDC 2026 发布）。

**「iOS 27 原生风格」的精确定义**（执行时以此为准）：

- **系统外壳零改动自动达标。** iOS 27 的 Liquid Glass 改进（更好的内容扩散可读性、暗边与更亮高光、滚动时的统一 toolbar、用户透明度滑块）对使用系统标准组件的 App 自动生效。本项目外壳已经是原生 `TabView` + LNPopup floatingCompact + `.glass` 按钮，不自绘底栏/玻璃——这正是 iOS 27 要求的方向，保持即可。Xcode 27 起 Liquid Glass 不可退避（`UIDesignRequiresCompatibility` 被移除），本项目不使用该 flag，无需迁移。
- **内容层对齐 iOS 27 Apple Music 的秩序感**：系统标准组件、清晰字号层级、克制材质、无自定义炫技。两个既有方向已被 iOS 27 Apple Music 验证为正确，继续保持：播放器背景由封面色塑形整页（`PlayerArtworkPalette`，与 iOS 27 艺人/专辑页「图片色彩融入整页」同向）；Now Playing 横屏布局（iOS 27 起 Apple Music 官方支持横屏，本项目已有 `landscapeNowPlayingPage`）。
- **材质合规红线**：玻璃与材质只允许系统 API（`.glass` 按钮样式、`ultraThinMaterial` 等系统材质、LNPopup/TabView 默认外观），禁止自绘玻璃或自行包装 `UIBlurEffect`/`UIGlassEffect`。系统材质自动响应 iOS 27 透明度滑块与 Reduce Transparency，自定义实现则不会。
- 项目既有视觉身份不变：首页纯海报瀑布流、16:9 封面、封面派生双色光场（见 `cairn/visual-language.md`）。本方案不推翻它们，只把它们收进统一 token 体系。
- 可选抛光（不强制）：歌词/队列按钮的激活态可用 `GlassEffectContainer` + `.glassEffectID` 做 morphing；仅在真机确认 iOS 27 上有视觉增益时才做。

## 2. 已拍板决策（用户可推翻，执行者不可）

| # | 决策点 | 拍板 |
|---|---|---|
| Q1 | 歌词页顶部小封面比例 | **16:9**（品牌一致；宽 96pt，6pt 圆角） |
| Q2 | 「合集」入口 | **留在更多菜单 sheet**，不进队列页 |
| Q3 | 队列拖拽排序 | **本期不做**；删除行尾 `line.3.horizontal` 假 affordance 图标 |
| Q4 | mini player 封面 | **保持 16:9** |
| Q5 | 歌词控制（偏移/翻译/搜索等） | **全部收进歌词页 `⋯` 菜单**，底部不外露 |
| Q6 | 首页顶部保护渐变 | **改为基于 `AppTheme.background` 的动态渐变**（见 §4.1），浅色模式不再出现黑带 |

## 3. 全局设计 Token（唯一合法值表）

### 3.1 间距（pt，全是 4 的倍数）

| Token | 值 | 用途 |
|---|---|---|
| `xs` | 4 | 行内图标-文字间隙、组内封面间距（首页） |
| `sm` | 8 | 默认控件组间隙、首页组间 |
| `md` | 16 | 页面边缘 padding、section 间距 |
| `lg` | 24 | 大区块分隔 |
| `xl` | 32 | 播放器控制簇分隔 |

既有例外（组件尺寸，不算布局间距，保留）：首页页面边距 8；`TrackRow` 封面 64×36 / 72×40.5；触摸目标 ≥44。

### 3.2 字级（优先用语义样式，保留 Dynamic Type）

| 角色 | 样式 | 用途 |
|---|---|---|
| 标题 | `.headline` / `.subheadline.weight(.semibold)` | 行标题、卡片标题 |
| 正文 | `.subheadline` | 行副标题 |
| 辅助 | `.caption` | 元信息、时长（时长一律 `.caption.monospacedDigit()`） |
| Section 标题 | `.title3.weight(.bold)` | `MusicSectionHeader` 已统一 |
| 播放器标题 | `.system(size: 23, weight: .bold)`（compact 20） | 仅播放页 |
| 歌词行 | `.system(size: 26, weight: .bold)` | 仅歌词页，所有行统一 |

### 3.3 颜色

工具页/列表页：只用 `AppTheme`（`accent` / `background` / `groupedBackground` / `secondaryBackground` / `separator` / `label` / `error` / `success` / `brandSoft`），禁止新增字面量颜色。

播放器沉浸页：`PlayerSurface` 扩展为下表，**替换全部散落字面量**：

| Token | 值 | 归并的旧字面量 |
|---|---|---|
| `textPrimary` | white 0.94 | 0.94 |
| `textSecondary` | white 0.66 | 0.66、0.68 |
| `textTertiary` | white 0.46 | 0.46、0.48、0.58（进度时间标签归此级，设计意图：弱于歌手名） |
| `controlStrong` | white 0.96 | 0.95、0.96、0.92（音量条 tint） |
| `controlEmphasized` | white 0.82 | 0.80、0.82 |
| `controlIdle` | white 0.74 | 0.72、0.74、0.76 |
| `controlDisabled` | white 0.34 | 0.34、0.40、0.42 |
| `fill` | white 0.14 | 0.11、0.12、0.14 |
| `fillStrong` | white 0.74 | 0.72、0.74（激活胶囊底） |
| `stroke` | white 0.17 | 0.17 |
| `divider` | white 0.11 | 0.11 |
| `lyricInactive` | white 0.35 | 歌词非激活行（原 0.58 opacity 方案废弃） |
| `lyricUnsung` | white 0.34 | 逐字未唱部分 |

### 3.4 圆角（全部 `.continuous`）

4（首页封面/小缩略图）· 5（行封面）· 6（prominent 行封面/歌词页小封面）· 8（卡片/播放器封面，`AppTheme.playerCoverRadius`）。

### 3.5 图标

只用 SF Symbols。现有映射冻结，不许换：播放 `play.fill`/`pause.fill`、上一曲/下一曲 `backward.fill`/`forward.fill`、随机 `shuffle`、单曲循环 `repeat`、电台/自动播放 `infinity`、歌词 `quote.bubble(.fill)`、队列 `list.bullet`、收藏 `star(.fill)`、缓存 `arrow.down.circle`/`checkmark.circle.fill`、MV 切换 `headphones`/`play.rectangle(.fill)`、更多 `ellipsis`。

### 3.6 触感

只允许 `SensoryFeedback.intent(_:)`。`HapticIntent` 新增 `case transportImpact → .impact(weight: .medium)`；替换 `NowPlayingView` 中所有直接写的 `.sensoryFeedback(.impact(weight: .medium), ...)`（transport 三键、full queue header 残留）。禁止在视图里直接写 `SensoryFeedback.impact/success/...`。

## 4. 逐页面规格

### 4.1 首页（HomeView）——仅一处调整

海报瀑布流、顶部胶囊、进度线全部保持现状（它们是既定视觉语言）。

唯一变更：顶部 72pt 保护渐变从固定黑色改为跟随背景色，解决浅色模式黑带：

```swift
// 现状（HomeView body 内）：
LinearGradient(colors: [Color.black.opacity(0.65), Color.black.opacity(0.20), Color.clear], ...)
// 改为：
LinearGradient(colors: [AppTheme.background.opacity(0.88), AppTheme.background.opacity(0.35), .clear], ...)
```

深色模式下视觉与现状基本一致（背景近黑），浅色模式下变成自然的白纱。

### 4.2 搜索（SearchView）——不变

已是原生范式：`NavigationStack` + large title + `.searchable` + 统一 `TrackRow`。仅随 §3 token 表例行归位（本页基本没有字面量颜色，预计零改动）。

### 4.3 收藏夹（FavoritesView / FavFolderDetailView / LikedLibraryView）——不变

双列格子 + 拼贴封面 + large title 已是系统语言。frozen：格子横向 padding 10、行距 18、标题 `.subheadline.weight(.bold)` + 副标题 `.caption` secondary。

### 4.4 缓存（LibraryView）——不变

`List(.plain)` + `.searchable` + toolbar 菜单，已是原生。音质标签 `AppTheme.accent` 保留。

### 4.5 设置（SettingsView）——不变

grouped `Form`，原生。CDN 测速区保留现状（自用工具属性，不扩散到其他页）。

### 4.6 播放器（NowPlayingView）——核心改造，见 §5–§7

### 4.7 各 sheet（UPPlaylistsView / FavoriteFolderPickerView / QRLoginView / LyricsSearchSheet / TrackIdentityEditorSheet）——不变

统一模式已是：`NavigationStack` + inline title + `List/Form` + 完成按钮。

## 5. 方案 A：歌词模式化（详细规格）

### 5.1 页面状态机

`NowPlayingView` 内新增：

```swift
private enum PlayerPage {
    case artwork
    case lyrics
    case queue
}
@State private var playerPage: PlayerPage = .artwork
```

- 取代 `showQueue` 与 `showLyrics` 两个 Bool（两者删除）。
- `playerPages` 由 `if showQueue` 改为 `switch playerPage` 三分支；过渡动画沿用现有 `.opacity.combined(with: .scale(...))` 与 `contextTransitionAnimation`，`reduceMotion` 降级不变。
- utility bar：歌词按钮（`quote.bubble(.fill)`）切 `.lyrics`，队列按钮（`list.bullet`）切 `.queue`；在歌词/队列页再点同一按钮回 `.artwork`。激活态视觉沿用队列按钮现有的白底圆形反转样式，两个按钮一致。
- 删除 `.sheet(isPresented: $showLyrics)` 与 `LyricsSheetView` 外壳；`LyricsSearchSheet`、`TrackIdentityEditorSheet`、导入歌词 sheet 保留，由 `NowPlayingView` 继续持有（菜单触发）。
- MV 模式下歌词按钮置灰（沿用 `engine.current == nil` 之外的 `canSwitch` 判断：MV 中不允许进歌词页）；`handleLandscapeMVFullscreen` 的触发条件由 `!showLyrics && !showQueue` 改为 `playerPage == .artwork`。

### 5.2 歌词页布局（PlayerLyricsPage）

歌词开关对齐 Apple Music：底部 `歌词 | AirPlay | 队列` 留在同一层正在播放界面，不随歌词内容一起翻页。再点歌词按钮关回封面。小封面点击仍可返回。图标固定 `quote.bubble`，选中态只用白底圆，不靠 `.fill` 表示「已有歌词」。

歌词模式不是新页面：大封面在同一视图里收到顶栏小封面（只改 frame，不用 matchedGeometry），进度 / 播放键 / 音量直接不出现。utility bar 始终挂在 `NowPlayingView` 底部。

```
VStack(spacing: 0) {
    header                          // HStack，高 56，左右 padding 30；小封面 matchedGeometry
    lyricsScrollView                // 整幅，权重撑满
}
utilityBar                          // 由 NowPlayingView 持有，不进歌词子树
```

**header**：左起 96×54（16:9）封面（6pt 圆角，点击回 `.artwork`，`accessibilityLabel("返回封面")`，id `lyricsArtworkButton`）→ 标题 `.system(size: 17, weight: .semibold)` `textPrimary` 一行 + 歌手 `.system(size: 15)` `textSecondary` 一行 → Spacer → `⋯` 菜单按钮（id `lyricsMoreMenu`，46×38 热区）。

**版本横幅**（`engine.lyricsBanner` 非空时）：歌词区顶部居中胶囊，`caption.weight(.semibold)` + `.ultraThinMaterial`，id 保持 `lyricsVersionBanner`。

**歌词滚动区**：

- `ScrollViewReader` + `ScrollView` + `LazyVStack(alignment: .leading, spacing: 28)`，水平 padding 30，垂直 padding 96。
- 上下 mask 渐变保留现状（stops 0→0.13 / 0.82→1）。
- 每行是 `Button`（点句跳转 `engine.seek(to:)` 保留），`accessibilityLabel(line.text)` + `accessibilityHint("跳转到这句歌词")` 保留。

### 5.3 歌词排版（拍死值）

| 元素 | 值 |
|---|---|
| 所有歌词行 | `.system(size: 26, weight: .bold)`，左对齐，`lineSpacing(4)` |
| 非激活行 | `foregroundStyle(PlayerSurface.textPrimary)` + `opacity(0.35)`（即 `lyricInactive`） |
| 激活行 | opacity 1 + `scaleEffect(1.02, anchor: .leading)`；动画 `spring(response: 0.35, dampingFraction: 0.8)` |
| 翻译行 | `.system(size: 14, weight: .medium)`；激活时 `textPrimary.opacity(0.72)`，非激活随主行 0.35 |
| 行容器 | 高度不随激活态变化（字号统一，scaleEffect 不影响布局） |

### 5.4 逐字辉光（05-04 实施）

纯逻辑先进 `BiliMusic/Player/` 新文件 `LyricHighlightModel.swift`（可单测）：

```swift
enum LyricWordState: Equatable { case sung, current(progress: Double), unsung }

enum LyricHighlightModel {
    static func activeLineIndex(lines: [PlayerEngine.LyricLine], at t: Double) -> Int
    static func wordStates(of line: PlayerEngine.LyricLine, at t: Double) -> [LyricWordState]
}
```

- `activeLineIndex` 即现有 `currentLyricIndex` 逻辑平移（先命中 `from <= t < to`，否则取最后一句 `from <= t`）。
- `wordStates`：`t >= word.to` → `.sung`；`word.from <= t < word.to` → `.current(progress: (t-from)/(to-from))`；否则 `.unsung`。

渲染（激活行内逐字 `Text` 拼接，沿用现有 `AttributedString` 思路）：

| 字状态 | 样式 |
|---|---|
| `.sung` | `textPrimary` |
| `.current` | `textPrimary` + `shadow(color: .white.opacity(0.55), radius: 8)`；可选 `scaleEffect(1.04, anchor: .leading)` |
| `.unsung` | `lyricUnsung`（white 0.34） |

无逐字数据（`line.words` 为空）：整行走 5.3 的激活/非激活亮度，不逐字。原唱时间轴未确认（纯文本降级）同理。

**时间源**：歌词页可见且 `engine.state == .playing` 且当前行有逐字且非 `reduceMotion` 时，用 `TimelineView(.animation(minimumInterval: 1.0/30.0, paused: !shouldAnimate))` 驱动；其余情况回退现有 `engine.adjustedLyricTime` 的 0.5s 更新。`shouldAnimate` 计算放视图内，歌词页不可见时必须暂停（性能红线）。

### 5.5 跟随 / 游离

- 激活行变化且 `engine.lyricsFollowPlayback == true`：`withAnimation(spring)` `scrollTo(activeID, anchor: .center)`。
- 用户在歌词区拖动（`simultaneousGesture(DragGesture)` 检测）：置 `isUserScrolling = true`，取消自动跟随；手势结束起 4s 无操作 → 恢复跟随并居中当前行。
- 游离期间右下角浮「回到当前句」胶囊（`.caption.weight(.semibold)` + `.ultraThinMaterial`，id `lyricsResumeButton`），点击立即恢复。
- `reduceMotion`：滚动居中不动画（走现有 `animate()` helper 的降级）。

### 5.6 `⋯` 菜单内容（顺序冻结）

1. `显示翻译` / `隐藏翻译`（仅当存在翻译行）
2. `歌词校准` 子菜单：`提前 0.5 秒` / `延后 0.5 秒` / `重置偏移（当前 %+0.1fs）`（复用现有 `engine.adjustLyricOffset` / `resetLyricOffset`，偏移值文案沿用 `offsetLabel` 格式）
3. （分割线）
4. `重新识别歌曲` / `搜索翻唱者版本` / `搜索原唱歌词` / `手动搜索候选…`（打开 `LyricsSearchSheet`）
5. `导入本地歌词` / `手动修正歌曲身份`
6. `这份歌词适用于当前翻唱版本`（仅 `versionScope == .canonicalOriginal` 时出现）

## 6. 方案 B：死代码删除清单（05-01）

以下符号在 `BiliMusic/Features/Player/NowPlayingView.swift` 中**无活跃调用点**，逐个用符号搜索确认后删除（UI 测试 `PlayerChromeUITests.swift:109` 已断言抽屉不存在，删除后该测试继续通过）：

**类型**：`QueuePresentationState`、`BottomContextTab`、`BottomContextFrameBox`（先确认无引用）。

**状态字段**：`queuePresentationState`、`bottomContextTab`、`bottomContextDragOffset`。

**视图/函数**：`fullQueueMiniPlayerHeader`、`portraitCoverSize`、`portraitTopPadding`、`portraitCoverBottomSpacing`、`portraitMetadataBottomSpacing`、`bottomContextMaxRows`、`portraitPlayerControls`、`portraitTransportTopPadding`、`portraitToolbarTopPadding`、`portraitBottomContextTopPadding`、`bottomContextDrawer`、`bottomContextHeader`、`bottomContextCornerRadius`、`bottomContextBackgroundHorizontalInset`、`bottomContextBackgroundOpacity`、`bottomContextStrokeOpacity`、`bottomContextPanelTransition`、`bottomContextHandle`、`bottomContextTabPicker`、`bottomContextListPanel`、`currentPlaylistBottomPanel`、`queueBottomPanel`、`recommendationsBottomPanel`、`playerPageState`、`hasBottomContextContent`、`bottomContextEyebrow`、`bottomContextTitle`、`collapsedNextTrackTitle`、`bottomContextFullTitle`、`bottomContextFullListLabel`、`bottomContextAccessibilityLabel`、`bottomContextInteractiveOffset`、`bottomContextHeaderDrag`。

**保留**（被活跃队列页使用）：`guardedPlayerRowButton`、`bottomSheetTrackRow`、`fullQueueHeaderArtwork`、`Layout.bottomSheetRowHeight`。`Layout` 其余成员确认无引用后删。`playerPanelBackground` View 扩展确认无引用后删。

**活跃代码的连带修改**：

1. utility bar 队列按钮：删除 `queuePresentationState = showQueue ? .fullQueue : .collapsed` 一行（`showQueue` 本身在 05-03 才并入 `playerPage`，本片保留）。
2. `appleMusicQueuePage.onAppear`：删除 `queuePresentationState = .fullQueue`。
3. `playerContentTopInset`：三分支同值，简化为 `max(12, safeAreaTop - 12)`（保留 landscape 早退）。
4. `isRecommendationContextVisible`：简化为 `showQueue`。
5. 删除 `onChange(of: queuePresentationState)` 修饰块。
6. `bottomSheetTrackRow`：删除行尾 `Image(systemName: isCurrent ? "waveform" : "line.3.horizontal")` 中的 `line.3.horizontal` 分支——非当前行行尾不再显示任何图标（当前行保留 `waveform`）。
7. `guardedPlayerRowButton` 增加按压反馈：`@GestureState private var isPressed`（改为结构体视图），行背景 `Color.white.opacity(isPressed ? 0.08 : 0)`，圆角 8。

## 7. 方案 C：文件拆分映射（05-02）

新增文件后必须 `xcodegen generate`。

| 新文件 | 迁入符号 |
|---|---|
| `NowPlayingView.swift`（保留） | `body`、`playerPages`、`playerBackground`、`nowPlayingPage`/`portraitNowPlayingPage`/`landscapeNowPlayingPage`、`mediaView`、`artworkPlaceholder`、`playerContentTopInset`、`Layout`、`PlayerSurface`（扩展后）、`contextTransitionAnimation`/`animate`、`handleLandscapeMVFullscreen`、`InlineMVPlayerView`/`InlinePlayerLayerContainerView`、utility bar / metadata row / volume / transport / toolbar 各私有视图 |
| `Features/Player/PlayerQueuePage.swift`（新） | `appleMusicQueuePage`、`appleMusicQueueHeader`、`appleMusicQueueModeControls`、`appleMusicQueueModeButton`、`appleMusicQueueList`、`appleMusicAutoPlayRows`、`bottomSheetTrackRow`、`guardedPlayerRowButton`、`fullQueueHeaderArtwork`、`scrollCurrentQueue`、`playerDivider` |
| `Features/Player/PlayerLyricsPage.swift`（新） | 方案 A 产物（05-03 填充） |
| `Features/Player/PlayerContextStore.swift`（新） | 新增 `@Observable @MainActor final class PlayerContextStore`：迁入 `recommendedTracks`、`recommendationsLoading`、`recommendationsError`、`currentPlaylist`、`currentPlaylistTracks`、`currentPlaylistLoading`、`currentPlaylistError`、`suppressNextRecommendationRefresh`、`recommendationsStale`、`recommendationSeedKey`、`shownRecommendationKeys`、`recommendationTask`、`recommendationLoadID`、`playlistLookupTask`、`scheduledPlaylistBVID` 十五个状态字段，以及 `scheduleRecommendationLoad`/`loadRecommendations`/`scheduleCurrentPlaylistLookup`/`loadCurrentPlaylistIfNeeded`/`applyPlaylistLookup`/`storePlaylistLookup`/`playCurrentPlaylistTrack`/`scrollCurrentPlaylist`/`ensureRecommendationsLoadedIfVisible` 方法（改为以 `PlayerEngine` 为参数的 `@MainActor` 方法）。`RecommendationPanelRefreshPolicy`、`RecommendationVisibleLoadPolicy`、`PlaylistLookupResult`、`PlayerPlaylistLookupCache` 一并迁入本文件，保持纯值语义不改逻辑 |
| `PlayerControlViews.swift` | 不动 |
| `PlayerSheetViews.swift` | 删除 `LyricsSheetView`（05-03），其余不动 |

`NowPlayingView` 持有 `@State private var contextStore = PlayerContextStore()`，队列页/歌词页通过参数或 environment 读取。迁移时**逐方法保持函数体不变**，只改 `engine.xxx` 为入参。

同步进行 §3.3 的 `PlayerSurface` 扩展与字面量归并（按归并表逐处替换）。

## 8. 方案 D：抛光项精确变更（05-05）

| # | 变更 | 精确做法 |
|---|---|---|
| D1 | 文案中文化 | `appleMusicQueueList` 的 `"Queue"` → `"队列"`；`"AutoPlay"` → `"自动播放"`（死代码里的 `"Playing from"/"Up Next"/"Related"` 随 05-01 消失） |
| D3 | 封面页布局公式 | 删除 `fixedContentHeight`/`gapBudget`/`minimumGapBudget` 数学。`portraitNowPlayingPage` 改为：`mediaView` → `Spacer(minLength: 12)` → metadataRow → `Spacer(minLength: 12)` → progressView → `Spacer(minLength: 16)` → transportControls → `Spacer(minLength: 20)` → volumeControl → `Spacer(minLength: 12)` → utilityBar → 底部 padding 16。封面尺寸计算保留现有 `playerCoverSize`（含 availableHeight 检查）。验收：667pt 高（SE 类）与 932pt 高（Pro Max 类）模拟器均不溢出不重叠；动态字体最大档标题截断为单行不挤压控制区 |
| D4 | 图片淡入 | `CachedAsyncImage.body`：`content(...)` 分支加 `.transition(.opacity)`，Group 上加 `.animation(reduceMotion ? nil : .easeIn(duration: 0.15), value: resolvedDisplayImage == nil)`；新增 `@Environment(\.accessibilityReduceMotion)`。跑 `PlayerChromeUITests` 确认无闪烁回归 |
| D6 | 长按预览 | 首页 `coverTile` 与 `FavFolderDetailView` 的 `MagazineTrackTile`：`contextMenu` 增加 `preview:` 闭包，内容为 `MagazineArtwork(url: track.coverURL, pixelWidth: 640).frame(width: 320)` |
| D7 | 收藏错误 | 删除 metadata 下方红色 `Text(favoriteError)`；改为播放器底部浮层胶囊：`caption.weight(.semibold)` + `.ultraThinMaterial`，出现 4s 自动消失（`Task` + `withAnimation`），id `playerFavoriteErrorToast` |
| D8 | 触感收口 | 见 §3.6 |

## 9. 执行切片

### 05-01 死代码删除与状态收敛

- 内容：§6 全部。
- files_modified：`NowPlayingView.swift`。
- 验证：
  - `xcodebuild -project BiliMusic.xcodeproj -scheme BiliMusic -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  - `xcodebuild test ... -only-testing:BiliMusicUITests/PlayerChromeUITests`（含抽屉不存在断言与密集布局门禁）
  - `xcodebuild test ... -only-testing:BiliMusicTests`
- 回滚：`git checkout -- BiliMusic/Features/Player/NowPlayingView.swift`。

### 05-02 拆分与 token 收敛

- 内容：§7 + §3.3 归并表 + §3.6 `HapticIntent.transportImpact`。
- files_modified：`NowPlayingView.swift`、新增 `PlayerQueuePage.swift`、`PlayerContextStore.swift`、`Design/Haptics.swift`、`Design/AppTheme.swift`（PlayerSurface 若移入）。
- 验证：同上三条命令 + 全量 `PlayerChromeUITests`。
- 注意：先加文件 → `xcodegen generate` → 再迁移符号。

### 05-03 歌词模式化

- 内容：§5.1–5.3、§5.6；新增 `PlayerLyricsPage.swift`；删除 `LyricsSheetView`；`showLyrics`/`showQueue` 并入 `playerPage`。
- UI 测试更新（必须同片完成）：
  - `testLyricsSheetShowsSyncedTranslationAndOffsetControls` 重写：点歌词按钮 → 断言 `playerLyricsPage` 出现在 `nowPlayingView` 内（不再是独立 `navigationBars["Fixture Song One"]`）；翻译行可见；打开 `lyricsMoreMenu` → `歌词校准` → 断言偏移项存在。
  - 新增断言：歌词模式下 `nowPlayingProgress` 与 transport 不存在；底部 `playerUtilityBar` 仍在同一正在播放层。
- 验证：三条命令 + 上述测试。

### 05-04 逐字辉光与跟随

- 内容：§5.4、§5.5；新增 `BiliMusic/Player/LyricHighlightModel.swift`。
- 单测（新增 `BiliMusicTests/LyricHighlightModelTests.swift`）：边界（t 在行间空隙、首行前、末行后、空 words、words 乱序输入按 from 排序后处理）。
- UI 测试：fixture 若含逐字歌词，断言激活行内存在未唱字（透明度分层）；不含则只测行级激活。
- 验证：三条命令。

### 05-05 抛光批量

- 内容：§4.1 首页渐变 + §8 全部。
- 验证：三条命令 + 全量 UI 测试；首页渐变在浅色/深色两种外观各截一张模拟器图人工比对。

### 通用验证命令

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BiliMusic.xcodeproj -scheme BiliMusic \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

测试目的地按本机模拟器调整（历史命令用 `platform=iOS Simulator,name=iPhone 17`）。

## 10. 验证边界与真机清单

- 每片：编译 + `BiliMusicTests` 全绿 + 相关 `PlayerChromeUITests`。
- 真机确认（05-03/05-04 后）：短歌/长歌/无逐字/带翻译四类样本的歌词滚动与辉光；歌词页与队列页往返切换 20 次无卡顿；动态字体最大档封面页不溢出；浅色模式首页顶部无黑带。
- 性能红线：歌词页不可见时 `TimelineView` 必须暂停；逐字渲染只在激活行做逐字拼接，其余行整行 `Text`。

## 11. 风险

1. `popupTransitionTarget` 挂在 `mediaView` 上；歌词/队列页没有等尺寸封面，LNPopup 开合动画的 target 缺失可能导致转场跳变 → 05-03 真机必测，必要时把 target 移到歌词页小封面。
2. `PlayerContextStore` 迁移涉及时序敏感代码（推荐/合集加载），函数体逐字迁移、不改逻辑；迁移后跑推荐相关单测。
3. 死代码清单以 2026-08-19 的调用点核查为准；执行时逐符号再确认一次（防止期间新增引用）。
4. 图片淡入可能让快速滚动时封面「晚到」感增强；0.15s 是上限，不得更长。

## 12. 开放问题（执行中才允许问用户的）

- 真机若确认 LNPopup 转场跳变，歌词页小封面是否承担 transition target（默认：是）。
- 队列拖拽排序是否立项（默认：不立项）。

---

*2026-08-19 初稿为讨论稿；同日按用户要求扩为可直接移交执行的实施规格（决策全部拍死，见 §2）。*
