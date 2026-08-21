---
type: project_topic
status: active
summary: "NowPlaying 播放主页中区高能歌词光场舞台、三层景深排版、字级 VFX 引擎与 Luna 智能装帧。"
tags: [lyrics, luna, motion, embellishment, vfx, nowplaying]
contains: [decision, contract, deployment-boundary]
created: "2026-08-19"
updated: "2026-08-21"
related: ["BiliMusic/Features/Player/NowPlayingLyricStageView.swift", "BiliMusic/Features/Player/LyricVFXTokens.swift", "BiliMusic/Features/Player/LyricEmbellishment.swift", "BiliMusic/Features/Player/LyricEmbellishmentStore.swift"]
authoring_mode: ai_generated
---
# NowPlaying 歌词光场舞台与微巧思演出系统

## 当前状态

- **NowPlaying 播放主页中区高能舞台落地 (`NowPlayingLyricStageView`)**：
  - 彻底重构播放主页封面与控制栏之间的黄金弹性空间，以三层景深排版（前句散焦微暗、当前 28~32pt Hero 大字、后句预备过渡）让中区稳稳“撑住场面”。
  - 底层渲染自适应流体双色光晕（`LyricStageLightField`），长间奏与前奏自动展现 3 颗随节拍呼吸的律动微点（`LyricInterludePulseView`），空间全周期拥有呼吸生命感。
- **高能字级 VFX 特效引擎 (`LyricVFXTokens`)**：
  - `impact`：唱响瞬间微弹性缩放（Pop 1.12x）+ RGB 赛博色散瞬闪 (0.12s) + 径向冲击波环；
  - `crystallize` / `shimmer`：字符中心旋转钻石十字星芒 + 白金流光遮罩；
  - `blaze`：赤金垂直流火渐变 + 2 颗向上飘散的微火星余烬微粒；
  - `neon`：高频双闪点火 + 青粉双色霓虹发光管质感；
  - `heartbeat`：双阶段心跳舒张（1.0 -> 1.08 -> 1.0 -> 1.04）+ 全局粉红光晕脉冲；
  - `ripple`：向后方留存 2 重不同透明度的运动残影与同心波纹；
  - `floating` / `sway`：正弦/余弦波轻柔垂直与水平浮游，如随风摇曳。
- **12 种微巧思风格库与本地/AI 双层分发**：
  1. 本地零延迟确定性规则引擎 (`LyricEmbellishmentDirector`)；
  2. 露娜 AI 智能装帧 (`LyricEmbellishmentClient` -> Worker `POST /v1/lyrics/embellish`)，秒级返回情感与重点词风格表，落盘至 `Documents/lyric-embellishments.json`。
- V5.3 与 V5.1 等全屏多幕实验保留在 Debug 菜单，不影响产品默认路径。
- V5.3 已形成唯一的通用链路：`LyricsFacts + AudioPerformanceMapV2 + optional Luna V3 -> LyricStageDirectorV3 -> LyricStagePreparedRuntimeV3`。歌词正文、行/字时间和并行声部始终由本地事实层拥有；音频只决定 section、强弱和 reveal 之后的 accent；Luna 只返回 Stage Bible、连续 section 和稀疏构图 override，不得返回坐标或修改时间轴。
- V4 在 V5.3 之上新增独立的 `AudioStructureScoreV4 + Gemini Scene Recipe` 层：App 将已缓存音频压成有界的 tempo/section/逐行事实/轮廓/结构地标，Gemini 只选择 typed motif 与 `topology × entrance × focus × sustain × continuity × driver`；本地编译器把 Rail Handoff、Semantic Lens、Chorus Memory、Silence Aperture 叠到完整 V5.3 fallback。结构地标使用 raw audio clock，歌词/逐字 reveal 使用 offset lyric clock；未 reveal 字形严格为 0，音频不能提前或延后歌词。
- V4 Prepared renderer 将 rail、focus、residue、aperture、双时钟 prelude 与长句 timing-run/row fallback 全部预编译。普通场景最多 48 个独立 glyph transform、2 层 residue、96 次文字绘制；超过 48 字改用完整换行 row/line fallback，不截字、不显示省略号。Reduce Motion 只保留颜色、字重、轨道和可读的相位变化。
- 默认运动语法改为 static-first：普通逐字/逐行歌词只在落点后做一次最多 1.5% 的轻触并在 36% 进度前归零；背景色场静止，Cosmic Drift / tracking breath 落稳后严格为 0；V3/V4 正文不再随普通 beat/onset 缩放。强 onset/downbeat 仅可增强 section-edge 装饰，Impact、Heartbeat 与 structuralMoment 仍可作为明确的稀疏事件。
- `AudioPerformanceMapV2` 只分析已经完成的本地缓存，不下载、不等待播放连接；显式 beat/downbeat/onset、tempo、五类量化 envelope、silence/section region 和 confidence 以音频指纹独立缓存。相同 BV 的不同 CID 不得互相复用；分析版本变化会失效。App 的显式 V3 生成先应用完整本地计划，再请求 Luna，取消、切歌、旧缓存任务都由 generation ID 隔离。
- V5.3 执行层把场景边界索引、glyph、字体拟合、换行、arc 与 interlude 布局移出 Timeline draw；逐帧只做 O(log n) scene sample、O(1) visual lookup、时钟、音频二分查询、插值和绘制。长 hero/arc/hook/dialogue/stack 在编译预算阶段降级到完整换行 anchor，不截字、不显示省略号。
- 2026-08-19 起 App 另有 V5.1 Event 舞台合同 `lyric-stage-v2-events`：StyleSheet / Section / Scene / Actor / Event，由 `LyricStageCompilerV2` 预编译绝对字符轨道，`LyricStageCanvasView` 每帧只执行 `sample(at:)`。Debug 可在本地规则、当前 V5 行级舞台、V5.1 Event 舞台和样片之间切换；默认仍是本地规则。
- Worker 已上线 `/v1`、`/v2`、`/v3/lyrics/direct`、`/v4/lyrics/direct` 与 `/v1/lyrics/embellish`。V2/V3/V4 使用独立 KV 前缀；V4 只缓存双端门禁通过、非 degraded 的完整结果，并等待 KV 写入后响应。生产当前版本为 `79c3d38c-363f-4c5d-b76b-625c16b3bdf1`，normalize、V1、V2、V3、V4 和 embellish 全部使用 CPA `gemini-3.7-flash-high`；CPA Secret 与旧上游 Secret 独立。上一 V4 版本为 `14834316-d27d-4c15-8bbb-435c3e7fae5c`，V4 上线前版本为 `52cc64da-2efd-4ce6-84ad-df1472b9e692`；关闭 `LYRIC_DIRECTOR_V4_ENABLED` 可只停 V4；包含 embellish、但尚无 V3 的回滚基线为 `1b07471b-49e4-48cf-adb1-c3ca591db573`。
- V5.1/V5.3 选择动作都不再自动联网；网络生成只存在于明确标注 Luna 的 Debug 操作。低强度 hold pulse、Timeline tick 与歌词时钟修复仍保留，Reduce Motion 只降级动作而不冻结换行。
- V5.2 目前是「You＆合図」0–176.518 秒的专曲全曲舞台：从真机 AAC 提取 178.206 BPM、524 拍、131 重拍、341 个高置信 onset 和约 21.53Hz 能量包络；40 行逐字歌词覆盖开篇、原黄金段、推进、指挥断句、Sunday 弧线、主题再现与终章，前后器乐段也有声音场。它是本地手工 Canvas，不读 V2 score、不调用 Worker。精确逐字轴拥有 reveal 时刻，绝不等待后续鼓点；±90ms 附近的 onset/beat 只追加回弹、冲击、方向和场景强弱。Debug 入口只对该 BVID 开放，点击会从 0 秒播放全曲。
- 本地导演 V2 只生成安静基线、重复句 echo 和真实 overlapGroup 的 splitVoices；旧 v4/v5 缓存经 `LyricStageLegacyAdapter` 进入同一渲染器。无逐字轴时不写 syncWindow，不做伪卡拉 OK。
- 执行层现按 Actor 独立 typeRole 布局（关键词可大于整行）；entrance/performance/hold/exit 有动词允许表；超预算时去掉 backdrop 并删除 `.echo` Event，采样不再把残影加回来。中日文按 token 边界换行。Actor 中心按 `(sceneID, actorID)` 隔离；partial Luna 补缺会裁掉已覆盖的声部行。Section 的 density / heroBudget / accentBudget / motifRef 会进入预算降级。封面色进入缓存指纹。

- App 与 Worker 继续使用兼容的 `lyric-performance-v4` envelope；Cloudflare Worker 已于 2026-08-19 部署版本 `ac89c921-a471-4f65-bde8-1fd8141ba2a1`，线上 `/v1/lyrics/direct` 直接返回 v5 Stage Bible 与 stage directives。导演实现版本为 `luna-lyric-director-v5-stage-preview`。
- App 已有 `lyric-performance-v5-stage-local` 第一版：`LyricStageCompiler` 把真实歌词、逐字时间、voice role/overlap group 与现有 Luna v4 score 编成逐行 StageScore，`LyricStageView` 以局部 60fps 时间轴渲染每个字形。Debug 可在真实歌词舞台、v4 预览和硬编码样片之间切换；三者都只替换中央画布。
- Worker 两阶段 v5 已上线：先用全曲 outline 生成 `stageBible`，再把它交给并行分段导演生成受限 `stageDirectives`。App 已能解码、双重校验、随既有 score 缓存并优先编译这些 directives；全曲导演失败或某行 directive 缺失时仍由 v4 scene / 本地规则无缝补齐。
- Luna 仅是开发阶段显式创作工具：Debug 播放器 `更多 → 歌词 → 用 Luna 编排演出` 才发请求，不在起播、自动歌词加载、换歌或 Release 播放路径调用。
- App 发送当前曲目的 trackID、标题、作者、时长、歌词哈希，以及最多 180 行的原文、逐行 from/to 和已有的真实 word/character index/from/to/text；不发送 Cookie、B 站登录凭据、缓存音频或上游 API key。Worker 保留全曲文本轮廓，把详细逐字输入压成时间元组并按约 12 行、最多 8 段并行交给 Luna，再合并做一次全局校验。Bearer token 继续由 macOS 钥匙串注入 App，并由 Worker 隔离上游密钥。
- v5 请求同时带 `voiceRole / layerID / overlapGroup`；歌词指纹也纳入这些字段，声部分配改变后旧导演缓存自动失效。

## 合同

- 端点：`POST /v1/lyrics/direct` 仍为当前生产合同，与元数据端点共用 Worker Bearer 认证；导演版本当前为 `luna-lyric-director-v5-stage-preview`。
- 生产 V2 端点：`POST /v2/lyrics/direct`，输出 `lyric-stage-v2-events`。Luna 只给 Section/Actor/Event/相对时间；绝对秒、坐标、换行、预算和 Reduce Motion 由 App 编译器处理。
- 生产 V3 端点：`POST /v3/lyrics/direct`，输出 `lyric-stage-v3-choreography`。输入最多 180 行完整歌词轮廓与稀疏 `LyricStageAudioSummaryV3`；180 行长文本+rich audio 的 App 请求实测 93,401 bytes，低于 Worker 98,304-byte 实际 body 门禁，且不发送 words/tokens/音频。输出只含 Stage Bible、连续 sections 与不超过预算的稀疏 scene override。
- 生产 V4 端点：`POST /v4/lyrics/direct`，输出 `lyric-stage-v4-scene-recipe` / `scene-recipe-grammar-v1`。请求保留完整歌词与逐行时间，音频结构采用 Q8/毫秒 tuple；App 以 88KiB 软预算依次减少 line details、moments 和 contour，绝不截歌词，仍超过 98,304-byte 硬门限就本地回退。`audioScoreHash` 只做双端身份，音频指纹、raw beat/onset/accent arrays、Secret 和设备信息不进入 Gemini prompt。
- 输出：`lyric-performance-v4`，包含 lineCount、覆盖每个时间点的 compositions、稀疏 scenes 与可选 wordCues。每个 composition 必须包含当前 lineIndex，并按视觉顺序选择 1–3 个相邻不超过两位的真实歌词索引。scene 可选择九种逐行动效；Cascade 必须对应至少两行 composition。
- 真实逐字歌词始终由 App 本地执行克制的 Sweep。Luna 只为约 10%–30% 有逐字时间的行追加一个范围 cue，可选 Sweep / Impact / Stretch / Echo Trail，最多连续 12 个真实 word index；无 words 的行、越界范围、同一行重复 cue 和未知效果会在 Worker 与 App 两端过滤。
- Luna 不改写、翻译、合并或拆分歌词；只引用 lineIndex。服务端和 App 各做一次 allowlist、范围 clamp、逐行覆盖、重复/越界过滤和版本/身份/歌词哈希校验。长句由 UI 完整换行，禁止用省略号；导演需通过减少同屏行数控制密度。
- 有效脚本写入 `Documents/lyric-performances.json`，最多 100 首；歌词正文、分行、逐行时间或逐字时间任一变化都会改变哈希并使旧脚本失效。手动 offset 不改变脚本身份。
- 缺 scene 的行继续走本地 `LyricMotionDirector`；请求失败、degraded、schema 不匹配或缓存失效时整首歌也可无缝回退，不阻塞播放。
- 分段调用允许部分成功：有效段照常使用，失败段由本地导演补齐，部分结果不写入 KV。全部分段失败才返回 degraded；超时明确标记 `upstream_timeout`，App 不再把它误报成“没有生成有效演出”。
- v5 本地 StageScore 每行选择 assemble / gravityDrop / ripple / stretch / echo / drift / focus / converge 之一；Luna 原生 directive 缺失时由 v4 scene 确定性映射。逐字轴按真实 word 边界拆成 grapheme 时间轨，逐行轴只提供视觉 stagger，不冒充真实唱字时间。所有文本完整进入自动换行 layout。

## 开发入口与撤销

- Debug 菜单分为「歌词舞台」与「Luna」：本地规则 / V5 / V5.1 / 样片互斥；Luna 可生成 V5.1、查看演出摘要或清除独立 V2 缓存。V5 生成入口仍保留便于回滚。
- V5.3 有独立的显式「Luna V3」生成、摘要和清除入口；失败时保留本地完整 V5.3，不影响播放或歌词库。V3 缓存为 `Documents/lyric-stage-v3.json`，身份包含歌词、音频摘要、compiler 与线上 director version，不覆盖 V1/V2 缓存。
- V4 有独立的显式「生成 V4 音频结构演出（Gemini）」、摘要和清除入口。生成先分析已完成的本地音频缓存；缺缓存时不请求 Gemini。有效 direction 写入 `Documents/lyric-stage-v4.json`，显式进入 V5.3 时按相同的确定性 request degradation 恢复；切歌、V3/V4 并发、清除与旧任务都由独立 generation ID 隔离。V4 无效或超时只保留完整本地 V5.3。
- “恢复本地歌词导演”会清除当前曲目的 Luna 缓存，便于 A/B。
- “播放动态文字样片”只启用本地 v5 motion study，再点一次关闭；不请求 Worker、不写歌词演出缓存，也不影响当前 v4/Luna 脚本。
- “启用 v5 真实歌词舞台”使用当前真实歌词和已缓存的 Luna score；再次点击回到现有 v4 中央歌词。样片与真实舞台互斥。
- UI 只针对 iPhone 17 Pro / iOS 27 验收；Luna 参数最终仍受 22–36pt、位移/强度和 Reduce Motion 边界限制。

## 部署与真实验证

1. 2026-08-19 经用户明确授权部署；`/health` 已列出 normalize 与 director 两个端点，Worker 版本见上。
2. 线上有界验收曲共 12 行：首次 `cache=miss`、`degraded=false`、协议为 `chat-json-object`，Luna 返回 7 个 scene（58.3%）且五种效果均出现；所有索引、强度、字号和字距约束通过。相同请求第二次 `cache=hit`，没有再次调用模型。
3. 旧 `/v1/music/normalize` 同轮线上回归为非降级，日文原名、原唱与翻唱者分层正常；未授权 director 请求返回 401。
4. v2 线上验收：12 个时间点均有合法 composition，其中 5 次单行、7 次双行；6 个稀疏 scene，非降级，第二次相同请求 KV 命中。Worker 14/14、iOS 合同 5/5、iPhone 17 Pro / iOS 27 长歌词 UI 1/1；截图确认四行长句完整显示且未压住播放控件。
5. v3 线上验收：16 行 composition 覆盖单行、双行和三行；9 个 scene 实际使用 8 种效果，新增 Focus / Drop / Stretch / Cascade 四种全部命中，Cascade 多行约束通过。Worker 15/15、iOS 14/14、长歌词 UI 1/1；旧 normalize 与 401 鉴权正常。
6. v4 线上验收：6 行逐字样本首次请求非降级，返回 6 个 composition、3 个 scene 和一个准确引用 line 1 / word 0–3 的 Echo Trail；第二次请求 KV 命中。Worker 16/16、iOS 导演与逐字模型 20/20、逐字长句 UI 1/1。Debug 真机包已覆盖安装并启动，基础 Sweep 可本地工作。
7. v4.2 长歌修复：从 iPhone 当前播放的真实「千鳥」读取 42 行、407 个逐字 token，复现旧 Worker 在 25 秒整返回 `upstream_error`。单次紧凑请求即使放宽到 40 秒仍超时，因此改为保留全曲 outline、约 12 行并行分段。相同真实请求上线后 23 秒返回 `degraded=false`，得到 42 个 composition、14 个多行构图、29 个 scene 和 13 个 word cue；Worker 18/18。Debug 真机包重新签名、覆盖安装并启动。
8. 待办：用户在 Debug 真机再次点击当前歌曲，确认成功提示与实际演出体感；重开 App 验证本地脚本缓存，再切回本地规则确认撤销。
9. 待办：用 iPhone 17 Pro Release 真机确认局部 30fps 逐字舞台、LNPopup 开合和长时间播放；完成前不自动化批量生成，不开放 Release 入口。
10. v5 样片已在 iPhone 17 Pro 模拟器检查四幕关键帧；定时/easing 单测 10/10、播放器局部替换 UI 回归 1/1、generic iOS Debug build 通过。当前渲染为少量 SwiftUI glyph view，只用于判断视觉方向；正式 v5 仍应改为版本化 StageScore、预编译时间轨与 `TextRenderer`，并在真机验证 60fps。
11. v5 真实歌词第一版：iOS StageScore/compiler/directive/指纹窄测与既有导演测试合跑 23/23，真实逐字 fixture 的中央画布局部替换 UI 1/1，generic iOS Debug build 通过；Worker 本地 20/20。模拟器实图确认长英文完整四行显示且不压住 progress。尚未部署 Worker、安装新真机包或测 Release 60fps，当前 SwiftUI glyph renderer 仍是功能原型而非最终 TextRenderer 后端。
12. v5 生产部署：Cloudflare 版本 `ac89c921-a471-4f65-bde8-1fd8141ba2a1` 上线。健康端点正常、未授权 director 为 401、旧 normalize 日文翻唱样本非降级；8 行逐字/二重唱线上样本在 27.2 秒内非降级返回 Stage Bible、5 条 stage directive、3 种 behavior、4 个 scene 与 2 个 word cue。签名 Debug 包已覆盖安装并启动于连接的 iPhone 17 Pro，设备进程存活；真实歌曲的生成体感、重启缓存与 Release 60fps 仍待用户确认。
13. V5.1 生产部署：Cloudflare 版本 `153857a6-dc21-4e5b-8710-3b153f24f131` 上线。第一轮真实调用暴露 Luna 场景对象全部被校验器丢弃却误报非降级，随后补全精确 Actor/Event JSON 合同，并将空场景改为 `degraded=true`。修正版 8 行逐字/二重唱/和声样本首次请求 `cache=miss`、`degraded=false`，返回 4 Section、2 Scene、2 Actor、7 Event，覆盖 entrance/performance/hold/exit 和 appear/echo/dissolve/pulse；旧 V1 同轮非降级返回 2 Scene 与 3 stage directive，健康端点列出三个 API。本轮只部署 Worker，未安装新的真机 App 包；四首 A/B 与 Release 帧率仍待验证。
14. V5.1 真机无动画修复：首次选择舞台自动发起线上生成，等待期间本地逐行场景保留低强度 hold pulse；随后根据已有 10 Scene / 41 Event 仍卡顿的复测，把 Timeline tick 显式送入 Canvas，并把歌词时钟从 motion/reduce-motion gate 分离。compiler/timeline 21/21、物理设备 Debug build 通过。第二份修正版已覆盖安装并启动，V2 缓存与既有 Documents 保留；仍需用户对真实歌曲确认持续换行和帧感。
15. V5.2 专曲全曲舞台：由原 29.66 秒样片扩到「You＆合図」完整 176.518 秒，AudioPerformanceMap 覆盖全曲 beat/downbeat/onset/energy，40 行按段落使用确定性 motif。用户指出向后吸附造成逐字微延迟后，精确逐字轴重新独占 reveal，音频只做附近事件的 accent。时间线/音频窄测 2/2、iPhone 17 Pro 尺寸 14 关键帧 UI 1/1；仍不表示通用 iPhone 分析器、V5.2 合同或 Luna 调度完成。
16. V5.3 通用编舞：V5.2 保留作 A/B；新规划器无歌曲身份和固定时间分支，连续重复 Hook 自动四阶段递进，普通行产生七种构图。初次关键帧暴露前奏空白和全曲重复计数使首轮 Hook 不锁定，现分别以通用标题前奏和连续重复簇修正。iOS 27 / iPhone 17 Pro 规则 19/19、10 时间点 UI 1/1；签名 Debug 已安装启动。用户整首体感、其他歌曲泛化、真实音频分析与 Luna 调度仍待验证。
17. 2026-08-20 按用户“启用 V2 服务端”复核：当时生产仍是 `153857a6-dc21-4e5b-8710-3b153f24f131`。健康端点三个 API、V2 未授权 401、normalize 非降级、V1 8 行样本非降级、V2 8 行样本返回 `lyric-stage-v2-events` 且延迟复打 KV 命中。
18. 同日真机提交超时：App 45s 无首包断开，Worker 串行 bible+scene 需要 45–51s。随后部署 `c593e5b3-eb9e-4360-9a1e-8dd1a58ad723`，bible 与最多 4 段 scene 并行并在返回前写入 KV。24 行线上样本 19.2s 非降级、复打 354ms hit。客户端超时改为 90/120s，需下次真机安装。Worker 26/26。
19. 2026-08-21 V3 完整链路上线：Worker `414458cf-77d5-4bc8-ba10-ff6a6aebbb6a` 的 `/health` 列出五个端点且 V3 enabled；12 行重复 Hook/二重唱/音频摘要生产请求 23.35s miss，返回 5 个连续 Section、5 个有效 Scene、`degraded=false`，复打 53ms hit。V1、V2、embellish、normalize 同轮均 200/非降级，V3 未授权为 401；Worker 43/43。
20. App/事实层聚焦测试在 iPhone 17 Pro / iOS 27 模拟器 26/26；Python 合同 2/2；V5.3 十关键帧、长歌词和 LNPopup 四项 UI 均通过（旧 accessibility 名称已随现行 `nowPlayingLyricStageView` 修正）。真实 152.04s B 站 AAC 临时装入测试包后在 iPhone 17 Pro / iOS 27 完整解码、分析并通过，测试结束已从工程移除，未提交音频。
21. 真机 Debug V5.3 固定 Hook 画面录制 31.1s Animation Hitches：120Hz 门槛下 29 个 missed-frame 记录，其中仅 2 个超过 16.7ms，最大 33.34ms；App 进程完整存活。这个证据包含 SwiftUI/合成器，不能冒充歌词 draw 自身 p95。随后按用户选择改用 iPhone 17 Pro / iOS 27 模拟器，在 Debug-only 性能开关下直接包住 Canvas draw：Hook、Dialogue、Final 三种构图各 240 帧，p50 分别为 0.64 / 1.95 / 2.43ms，p95 为 1.52 / 5.91 / 4.68ms，p99 为 3.36 / 7.04 / 6.76ms，最大 6.20 / 8.41 / 12.87ms，三轮均 0 帧超过 16.67ms。逐帧封面调色板解析已提升到 Canvas 外；当前构建冷编译为 17.18–24.01ms，低于 50ms 拆分门槛。`makePreparedStage` 与其外侧的 plan digest 仍同步发生在 SwiftUI 主线程，但只在 identity 改变时执行；若真实歌曲或更长歌词把冷编译推过 50ms，再拆成后台 Sendable 编译阶段。
22. 用户在 App 发起一次真实 V3 请求后命中原 38 秒上限。只放宽 V3：Luna 单次请求 35→55 秒、整个兼容协议预算 38→60 秒；App 仍允许 120 秒，V1/V2/embellish 的短预算不变。修复部署为 `060adf92-75b7-4719-a55c-3936ce5e727e`，Worker 43/43；线上全新 12 行 Hook/二重唱/音频摘要冷请求 18.22 秒、3 Section / 5 Scene、`degraded=false`，复打 71.8ms KV hit，健康端点与未授权 401 同轮通过。
23. 用户随后在真实 App 完成一次约 3 分钟的 V3 生成。设备容器证据显示 `BV1XWdrBVEn3#37667474477` 的 176.47 秒音频图在 01:53:25 JST 写入，包含 261 beat、65 downbeat、480 onset、38 region、overall confidence 0.827；通过 App 本地门禁的 40 行 V3 演出在 01:54:54 写入，包含 7 Section、16 Scene 与完整 Stage Bible。用户观察的约 3 分钟是“首次整首本地音频分析 + Luna 请求”的总时长，现有时间戳不能进一步精确拆分；相同音频指纹和歌词再次生成会复用本地 AudioPerformanceMap 与 Worker KV。
24. 经用户指定，全链路从旧上游切换到 CPA `gemini-3.7-flash-high`。新 `CPA_UPSTREAM_API_KEY` 只存 macOS 钥匙串与 Cloudflare Secret，旧 Secret 未覆盖，便于回滚；normalize、V1、V2、V3、embellish 的版本全部 bump，避免同曲继续命中旧模型缓存。生产 `52cc64da-2efd-4ce6-84ad-df1472b9e692` 全新 miss 依次为 4.63 / 14.79 / 19.63 / 6.50 / 5.95 秒，均 `chat-json-object`、`model=gemini-3.7-flash-high`、非降级；V2 为 4 Section / 5 Scene / 7 Actor / 18 Event，V3 为 3 Section / 4 Scene，V3 复打 321ms hit。Worker 44/44。
25. V4 Audio Structure + Scene Recipe 当前部署为 `79c3d38c-363f-4c5d-b76b-625c16b3bdf1`。最终修正版在 98,304-byte 门限内保留每行完整歌词，V1–V3 兼容行为不变；Worker 54/54。首个 12 行逐字/重复 Hook/二重唱/量化音频结构 canary 冷请求 9.10 秒，返回 2 个连续 Section、4 个有效 Recipe、`model=gemini-3.7-flash-high`、`degraded=false`，相同请求 83ms KV hit；最终部署的新 4 行请求也非降级产出有效 `chorusMemory`，复打命中 V4 KV，六条路由无令牌均保持 401。正式默认路径仍不自动联网，V4 只在 Debug 显式生成/恢复。
26. 用户实际观看后指出默认歌词持续跳动会疲劳。普通字的默认 6% 全词程缩放/2.2pt 上浮改为最多 1.5% 的短落点，36% 后严格静止；整行模式共用同一 envelope，动态色场改静态；Cosmic Drift、Rail/Semantic `trackingBreath` 由永久正弦改为一次性落稳。V3 整体 beat 缩放与四个 V4 family 的音频文字缩放全部移除，只有 section start 的强 onset/高能 downbeat 可点亮装饰线。iPhone 17 Pro / iOS 27：V4 全链 24/24、默认歌词和 V4 UI 各 1/1；V4 双 residue 短 Hook 最新 240 帧 Canvas draw p50/p95/p99/max 为 0.93/3.30/5.56/12.01ms，0 帧超过 16.67ms。
