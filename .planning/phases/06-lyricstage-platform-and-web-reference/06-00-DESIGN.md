---
phase: 06
slug: lyricstage-platform-and-web-reference
status: draft
created: 2026-08-21
---

# Phase 06 — LyricStage Core v0 与全屏 Web Stage · 设计规格

## 0. 设计目标

Web 端要利用整块屏幕重新组织演出，而不是把手机中央歌词区同比例放大。第一版以 1920×1080 为参考画布，支持 1280×720、2560×1440 和 16:10；超宽屏先扩展环境层或留黑，不拉伸文字几何。

产品分为两个表面：

- **Control / Rehearsal**：导入、校验、分析、生成、预览、seek、缓存与错误说明。
- **Stage / Audience**：纯画面、无调试 UI、无常驻音乐控件，鼠标静止后隐藏指针。

## 1. 共享合同与所有权

```text
Provider / Local Import
        |
        v
RecordingIdentity + ProviderTrackRef
        |
        +----> LyricDocumentV0 -----------------------+
        |                                              |
        +----> HTMLAudio PlaybackClock                |
        |                 |                            |
        |                 +--> AudioPerformanceMapV2  |
        |                          |                   |
        |                          v                   |
        |                 AudioStructureScoreV4       |
        |                                              |
        +-------------------------------> Local Director / Luna Recipe
                                                       |
                                                       v
                                             PerformancePlanV0
                                                       |
                                             StageCapabilityProfile
                                                       |
                                                       v
                                             PreparedStageV0
                                                       |
                                                       v
                                                Web Renderer
```

所有权固定如下：

| 数据 | 唯一所有者 | 禁止事项 |
|---|---|---|
| 原文、行/字时间、声部、重叠 | `LyricDocumentV0` | Luna/音频不得改写或移动 |
| 播放位置、暂停、速率、seek | `PlaybackClock` | rAF 不得自己累计另一套时钟 |
| beat/onset/energy/section | `AudioPerformanceMapV2` | 不直接决定文字 reveal |
| motif、scene family、结构意图 | `DirectorRecipeV0` | 不输出坐标、绝对 reveal 时间或 glyph index |
| 字号、换行、坐标、曲线、预算 | 本地 compiler + capability profile | 不由模型临场生成 |
| 每帧可见状态 | prepared runtime | 不在帧循环测字、换行、排序、哈希 |

## 2. 来源无关合同

首版以 JSON Schema 2020-12 为跨语言唯一真相，Swift Codable 与 TypeScript 类型都必须通过同一组 fixture。

### 2.1 `RecordingIdentityV0`

- `recordingID`：v0 中是演出包内的 opaque ID，不等于 provider 页面 ID，也不承诺自动识别不同平台上的同一录音。
- `assetHash`：当前本地音频资产的稳定 hash；只用于缓存与失效，不进入模型 prompt。
- `durationMs`、可选标题/艺人/版本提示。
- `providerRefs[]`：Bilibili 可放 bvid/cid，YouTube 可放 video ID；这些字段不得进入核心演出决策。跨 Provider 的录音 reconciliation 留到第二个 Provider 真正接入以后。

### 2.2 `LyricDocumentV0`

- 连续 `lineIndex`、完整 `text`、`fromMs/toMs`。
- 可选真实 word/token 时间、voiceRole、layerID、overlapGroup。
- 无逐字时间时明确标记 line-timed，不平均伪造逐字轴。
- 原文不得截断、不得省略号、不得因无法排版而丢行。

### 2.3 `AudioStructureFactsV0`

- Web v0 兼容现有 `AudioPerformanceMapV2` 与 `AudioStructureScoreV4` 的版本化形状。
- 完整 map 留在本地；发给 Luna 的仍是量化 tempo/section/line facts/structural moments。
- 原音频、PCM、完整 beat/onset 数组与文件指纹不进入模型 prompt。

### 2.4 `DirectorRecipeV0`

- 初始继续支持 V4 四种语义 family：Rail Handoff、Semantic Lens、Chorus Memory、Silence Aperture。
- Recipe 描述**意图**而不是画布坐标。同一 Recipe 可在 `compactMobile` 与 `fullscreen16x9` 编译成不同空间结果。
- 未知版本、枚举、越界引用或坏 scene 只降级该 scene；完整本地计划始终存在。

### 2.5 `PerformancePlanV0`、`PreparedStageV0` 与 `.lyricstage`

- `PerformancePlanV0` 是与字体像素无关的语义编译结果，包含版本、身份、scene index 和资源需求。
- `PreparedStageV0` 才包含 capability、viewport、字体测量、换行与最终几何；只作为当前设备缓存，其 identity 必须包含 rendererVersion、capability、font asset hash 与 viewport。
- `.lyricstage` 首版只携带 manifest + lyric document + audio facts + recipe + 字体需求；不携带 capability/分辨率相关的 prepared plan，默认也不含版权音频。

## 3. Web 工程边界

建议保持在现有仓库内，但使用独立 npm workspace：

```text
web/
  package.json
  apps/stage/
    src/app/                 # React 控制壳，不参与逐帧绘制
    src/playback/            # HTMLAudio + PlaybackClock
    src/import/              # local audio / LRC / canonical JSON
    src/show/                # M5 才启用 control window / audience window
  packages/contracts/
    schemas/
    fixtures/
    src/
  packages/core/
    src/lyrics/
    src/director/
    src/compiler/
    src/timeline/
  packages/renderer/
    src/text/                # Canvas 2D 排版与文字平面
    src/environment/         # M3 后可选 WebGL2 环境层
  packages/audio-analysis/
    src/worker/
  tests/e2e/
```

技术选择：

- TypeScript `strict`、Vite、React；React 只管理控制界面和资源生命周期。
- JSON Schema + Ajv 做运行时门禁；不让 Zod 或 Swift 成为跨语言唯一合同。
- Vitest 做纯逻辑；Playwright 的 v0 阻断门以 macOS Chrome 与 Windows Edge 为准，WebKit 只做基础 smoke。
- M0–M2 只使用 Canvas 2D，先保证 CJK shaping、完整换行和两台目标机器上的可读性；不承诺不同字体引擎像素一致。
- M3 以后若 Canvas 2D 环境层不足，再引入独立 WebGL2 层；WebGPU 只作为后续 capability，不是 v0 前提。
- `<audio>` 是主播放链；Web Audio 只用于离线分析/FFT 旁路，不能接管后台和同步时钟。
- 音频分析、hash 与纯语义 plan/scene 编译可以放 Web Worker。字体加载、`measureText` 与最终 wrap 默认留在页面线程的有界 prepared layout 阶段；只有 capability probe 证明 Worker FontFace + OffscreenCanvas 可用时，才允许整段 layout 下沉。

## 4. 全屏空间语法

### 4.1 参考画布

- 归一化舞台坐标：`0...1 × 0...1`。
- 16:9 主构图；四周 6–8% 字幕安全区。
- 控制 UI 不占 Stage 的 layout safe area。
- 16:10/超宽屏只改变环境层与留白，核心文字构图保持比例。

### 4.2 五层画面

1. **Environment**：颜色、光、雾、少量粒子与段落氛围；可持续缓慢运动。
2. **Structural Field**：轨道、切线、窗口、段落边界与节奏几何。
3. **Primary Lyrics**：当前正文，清晰度与真实时间优先。
4. **Memory / Counterpoint**：副歌残留、前后句、二重唱与声部关系。
5. **Transition Veil**：scene 交接、silence blackout 与短时后处理；不得长期盖住正文。

### 4.3 手机语义到大屏编译

同一个语义 family 在大屏重新布局：

- **Rail Handoff**：轨道可以跨越整个横向画幅，上一句留下的结构线把视线交给下一句，而不是只在中心附近滑动。
- **Semantic Lens**：全文保持可读，关键词可占据独立大尺度焦点区，其他文本退到安全背景层。
- **Chorus Memory**：重复 Hook 可以在画面不同区域积累记忆与声部，不只是同位置叠两层残影。
- **Silence Aperture**：静音不是“空白等待”，而是控制环境、遮幕和下一幕入口；歌词仍严格到时才出现。

大屏允许环境连续运动，但正文继续 static-first：

- 普通行：短入场后稳定；
- 结构转折：允许一次大幅位移、聚合、切幕或焦点交换；
- Hook：允许跨段记忆逐次发展；
- 长句与双声部：优先重新分区和换行，不压缩成手机字级。

## 5. 运行时与性能原则

- 本地模式由 `HTMLAudioElement.currentTime` 独占媒体时钟；YouTube Music 模式由宿主播放器快照独占时间真相。Stage 可以用接收时的 monotonic timestamp 在快照间按 playbackRate 外推，但每次新快照必须重新校准，不能积累第二套独立时钟。
- M2 单窗口时由当前页面唯一 `<audio>` 输出声音；M5 分窗后由 Stage 窗独占唯一 `<audio>` 和声音，Control 只发 command、接收 snapshot，进入 Show Mode 前必须停止 Control 预览。
- 暂停或页面不可见时停止连续 rAF；seek、resize、字体完成时单帧重绘。
- 字体测量、换行、token 几何、scene 边界、轨道和粒子种子都在 prepared compile 阶段完成。
- 每帧只做 O(log scene/event) lookup + O(visible glyphs/particles) sample/draw。
- Canvas 与未来 WebGL 环境层必须共用一个 rAF 和同一次媒体时间采样；WebGL context lost 时立即退到静态 Canvas 完整歌词。
- 开始播放不等待音频分析或 Luna；先展示完整 local fallback，增强结果准备好后按 identity 原子替换。
- 编译结果必须带 track/lyrics/audio/director/compiler/capability identity，旧曲异步结果不得覆盖新曲。

## 6. 隐私与服务边界

- 本地音频和 PCM 永不上传。
- 浏览器不保存 Bilibili Cookie、上游模型 key 或长期 Worker Bearer。
- Luna 只接收完整歌词、时间轴与有界音频结构事实，并只在用户显式排练时调用。
- 正式演出阶段不发网络请求；刷新或断网后应从本地演出包/缓存恢复。
- 后续 Bilibili Provider 必须通过同源 BFF 处理 Cookie、WBI、短效 URL 与 Range 206；YouTube Music 优先用浏览器 companion 读取宿主播放状态，不复制或绕过媒体权限。

## 7. v0 非目标

- 不承诺移动 Safari、后台 PWA 或锁屏控制。
- 不做云账号、云曲库、多人协作、公开作品市场。
- 初始 Phase 06 不包含自动歌词搜索；用户随后明确授权 YouTube Music Companion 增加有界自动歌词切片。该切片只使用标题、歌手、时长与 provider track ID 查公开只读歌词源，高置信结果自动采用、歧义结果必须手选；ASR、强制对齐与自动跨平台录音 reconciliation 仍不做。
- 不做实时生成；Luna 只生成预先可验证、可缓存的导演 Recipe。
- 不把效果数量当作 KPI；可读性、结构因果、整曲连贯与 seek 可恢复更重要。

## 8. 执行切片

| Plan | 结果 | 非承诺粗估 |
|---|---|---:|
| 06-01 | 正式重基线、跨语言 schema 与 golden fixtures | 2–4 天 |
| 06-02 | 单窗口本地音频 + 歌词的全屏 Stage alpha，并追加只读 YouTube Music Companion v0 | 4–6 天 |
| 06-03 | 音频结构 Worker、完整四 family 与大屏环境层 | 2–4 天 |
| 06-04 | 显式 Luna 排练、缓存与 `.lyricstage` 演出包 | 2–4 天 |
| 06-05 | 独立 Control/Stage 第二屏 Show Mode | 2–3 天 |
| 06-06 | Apple Music 式稳定外壳、Performance Direction Skill 与有证据的开放演出语法 | 以 Task 0–6 退出门推进 |

这些数字只用于控制范围，不是交付承诺。确认 Phase 06 后先执行 06-01 与 06-02；其余切片必须在前一退出门通过后再启动。
