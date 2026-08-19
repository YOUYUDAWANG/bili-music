[根目录](../../../CLAUDE.md) > [Features](../) > **NowPlaying (播放器 UI)**

## 模块职责

全屏正在播放页的 UI 实现。内容视觉采用“横版影像唱片机”：16:9 封面、电影字幕式信息与封面派生双色光场。首页封面入口与 mini player 入口统一使用 LNPopupController。

## 入口与启动

- **文件**: `NowPlayingView.swift`（主入口）、`PlayerQueuePage.swift`、`PlayerLyricsPage.swift`、`PlayerContextStore.swift`、`PlayerControlViews.swift`（控制子视图）、`LyricMotionDirector.swift`、`LyricStageScore.swift`、`LyricStageView.swift`、`LyricStagePrototypeView.swift`、`LyricStageScoreV2.swift`、`LyricStageTokenizer.swift`、`LyricStageCompilerV2.swift`、`LyricStageCanvasView.swift`、`LyricWordPerformanceModel.swift`、`LyricPerformanceScore.swift`、`LyricPerformanceStore.swift`、`LyricStageStoreV2.swift`、`PlayerSheetViews.swift`（合集/收藏/歌词搜索等 sheet）
- 由 `RootView` 的 LNPopupUI `.floatingCompact + .automatic` 容器承载。
- 首页点击封面后由 RootView 直接打开同一个 LNPopup 内容控制器；播放页不区分“首页直开”和“mini player 打开”两套生命周期。
- 迷你播放器、主播放器开合、跟手下滑和安全区停靠由 vendored LNPopupController 统一管理；播放页自身不维护全屏级纵向关闭手势。

## 对外接口

### NowPlayingView


### 页面组成

| 子视图 | 用途 |
|--------|------|
| 播放器模式选择器 | 音乐/MV 切换 |
| 封面/视频 | 16:9 封面或 AVPlayer 视频播放器 |
| 曲目信息 | 标题、歌手、错误信息 |
| PlayerProgressBar | 原生 `Slider` 进度条（独立子视图限制 currentTime 订阅范围，并桥接 scrub 生命周期） |
| 控制按钮 | 上一曲、播放/暂停、下一曲 |
| 操作栏 | 收藏（短按/长按）、下载、音乐/MV 切换、更多 |
| 接下来播放页 | `PlayerQueuePage`：与主播放器同屏切换；显示完整当前队列和自动播放推荐 |
| 歌词预览/模式 | 封面页弹性区由本地规则或 Luna 驱动逐行演出；Luna 可为每个时间点选择 1–3 行真实歌词构图，不再固定当前句＋下一句。长句完整换行、禁止省略号；点击进入 `PlayerLyricsPage`。完整歌词仍是同一层正在播放，支持逐行/逐字高亮、翻译、跟随、点击跳转，校准/搜索收进 `⋯` 菜单 |
| MV 全屏 | MVFullscreenView（全屏视频播放） |

### 视觉边界

- 竖屏封面接近屏幕边缘，标题/歌手左对齐并与封面左缘同基线；横屏信息也保持左对齐。
- 竖屏封面与 metadata 是固定组合；progress / transport 是固定节奏控制簇。metadata 与控制簇之间的唯一弹性区支持 Rise / Impact / Drift / Breathe / Echo / Focus / Drop / Stretch / Cascade 九种逐行演出；无同步歌词时保持留白。动画只在 full player 展开、播放中且 App active 时运行。播放器不显示软件音量条，音量交给实体键，AirPlay 入口保留。
- 当前 UI 与性能只以用户自用的 iPhone 17 Pro / iOS 27 为目标，不再为了 SE 收缩字号、位移和留白；Reduce Motion 仍必须可用。
- Debug 菜单可显式请求 Luna 编排并缓存 `lyric-performance-v4`；逐行 composition/scene 规则不变，新增稀疏 wordCues。真实逐字歌词始终有本地 Sweep；Luna 每行至多给一个不超过 12 个字的 Sweep / Impact / Stretch / Echo Trail 范围。逐字舞台只在 full player、播放中、App active 时以局部 30fps 读取 AVPlayer 时间，不扩散刷新到 RootView/LNPopup；Reduce Motion 关闭位移、缩放和残影但保留高亮。网络失败无缝回退，该入口不得自动触发或进入 Release 播放关键路径。
- Debug 菜单另有完全本地的 `LyricStagePrototypeView`：18 秒四幕循环验证逐字、整句与双声部二维编排。它不读取真实歌词、不调用 Luna、不写缓存，只替换中央歌词预览区域；正式 v5 前不得把这个少量 SwiftUI glyph view 原型误记为 StageScore/TextRenderer 引擎。
- Debug 的 v5 真实歌词舞台由 `LyricStageCompiler` 将真实歌词、多声部和现有/原生 Luna directive 编成八种 behavior；真实逐字边界驱动 glyph emphasis，逐行轴只做视觉 stagger。`LyricStageView` 局部 60fps、暂停/后台/Reduce Motion 停止逐帧运动，完整文本用自定义 wrap layout。
- Debug 另有 V5.1 Event 舞台：`LyricStageScoreV2` + 本地导演/旧脚本适配 + `LyricStageCompilerV2` 预编译字符轨道，`LyricStageCanvasView` 每帧只做 `sample(at:)`。Luna `/v2` 脚本写入独立的 `lyric-stage-v2.json`，不覆盖 v4 缓存；失败时同一 Score 退回静态完整歌词。默认仍是本地规则，V5 / V5.1 / 样片均需 Debug 开关。线上 `/v2` 并行生成 bible 与最多 4 段 scene；客户端空闲 90s、总超时 120s。
- 生产 Luna 已能直接返回全曲 `stageBible` 与逐行 `stageDirectives`；Debug 真机先点“启用 v5 真实歌词舞台”，再用“用 Luna 编排演出/重新生成 Luna 演出”取得原生 v5 编排。旧的本地 v4 缓存仍会映射运行，但需重新生成才会获得原生 v5 directive。
- 背景仅使用 `PlayerArtworkPalette.top → bottom` 的克制双色渐变和轻微暗化，不做封面模糊、径向 glow 或高饱和硬撞色。
- 系统 Liquid Glass 由 RootView 的底栏浮岛和必要 MV 浮层承担；播放内容层与队列不新增材质卡。
- 播放器不再提供本机 MLX 生成：真机 ASR 与 Forced Aligner 均出现过 Metal 完成队列不可捕获 `SIGABRT`。相关算法只留作 smoke test，用户逐字生成统一走高精度主机。
- 已有逐行 LRC 时，`⋯` 菜单另提供「高精度主机生成/重新生成」：显式上传缓存音频到 Windows，等待双模型共识，App 二次门禁通过后才替换；纯文本和并行声部不走该路径。
- 同时演唱时完整歌词页高亮全部 active 声部；中央画布优先显示真实 overlap group，主唱保持主视觉、和声缩小降权、A/B 二重唱接近等权。Luna 只能作用于视觉，不能用 composition 改写真实声部时间关系。
- 完整歌词页的自动滚动与亮度共用同一行索引：严格时间窗内保留所有并行 active 声部；两句时间戳存在空档时，滚动与高亮都回退到最近已开始的一行。
- 完整歌词页会消费 `current(progress)`，在每个真实字/词的持续时间内以 30fps 从左到右扫亮字形，不再在字与字之间整块瞬间变亮。自定义 wrap layout 按原 token 宽度换行，不丢英文空格或中日韩文字。

## 关键依赖与配置

- `PlayerEngine` — 所有状态通过 Environment 读取。
- `RecommendationEngine(.relatedPanel)` — 推荐歌曲数据源。
- `BiliClient.upPlaylistContaining` — 合集检测。
- `FavoriteManager` — 收藏操作。
- `CacheStore` — 检查/显示下载状态。
- `DownloadManager` — 下载操作。

## 数据模型

所有使用的模型在 PlayerEngine 或其他模块中定义。本模块内：
- `PlaylistLookupResult` — 合集查找结果
- `PlayerContextStore` — 推荐与合集加载状态
- `PlayerPage` — 封面 / 歌词 / 队列三页
- `LyricPerformanceScore` / `LyricPerformanceStore` — Luna 稀疏演出脚本及按歌曲＋歌词哈希持久化
- `LyricStageScore` / `LyricStageCompiler` — v5 本地舞台合同、Luna directive 适配、grapheme 时间轨与多声部构图
- `LyricStageScoreV2` / `LyricStageCompilerV2` / `LyricStageStoreV2` — v5.1 Event 舞台合同、预算编译与独立缓存

## 相关文件清单

- `NowPlayingView.swift`
- `PlayerQueuePage.swift`
- `PlayerLyricsPage.swift`
- `PlayerContextStore.swift`
- `PlayerControlViews.swift`
- `LyricMotionDirector.swift`
- `LyricStageScore.swift`
- `LyricStageView.swift`
- `LyricStagePrototypeView.swift`
- `LyricStageScoreV2.swift`
- `LyricStageTokenizer.swift`
- `LyricStageCompilerV2.swift`
- `LyricStageCanvasView.swift`
- `LyricStageStoreV2.swift`
- `LyricWordPerformanceModel.swift`
- `LyricPerformanceScore.swift`
- `LyricPerformanceStore.swift`
- `PlayerSheetViews.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-08-20 | 完整歌词页改为消费逐字 progress 的左到右连续扫亮，保留自动换行与完整可访问文本。 |
| 2026-08-20 | V5.2 扩为「You＆合図」176.518 秒专曲全曲舞台；精确逐字轴严格拥有 reveal，±90ms 音频事件只做 accent，不再向后吸附造成延迟；仍不是通用分析器。 |
| 2026-08-20 | V5.3 以「You＆合図」作基准但运行时不含歌曲分支：重复 Hook 簇四阶段递进，普通段落七种通用构图；规则 19/19、十关键帧 UI 1/1，签名真机包已安装启动。 |
| 2026-08-19 | 增加「You＆合図」37.8–67.4 秒 V5.2 黄金样片：真实逐字轴加 beat/onset/energy 物理场，点击 seek 播放；八关键帧检查后安装真机。 |
| 2026-08-19 | 修复歌词时间戳空档期间只自动滚动却不高亮；滚动与亮度统一回退行。 |
| 2026-08-19 | 修复 V5.1 选择后无反应与几帧卡顿：首次进入自动请求线上导演，hold 呼吸不再被预算删除，Canvas 显式消费播放 tick 并以 60/30fps 刷新；Debug 包已覆盖安装真机。 |
| 2026-08-19 | Luna V5.1 `/v2` Worker 已上线并通过真实 Event Score；本轮未安装新真机包，默认仍是本地规则。 |
| 2026-08-19 | 停用会触发真机 MLX Metal SIGABRT 的本机生成入口；主机按钮改为可点击并显式报配置错误。 |
| 2026-08-19 | 播放器菜单接入 Windows 高精度歌词来源，显示主机进度与共识摘要。 |
| 2026-08-19 | Luna v5 Worker 上线并安装 Debug 真机包；原生 Stage Bible/stageDirectives 可由播放器显式生成。 |
| 2026-08-19 | v5 真实歌词舞台第一版：StageScore、逐字 glyph 轨、多声部与 Luna v4/v5 兼容编译。 |
| 2026-08-19 | 增加本地 v5 kinetic typography 四幕样片与 Debug 开关，不改 Luna v4。 |
| 2026-08-19 | 歌词页与中央画布支持同时显示主唱、和声及 A/B 二重唱声部。 |
| 2026-08-19 | Luna v4 增加受约束的逐字导演谱；本地 Sweep 加稀疏 Impact / Stretch / Echo Trail，保持完整自动换行。 |
| 2026-08-19 | 文本候选在时长接近时恢复跟随播放；时长差过大才不跟播。 |
| 2026-08-19 | 同版本优先有时间轴的歌词；文本候选保留 LRC 但不跟随播放。 |
| 2026-08-19 | 增加本机逐字歌词入口；Qwen3 按逐行时间轴分段对齐并严格校验后才替换。 |
| 2026-08-19 | 手动歌词搜索一次聚合五个源，列表显示来源。 |
| 2026-08-19 | 手动歌词搜索增加 LRCLIB / VocaDB；自动匹配不再一写入就平移。 |
| 2026-08-19 | Luna 合同升级 v2：导演逐行决定 1–3 行真实歌词构图；中央歌词移除所有单行截断，长句完整换行。 |
| 2026-08-19 | 增加 Debug Luna 编排/重新生成/恢复本地规则入口；演出脚本校验缓存后才覆盖本地 cue。 |
| 2026-08-19 | 中央歌词加入确定性 LyricMotionDirector 与五种逐行动效；验收目标收窄为 iPhone 17 Pro / iOS 27。 |
| 2026-08-19 | 「自动对齐」改为歌词落点打分，有缓存时再用音频能量对轴。 |
| 2026-08-19 | 手动歌词搜索默认填清洗后的日文原名，不沿用中文译名关键词。 |
| 2026-08-19 | 歌词校准改为系统 sheet 滑块（±10 秒），不再用菜单里的 ±0.5 秒按钮。 |
| 2026-08-19 | 竖屏 artwork 页重分配弹性空间：封面/信息与控制簇内部采用 compact/regular 固定节奏，只保留一处主弹性 Spacer。 |
| 2026-08-19 | 歌词封面缩放改为同一视图改 frame，去掉 matchedGeometry 与动画中的大图阴影。 |
| 2026-08-19 | 歌词改为同一层正在播放模式：封面就地缩小，进度/播放键/音量直接不出现；底部歌词/AirPlay/队列栏由 NowPlayingView 持有。 |
| 2026-08-19 | 歌词页播放控件按 Apple Music 空闲约 5 秒淡出，底部歌词/AirPlay/队列栏保持可见。 |
| 2026-08-19 | 歌词开关对齐 Apple Music：歌词页保留底部歌词/AirPlay/队列栏，同一按钮再点关闭；选中态用白底圆而不是气泡 fill。 |
| 2026-08-19 | Phase 05：删除抽屉死代码；拆分队列页与推荐状态；歌词改为播放器内整页；逐字辉光与跟随；播放器 token 收口。 |
| 2026-08-19 | 歌词页升级为逐字/翻译沉浸视图，加入手动来源、候选选择、点击跳转与偏移校准。 |
| 2026-08-19 | 首页直开与 mini/full 开合统一回归 LNPopup，移除 Home 自制播放器转场。 |
| 2026-08-14 | 首页封面原位放大与反向缩回改为非阻塞局部动画层；缩回期间瀑布流仍可操作。 |
| 2026-08-14 | 建立横版影像唱片机视觉：封面贴近边缘、电影字幕式左对齐、封面双色光场；系统玻璃只保留在外壳。 |
| 2026-08-14 | 按 Apple 官方正在播放与队列行为重构：LNPopup 原生 grabber、系统音量/AirPlay、同屏 Queue + AutoPlay，移除主页面常驻抽屉。 |
| 2026-08-14 | 收紧播放器纵向节奏；collapsed 显示下一首标题，split 在固定可视高度内开放完整队列滚动。 |
| 2026-08-14 | 融合 LNPopup 性能架构与底部三段式抽屉；移除已由框架取代的自制开合手势和逐帧 frame 监听。 |
| 2026-07-27 | 全项目 review 修复 + 文档同步：播放器子视图拆分并补充列表与手势回归；UI 层行为由 `BiliMusicUITests/PlayerChromeUITests` 以 fixture 覆盖。 |
| 2026-06-24 | 初始文档创建。 |
