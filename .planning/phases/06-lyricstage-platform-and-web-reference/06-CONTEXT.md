---
phase: 06
slug: lyricstage-platform-and-web-reference
status: draft
created: 2026-08-21
---

# Phase 06 — LyricStage 平台内核与全屏 Web 参考舞台 · 上下文

> 本阶段目前是第一版草案。用户确认后，才把 `.planning/STATE.md`、项目范围和需求追踪正式切换到 Phase 06；当前不改 BiliMusic iOS 的已完成基线。

## 1. 为什么现在做

BiliMusic 已经证明三件事：

1. B 站音乐播放、缓存、歌词与 LNPopup 日常交互可以成为稳定的个人客户端。
2. 逐行、逐字、声部、音频结构与 Luna Scene Recipe 可以共同生成确定性的整曲演出。
3. 小尺寸 iPhone 舞台迫使排版、绘制次数和运动幅度非常克制，但这些限制不应该成为歌词演出生态的最终上限。

用户的新目标不再只是“做一个 Bilibili Music 网页版”，而是让同一套歌词演出能力可以承接：

- 本地导入的音频；
- Bilibili；
- YouTube Music 与其他网页播放器；
- 将来可能出现的桌面播放器、第二屏、投影和安装式展示。

因此当前项目进入的是**跨平台内核抽取前的 Phase 0**：iOS 是第一个成熟参考客户端，Web 是第一个真正检验来源无关合同与大屏演出空间的第二运行时。

## 2. 本阶段的产品定义

Phase 06 的首个产品不是音乐库，也不是手机播放器的放大版，而是：

> 用户可以选择本地音频，也可以让 YouTube Music 宿主标签页提供声音与播放时钟；导入匹配时间轴歌词后，把纯歌词舞台全屏投到显示器或投影仪，并完整演完一首歌。

观众画面不显示 Tab、mini player、封面卡、常驻进度条或调试工具。控制与演出分离：控制页负责载入、排练、播放与 seek，Stage 页只负责画面。

## 3. 已确认的方向

1. **共享语义，不共享像素布局。** Swift 与 Web 可以共享歌词事实、音频结构、导演意图和演出身份；340pt iPhone 排版、字号与位移不能机械放大到 1920×1080。
2. **Web 是旗舰舞台，不是降级端。** 首个目标是 16:9 全屏、桌面显示器与投影；手机响应式、PWA 和后台播放不是 v0 门槛。
3. **静止仍是默认。** 大屏允许更远的运动、更深的层次和更多环境效果，但正文不能持续跳动。普通段落落稳后静止，结构事件才触发大动作。
4. **本地音频优先是架构检验，不是因为在线取流困难。** Bilibili 等音频链路已有大量可参考实现；先用本地文件，是为了先证明 LyricStage 能脱离 BVID/CID 与 SwiftUI 独立存在。
5. **媒体时钟拥有同步。** 歌词 reveal 只服从歌词事实和播放时钟；音频结构与 Luna 都不能提前、延后或改写歌词。
6. **在线导演只在排练阶段运行。** 正式开演不得等待模型；生成失败、断网或缓存失效时必须有完整本地演出。
7. **先保留一个 canonical 语法。** Web v0 只以 `LyricsFacts + AudioStructureScoreV4 + Scene Recipe V4 + 完整本地 fallback` 为参考，不全量移植 V1–V5.2 历史实验。

## 4. 第一版的目标用户旅程

```text
打开 Web Stage / YouTube Music Companion
  -> 导入本地音频，或连接正在播放的 YouTube Music
  -> 导入 LRC 或规范逐字歌词
  -> 立即可播放并看到安静 fallback
  -> 后台分析音频结构
  -> 可选显式请求 Luna 编排
  -> 排练、seek、检查长句与声部
  -> 打开独立全屏 Stage
  -> 断网也能完整演完
  -> 导出不含音频的 .lyricstage 演出包
```

## 5. 明确不做

- 不先做完整 BiliMusic Web 客户端。
- 不在 v0 自建 Bilibili/YouTube 登录、收藏夹、搜索、推荐和在线曲库；YouTube Music 只以宿主 companion 提供曲目与时钟。
- 不在浏览器内做 ASR、人声分离或逐字强制对齐。
- 不把任何 Cookie、Gemini 密钥或 Worker Bearer 暴露给前端脚本。
- 不做 4K/HDR、多投影融合、MIDI/DMX、直播推流、协作编辑或插件市场。
- 不把每种 iOS 实验动效逐一移植；不以“效果数量”作为完成标准。

## 6. Phase 06 完成定义

在 Mac Chrome 与 Windows Edge 上，同一个来源无关演出包能够完成：

```text
本地音频 + 时间轴歌词
  -> 本地 fallback / 可选 Luna Recipe
  -> 1080p 第二屏全屏
  -> 连续演完 5–6 分钟
  -> 任意 seek / pause / restart 后确定性恢复
```

本地切片继续作为离线完成门；YouTube Music Companion 已提前成为第一个在线播放桥接。完整 Bilibili Provider 仍留在后续里程碑。
