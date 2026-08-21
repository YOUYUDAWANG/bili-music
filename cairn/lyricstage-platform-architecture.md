---
type: project_topic
status: active
summary: "LyricStage 以 BiliMusic iOS 为参考实现，使用来源无关合同、独立全屏 Web 舞台与后续 Provider/Bridge 分层。"
tags: [lyricstage, web, platform, architecture, renderer, provider]
contains: [decision, boundary, architecture]
created: "2026-08-21"
updated: "2026-08-22"
related: [".planning/phases/06-lyricstage-platform-and-web-reference/06-CONTEXT.md", ".planning/phases/06-lyricstage-platform-and-web-reference/06-00-DESIGN.md", "cairn/lyric-stage-v4-scene-recipe.md"]
authoring_mode: ai_generated
---

# LyricStage 平台架构

## 当前定位

BiliMusic iOS 是第一个可日用的参考客户端，也是歌词事实、音频结构、Luna Recipe 与确定性渲染器的现有验证场。它不是未来所有客户端都必须复制的 UI 或数据模型。

Phase 06 已由用户启动：本地音频与时间轴歌词已证明第二运行时，YouTube Music Companion v0 随后成为第一个在线来源。当前已落地来源无关歌词/导演合同、六组共享 fixture、单窗口全屏 Web Stage Alpha 和只读 YTM 时钟桥；真实 Chrome 已关闭原生 Lyrics 挂载、切出恢复与切回唯一 host 的核心门。自动歌词已从单一 LRCLIB 扩为本地身份清洗、LRCLIB 多查询、酷狗直连与可选私有 LDDC 的分层实现并通过自动检查；真实 Chrome 命中、全屏、seek/换歌/多标签与性能门仍待继续。

2026-08-21 起另开不接触 YTM Column 的 Performance Lab 演出切片；时间索引、可 seek 动作剪辑、PixiJS GPU 环境、Theatre.js 开发期 authoring、Director Plan、结构边界热切换与生产全屏 Stage 均已落地。Column 仍只负责克制可读的宿主歌词增强，演出复杂度只进入全屏。

## 稳定边界

1. **共享语义合同，平台分别编译布局。** 可共享 Recording/Lyrics/Audio Structure/Director Recipe/Performance identity；SwiftUI 的 340pt 几何、字号与运动预算不进入跨平台合同。
2. **歌词事实拥有正文与同步。** Luna 和音频结构都不得改写歌词或提前/延后 reveal。
3. **Web 是全屏旗舰舞台。** Control 与 Stage 分离，观众画面不保留手机播放器 chrome；16:9、第二屏与投影是 v0 参考环境。
4. **static-first 不因画布变大而失效。** 环境可持续缓慢运动，正文普通段落必须落稳；大动作只属于结构时刻、声部交换和 Hook 发展。
5. **本地文件先行是解耦门禁。** 它不代表 Bilibili 取流困难，而是保证核心在没有 bvid/cid、Cookie 或私有 API 时仍能完整运行。
6. **在线导演是排练工具。** 正式演出只消费已校验、已缓存的 Recipe/Plan；断网始终有完整本地 fallback。
7. **Provider 与 Runtime 分层。** Bilibili 未来由同源 BFF 处理鉴权、WBI、Range 与短效 URL；YouTube Music 优先用 companion/bridge。Provider 不拥有歌词演出语法。
8. **宿主播放不搬家。** YouTube Music 标签页继续拥有账号、音频、播放控制与权威时钟；扩展只传 `videoID`、展示元数据和播放快照。单曲绝对时间与总时长以 `ytmusic-player-bar` 可见时钟为准，不以可能被 YTM 跨曲复用的 `<video>/<audio>` 内部轴为准；媒体元素只提供播放状态、倍速与整秒锚点间的亚秒增量。Stage 可在快照间平滑外推，但 seek、换媒体或新快照必须重校准，不能建立第二播放时钟。
9. **演出只属于全屏。** 原生 Lyrics Column 保持克制、可读与稳定；Performance Runtime 不挂进窄栏。每首歌允许完全不同的美术方向，但必须由有限、可校验的构图和运动语法生成，不能让模型直接输出任意脚本。
10. **自动导演后台生成、结构边界换装。** 曲目身份稳定后可在后台以标题、歌手、完整歌词/时轴与精确公开 YouTube video ID 请求 Director Plan；Gemini 3.7 可把该公开视频作为整曲语义/结构上下文，但不上传 PCM、Cookie、私有媒体 URL 或封面像素。未命中缓存时立即使用高质量本地 fallback；线上结果只在下一结构边界接管，避免半句跳风格。
11. **字体与封面是受控输入。** 字体只从项目内审定的日文/CJK/拉丁字体集合中选择；06-06 起真实封面作为稳定 Now Playing 锚点直接展示，环境只消费其抽象颜色与纹理，不拉伸封面充当背景。默认模式保留可读性与闪烁保护，VJ 强度不得覆盖 Reading、效果证据或 reduce-motion。
12. **MusicMap 只携带压缩音乐事实。** 本地 tab audio 最终只编译为有界 `MusicMapV1`：归一化频段/能量/明亮度/flux/onset/声场、可信 tempo、最多 96 个段和 256 个结构地标；不得发送 PCM、FFT frame、MediaStream、媒体 URL 或可还原音频的样本。歌词时轴仍是 reveal 唯一事实，MusicMap 只能在已测时间之后影响强调与结构。
13. **人声感知只修正本地低置信估算。** `VocalTimingMapV1` 只保存滚动窗口内的归一化人声存在度、起音与置信度，用于 Column 对 `estimated` 逐字做单调、有界的局部时间扭曲；覆盖或置信不足时必须精确回退文本估算。它不缓存、不发送给 Director/Fullscreen，不改变 `LyricDocument`，也不得覆盖原生 word timing 或成为 reveal/beat/结构事实。

## 06-06 当前实现边界

- 默认使用 Stage-first 30/70 构图：真实封面、标题/艺人、细进度和 Bridge 权威运输控制在左，三层常态歌词/分幕/Hero/Duet/Aperture 在右；顶部和底部无浮动控制条。
- 三层常态 Reading 是一条统一 leading axis 的连续歌词栈，不是三个独立居中标题：短 CJK/Latin 在换行前测量缩字以避免孤行，换句整栈确定性上移，唱词期间保持稳定；本地日文默认无衬线，AI 只有在有证据的特殊 presentation 才可改变字体或破轴。
- Apple Music 只提供完成度与层级参考，不做像素复刻；Liquid Glass 只属于瞬时交互功能层，不铺在内容背景。
- 每个 section 可申请封面缩岛与 Hero，但只在结构、语义、冷却、可读性和运动预算成立时执行；Hero 全曲目标 15–25%。
- Performance Direction Skill 由小型 primitive registry、effect cards、正反例、schema 和 evidence grammar 构成。导演可选 card、修改 card 或组合已注册 primitive，不得输出任意代码或新 runtime 原语。
- 强效果必须引用 song motif、section trigger 和真实 lineIndex；单个关键词最多触发逐句微动作，不能独立导致背景换装。
- AMLL 0.5.2/TTML 1.0.1 spike 已形成 `06-06-AMLL-ADR.md`：生产选择 AMLL 原则 + 单一 LyricStage glyph renderer，不并置第二套 DOM player/逐帧 clock；真实 TTML 输入出现前不增加无用途 parser 依赖。
- `EffectRecipeV1`、20 个 typed primitives、17 张 evidence-bearing cards、互斥/成本/反证/reduce-motion fallback 已进入本地 compiler、renderer、独立 Director Skill、服务端验证与扩展客户端二次验证。除既有场/几何/记忆/密度/封面/转场外，新增 ribbon、prism、rain、orbit、memory trail、cover portal 与 bloom；未知 primitive、任意代码、低证据 Hero 与冲突组合 fail closed。
- 实施与退出门以 `06-06-DESIGN.md` / `06-06-PLAN.md` 为准；当前只剩最新扩展在真实 Chrome 重载后的整首视觉/交互确认，不能把本地 fixture 门替代成真实 YTM 已验收。

## 当前 canonical 参考链

```text
LyricDocument
  + AudioPerformanceMapV2 / AudioStructureScoreV4
  + optional Scene Recipe V4
  -> local deterministic compiler
  -> capability-specific PreparedStage
  -> Swift or Web renderer
```

Web v0 不全量移植 V1–V5.2 历史实验。V5.2 单曲样片和旧导演版本保留作研究/fixture；V5.3 完整 fallback 与 V4 typed Recipe 是首个跨平台参考基线。

## Web Alpha 当前实现

- `web/apps/stage`：本地音频、LRC/规范 JSON、唯一 `<audio>` 时钟、排练控制与单窗口 Fullscreen。
- `web/packages/contracts`：JSON Schema、严格 TS validator、六组无版权 fixture。
- 扩展环境不在运行时调用 Ajv codegen；合同校验器在构建期生成静态 ESM，extension build 会拒绝 `eval`、`new Function`、CommonJS `require` 与浏览器中不存在的 `process.env`，以满足 Manifest V3 CSP。
- `web/packages/core`：LRC 解析、确定性 local plan、O(log n) 时间边界采样。
- `web/packages/renderer`：保留旧 `PreparedStageV0` 作兼容；生产全屏改用 `PreparedDirectedStageV1`，直接保留 section 与完整 line directive，负责受控字体、完整安全区换行、五层 Canvas2D 合成和九种动作的确定性任意时间采样。
- `web/packages/performance`：Production Performance Runtime。`TimedTextIndexV1` 提供真实 phrase/word/character O(log n) 采样且不伪造逐字；`MotionClipV1` 提供可 seek 数字动作轨；`EnvironmentSceneV1` 按 recording/section/direction identity 确定性编译 palette/particle/rail/orb。`DirectorPlanV1` 以连续 section、完整 line directive、受控 art/layout/typography/palette 和 plan identity 为唯一生产导演合同；本地 compiler 始终完整覆盖。0.2.1 的生产路径只接受独立 Fullscreen Director 返回的 non-degraded、同 track/recording/lyrics identity、连续 section 和全行 directive；旧 Legacy adapter 只留兼容测试，不再被 Background 调用。handoff 只在下一 section 边界生效。
- `web/apps/performance-lab`：与 YTM、AI、正式 Stage 隔离的开发排练台。PixiJS 8.20.0 WebGL 只负责环境层，DOM/CJK 正文继续独立；可切六组共享 fixture/MotionClip，以播放、毫秒、滑杆或 ±1 frame 检查 16:9 构图。Theatre.js 0.7.2 仅在 DEV 动态加载，可编排 intensity/bloom/drift/railOpacity、跟随 playhead、显隐 Studio 与导出 project state；production 静态门确认不含 Theatre。
- 2026-08-21 真实浏览器验证：2900ms 逐字命中；15000ms 日英重叠声部；GPU 为 WebGL，680×383 CSS 画布对应 1360×766 backing store；换 fixture 后 scene seed 更新，Theatre 值实时回写 GPU tuning。React StrictMode/Pixi 异步销毁和 Theatre CJS/重复配置竞态已在真实运行中修复。聚焦测试 9/9、typecheck、独立 production build 通过。
- `web/apps/youtube-music-companion`：Manifest V3 content script + Service Worker + popup + extension Stage；单一来源择主、换歌歌词失效和本地模式回退。
- Column 的放大镜提供显式手动歌词搜索：用户输入歌名、可选歌手后，后台不读取自动 miss cache，按输入身份重跑 LDDC/LRCLIB/酷狗；精确结果也先作为候选，不自动采用。候选仍受当前 trackID、来源/艺人/时长显示、签发缓存和换歌失效约束，选择后才成为当前歌曲的本地记忆；手动搜索不是绕过身份安全门的任意 LRC 注入接口。
- LDDC 原生逐字不再在 Web adapter 中降为逐行 LRC：只有后端明确返回 `timingKind=word` 且每个 word 单调、位于所属行内、数量受限时，候选才携带严格 `wordTimedDocument`。安装时只重绑当前 YouTube recording identity，SponsorBlock 同步平移行与 word；Column 和 Fullscreen 使用同一真实轴。无 word timing 时歌词合同仍保持 line-only，不平均分字、不伪造可持久化 timing；Column 可在纯渲染边界用 `estimated` 词组做零模型轻量扫亮，并以独立 `estimatedWords` 低置信字段发给 Director 作视觉 pacing 提示。用户显式开启“人声感知逐字”后，扩展只在本地从当前 tab audio 生成最长约 20 秒、最多 640 个样本的滚动 `VocalTimingMapV1`，以中置人声存在度/起音修正该 `estimated` 扫亮；时间偏移有界并在行首尾归零，覆盖不足 52% 或平均置信度低于 0.28 时精确回退原估算。native/estimated 的 Column 扫亮都必须严格停在当前 `word-progress`，不得用前探光带、白色 drop-shadow 或活动行白色 text-shadow 提前擦亮相邻未到字。估算轴与人声滚动图不得缓存、发送给 Director、进入 Fullscreen、覆盖 reveal，或充当 beat/onset/结构证据；旧 Director 会安全忽略独立估算字段。该合同已随 OCI Director 1.3.3 部署，loopback/public 授权 canary 均已消费估算 cues 并返回非降级计划。用户明确不要的音频上传/Windows Forced Aligner 不进入 Web 路径。
- 0.2.1 全屏生产链：`StageCanvas` 使用 Stage-first 30/70 shell、真实 YTM 封面、标题/艺人、常驻细进度与 Bridge 实际支持的播放/暂停/上一首/下一首。顶部/底部无浮动 chrome；Hero 时封面连续缩为信息岛。右侧 Canvas2D 保持唯一 glyph owner，常态完整显示上一句/当前句/下一句，长 Latin 按词换行、长 CJK 不截句；Hero 只覆盖证据行窗口，Duet 维持声部两侧关系，Aperture 只在没有 active lyric 时成立。Pixi environment、Canvas、进度和封面状态共享一次 clock sample；后台恢复、random seek、reduced-motion 与 WebGL context restore 不撤正文。
- 独立自动导演：`services/lyricstage-director` 当前线上为 1.3.4，不复用 iPhone Luna V1–V4 或 Metadata Worker，以版本化 `skills/performance-direction-v1` 为知识包，为 16:9 Runtime 返回 `lyricstage-fullscreen-director-v2`。合同除 concept/motif/intensityArc/连续 section/全行 directive/typed `EffectRecipeV1` 与 song-wide `world` 外，也可接收严格有界的 `MusicMapV1`：用户进入全屏时 tabCapture 在本机约 30Hz 提取 energy/bass/mid/treble/brightness/flux/onset/stereo width，offscreen 将同一流接回 destination 防止静音，仅上传最多 96 段/256 地标的归一化地图；PCM、视频、媒体 URL 不上传、不落盘。AI 先按歌词生成，地图覆盖达到门槛后生成音频增强稿，Runtime 仍在下一结构边界接管。Skill 把语法视为乐器而非模板，普通 Reading 以封面颜色、光、材质和留白成立，拒绝无证据的对称空面板、持续网格/轨道、扫描线、汇聚射线和 particle soup；一个结构 motif 只能有一个 owner。线上模型/版本为 `gemini-3.7-flash / lyricstage-fullscreen-gemini-3.7-world-musicmap-v5`，服务端继续验证 evidence、primitive、conflict/cost/Hero budget 和全文覆盖；同一服务的 `/v1/music/identity` 保留 grounding 门。
- YTM 默认展示入口现为增强宿主原生「歌词 / Lyrics」标签：content script 只认活动 `ytmusic-tab-renderer` 自身的真实 DOM `page-type="MUSIC_PAGE_TYPE_TRACK_LYRICS"`，在其内部挂载扩展 Shadow DOM host；不读取 Polymer 私有变量，不新建同级 tab、sibling panel、overlay 或页面。原生歌词节点仅在 React ready 后隐藏，并精确保存/恢复 inline display、`hidden`、`aria-hidden` 与 `inert`。
- **Column / Fullscreen 双模式（增强原生歌词）**：侧栏 React `ColumnStageView` 由独立 production IIFE content bundle 直接挂入 Shadow DOM，不再使用会被 YTM 阻断的 extension iframe。两个隔离脚本以 DOM marker 和每次 attempt 的 ready/error/dispose 事件握手；runtime 缺失、渲染错误、超时、切 tab 或 renderer replacement 都 fail closed，保留原生歌词并拒绝迟到 ready。全屏按钮或 `F` 仍在用户手势栈内对稳定 fullscreen host 调用 `requestFullscreen`；浏览器 Fullscreen 生命周期只由用户 Esc/显式退出或浏览器自身 `fullscreenchange` 结束，不再服从歌词 readiness。切歌先撤下旧歌词事实，并由常驻在 `StageCanvas` 下方的同构 Stage-first 30/70 过渡层保留封面、身份、进度和左右 shell 几何；右侧歌词区只显示新曲匹配状态，新 `StageCanvas` 在同一区域淡入覆盖。过渡不得切成另一套居中布局，也不得为了连续感保留上一首歌词。候选待选、未命中和临时错误仍不得主动 `exitFullscreen`。真实 word-timed 行以 `line.text` 为唯一正文；line-only 行可在 Column 显示明确标注的“轻量逐字”估算扫亮，Fullscreen 仍按逐行事实渲染，避免把估算时间解释成字符出现真相。
- 2026-08-21 真实 Chrome 验证：production content-ui marker 出现；Lyrics 内 direct Shadow Column 可见；切到 Up next 后 host 为 0、原生节点恢复；切回 Lyrics 后 host 恰为 1、原生正文由扩展隐藏；刷新后的新版无 LyricStage error/warn。Chrome 扩展详情中的 `allowfullscreen` 条目是旧 iframe 构建的历史记录，当前源码/产物无 iframe/allowfullscreen。
- YTM 的 Polymer 重绘可能替换 tablist/renderer；content script 通过幂等挂载、`MutationObserver`、`yt-navigate-finish` 与有界心跳重新接入，extension reload 时 `stop()` 撤销监听、注入节点并恢复原生状态。
- Companion Manifest 保留歌词缓存/私有后端配置所需的 `storage`，并为用户显式启动的本地音频分析加入 `activeTab + tabCapture + offscreen`；YTM tab 发现仍使用 `https://music.youtube.com/*` host permission 约束的 URL query，不申请可读取所有标签 URL/title 的宽泛 `tabs` 权限。Chrome 只允许在用户调用扩展后捕获当前标签页，因此 Column 首次开启人声增强会给出短时授权提示，popup 在该窗口内自动续接 pending capture；捕获流立即接回输出，不能让宿主静音。公开歌词源只列出 LRCLIB、SponsorBlock 与酷狗三个固定 host；当前自用 LDDC 地址作为单一 optional host，只有用户在弹窗保存配置时才请求授权。
- YTM content script 把 extension reload 视为终止条件：若 `chrome.runtime` 上下文失效，会撤销媒体事件、MutationObserver、待发送任务与心跳；用户刷新 YTM 后再由当前扩展版本重新注入，旧脚本不得无限报错。
- `web/packages/lyrics`：来源无关自动歌词边界。YTM 展示元数据先按角色解析而非按单曲打补丁：先确认 cover marker，再剥离 `covered by / Cover: / Vocal:` 翻唱者 credit 与 acoustic 等版本包装，最后解析「歌名（原唱）」或「歌名 / 原唱」中的明确原唱；`/／|｜-—` 只作为结构分隔符，不得残留进规范歌名。标题没明确写出原唱时，确定性代码不得再按歌词候选多数艺人猜测，因为候选可能全部是另一位翻唱者。首轮未命中当前录音时，可选 `/v1/music/identity` 以 `gemma-4-26b-a4b-it` minimal thinking + Google Search 区分当前演唱者、原唱与创作者；Gemma API 不可用时才使用 Vertex `gemini-3.5-flash` 执行同一 Google Search 任务。只有 API grounding chunk 或 search entry point 存在、置信度 ≥0.65、当前演唱者一致且翻唱存在原唱时，结构化身份才触发第二轮 LDDC/LRCLIB/酷狗搜索。本地不接受模型自写 URL，歧义/无来源/角色混淆结果只展示候选或回退手动导入，不得伪装成原唱。自动仍优先同标题、翻唱者一致、时长差 ≤4 秒的翻唱录音；已证明原唱仅以显式 `originalFallback` 次选。扩展复用本机 Director Bearer，但音乐身份请求只发送 video ID、标题、歌手、时长与启发式提示，不发送歌词、音频、Cookie、封面或媒体 URL。后台使用 `lyrics-v8` cache namespace 淘汰旧误判和 line-only 中间缓存，最多返回 5 个候选；任一 AI/歌词源失败不得饿死其余来源或手动导入。
- `web/packages/companion`：版本化 YTM snapshot、权威快照时钟与多标签 source registry；不包含 Cookie、媒体 URL 或音频事实。
- Swift `LyricStageWebContractTests` 从同一 fixture 资源验证正文、时间、逐字与重叠声部；不比较字体像素几何。

Performance Runtime 已形成新的 0.2.1 可安装候选。2026-08-22 当前发布门：Web 聚焦 6 文件 74/74、typecheck、extension 双构建/MV3 CSP 与 Director 13/13 通过；真实 Chrome 已证明新版播放器 metadata 回退能恢复曲目桥、tabCapture 全屏期间播放继续前进、高清封面与三层歌词不截断。OCI Director 1.3.4 在原 loopback/Tunnel 原位运行，public/loopback health 均为 Gemini 3.7 MusicMap v5，无认证 401；授权 MusicMap canary 非降级并在公网复打命中缓存。经用户授权，当前 Chrome 已把客户端 Bearer 只存入扩展本地存储；真实《non-reflection (Cover Live)》从“下一段接管”进入全屏“已接管”，同轮 Chrome 保持 `Audio playing`。仍不能把单曲闭环或 fixture/canary 当成快歌、慢歌、重复副歌、二重唱、长句五类整首主观 A/B；同时启用其他 YTM 歌词增强扩展时，原生 side panel 偶发长期 loading，需在不改变用户其他扩展设置的环境中另做冲突隔离验收。无 AI 的完整本地路径继续独立成立。

## 计划指针

- 上下文：`.planning/phases/06-lyricstage-platform-and-web-reference/06-CONTEXT.md`
- 设计：`.planning/phases/06-lyricstage-platform-and-web-reference/06-00-DESIGN.md`；批准的视觉/导演增量为 `06-06-DESIGN.md`
- 实施：`.planning/phases/06-lyricstage-platform-and-web-reference/06-01-PLAN.md` 至 `06-06-PLAN.md`
- 验证：`.planning/phases/06-lyricstage-platform-and-web-reference/06-VALIDATION.md`
