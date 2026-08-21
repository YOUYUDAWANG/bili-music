---
phase: 06
slug: lyricstage-platform-and-web-reference
status: draft
created: 2026-08-21
---

# Phase 06 — 验证策略

## 1. 合同门禁

- JSON Schema 正反例：版本、必填字段、连续 lineIndex、单调 line/word 时间、完整文本、声部与重叠。
- 同一 fixture 在 Swift 与 TypeScript 两端均可解码并产生相同的语义内容与核心 identity；不比较字体测量、PreparedStage 或像素输出。
- `providerRefs` 可为空；核心合同中不得要求 bvid/cid。
- lyrics/audio/direction/compiler identity 变化必须失效语义 plan；renderer/capability/font/viewport 变化必须失效 PreparedStage。
- 未知 scene、越界 line/token、坏 landmark 只局部降级；完整 local fallback 永远可用。

## 2. 时间与同步门禁

- 本地模式由 `<audio>.currentTime` 独占播放时钟；YouTube Music 模式由宿主快照独占时间真相。rAF 只在快照间按 playbackRate 外推并持续重校准，不积分长期自有时钟。
- line-only 歌词的所有 word timing 都为空；不得平均分配字符时间。
- 真实逐字 glyph 的 earliest visible 不早于 word.from，也不等待 beat/onset。
- 用户 offset 只影响 lyric clock；audio clock 与结构事件保持原位。
- 固定做 20 个随机 seek、pause/resume、restart；从 `seeked` 事件或媒体时间进入目标容差开始，两帧内恢复正确 scene，无补播历史动画。
- M5 分窗后 Stage 窗独占唯一 `<audio>` 和声音；Control 只发送命令与读取 snapshot，不创建第二媒体时钟。

## 3. 文本与视觉门禁

固定 fixture：

1. 逐行日文；
2. 中英日混排逐字，含空格、标点与 emoji；
3. 超长中文/日文行；
4. 重复 Hook；
5. 二重唱/和声 overlap；
6. 5–6 分钟长歌结构。

每份在 1280×720、1920×1080、2560×1440 和 16:10 截图检查：

- 无省略号、裁字、越界或不可恢复重叠；
- 6–8% 安全区有效；
- line-only 不伪逐字；
- Reduce Motion 仍保留完整层级与可读性；
- static-first：普通正文落稳后静止，结构事件才有大动作；
- Stage 无观众可见控制、toast、debug label 或鼠标残留。
- 已支持 family 的 1080p 关键帧不得保留固定窄内容列或手机卡片边界，必须形成跨画幅关系或至少主/次两个空间区，并在实际观看距离可读。

## 4. 性能门禁

首轮平台：macOS Chrome 与 Windows Edge；WebKit 只做基础兼容，不作为 Show Mode v0 阻断。

- 1080p / 60fps：整个 rAF callback p95 < 8ms、p99 < 16.67ms，240 帧 fixture 无持续/连续超预算；text draw 作为子指标单独记录，不能冒充整帧。
- 播放阶段无 compile/layout/analysis 引起的 >50ms main-thread long task。
- 180 行纯语义 compile 目标 <=50ms，超过即移入 Worker。字体加载、`measureText` 与最终 wrap 默认留在主线程的有界/分片 prepared layout；只有 capability probe 通过才整体下沉。
- 帧循环只能 O(log scene/events) + O(visible glyphs/particles)，禁止全文扫描、测字、wrap、sort、hash 与 React state 更新。
- 5–6 分钟连续播放内存达到稳定平台后不持续增长；关闭/换曲会释放 PCM、旧 texture 与旧 plan。
- 音频分析不阻塞首次出声；失败仍可使用完整静态计划。
- `decodeAudioData` 后的 downmix/resample 必须分片并 transfer mono `Float32Array`；PCM 转换本身也不得在播放中制造 >50ms long task。
- 若启用 WebGL 环境层，Canvas/WebGL 必须共用一个 rAF 与一次媒体时间采样；同时记录整段 callback、掉帧率、连续 missed frame，并验证 context loss 静态 fallback。

## 5. 演出与故障门禁

- 生成 Luna 时可继续播放本地 fallback；取消/换曲后旧结果不能覆盖新曲。
- 演出开始前完成音频、字体、歌词、plan 与 fallback preflight。
- 演出开始后关闭网络，整曲仍能完成。
- Stage 窗被关闭、断连或退出全屏时，观众面安全静止/blackout；控制端可重新打开并恢复当前媒体时刻。
- `.lyricstage` 默认不内嵌音频，也不携带 capability/字体/viewport 相关 PreparedStage；导入坏包只显示可操作错误，不改写用户源文件。

## 6. Phase 06 退出门

Phase 06 只有同时满足以下条件才算完成：

1. 来源无关合同由同一套 schema/fixtures 约束 Swift 与 TypeScript。
2. 本地音频 + 时间轴歌词可以完整经过排练与 1080p 全屏演出。
3. 5–6 分钟歌曲、20 次 seek 与暂停/恢复保持同步和确定性。
4. Luna 可选且完全不拥有正文/时间；断网仍可演出。
5. Mac Chrome 与 Windows Edge 第二屏各完成一首真实歌曲。
6. YouTube Music Companion 失效或未安装时，本地模式仍完整成立；Bilibili 尚未接入不影响上述能力。
