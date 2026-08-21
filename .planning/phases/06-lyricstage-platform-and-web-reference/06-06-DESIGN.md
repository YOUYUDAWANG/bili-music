---
phase: 06
plan: 06
slug: stage-first-now-playing-and-performance-direction-skill
status: approved
created: 2026-08-21
updated: 2026-08-21
supersedes_visual_sections_of: [06-00-DESIGN.md]
---

# Phase 06-06 — Apple Music 式稳定外壳、歌词演出舞台与 Performance Direction Skill

## 0. 执行摘要

LyricStage 全屏不再被定义为“放大的歌词 Canvas”，也不做 Apple Music 的像素复刻。产品目标是：

> 以 Apple Music 级别的 Now Playing 完整度建立稳定视觉锚点，再让歌词导演在受控舞台内做真正有因果的演出。

本文件取代 `06-00-DESIGN.md` 中关于全屏观众表面、空间语法和效果策略的阶段性描述；来源无关合同、歌词/时钟所有权、断网 fallback、随机 seek 与身份门禁继续有效。

最终产品由两个明确层次组成：

1. **稳定播放器外壳**：封面、标题/艺人、细进度、必要运输控制，建立完整 Now Playing 与操作信任。
2. **可变歌词舞台**：三层连续阅读、结构分幕、单句英雄演出、声部/记忆关系和有证据的背景几何。

复杂度必须来自歌词、歌曲母题和结构发展，而不是来自控件数量、玻璃数量或随机特效数量。

## 1. 已冻结决定与专业修正

### 1.1 已冻结

| 决定 | 结论 |
|---|---|
| 默认构图 | B「舞台型」：封面信息约 28–32%，歌词舞台约 68–72% |
| 封面 | 必须显示当前歌曲真实封面；背景只消费其抽象色彩/纹理，不把封面拉伸铺满 |
| 常态歌词 | 上一句、当前句、下一句三层；当前句清晰，邻句可辨而非不可读的重度模糊 |
| 英雄演出 | 结构证据成立时允许封面缩为信息岛，歌词进入单句海报式演出 |
| 分幕资格 | 每个 section 都可申请构图变化，但不保证执行 |
| 控件 | 删除顶部和底部浮动胶囊；封面区内保留细进度与真实可用的播放/暂停、上一首、下一首 |
| 材质 | Liquid Glass 只用于瞬时交互控件，不进入内容背景或歌词卡片 |
| AMLL | AGPL-3.0 可接受；LyricStage 将以同等开源义务发布，可正式评估其 core/parser/background |
| AI 导演 | 使用版本化 Performance Direction Skill；可选成熟配方，也可组合新演出 |
| 效果理由 | 每个主效果必须给出歌曲母题、分幕结构和歌词行证据；理由只用于排练/诊断，不显示给观众 |

### 1.2 专业修正与否决

- **不做 Apple Music 像素复刻。** 学习其信息层级、字重节奏、封面锚点和材质克制；歌词演出是 LyricStage 的产品差异。
- **不让封面每幕必缩。** 每幕都有资格，但必须通过结构强度、语义证据、最短稳定驻留和当前构图状态门禁。
- **不把效果数量当 KPI。** 初版宁可 12–18 个可信配方，也不要 100 个换皮模板。
- **不做关键词直译器。** “接近”不自动等于画圆，“破碎”不自动等于 glitch；局部证据必须服从全曲母题。
- **不允许模型输出任意 JS、CSS、GLSL、坐标脚本或绝对逐字时间。** 创作自由来自受控原语的开放组合。
- **不为填空持续运动。** 空白、静止、遮幕和低对比环境同样是编舞材料。
- **不伪造媒体控制。** Bridge 不支持的 AirPlay、系统音量、收藏、队列或随机播放不出现在全屏。

## 2. 产品状态模型

### 2.1 Reading — 常态阅读

- 封面保持大尺寸方形锚点，标题/艺人位于封面下方。
- 细进度始终可见；运输控制只在指针进入封面区、键盘媒体操作或短时播放状态变化时出现。
- 右侧显示三层歌词：上一句 28–38% 视觉权重，当前句 100%，下一句 38–48%。
- 当前句只做 160–320ms 的有向入场/落稳；普通段落随后静止。
- 环境延续全曲母题，section 只能调整密度、方向、空间关系和强度，不能无因换世界。

### 2.2 Section Transform — 分幕变形

- 只在 section 边界、显著空隙、声部交换或导演已缓存计划接管时发生。
- 允许改变歌词分区、几何场、色板角色和封面比例。
- 转场保留对象恒常性：封面缩岛必须沿连续路径移动，当前句不得瞬间消失再在无关位置重建。
- 推荐时间 450–800ms；转场结束后必须有稳定驻留，不连续串联多次大变形。

### 2.3 Hero Line — 单句英雄演出

- 只用于 Hook、关键转折、强问题、终章落点、声部合流或经过验证的高强度结构点。
- 封面可缩为约 12–16% 画幅的信息岛；当前句接管主舞台。
- 全曲占比目标为 15–25%，不得把每一幕都做成高潮。
- 单句完整显示，禁止为放大而截词；长句优先改为双行海报或保持 Reading。

### 2.4 Duet / Counterpoint — 声部关系

- 重叠声部优先用左右、前后或镜像关系表达，而不是把两句叠在同一中心。
- lead、harmony、duetA、duetB、choir 使用稳定空间角色；换声部时由轨迹交接视线。
- 未标注声部的歌词不由 AI 猜测二重唱。

### 2.5 Aperture — 留白与间奏

- 无 active lyric 时不显示等待文案、debug 或空白错误。
- 环境降低信息密度，保留封面锚点和细进度；下一幕入口可由 aperture、遮幕或单一结构线暗示。
- 音频结构尚未接入时，只依据真实歌词间隙；不得伪造 beat/onset。

## 3. UI 规格

### 3.1 参考画布与网格

- 主参考：1920×1080；支持 1280×720、2560×1440、16:10。
- 外侧安全区 5–6%；封面列与歌词列之间保留 4–6% 的呼吸区。
- 默认列比例 30/70；封面列最小 220 CSS px，歌词列不得因小窗口压成不可读窄栏。
- 16:10/超宽只扩展环境和列间距，不横向拉伸字体。

### 3.2 封面与曲目信息

- 封面圆角克制，阴影来自背景明度而非固定重黑投影。
- 封面原图保持清晰，不施加持续缩放、旋转、色差或故障特效。
- 曲名一行优先；过长时允许两行，不滚动跑马灯。
- 艺人/版本为次级信息；来源、AI 状态、录音 ID 不进入观众表面。
- 缺封面时由本地色板和标题首字生成稳定占位，不请求额外生成图片。

### 3.3 进度与运输控制

- 细进度常驻，当前/剩余时间可在封面区 hover/focus 时出现。
- 播放/暂停、上一首、下一首只能调用 YTM Bridge 的权威命令；失败时不乐观伪装成功。
- Space 只在非输入控件焦点时控制播放；左右方向键 seek 的步长需显式且与 YTM 行为一致。
- 控件不得出现在屏幕顶部或底部浮动条，不覆盖歌词安全区。

### 3.4 歌词层级

- 当前句对比度必须稳定达到可读门槛；颜色来自 section palette role，但不得与背景同亮度。
- 邻句依靠透明度、尺度和空间深度退后；模糊半径只作轻微景深，不能让用户看不清上下文。
- 有真实 word timing 时使用逐字扫亮；无 word timing 时整行按行轴出现，不平均伪造。
- AMLL 与 LyricStage renderer 切换时，同一时刻只能有一个 glyph owner，禁止双层重影和不同步。

## 4. Motion Bible

### 4.1 三个时间尺度

1. **Song scale（整曲）**：1 个核心母题、1 套封面派生基础色场、1 条强度弧。
2. **Section scale（分幕）**：布局、几何关系、密度、色板角色和封面比例发生有限变形。
3. **Line/word scale（逐句）**：显现、落稳、短残影、方向交接和逐字扫亮。

低尺度不得推翻高尺度：逐句词义只能改变当前母题的表现方式，不能临时换成另一首歌的视觉世界。

### 4.2 运动物理

- 位移必须有来源和目标；同一对象跨状态保持方向连续。
- 封面表现为有质量的锚点，歌词表现为可重组的文字平面，环境表现为低频场。
- 大动作使用 ease-out 或受控 spring，禁止全局统一线性 tween。
- 入场结束后归稳；持续呼吸只允许环境和极低幅结构层。
- 同一时刻只能有一个主要运动焦点，通常只有一个辅助运动；硬上限两个辅助效果。

### 4.3 时间与幅度基线

| 行为 | 建议区间 | 约束 |
|---|---:|---|
| 逐字亮度过渡 | 90–180ms | reveal 时刻仍由歌词轴拥有 |
| 普通句落稳 | 160–320ms | 完成后静止 |
| 结构线交接 | 320–620ms | 不遮挡正文 |
| 封面缩岛/复位 | 500–800ms | 必须保持连续路径 |
| 切幕/空间换装 | 450–900ms | 不连续叠加 |
| 环境低频运动 | 6–14s 周期 | 不作为节拍器 |

这些值是编译器默认，不是 AI 输出自由参数；后续只能根据真实 UAT 调整有限范围。

## 5. 效果因果与证据合同

### 5.1 三层证据

每个主效果必须同时满足：

1. **Song motif evidence**：全曲概念、封面色场、主要意象或强度弧支持该视觉世界。
2. **Section evidence**：重复 Hook、结构空隙、声部变化、密度变化、转折或终章等事实支持本幕改变。
3. **Line evidence**：引用真实 `lineIndex`，说明当前句如何发展母题。

只有 line 关键词、没有 song/section 支持时，最多允许逐句微动作，不得触发背景换装或封面缩岛。

### 5.2 受控 trigger vocabulary

- `repeated_hook`
- `section_boundary`
- `silence_gap`
- `duet_overlap`
- `voice_handoff`
- `density_lift`
- `density_release`
- `semantic_distance`
- `semantic_motion`
- `semantic_contrast`
- `question_suspension`
- `collective_chorus`
- `final_resolution`

AI 可在 rationale 中描述新语义，但进入运行时前必须映射到一个或多个受控 trigger；未知 trigger 只保留作排练建议，不进入演出。

### 5.3 反证与抑制

- 长句、低对比背景、低置信语义、连续大动作、上一个英雄演出尚未稳定时，降低或拒绝强效果。
- 同一个配方在相邻两个 section 不重复原样执行；重复 Hook 必须发展而非复制。
- 字幕可读性、reduce-motion、闪烁保护和帧预算可覆盖导演选择。

## 6. Performance Direction Skill

### 6.1 定位

Performance Direction Skill 是独立 Director 后端的版本化知识包，不是向模型粘贴一串特效名称。它包含：

- 产品审美和专业否决项；
- typed primitive 词汇；
- 有证据的成熟 effect cards；
- 组合语法、预算、互斥和 fallback；
- 正例、反例和整曲发展示例；
- 输出 JSON Schema 与本地编译能力清单。

建议目录：

```text
services/lyricstage-director/
  skills/performance-direction-v1/
    SKILL.md
    grammar.json
    effect-cards/
    examples/
    anti-patterns.md
    schema.json
```

服务只读取并版本化此包；skill 变更必须 bump `directorVersion` 与缓存 namespace。

### 6.2 开放创作而不失控

导演有三条合法路径：

1. 选择成熟 effect card；
2. 选择 card 并在受控范围内改参数/配角原语；
3. 用已注册 primitive 组合新的 typed recipe，并说明证据与预算。

第三条保证导演不拘泥于目录。模型不能临场创造新的底层 primitive；若提出新原语，只作为 `authoringSuggestion` 进入 Performance Lab，不进入当前歌曲运行时。

### 6.3 初始 primitive 词汇

| 层 | 初始原语 |
|---|---|
| Typography | settle、assemble、gravityDrop、ripple、stretch、echo、drift、focus、converge、wordSweep |
| Layout | monument、editorialSplit、railLeading、railTrailing、duetDivide、heroIsland |
| Geometry | lineRail、orbitalField、splitPlane、perspectiveGrid、aperture、echoRing、windowFrame、particleConstellation |
| Environment | coverColorField、softBloom、liquidMemory、paperTexture、monoImpact、celestialDepth、vignette、grain |
| Transition | veil、axisCut、irisOpen、fieldDissolve、blackout、coverShrink、coverRestore |
| Memory | previousLine、nextLine、hookResidue、voiceCounterpoint、motifRecall |

原语数量保持小而稳定；丰富度来自组合、发展和歌曲级母题，而不是不断扩 enum。

### 6.4 首批 effect cards

| 配方 | 合法理由 | 主要表现 | 不应使用 |
|---|---|---|---|
| Distance Convergence | 全曲母题支持空间/引力，当前段反复出现距离发展 | 轨道/窗口向当前句收束 | 单个“近/远”关键词 |
| Chorus Memory | 已确认重复 Hook，且为第二次或以后出现 | 环形残影、位置记忆、逐次发展 | 首次出现、非重复长句 |
| Contrast Cut | 结构与语义同时转折 | 空间切面、方向交换、色板角色互换 | 普通连接词 |
| Silence Aperture | 真实歌词空隙或音频结构静默 | 环境降密度、aperture 暗示下一幕 | 正文仍 active |
| Duet Mirror | 明确 overlap/voiceRole | 分屏、镜像轨迹、声部交接 | 未标声部的混唱 |
| Chorus Expansion | collective chorus + 强度上升 | 字面扩张、几何外放、封面缩岛 | 普通主歌 |
| Question Suspension | 连续疑问与未解决段落 | 上浮、悬置、未闭合几何 | 已完成结论句 |
| Gravity Resolution | 终章/落地语义 + 结构结束 | 文字重力落定、几何归轴 | 曲中普通短句 |
| Density Lift | 行密度/逐字密度显著提升 | 网格/粒子/排版密度增加 | 慢速留白段 |
| Field Release | 高密度后真实释放 | 结构退场、留白扩大 | 没有前置张力 |
| Motif Recall | 早期母题在后段再现 | 旧几何位置/颜色被重新引用 | 全新段落无关联 |
| Final Dissolution | 尾奏、终章与最后一句 | 文字保留、环境分解并静止 | 中段或下一句立即进入 |

## 7. Typed Recipe 与运行时合同

### 7.1 建议形状

```ts
interface EffectEvidenceV1 {
  songMotifIDs: string[];
  trigger: PerformanceTriggerV1;
  sectionID: string;
  lineIndices: number[];
  confidence: number;
  rationale: string; // 只在排练/诊断表面可见
}

interface EffectPrimitiveUseV1 {
  primitiveID: string;
  layer: "environment" | "structure" | "primary" | "memory" | "transition" | "cover";
  role: "primary" | "support";
  parameters: Record<string, number | string | boolean>;
}

interface EffectRecipeV1 {
  id: string;
  baseCardID?: string;
  evidence: EffectEvidenceV1;
  primitives: EffectPrimitiveUseV1[];
  intensity: number;
  fromLineIndex: number;
  toLineIndex: number;
  motionBudget: "quiet" | "standard" | "hero";
  fallbackCardID: string;
}
```

### 7.2 本地编译门禁

- primitive 必须存在于当前 `CapabilityRegistry`；未知项删除并记录排练诊断。
- 每幕 exactly one primary；support 默认最多 1、硬上限 2。
- 参数由 schema clamp；模型不能提供绝对 glyph reveal、任意坐标数组或 shader source。
- evidence 引用必须属于当前歌词和 section；低置信只允许 quiet/line-level。
- cover shrink、hero layout、强后处理必须同时通过结构证据、冷却、可读性和 reduce-motion 门。
- recipe 失败只降级该幕；完整 local DirectorPlan 继续覆盖整曲。

## 8. AMLL 集成边界

### 8.1 可采用

- `@applemusic-like-lyrics/core` 的成熟逐字歌词表现和状态模型；
- `@applemusic-like-lyrics/ttml` / lyric parser 的格式兼容能力；
- 动态背景中的色彩、模糊、低频运动和性能处理；
- AGPL 源码研究、修改和分发，但必须同步完成仓库许可证、版权声明、修改说明和对应源代码提供义务。

### 8.2 不采用

- 不让 `react-full` 决定 LyricStage 整个 Now Playing 外壳；
- 不让 AMLL 拥有 YTM Bridge、封面缩岛、AI 分幕、EffectRecipe 或本地 fallback；
- 不同时让 AMLL 与 Canvas 绘制同一 current glyph；
- 不为了“已经像 Apple”而取消 LyricStage 的 Hero Line、声部空间和结构几何。

### 8.3 技术 spike 的选择门

实现前必须比较两条路径：

1. **AMLL normal / LyricStage hero**：AMLL 负责 Reading，Hero/特殊分幕切换到 directed renderer。
2. **AMLL algorithms / single LyricStage renderer**：复用 AMLL 的解析、逐字与背景算法，但保持单一 glyph renderer。

默认倾向第二条，因为单一 glyph owner 更容易保证 seek、长句、声部、handoff 和无闪烁；只有 spike 证明第一条切换无重影、无布局跳变且维护成本更低，才使用双 renderer。

## 9. 运行时数据流

```text
LyricDocument + authoritative PlaybackClock + cover palette
          + local structural facts
          + optional cached AI DirectorPlan
                         |
                         v
            Performance Direction Skill
                         |
                         v
          validated EffectRecipeV1 collection
                         |
                         v
       local capability / budget / evidence compiler
                         |
                         v
              PreparedDirectedStageV2
                         |
             +-----------+-----------+
             v                       v
      Now Playing Shell        Directed Stage Layers
```

- AI 继续后台生成并缓存；当前曲立即使用完整 local plan。
- AI 结果只在下一合法 section 边界接管。
- cover palette、字体 readiness、viewport 与 renderer version 进入 prepared identity。
- 每帧只采一次宿主时钟；React 不参与逐帧状态更新。
- audience 不显示 evidence/rationale；Control/Performance Lab 可查看导演为什么选择该效果。

## 10. 性能、无障碍与质量降级

### 10.1 目标

- 1920×1080、DPR ≤2、macOS Chrome 连续 60fps。
- Canvas2D draw 区间 P95 ≤2ms、P99 ≤4ms；环境 WebGL 不产生持续 long task。
- 不在每帧测字、换行、创建渐变/纹理、排序、哈希或 set React state。
- 粒子、模糊半径、离屏纹理和 residue 数量按 capability 分级；超预算先删支持层，不删正文。

### 10.2 Reduce Motion

- 保留封面、三层歌词、色板、静态几何和逐字亮度进度。
- cover shrink 变为短交叉布局或直接保持常态；不做大尺度飞行。
- ripple、drift、continuous orbit、camera-like motion 关闭。
- 不使用超过 3 次/秒的明显闪烁；高对比闪光由 dim-flashing policy 直接拒绝。

### 10.3 失败顺序

1. 删除 post-FX、粒子和支持几何；
2. 环境退为封面色场静态图；
3. Hero 退为三层 Reading；
4. AMLL/Directed renderer 失败时恢复完整静态歌词；
5. 任何失败都不得影响 YTM 音频、播放控制或原生 Lyrics 恢复。

## 11. 验收矩阵

### 11.1 固定 fixture

- 普通 line-timed 日文主歌；
- 中英混排真实 word timing；
- 重复 Hook 三次发展；
- 明确 duet overlap；
- 超长 CJK/拉丁混排；
- 3 秒以上 silence gap；
- 无封面、无逐字、AI degraded 三种 fallback。

### 11.2 必须回答的视觉问题

- 第一眼是否是完成的 Now Playing，而不是技术 demo？
- 封面是否稳定提供视觉锚点，而非抢夺歌词？
- 普通段是否足够安静，使 Hero 真正成立？
- 每个强效果能否指出 song/section/line 三层理由？
- 随机 seek 是否立即恢复同一画面，而非依赖此前播放历史？
- 长句、二重唱、无逐字和 reduce-motion 是否仍完整可读？
- 连续听三首不同歌曲时，是否既有歌曲差异又保持 LyricStage 产品一致性？

### 11.3 真实 Chrome 门

- 至少快歌、慢歌、重复副歌、二重唱、长句各一首。
- 每首 20 次随机 seek、pause/resume、section handoff 和一次 extension reload。
- 检查 cover/current track identity、单实例 host、Bridge 控制反馈、GPU/context-loss fallback。
- 记录 Canvas、WebGL、long task、内存和 console；不能只用单次截图声称完成。
- 最终由用户做整首主观 A/B；团队不得把“测试通过”冒充“视觉已经优秀”。

## 12. 设计完成定义

只有同时满足以下条件，06-06 才可称为完成：

- 稳定 Apple Music 级 Now Playing 外壳与 LyricStage 演出层均成立；
- 顶部/底部无多余浮动 chrome；
- AMLL 边界清晰且履行 AGPL；
- EffectRecipe 可选择成熟配方，也可组合新演出；
- 强效果有三层证据、预算和 fallback；
- 普通段、Hero、Duet、Aperture 都能随机 seek 确定恢复；
- 真实 YTM 五类歌曲的完整播放和视觉 A/B 关闭；
- 无 AI、无逐字、无封面、GPU failure、reduce-motion 均保留完整可用歌词。

剩余模糊强度、封面缩岛精确比例、弹性曲线和粒子密度不再由用户抽象猜测；它们在第一版真实画面上由 UI/动效评审调整。
