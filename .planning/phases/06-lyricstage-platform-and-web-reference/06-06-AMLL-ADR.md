---
phase: 06
plan: 06
decision: amll-integration-boundary
status: accepted
date: 2026-08-21
---

# ADR — AMLL 接入边界：保留单一 glyph renderer

## 决定

LyricStage 不在生产全屏中并置 `@applemusic-like-lyrics/react` 与现有 Canvas renderer，也不在 Reading/Hero 之间切换两个歌词播放器。生产路径保持一个 glyph owner、一个 clock sample、一个任意 seek 状态函数。

AMLL 作为算法与质量基准使用。首期吸收以下原则并在 LyricStage 自有 renderer 中实现：

- 上一句／当前句／下一句的稳定阅读层级；
- 逐字 mask 的有限渐变宽度，不把 reveal 时刻交给装饰动画；
- 行布局与字形动画分离，resize/seek 才允许强制 reflow；
- 普通行完成短暂落稳后静止；
- 背景人声、对唱、音译和翻译属于歌词结构，不由视觉模型猜测；
- reduce-motion 与低能力设备可关闭 spring、blur、support layer，而不撤正文。

TTML parser 暂不成为运行时依赖。当前 Lyrics Bridge 交付的是已验证的 `LyricDocumentV0`，在没有真实 TTML 输入链路前加入 parser 只会增加包面和许可证表面积。接入真实 TTML 来源时，单独建立 parser ADR。

## 实测证据

审计对象为 npm 官方发布包：

| 包 | 版本 | 许可证 | unpacked size | 结论 |
|---|---:|---|---:|---|
| `@applemusic-like-lyrics/core` | 0.5.2 | AGPL-3.0-only | 1,125,448 B | DOM LyricPlayer、逐帧 update、spring、word fade、seek/reflow 完整 |
| `@applemusic-like-lyrics/react` | 0.5.2 | AGPL-3.0-only | 122,443 B | React wrapper，仍要求 AMLL 自己持有播放器实例与逐帧更新 |
| `@applemusic-like-lyrics/ttml` | 1.0.1 | AGPL-3.0-only | 371,129 B | parser/generator 能力成熟，但当前输入链路用不到 |

AMLL core 的公开类型表明：

- `setLyricLines` 持有不可变歌词数组；
- `setCurrentTime` 只更新内部时间，仍需逐帧调用 `update`；
- resize/new lyrics/random seek 会触发 `calcLayout`；
- `setEnableSpring`、`setEnableBlur`、`setEnableScale`、`setWordFadeWidth` 分别拥有独立表现状态；
- line click、scroll/reset、background renderer 都由 AMLL player 自己管理。

这些能力对普通连续歌词很强，但与 LyricStage 当前 `PlaybackClockV0 -> prepareDirectedStageV1 -> drawDirectedStageV1` 路径形成重叠所有权。

## A/B 结论

### 路径 A：AMLL normal + LyricStage hero

优点：普通逐字歌词可以较快获得成熟 Apple Music 风格。

否决原因：

1. Reading 与 Hero 各有独立 glyph tree，切幕必须在 DOM 与 Canvas 间交接同一句文字。
2. AMLL 要求自己的逐帧 `update`，与 Canvas、环境层、封面布局形成第二个动画循环。
3. random seek、resize、AI section handoff 同时触发布局接管，容易出现双层残影或跳字。
4. 为避免残影而销毁／重建 AMLL player，会丢失对象恒常性和滚动状态。
5. 双 renderer 的视觉优势只集中在 Reading，不能抵消演出系统的维护与性能成本。

### 路径 B：AMLL 原则 + LyricStage 单 renderer

优点：

1. 同一字形在 Reading、Section Transform、Hero、Duet、Aperture 中连续变形。
2. reveal、seek、pause、section handoff 共用一次权威时钟采样。
3. 视觉预算可以先降 support/post-FX，再保持完整三层 Reading。
4. 本地 plan 与 AI plan 消费同一 prepared scene，不需要跨引擎适配。

代价：三层排版、字形 mask、spring/fallback 和虚拟化需要自行实现与测试。

## Fixture 门

生产 renderer 必须用同一 fixture 集关闭以下门：

- word-timed mixed：逐字 reveal 不延后、不倒退；
- line-only Japanese：不伪造字级 timing；
- long CJK/Latin：完整换行，不因 Hero 截词；
- repeated hook：相邻 Hook 有发展而非复制；
- duet overlap：声部并列且不重叠；
- random seek/resize：同一时间得到确定画面，无第二 glyph tree。

## 许可证

用户已接受 AGPL-3.0-only，并计划以同等标准公开完整对应源代码。仓库在 Release Candidate 前必须补齐：

- 根级 AGPL-3.0-only 许可证声明；
- 第三方 NOTICE，记录 AMLL 作为设计／算法基准；
- 若未来复制或修改 AMLL 代码，记录具体文件、上游 copyright、修改说明与对应源码提供路径；
- 发布产物不得只提供构建后的扩展而隐藏对应源码。

当前实现不复制 AMLL 发布包代码，也不把其 npm 包加入生产依赖；因此 NOTICE 只陈述研究参考，不虚构派生关系。

## 后果

- Task 3 直接在 LyricStage renderer 内实现三层 Reading 和 typed effects。
- AMLL 继续作为视觉／性能 benchmark，而不是运行时 owner。
- 未来若 AMLL 提供无 UI 的纯 layout/mask primitive，可重新评估；任何重新评估仍以单 glyph owner 为硬门。
