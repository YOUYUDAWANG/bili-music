---
type: project_topic
status: active
summary: "NowPlaying 播放主页中区高能歌词光场舞台、三层景深排版、字级 VFX 引擎与 Luna 智能装帧。"
tags: [lyrics, luna, motion, embellishment, vfx, nowplaying]
contains: [decision, contract, deployment-boundary]
created: "2026-08-19"
updated: "2026-08-20"
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
- V5.3 当前没有通用 AudioPerformanceMap，也不调用 Luna；真实逐字轴拥有文字出现时刻，结构规划与构图只改变视觉。它证明“专曲 Demo 的构图知识可以先抽象为通用语法”，尚未证明音乐段落分析、音频重拍或模型分镜已经泛化。
- 2026-08-19 起 App 另有 V5.1 Event 舞台合同 `lyric-stage-v2-events`：StyleSheet / Section / Scene / Actor / Event，由 `LyricStageCompilerV2` 预编译绝对字符轨道，`LyricStageCanvasView` 每帧只执行 `sample(at:)`。Debug 可在本地规则、当前 V5 行级舞台、V5.1 Event 舞台和样片之间切换；默认仍是本地规则。
- Worker 已上线 `POST /v2/lyrics/direct`，与 `/v1/lyrics/direct` 并存；V2 使用独立 KV key `director-v2:`，缓存写入 App 的 `lyric-stage-v2.json`。生产当前版本 `c593e5b3-eb9e-4360-9a1e-8dd1a58ad723`：bible 与最多 4 段 scene 并行，避免超过现有 App 45s 无首包超时。Debug「生成 V5.1」打线上 `/v2`。
- 真机曾出现点击 V5.1 后“完全不动”：设备 Documents 起初没有 V2 缓存，旧按钮只切换渲染器；同时 Section density/accent 预算把本地 hold pulse 当装饰删掉。生成 10 Scene / 41 Event 后又暴露 Canvas 只偶发刷新：AVPlayer 时间藏在绘制闭包，Timeline 还会被 motion/reduce-motion gate 整体暂停。现首次选择会自动生成；低强度 hold pulse 作为基线保留；tick 明确进入 Canvas，歌词时钟与动作强度分离，正常展开 60fps、状态门禁异常时仍保底 30fps，Reduce Motion 只降级动作而不冻结换行。
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
- 输出：`lyric-performance-v4`，包含 lineCount、覆盖每个时间点的 compositions、稀疏 scenes 与可选 wordCues。每个 composition 必须包含当前 lineIndex，并按视觉顺序选择 1–3 个相邻不超过两位的真实歌词索引。scene 可选择九种逐行动效；Cascade 必须对应至少两行 composition。
- 真实逐字歌词始终由 App 本地执行克制的 Sweep。Luna 只为约 10%–30% 有逐字时间的行追加一个范围 cue，可选 Sweep / Impact / Stretch / Echo Trail，最多连续 12 个真实 word index；无 words 的行、越界范围、同一行重复 cue 和未知效果会在 Worker 与 App 两端过滤。
- Luna 不改写、翻译、合并或拆分歌词；只引用 lineIndex。服务端和 App 各做一次 allowlist、范围 clamp、逐行覆盖、重复/越界过滤和版本/身份/歌词哈希校验。长句由 UI 完整换行，禁止用省略号；导演需通过减少同屏行数控制密度。
- 有效脚本写入 `Documents/lyric-performances.json`，最多 100 首；歌词正文、分行、逐行时间或逐字时间任一变化都会改变哈希并使旧脚本失效。手动 offset 不改变脚本身份。
- 缺 scene 的行继续走本地 `LyricMotionDirector`；请求失败、degraded、schema 不匹配或缓存失效时整首歌也可无缝回退，不阻塞播放。
- 分段调用允许部分成功：有效段照常使用，失败段由本地导演补齐，部分结果不写入 KV。全部分段失败才返回 degraded；超时明确标记 `upstream_timeout`，App 不再把它误报成“没有生成有效演出”。
- v5 本地 StageScore 每行选择 assemble / gravityDrop / ripple / stretch / echo / drift / focus / converge 之一；Luna 原生 directive 缺失时由 v4 scene 确定性映射。逐字轴按真实 word 边界拆成 grapheme 时间轨，逐行轴只提供视觉 stagger，不冒充真实唱字时间。所有文本完整进入自动换行 layout。

## 开发入口与撤销

- Debug 菜单分为「歌词舞台」与「Luna」：本地规则 / V5 / V5.1 / 样片互斥；Luna 可生成 V5.1、查看演出摘要或清除独立 V2 缓存。V5 生成入口仍保留便于回滚。
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
