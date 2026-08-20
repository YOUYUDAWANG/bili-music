# Project Cairn 日志

本文件按反向时间顺序记录实质进展——最新记录放在本行下方最顶部。每条记录保持简短，只写摘要与指针；稳定结论沉淀到 `cairn/<topic>.md`。

## 2026-08-20 · 优化歌词视觉体验：全面移除突兀歌词光点

- 彻底移除 `LyricVFXWordToken`（逐字流光光斑）与 `LyricVFXLineView`（整行推进光针）中的附加移动圆点，保持纯净高级的羽化流光扫亮（Liquid Mask Sweep）与字级物理呼吸，视觉更加优雅沉浸。
- `NowPlayingLyricStageTests` 6/6 与 `LyricEmbellishmentTests` 12/12 单测全通。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-20 · 歌词微巧思扩充至 12 种风格与露娜 AI 智能装帧

- 微巧思库扩充为 12 种风格：新增 neon / blaze / crystallize / heartbeat / vintage / sway；实现唱响瞬间微弹跳（Pop）、长音正弦浮游、冰晶折射星芒、赤金微温与双色霓虹等单字/单词级微动效。
- 新增 `LyricEmbellishmentStore.swift` 本地持久化与内存缓存；新增 `LyricEmbellishmentClient.swift` 支持调用极速装帧接口。
- Worker 端新增 `POST /v1/lyrics/embellish` 与 Prompt，秒级输出轻量情绪标签与词级/句级风格清单；歌词更多菜单提供一键「露娜智能装帧」与「恢复本地规则」。
- 双端单测全通：iOS `LyricEmbellishmentTests` 12/12，播放单测 27/27；Worker 端单测 30/30。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-20 · 歌词演出收敛：落地语义微巧思系统

- 歌词演出正式从重型全屏舞台剧转向“标准排版 + 词级语义微巧思（Lyric Embellishment）”。
- 新增 `LyricEmbellishment.swift`：定义 whisper / shimmer / impact / floating / digital / ripple 等 6 种轻量字形与微动效，实现零延迟本地确定性规则引擎与 SwiftUI 修饰器。
- `PlayerLyricsPage` 与 `PlayerControlViews` 接入微巧思，字级高亮、弹跳、流光与等宽/衬线字体点缀生效，不影响滚动排版与 60fps 性能。
- `LyricEmbellishmentTests` 10/10，相关高亮与播放单测 27/27 全部通过。

## 2026-08-20 · 写下整机接手手册

- 新增 `cairn/handoff.md`：当前默认路径、禁止事项、密钥只记名字、Worker/LDDC/高精度主机操作、歌词舞台版本对照、验证与回滚、下一步验收。
- `CLAUDE.md` 阅读顺序与 `AGENTS.md` 入口已加指针。不复制完整架构，不写入任何 Token。

## 2026-08-20 · V2 真机超时：并行生成并放宽客户端时限

- 用户提交真实 `/v2` 后显示超时。根因是 App 在 45s 无首包就断开，而 Worker 先跑 25s bible 再跑 30s 场景；8 行样本都要 45–51s，真曲必超时。
- 现已部署 `c593e5b3-eb9e-4360-9a1e-8dd1a58ad723`：bible 与最多 4 段 scene 并行，成功结果先写入 KV 再返回。24 行线上样本 19.2s 非降级，复打 354ms `hit`。现有真机包可以立刻重试。
- App `LyricStageClientV2` 改为空闲 90s / 总超时 120s，URL 超时映射为「Luna 编排超时」；需下次签名安装才生效。Worker 26/26。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-20 · V5.3 用单曲基准推进通用全曲编舞

- 保留「You＆合図」V5.2 专曲舞台作 A/B，新 V5.3 不读取 BVID、标题、固定秒数或固定歌词行号；任何同步歌词都可从 Debug「歌词舞台」进入并从头播放。
- 本地规划器按歌词间隙、重复 Hook 簇、短句、并行声部与相邻关系生成通用构图。连续重复 Hook 自动经历 call → echo → converge → lock；普通段落在 stillness / leading / trailing / dialogue / stack / arc / hero 间形成对比。真实逐字轴继续独占 reveal。
- 视觉复核修掉了前奏空白和“全曲重复次数导致第一段副歌不收束”：前奏用真实标题/作者，Hook 递进改按连续重复簇计算，后段孤立再现仍可独立收束。
- iOS 27 / iPhone 17 Pro 模拟器规则测试 19/19，10 个跨全曲关键帧 UI 1/1；物理设备签名包已安装并启动，进程 PID 2370。当前仍是歌词结构/时间驱动，不等于通用音频分析或 Luna 整曲分镜已经接入。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-20 · 生产 V2 导演端点复核：无需重发

- 用户要求启用 V2 服务端。线上 `bilimusic-metadata` 当前仍是 `153857a6-dc21-4e5b-8710-3b153f24f131`；本地 Worker 源文件时间不晚于该版本，未重新 `wrangler deploy`。
- `/health` 列出 normalize、`/v1/lyrics/direct`、`/v2/lyrics/direct`；无 Bearer 的 V2 POST 为 401。旧 normalize 日文翻唱样本非降级：`夏夜のマジック` / indigo la End / 花譜。
- 8 行逐字/二重唱/和声样本：V1 非降级 `lyric-performance-v4`（5 scene / 5 directive）；V2 非降级 `lyric-stage-v2-events`（4 section / 3 scene / 11 event）。相同 V2 请求约 8 秒后再打为 KV `hit`（375ms）。
- Worker 本地 25/25。未改 App 默认舞台，未打开 Release 自动生成。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-20 · 「You＆合図」V5.2 扩为全曲且取消逐字延后

- 从真机重新读取完整 176.518 秒 AAC 与 40 行逐字歌词；全曲图包含 178.206 BPM、524 拍、131 重拍、341 个高置信 onset 和约 21.53Hz 能量包络。
- 0–176.5 秒现覆盖前奏、开篇、调音、原黄金段、推进、指挥断句、Sunday 弧线、主题再现、终章和尾奏；入口改为「全曲音频舞台」并从 0 秒播放。
- 用户感到的微妙延迟来自歌词锚点后最多 200ms 等待音频。现有逐字轴恢复 reveal 绝对所有权，字严格从原时间出现；±90ms 最近 onset/beat 只驱动其后的回弹、冲击和场景物理。缺逐字轴的未来路径才允许吸附。
- 时间线/音频窄测 2/2，iPhone 17 Pro 尺寸 14 个跨全曲关键帧 UI 1/1；当前仍是「You＆合図」专曲离线图，不表示通用 iPhone 分析器或 Luna 音频导演完成。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-20 · 完整歌词改为连续逐字扫亮

- 根因是 `LyricHighlightModel` 已经计算 `.current(progress)`，但 `PlayerLyricsPage` 把 current 和 sung 绘制为同一全亮文本，字与字之间只会硬切。
- 当前字/词现用 30fps progress 驱动左到右 mask，带轻微羽化与 glow；已唱/未唱作为底色与前景。wrap layout 保留长句换行，可访问替代仍是完整句。
- `LyricHighlightModelTests` 7/7、逐字歌词 UI 1/1，fresh `build-for-testing` 通过。固定在首个英文词 50% 时刻的截图已检查：左半亮、右半暗，完整长句与换行正常。

## 2026-08-20 · LDDC 逐字候选点击失败已修复

- 真机截图确认蓝色「逐字」已经进入列表，但点击后保留候选并显示「没有找到可用歌词」；这证明失败发生在选择阶段，而非搜索或显示阶段。
- 根因是面板自动搜索与用户搜索可重叠：两次请求共用并清空临时逐字文档，旧结果仍可被点击并退回普通网易云取词。现用 request generation 拒绝陈旧搜索，已验证文档按稳定 ID 有界保留；缺失时再向 LDDC 精确恢复一次。
- LDDC 客户端整组加排序测试 5/5，物理设备签名 build 通过；最终包再次核对 Mac mini URL 与 64 位签名资源 Token，已覆盖安装并启动。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-20 · V5.2 文字落点改由真实音频触发

- 用户真机判断上一版仍像“文字轴动画”：虽然 beat/onset/energy 已调节尺度与背景，文字进入、落定和切镜仍主要服从歌词轴，音频参与不够可感知。
- 「You＆合図」黄金样片改为双时钟：逐字轴只给出最早允许出现的时刻，之后 200ms 内最近的真实强 onset 优先、beat 次之，决定 glyph 的实际 reveal/landing；副歌标题 Hook 的开场、重击和回声也复用同一音频触发器。seek 仍由绝对时间确定性还原。
- onset/beat/landing 窄测 1/1、iPhone 17 Pro 八关键帧 UI 1/1；当前仍是专曲离线 AudioPerformanceMap，不代表通用 iPhone 分析器或 Luna 音频导演已经完成。

## 2026-08-20 · LDDC 手动搜索修复时长门禁与 Token 注入

- 真机请求已证实到达 Mac mini 且认证为 200，但 616 秒《Melt -10th ANNIVERSARY MIX-》被服务端返回 0；同标题曲库实际有 3 条 305 秒候选（2 条逐字），根因是手动搜索误用了自动采用的 ±4 秒硬门禁。
- 手动搜索现允许时长不符候选进入列表；只有时长兼容的逐字轴获得可靠排序加成，已知不符显示「逐字／时长不符」。自动采用的严格标题、歌手、时长门禁不变。
- 增量构建又复现最终 `Info.plist` 丢失 LDDC Bearer；现与高精度主机一致写入独立签名 plist，最终包验证 URL 正确、资源 Token 存在且 64 位。聚焦测试 2/2，签名 Debug 已覆盖安装并启动；同曲列表实机复看待用户确认。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-20 · 更正：《メルト》v3 排除同窗双模型假共识

- v1 的 `-3.000s / MAD 0` 来自 23 条 onset 撞到 `source_start - 3s` 左边界；v2 又错误地把受同一局部窗口约束的 Qwen/WhisperX 当作独立证据，主歌被提前 5–7 秒，用户复听确认仍严重不同步。
- 新增整曲精确歌词对齐与 1.7B ASR 诊断：真实前段约为 2.96、12.72、57.52、59.60、68.88 秒。v3 丢弃窗口边界样本，以 8/10 内部样本得到 +0.560s / MAD 0.96s；局部双模型偏离全局锚点超过 1.25s 时只保留逐字节奏，不再改行首。
- v3 完整重跑 76.995s：41/41 行、466 字、13 行受约束模型共识、28 行全局锚点、41 行 WhisperX 字符复核；前段为 2.992、12.090、57.732、58.075、67.510 秒。pipeline v3 job 已缓存。
- 真机旧 `-10000ms / userSet=true` 并非用户手调：自动值在校准 sheet 未拖动时被 Slider 的结束回调重新标成用户值。现只有实际收到开始编辑后才允许结束回调持久化；`precisionHost` 仍强制 offset=0 且不做 RMS 自动校准。
- v3 写入后又出现“行数不一致”假拒绝：旧门禁把服务端原始行数与 App 拆分和声后的显示行数直接比较。现原始 LRC/QRC/主机计数互比、排版后源/结果计数互比；同一 `overlapGroup` 的同时行合法。主机门禁 9/9、签名构建、安装和真机启动通过。

## 2026-08-19 · 更正：LDDC 后端迁移到 Mac mini 常驻服务器

- 前一条阶段记录把并非常驻的 Windows 主机误当成部署目标；现已停用其计划任务和 8788 监听，旧目录改名保留为可恢复备份，不影响独立的 Windows GPU 高精度对齐服务。
- 常驻根为 Mac mini `~/Library/Application Support/BiliMusic/LDDCLyricsBackend`，Python 3.12 虚拟环境、权限 600 的 Token 文件和用户级 LaunchAgent 已生效；只绑定 Tailscale `100.108.23.60:8788`，未改防火墙或开放公网端口。
- Mac 远程验证 health=200、无认证=401；真实「心拍数#0822」返回酷狗+QQ 两份 `timing=word` 候选、各 50 行。64 位 Bearer 从钥匙串注入签名包，Debug 已覆盖安装并启动于 iPhone 17 Pro；仍需 App 内实际搜索验收。

## 2026-08-19 · 「You＆合図」V5.2 黄金样片装入真机

- 读取真机现有 40 行逐字轴，选取 37.781–67.441 秒约 30 秒片段；不复用 V5.1 通用 verb，也不请求 Luna。
- 手工 Canvas 编排推进/呼吸、双眨眼、约定波浪、双主体汇合，以及四次逐级变化的标题 Hook；入口会 seek 到样片起点并播放。
- 同一片段从真机缓存 AAC 提取 178.2 BPM、88 拍、22 重拍、72 强 onset 与 638 字节能量包络；拍点驱动呼吸，onset 驱动落定，能量驱动背景物理场。分析脚本见 `scripts/analyze_audio_performance.py`。
- 时间线/音频映射窄测 2/2、iPhone 17 Pro 八关键帧 UI 1/1、物理设备 Debug build 通过；音频驱动版已覆盖安装并启动，原 Documents 保留。
- 当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-19 · 歌词页滚动与高亮统一

- 自动滚动在时间戳空档会回退到最近已开始行，但亮度原先只认严格 `from..<to`，导致滚到当前句后仍以 35% 非当前亮度显示。
- `LyricHighlightModel.highlightedLineIndices` 现与滚动共用回退；真实重叠声部仍保留多行 active。聚焦单测 6/6，fresh `build-for-testing` 通过。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 高精度主机不再无限等待，第三首真实任务通过

- 真机 Documents 证明《モドキステップ！》已有本地音频与 49 行逐行词，但 Windows 队列为 0；根因是 iPhone 到 Tailscale 地址不可达时 `waitsForConnectivity` 最长等待 20 分钟。现每个地址 5 秒探测，Tailscale 失败自动走 `192.168.10.129`，全部失败明确提示，阶段状态持续显示。
- 首次真实提交又暴露第 21 行模型 onset 倒退会整曲失败；Windows 改为仅将冲突行回退到全局 LRC 锚点的确定性节奏，旧脚本有时间戳备份，远端编译与哈希已核对。
- 重跑 66.313s 完成：49/49 行全文一致、544 字、行首严格单调、29 行 WhisperX 字符复核、10 行节奏回退、MAD 0。App 门禁改为低于 50% 拒绝、50–79% 写入但标记需确认、80% 以上确认。
- 后续《雑魚》又暴露重复歌词联合对齐的 token 跨行；现自动退回逐行窗口，不再整曲失败。服务端错误只保留异常摘要，App 再截为 180 字，禁止把 4000 字 traceback 铺进界面。重跑 66.387s 完成，48/48 行全文一致、626 字、48 行 WhisperX 字符复核、4 行节奏回退。
- 主机客户端 8/8、Python 编译、签名、双地址与 64 字符令牌、真机安装/启动均通过。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · V5.1 选择后无动画已修复并装入真机

- 真机 Documents 证明当前歌曲没有 `lyric-stage-v2.json`；旧入口只切渲染器，不会触发已上线的 Luna V2，且 Section 预算会删掉本地 hold 动作。
- 首次选择 V5.1 现自动请求线上导演并立即显示编排反馈；低强度 hold pulse 被定义为基线呼吸，不占高潮/强调预算。
- 首次真机复测进一步确认：已有 10 Scene / 41 Event 稿时仍只偶发刷新。Canvas 现显式消费 Timeline tick，歌词时钟不再被 Reduce Motion 或 motion gate 冻结；播放时展开 60fps、保底 30fps。
- V5.1 compiler/timeline 21/21、物理设备 Debug build 通过；修正版再次覆盖安装并启动，V2 缓存和原 Documents 保留。
- 当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-19 · Luna V5.1 `/v2` 上线并修正假成功

- 经用户明确授权部署 Cloudflare Worker `153857a6-dc21-4e5b-8710-3b153f24f131`；健康端点现列出 normalize、V1 和 V2。
- 首次线上调用发现模型场景全被校验丢弃却标记成功；现补全精确 Actor/Event JSON 合同，空场景会如实 degraded 且不缓存。
- 修正版 8 行逐字/二重唱/和声样本非降级返回 4 Section、2 Scene、2 Actor、7 Event；旧 V1 非降级回归。Worker 25/25。本轮未安装真机包。
- 当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-19 · 停用真机 MLX 生成并修复主机按钮

- 真机当前《青い珊瑚礁》有 26 条非空逐行歌词、无并行声部，电脑按钮本应可用；灰态来自 App 后来被另一包覆盖，内置主机配置丢失。
- 两份真机 `bug_type 309` 报告均为 `SIGABRT`，故障队列 `com.Metal.CompletionQueueDispatch`，栈落在 `mlx::core::gpu::check_error`；一次 Forced Aligner、一次 ASR。这不是普通 Swift 主线程卡顿，异常不可捕获。
- 播放器移除本机生成入口，设置只保留模型占用与删除；高精度主机按钮不再因配置缺失静默置灰。UI 回归 1/1、来源门禁 3/3。
- 修正 Xcode 脚本先于 `ProcessInfoPlistFile` 执行导致令牌被覆盖的问题：钥匙串令牌现写入独立签名资源，普通无额外参数的真机构建也能读取；资源存在、64 字符令牌、签名、安装、启动和主机健康均已检查。
- 主机同时修复纯逐行 LRC 没有旧逐字轴时的空 A/B 统计，并允许失败任务复用音频重试。《青い珊瑚礁》真实任务 65.1s，26/26 行全文一致且通过 App 门禁。签名包已覆盖安装并启动。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · V5.1 修掉 echo 残留与中日文整句不换行

- 超预算时删除 `.echo` Event，采样不再把残影加回。
- 排版按 token 边界换行，连续中日文不会并成一整句超出 340pt。
- Actor 中心改为 `(sceneID, actorID)`；partial 二重唱补缺只留下未覆盖声部。
- 指针：`LyricStageBudget.trimConcurrent`、`LyricStageCompilerV2.measureLine`、`LyricStageDirectorV2.fillMissingScenes`。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-19 · LDDC 私有逐字歌词后端正式实现

- `services/lddc-lyrics-backend/` 以独立 GPL FastAPI 进程聚合酷狗/QQ/网易云逐字词；Bearer、18s 总超时、成功缓存和无正文日志边界已落地。
- App 新增 `LDDCLyricsBackendClient`；自动采用与手动搜索都先查聚合服务。双重门禁通过的逐字候选在同版本内置顶并标记「逐字」；其余继续现有曲库直连。
- 翻唱的原唱候选强制为 `canonicalOriginal`，不得因时长接近被当成同录音。Python 窄测 6/6；LDDC 解析器与身份安全回归先后 3/3、5/5；最新逐字标识/排序/去重聚焦回归 7/7，fresh DerivedData `build-for-testing` 通过。
- 本机真实请求「心拍数#0822」返回酷狗+QQ 两个逐字候选，各50 行/481 字。尚未选定常驻主机、写入生产 token 或改网络边界。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · V5.1 执行层补上 Actor 构图与编译期预算

- 缓存指纹覆盖 Score / 旧 PerformanceScore / 真实封面色；同 Scene 数重新生成会刷新。
- Actor 按自身 typeRole 布局，hero 字号独立；英文按词换行；stacked 用整块高度避免压行。
- phase/verb 非法组合在校验时丢弃；120 字限制改为编译期去掉 backdrop/echo，绘制不再切正文。
- 预算开始消费 density、heroBudget、accentBudget、motifRef。`/v2` 仍未部署。
- 指针：`LyricStageFingerprint`、`LyricStageCompilerV2`、`LyricStageBudget`。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-19 · Windows 高精度对齐成为 App 歌词来源

- App 新增显式「高精度主机生成/重新生成」入口：只上传本地缓存音频，不进入起播路径；结果以独立 `高精度主机` 来源写入 `LyricsStore`。
- Windows `D:\BiliMusicAligner` 新增认证、串行 GPU 队列、确定性任务缓存与登录自启服务；Tailscale `:8765` 实测可达，令牌只留在 Windows 文件与 Mac 钥匙串。
- App 写回前强制检查全文/行数、单调逐字轴、WhisperX 覆盖、全局位移共识与回退比例；并行声部暂不允许覆盖。失败保留原词。
- 「You＆合図」真实 API 闭环 62.7s：40/40 行全文一致、364 字、40 行字符复核，+6.320s / MAD 0.040s；重复任务 13ms 返回缓存。窄测 3/3，签名包已覆盖安装并启动于 iPhone 17 Pro。当前真相见 `cairn/lyrics-architecture.md` 与 `scripts/windows_lyrics_aligner/`。

## 2026-08-19 · 网上歌词因歌手对不上而不跟播

- 文本候选一律 `followsPlayback=false` 过严：B 站 UP 名对不上曲库艺人时，有 LRC 也被标成「不跟随播放」。
- 现改为歌名已过门且时长差 ≤25s 时跟播；只在时长明显不对时停跟随。读缓存会按新策略写回。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · Windows 高精度歌词对齐离线 A/B

- RTX 5070 Ti Windows 主机的独立 `D:\BiliMusicAligner` 已部署：BS-RoFormer 分人声，Qwen3-ASR-1.7B/BF16 Forced Aligner 做整曲诊断与两遍局部对齐，WhisperX 日语 CTC 独立复核并提供逐字符节奏。
- 「You＆合図」从统一 PowerShell 入口完整跑通：稳定位移 +6.320s（8/20 共识、MAD 0.040s）；26/40 行采用双模型共识，14 行冲突回到全局锚点，8 行 Qwen 节奏回退均显式标记。
- 最终 QRC 40 行、全文一致、单调且不重叠；364 字最短 50ms、中位 180ms、无 ≤40ms。远端与本地 SHA-256 一致。仅作为离线对比，未覆盖 iPhone 缓存。当前真相见 `cairn/lyrics-architecture.md` 与 `scripts/windows_lyrics_aligner/`。

## 2026-08-19 · 歌词舞台升级为 V5.1 Event 引擎

- 中央舞台新增 StyleSheet / Section / Scene / Actor / Event 合同与 Canvas `sample(at:)` 渲染；默认仍是本地规则，V5 行级舞台保留。
- 无逐字轴不再伪卡拉 OK；旧 v4/v5 缓存可适配。Worker 本地 `/v2/lyrics/direct` 未部署。
- 指针：`LyricStageCompilerV2`、`LyricStageCanvasView`、`services/metadata-worker/src/director-v2.js`。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-19 · 点封面不再被首页发现堵住起播

- playurl / 补 cid 改走独立 URLSession；发现搜索最多 2 路，点歌立即取消。
- 首页发现推迟到封面墙出现 2 秒后。避免只出封面、干等近一分钟。
- 指针：`BiliClient.playbackSession`、`HomeView.cancelDiscovery`。当前真相见 `cairn/playback-startup.md`。

## 2026-08-19 · 更正：逐字生成先做整曲位移共识

- 上一轮只固定可靠 LRC 行首，修掉局部 250–950ms 漂移，却把来源 LRC 自身当成绝对真相；用户用「You＆合図」实听确认仍有约 7–8 秒整曲错位，单曲 `+7.5s` 尝试已清除。
- 通用链路现先用整曲 ASR 建立多行位移样本，以 60% 稠密簇、覆盖率和离散度门禁估计全局平移；重复副歌伪匹配、非线性漂移和低置信结果不会写入。校准后再用 ±2.5 秒窗口生成逐字节奏。
- 真机样本得到 -6.241 秒共识并写入实际 QRC，未保存用户 offset；25/25 窄测、设备构建安装与普通启动通过。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · Luna v5 两阶段导演上线并安装真机包

- Cloudflare Worker `ac89c921-a471-4f65-bde8-1fd8141ba2a1` 已部署，生产 `/v1/lyrics/direct` 直接生成全曲 Stage Bible 与受限 stageDirectives；兼容 v4 envelope 与本地回退保持不变。
- 线上 8 行逐字/二重唱样本非降级返回 Stage Bible、5 条 directive、3 种 behavior；健康、401 鉴权与旧 normalize 回归正常。本地 Worker 20/20。
- 签名 Debug 包已覆盖安装并启动于 iPhone 17 Pro，V5 URL 与 Bearer 注入存在；真实歌曲体感与 Release 60fps 仍待确认。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-19 · 可靠 LRC 行首不再被逐字模型漂移

- 真机「You＆合図」确认来源逐行 LRC 与同版本音频时长一致，但 Forced Aligner 曾把 6/40 行推迟超过 250ms、最大 950ms；问题是行首 ownership，而非歌词版本或 4bit 模型规模。
- 可靠逐行轴现在固定拥有行首，模型只编排行内逐字节奏；纯文本/ASR 重建的粗轴仍允许模型细化 onset。低置信 +1.05s 音频相关候选未写入偏移。
- 同曲真机重生成后 40/40 行首偏差为 0ms，推理 5.172s、峰值 1.421GB；窄测 22/22，设备构建、安装和普通启动通过。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · v5 真实歌词动态文字舞台第一版

- 新增 StageScore/Compiler/View：真实逐字时间展开为 glyph 轨道，逐行轴只做视觉 stagger；主唱、和声、A/B 二重唱按 overlap group 同台，完整文本自动换行。
- 现有线上 Luna v4 score 可立即映射为八种 stage behavior；兼容 envelope 新增可选 Stage Bible + stageDirectives，App 校验并缓存。Worker 两阶段实现仅在本地，未部署。
- iOS 窄测 23/23、v5 真实歌词 UI 1/1、Worker 20/20、generic iOS Debug build 通过；模拟器实图已检查。真机安装、Release 60fps 与 TextRenderer 后端仍待后续。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-19 · 日语逐字对齐改为模型边界＋节拍稳定

- 真机「千鳥」确认旧轴 46.2% 字被压成 40ms、最长 19.29s；日语系统分词只能把异常行从 40 降到 32，8bit A/B 更差，确认问题不是单纯模型量化。
- 日语改为词法分段后映射回完整字符；超长 LRC 空档收紧。模型行发生短时间坍缩或节拍差十倍时，以可信行首和汉字/假名节拍重建该行，并标记待确认；仍异常才拒绝保存。
- 「千鳥」最终降为 0.5% ≤40ms、0 个 >1.5s、最长 1.021s；当前「すきなことだけでいいです」为 2.0% ≤40ms、最长 1.113s。两首真机保存，峰值约 1.434–1.436GB；21/21，设备构建、安装与普通启动通过。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 本地 v5 动态文字舞台样片

- Debug 播放器增加 18 秒四幕硬编码 motion study：逐字画外聚合、重力坠落、左右双声部交汇、字符环绕后重组；只替换 metadata 与控制簇之间的歌词画布。
- 样片不调用 Luna、不改 v4 合同或缓存；用于先判断 AE 式 kinetic typography 的视觉方向，正式引擎仍待 StageScore + TextRenderer。
- iPhone 17 Pro 模拟器关键帧实图与完整录屏已检查；定时/easing 10/10、局部替换 UI 1/1、generic iOS Debug build 通过。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-19 · 歌词支持同时演唱与二重唱声部

- 歌词增加 lead/backing/duetA/duetB/together 与 overlap group；解析显式角色、行尾括号和声和相同时间戳多行，舞台说明与普通尾部重叠不误判。
- ASR 粗定位为同组声部共享搜索窗口，Forced Aligner 对各声部独立生成并允许重叠；结构化 vocal lines 随歌词缓存持久化。
- 完整歌词与中央演出可同时显示 active 声部，真实重叠优先于 Luna composition。窄单测 16/16、generic iOS Debug build 通过；真实二重唱真机精度与视觉仍待验证。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · Luna 长歌词改为保留全曲轮廓的并行分段编排

- 真机当前「千鳥」42 行 / 407 word 的原请求复现旧 Worker 25 秒超时；App 过去只显示通用 degraded，掩盖了 `upstream_error`。
- Worker 将详细逐字输入压成时间元组，保留全曲文本 outline，约 12 行并行分段生成并全局合并校验；失败段由本地导演补齐，全部超时明确返回 `upstream_timeout`。
- 部署 `0e12423f-b54f-45fd-a1ab-cbcec5ae0014` 后，同一真实请求 23 秒非降级，生成 42 composition / 29 scene / 13 word cue；Worker 18/18，Debug 包完成设备构建、覆盖安装和启动。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-19 · 找歌改为翻页 + 歌名，不再用 feed 掺水

- 检索同时用常听歌手和清洗后的歌名，页码在 1–3 间错开，刷新不会总拿到同一页热门。
- 品味候选够 8 首时不再拉首页流/related；UP 名不再进歌手档案。
- 指针：`ListeningTaste.searchPlan`。当前真相见 `cairn/home-discovery.md`。

## 2026-08-19 · Luna v4 接入真实逐字歌词演出

- 中央歌词加入局部 30fps 逐字舞台：所有真实 word timing 默认 Sweep，Luna 可为每行一个不超过 12 字的范围追加 Impact / Stretch / Echo Trail；日文标点、英文空格和长句换行均保留，映射失败显示完整原句。
- App/Worker 双端升级 `lyric-performance-v4`，把真实 word index/from/to/text 交给 Luna；歌词指纹纳入逐字时间，旧 v3 缓存不会误用。Worker 16/16、iOS 20/20、逐字长句 UI 1/1。
- 经既有部署授权上线 Worker `136feabc-d475-4f05-8050-63324d70e0dd`。线上 6 行样本非降级，返回 3 个 scene 和 line 1 / word 0–3 的 Echo Trail，第二次 KV 命中。
- Debug 真机包已覆盖安装并启动；真实收藏歌曲的 Luna v4 点击生成、缓存 A/B 和 Release 长时间帧率仍待用户体感确认。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-19 · 本机逐字对齐改为精度优先

- 修复模型调用硬编码 `English`：优先识别实际歌词强脚本，纯汉字等歧义才使用首次元数据清洗已缓存的歌曲语言。
- 多行短段改为逐行独立窄窗口；生成后修复字级回摆/越界，并让当前字连续保持到下一字开始。按用户要求不改变既有全局 offset 机制。
- 纯文本或显式忽略旧轴时，新增本机 Qwen3-ASR 20 秒分块粗定位；LCS 覆盖门禁通过后释放 ASR，再逐行 Forced Aligner 精修。两模型不同时驻留，低置信结果不保存。
- `OnDeviceLyricsAlignerTests` 9/9，generic iOS Debug build 通过；真实纯文本歌曲的精度、耗时和峰值内存仍需新 Debug 包真机复测。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 同版本优先有时间轴的歌词

- 自动匹配仍先对身份，同一档里才选逐字 / 逐行 LRC，不会拿错版本的轴去抢对上的纯文本。
- 文本候选不再抹掉 LRC，只是默认不跟随播放。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 修复本机逐字对齐整曲 Jetsam

- 初版短样本底层推理通过，但真实播放器点击把整首音频一次送入模型；手机日志确认 BiliMusic 以 `per-process-limit` 被 Jetsam，常驻页约 3.46 GB。该短样本验收不代表真实功能通过。
- 改为利用现有逐行时间轴切成不超过 12 秒/48 单元的短段，逐段推理、逐段清理 MLX cache，全部分段数量与时间轴校验后才写回；只接受真正的逐行歌词。
- iPhone 17 Pro / iOS 27 用 189.177 秒、45 行、585 字长音频复测：23 段、585/585 一致，累计推理 6.234 秒、峰值内存 1.430 GB，无新 Jetsam。真实「サマータイムレコード」281 秒、64 行、573 字也通过同一核心路径并写回 `word`，推理 5.807 秒、峰值 1.552 GB。
- 歌曲会出现零长度 timestamp span；现在先允许再补成至少 40ms，保留负时间、越界与大幅倒退门禁。分词/QRC/分段/交界重叠/零长度单测 6/6。
- 修复版已覆盖安装并正常启动；当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 首页找歌改走常听歌手

- `ListeningTaste` 从我喜欢、音乐收藏夹和历史里抽出清洗后的歌手，按权重抽 4 个去音乐区搜索。
- 推荐流降为补量；related 只用这些常听种子。UP 名和「高音质/合集」不会进检索词。
- 指针：`ListeningTaste`、`RecommendationEngine.tasteArtistSearchCandidates`。当前真相见 `cairn/home-discovery.md`。

## 2026-08-19 · 手动歌词搜索改为五源聚合

- 一次查询网易云、QQ、酷狗、LRCLIB、VocaDB；列表去重后按标题/歌手/时长排序，每条标明来源。
- 当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · You＆合図 这类无假名日文歌会漏掉 LRCLIB

- 「日语」不再只认假名；拉丁字母+汉字也会走国际源。LRCLIB 只用歌名搜，避免把翻唱者当成原唱歌手导致 0 条。
- 手动搜索在日语语境默认 LRCLIB。VocaDB 没有这首；LRCLIB 有音乃瀬奏的 *You & 合図*。
- 当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 歌词先选对的源，不再一匹配就平移

- 日语/虚拟歌手同时查 LRCLIB 与 VocaDB；网易云/QQ/酷狗结果合并后再按标题+歌手+时长挑，不再谁先返回谁采用。不用 LRCLIB 评分。
- 首次写入偏移为 0；后台只在本地音频互相关明显好过 0 轴时才改。已对上的官方词不会被结构打分拧歪。
- 手动搜索可选 LRCLIB / VocaDB。`LyricsIdentityTests` 26/26。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · Luna v3 扩展为九种歌词演出

- 在 Rise / Impact / Drift / Breathe / Echo 之外新增 Focus（模糊收焦）、Drop（上方落定）、Stretch（横向展开）与 Cascade（多行逐级入场）；动画约 0.62–0.82 秒落稳，Reduce Motion 继续降级。
- Worker 与 App 双重要求 Cascade 只能用于两行或三行 composition；不改变真实逐行时间轴、不恢复逐字伪同步或文本省略。
- Worker 15/15、iOS 14/14、长歌词 UI 1/1。部署 `a2beda16-00ab-4109-a861-2e27bedb7b1e` 后，线上 16 行样本的 9 个 scene 使用 8 种效果，四种新增效果全部命中；KV、旧 normalize 与 401 鉴权正常。
- 未安装新真机包；真实收藏歌曲的 App 内演出体感与 Release 帧率仍待验证。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-19 · Luna v2 接管歌词文本构图并禁止省略

- `lyric-performance-v2` 为每个时间点提供 composition，明确选择 1–3 个相邻真实歌词索引；不再把导演限制为固定当前句＋下一句，动效 scenes 仍保持稀疏。
- 中央歌词和 Echo 残影删除单行截断；长句完整换行。iPhone 17 Pro / iOS 27 长歌词 UI 1/1，实图确认四行全文可见且未压住控制区；iOS 合同 5/5、Worker 14/14。
- 经既有明确授权部署 Worker `2560706e-5d8a-476d-861f-0349b80aa127`。线上 12/12 composition 合法（5 次单行、7 次双行）、6 个 scene、非降级且第二次 KV 命中；旧 normalize 与 401 鉴权回归正常。
- 仍未安装新的真机包；真实收藏歌曲的 App 内 A/B、重启缓存和 Release 帧率待验证。当前真相见 `cairn/lyric-performance-director.md`。

## 2026-08-19 · 自动对齐不再被歌词跨度门槛挡住

- 音频互相关先于「歌词必须覆盖曲库 40%」；本地缓存开头的 onset 就能对轴。
- 落点打分忽略 2 秒以内的时长噪声；整数秒差不再直接当成偏移。
- `LyricsIdentityTests` 23/23。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · Luna 歌词导演 Worker 已部署并完成线上验收

- 经用户明确授权部署 `bilimusic-metadata`，当前版本 `6e7fbc6d-472c-450e-8757-a5d3f19ce652`；`/health` 已公布 normalize 与 director 两个端点。
- 12 行有界验收曲首次请求非降级，Luna 通过 `chat-json-object` 返回 7 个合法 scene（58.3%）；同请求第二次 KV 命中。旧 normalize 端点非降级，director 未授权请求仍为 401。
- Worker 本地 14/14；未安装真机 Debug/Release 包，真实收藏歌曲的 App 内 A/B、重启缓存和 iPhone 17 Pro 帧率仍待验证。
- 当前真相与边界见 `cairn/lyric-performance-director.md`。

## 2026-08-19 · Luna 开发期歌词导演已接入本地，Worker 待部署

- 新增 `lyric-performance-v1`、双层校验、歌词哈希缓存和 `LyricPerformanceClient`；有效脚本覆盖本地 cue，缺行/失败/非法结果回退 `LyricMotionDirector`。
- Debug 播放器菜单提供显式“用 Luna 编排演出 / 重新生成 / 恢复本地歌词导演”，不在播放、换歌、自动歌词或 Release 路径调用。
- Worker 源码新增 `POST /v1/lyrics/direct` 与独立 prompt，Luna 只能编排五种已验证效果，不能改词或生成代码。复用现有 Bearer/上游 Secret，未写入任何密钥。
- Worker 14/14；iOS `LyricMotionDirectorTests + LyricPerformanceScoreTests` 11/11；iPhone 17 Pro / iOS 27 的开发入口 1/1，既有歌词入口与密集布局 2/2。
- **未部署 Worker，未做真实 Luna 请求，也未安装新的 Release 真机包。** 当前真相与部署边界见 `cairn/lyric-performance-director.md`。

## 2026-08-19 · 首页新旧混排并打破 related 重复

- 封面墙先出收藏夹，再把首页推荐流新歌按 3:2 混进去；缓存/历史只作空库兜底。
- 推荐流用递增 `fresh_idx`；related 只在新歌不够时补。已展示 BV 记 6 小时。
- 电台不再死拿 related 第一条；多源重复的热门节点降权。
- 指针：`HomeCoverMixer`、`RecommendationMemory`、`BiliClient.homeFeed`。当前真相见 `cairn/home-discovery.md`。

## 2026-08-19 · 歌词自动对齐改成落点 + 音频互相关

- 不再把曲库和视频的整数秒差直接当成偏移。先看第一句/最后一句落在视频的哪里，分辨片头垫还是片尾多。
- 自动缓存落盘后读取本地 m4a 能量，和歌词 onset 互相关；不额外拉流，也不覆盖用户滑过的偏移。
- 指针：`LyricsOffsetEstimator`。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 中央歌词升级为自适应逐行动效画布

- 新增纯逻辑 `LyricMotionDirector`，按句长、标点、时值、重复结构和稳定歌曲/行标识，确定性选择 Rise / Impact / Drift / Breathe / Echo；同一句跨启动不随机变化。
- 当前句使用 24–32pt 与不同字重/对齐/字距；换句负责入退场，句中只启动一次漂移、呼吸或残影动画。逐行时间轴是完整主路径，不伪造字符时间。
- 动画仅在 full player 展开、播放中且 App active 时运行；中途打开只跑当前句剩余时间，Reduce Motion 降级为淡入淡出。
- 唯一视觉与性能目标为用户自用的 iPhone 17 Pro / iOS 27，不再以 SE 兼容限制设计。`LyricMotionDirectorTests` 7/7；iPhone 17 Pro / iOS 27 歌词入口与密集布局 2/2。逐字中央画布增强与 Release 真机帧率留待后续。
- 当前真相见 `LyricMotionDirector.swift`、`PlayerInlineLyricsPreview` 与 `cairn/visual-language.md`。

## 2026-08-19 · 歌词延迟可自动整段对齐

- 首次匹配且还没有手动偏移时，若曲库时长与视频相差 2–10 秒，按差值把歌词整体提前或延后。
- 只修片头多/少几秒；变速翻唱仍对不上。校准页增加「自动对齐」，已有偏移不覆盖。
- 指针：`LyricsOffsetEstimator`。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 歌词搜索改用日文原名

- 日文歌不再拿中文译名去搜网易云 / QQ / 酷狗。查询只用清洗后的假名原名，加上原唱或翻唱者。
- 译名仍留在 `aliases`，只用来判断候选是不是同一首歌。旧 Worker 缓存里带译名的 `lyricSearchQueries` 会被客户端丢掉。
- Worker `buildSearchQueries` 同步去掉译名查询。`LyricsIdentityTests` 20/20，Worker 12/12。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 歌词校准改为滑块

- `⋯` 里的 ±0.5 秒按钮换成系统 sheet：±10 秒滑块、拖动即时对轴、接近 0 吸附、松手后写入 `lyrics-library.json`。
- 指针：`LyricsOffsetSheet`、`PlayerEngine.setLyricOffset`。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 播放器中部改为两行同步歌词

- 删除封面页与队列页的系统音量条；音量继续交给实体键，AirPlay 系统路由入口保留。
- metadata 与控制簇之间的唯一弹性区显示当前句和下一句；换句时轻量向上滚动，最后一句退化为单行，点击进入同层完整歌词。无同步歌词或 MV 模式保持留白，不生成假歌词。
- 模拟器实图确认初稿 17/14pt 在整屏比例中过小；收口为当前句 24pt bold、下一句 18pt semibold，并取消长句自动缩小。
- UI target build-for-testing 通过；iPhone 17 / iOS 27 的歌词预览入口与密集布局 2/2、iPhone SE (3rd generation) / iOS 26.3.1 的密集布局 1/1 通过。当前真相见 `PlayerInlineLyricsPreview` 与 `cairn/visual-language.md`。

## 2026-08-19 · 竖屏播放器改为单一弹性空间

- 不改封面、控件造型、系统音量或底部功能栏，只重分配 portrait layout 的纵向空间所有权。
- 封面与 metadata 使用 12/16pt 固定间距；progress / transport / volume 组成 compact/regular 固定节奏控制簇；主要剩余高度仅由 metadata 与控制簇之间的一处 `Spacer` 吸收，volume 到 utility 使用 12/18pt 有界间距。
- `PlayerChromeUITests` 改为直接测封面、音量和各段 frame；iPhone SE (3rd generation) / iOS 26.3.1 与 iPhone 17 / iOS 27 的密集布局回归各 1/1 通过。当前真相见 `NowPlayingView.swift` 与 `cairn/visual-language.md`。

## 2026-08-19 · 自动歌词改优先原唱

- 自动匹配默认采用原唱歌词。翻唱词只有歌名、翻唱者、时长差 ≤3s 同时成立才抢先采用。
- 菜单「搜索翻唱者版本」仍按翻唱检索，不受该门槛限制。`LyricsIdentityTests` 18/18。
- 当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 删除 B 站字幕歌词来源

- 去掉 `BiliSubtitleLyricsProvider` 和 `BiliClient` 字幕接口；歌词只走网易云 / QQ / 酷狗、AMLL、VocaDB 与本地导入。
- 加载歌词库时丢弃已缓存的 B 站字幕，避免口白挡住正确匹配。`LyricsIdentityTests` 16/16。
- 当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · mini player 与 Tab Bar 回归 iOS 27 Apple Music 原生节奏

- 用户明确要求首页 mini player 和底部 Tab 使用 iOS 27 Apple Music 的原生滚动逻辑，而不是永久展开。
- 有当前歌曲时恢复 `.tabBarMinimizeBehavior(.onScrollDown)`；LNPopup `.floatingCompact` 继续继承 bottom-bar metrics，随系统 Tab 一起进入 inline。无歌曲时仍为 `.never`，防止空 accessory 槽位。
- 将旧的“始终可见”UI 回归改为验证滚动后 Tab 或 mini 的原生紧凑几何变化，并要求 compact 状态下 mini 仍存在。
- 当前工程与 UI 测试 target 的 build-for-testing 通过；在干净的 iPhone 17 / iOS 27 模拟器上，原生 Tab/mini 滚动紧凑态 UI 回归 1/1 通过。当前真相见 `RootView.swift` 与 `cairn/player-gesture-performance.md`。

## 2026-08-19 · 歌词封面缩放改成单视图 frame 动画

- 去掉封面 `matchedGeometry`：缩放时不再同时合成两棵播放页、大图解码和 16pt 阴影。
- 同一张已解码封面只改 frame；阴影在动画期间关掉。
- 指针：`NowPlayingView.portraitCover`。

## 2026-08-19 · 歌词改回同一层正在播放，而不是新页

- 纠正前一条：原版歌词没有进度/播放键/音量，也不是先显示再自动隐藏。
- 底部 `歌词 | AirPlay | 队列` 留在 `NowPlayingView`，不随内容翻页；封面在同一视图里收到顶栏，不用 matchedGeometry。
- 指针：`NowPlayingView.swift`、`PlayerLyricsPage.swift`。

## 2026-08-19 · 歌词页播放控件按 Apple Music 自动隐藏

- 进入歌词后进度、播放键和音量先出现，约 5 秒无操作后淡出，歌词铺满到 utility bar。
- 点歌词、滑动或拖动进度会再显示；底部 `歌词 | AirPlay | 队列` 与顶栏始终保留。
- UI 测试覆盖显隐往返。指针：`PlayerLyricsPage.swift`。

## 2026-08-19 · 手动选词不再冻成待确认

- 点选候选、按翻唱/原唱搜索会保留 LRC/逐字时间轴；「适用于当前翻唱」会从歌词正文恢复时间轴。
- 自动匹配仍对原唱套翻唱保守处理。`LyricsIdentityTests` 16/16。
- 当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 歌词开关对齐 Apple Music

- 歌词页补回底部 `歌词 | AirPlay | 队列`；同一按钮再点关回封面，也可从歌词页直接切队列。
- 图标固定 `quote.bubble`，选中只用白底圆，不再用 fill 表示「已有歌词」。
- UI 测试覆盖开关往返。指针：`PlayerLyricsPage.swift`、`NowPlayingView.appleMusicUtilityBar`。

## 2026-08-19 · 自动歌词必须标题对上才采用

- 自动匹配不再「有词就用」：候选歌名必须对上干净标题或别名，同翻唱者的另一首歌会被跳过。
- B 站字幕退出自动链路，避免口白/错歌被缓存成歌词；手动搜索三平台不受影响。
- 已缓存的错词需在歌词页「重新搜索」。`LyricsIdentityTests` 14/14。
- 当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 去掉 B 站字幕翻译轨

- `BiliSubtitleLyricsProvider` 不再拉取或对齐中文字幕；B 站来源只保留日文或主轨歌词。
- 网易云 / QQ / AMLL 翻译不受影响。已缓存的旧字幕需「重新搜索」才会去掉串台翻译。
- 当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 执行 Phase 05 原生风格与歌词页

- 05-01…05-05 已落地：删底部抽屉死代码；拆出 `PlayerQueuePage` / `PlayerContextStore` / `PlayerSurface` token；歌词改为播放器内三页之一；逐字辉光与跟随；首页渐变、队列中文、封面淡入、长按预览、收藏错误胶囊。
- 编译通过；`BiliMusicTests` 203/203。歌词页/队列页/密集布局 UI 断言通过。搜索框与 mini 浅拖仍偶发失败，与本期无关。
- 真机待确认：歌词/队列往返、LNPopup 转场、浅色首页顶部无黑带。
- 指针：`PlayerLyricsPage.swift`、`LyricHighlightModel.swift`、`.planning/phases/05-native-feel-and-lyrics/05-00-DESIGN.md`。

## 2026-08-19 · 歌词匹配与时间轴误用修复

- 官方歌在没有清洗结果时不再因为「歌手对不上」被全部跳过；标题重合即可采用。
- B 站字幕必须像歌词才自动采用，避免短 CC 永久挡住三平台结果。
- 原唱无时长或时长差大时不再假装可同步；AMLL 翻译/罗马音不再并进主歌词。
- 重新匹配保留用户偏移；纯文本歌词不再滚动到最后一行。
- `BiliMusicTests` 198/198。当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 原生感收敛与歌词重构设计稿

- 全量 UI review 结论：不推倒重构，做结构性收敛；差距集中在歌词容器、播放器死代码与抛光细节。
- 核查更正：底部三段抽屉（`bottomContextDrawer` 子树约 700–900 行）是无调用点的死代码，活跃队列只有整页队列一套，与 STATE.md「dormant drawer」记录一致。
- 用户要求全 App 对齐「iOS 27 原生风格」（Liquid Glass 2.0）且方案需移交给其他模型执行；设计稿已扩为实施规格：基准定义、全局 token 表（间距/字级/颜色/圆角/图标/触感唯一合法值）、逐页面规格、死代码删除清单、文件拆分映射、05-01…05-05 切片与逐片验证命令。iOS 27 关键含义：系统外壳已自动达标；材质只许系统 API；封面色塑形整页与横屏 Now Playing 与 iOS 27 Apple Music 同向。
- 审美决策已全部拍死（歌词页 16:9 小封面、合集留更多菜单、不做拖拽排序并删假图标、mini bar 保持 16:9、歌词控制收进 ⋯ 菜单、首页顶部渐变改动态背景色）；执行者守则禁止自由发挥。
- 指针：`.planning/phases/05-native-feel-and-lyrics/05-00-DESIGN.md`。

## 2026-08-19 · 分层身份 + 翻唱优先歌词

- Worker 升到 `music-metadata-v7-layered-identity` 并已部署，未回滚 v6；输出原唱/翻唱/isCover/检索词，低置信度不填原唱。
- App 显示翻唱为「翻唱者（翻唱） · 原唱：…」；清洗写入 `track-metadata.json`，降级结果不落盘。
- `LyricsResolver` 改为翻唱版优先、原唱回退，带版本范围与时间轴安全；本地命中和第二遍播放不发歌词请求，未命中缓存 7 天。
- 接入 B 站字幕、AMLL TTML、VocaDB；歌词页可重新识别、分版本搜索、导入和手动修正。
- 窄测：Worker 12/12，`BiliMusicTests` 189/189。真机尚未重装。
- 当前真相见 `cairn/lyrics-architecture.md`。

## 2026-08-19 · 已登录收藏写入音乐收藏夹

- 播放器点收藏改为 `FavoriteFolderSelector`：设置里的音乐收藏夹优先，其次标题含音乐/歌曲/music 的夹，没有才退回 B 站「默认收藏夹」。
- 首页封面源用同一套选择，避免 lastFolderId 把音乐夹挤掉。
- 本环境仍无法写 `~/Library/Caches/org.swift.swiftpm`，`xcodebuild test` 未跑成。
- 指针：`FavoriteFolderSelector.swift`、`FavoriteManager.targetFolderId()`。

## 2026-08-19 · 补齐会话、本地库和音乐身份

- 对照 AprDeci 落地三刀：`MusicMetadata` 从播放器拆出，`BiliSession` 承接 Cookie，收藏增加本地「我喜欢」和远程夹离线缓存。
- 歌词自动匹配/手动候选改由 `MusicMetadataController` 编排，`PlayerEngine` 仍只在出声后调用。
- 401/-101 进入共享过期态；设置页和收藏页提示重新扫码，本地库可继续播。
- 新增单测：`BiliSessionTests`、`LibraryStoreTests`、`MusicMetadataTests`。本环境 SwiftPM 沙箱无法跑 `xcodebuild`。
- 当前真相见 `cairn/session-library-metadata.md`。

## 2026-08-19 · 队列恢复、cid、缓存限额与搜索首屏

- 冷启动从 `playback-queue.json` 恢复队列、下标、模式和进度，暂停待命并显示 mini player；电台恢复为顺序播放。
- 收藏夹解码 `ugc.first_cid`，首页快照按 bvid 去重并优先保留 cid；播放补全后写回封面库。
- `CacheStore` 上限 120 首，按访问 LRU 淘汰，不删正在播放或下载的文件。
- 首次搜索在第一页返回后立刻展示，页 2 失败仍保留页 1+3。
- 窄测通过：`PlaybackPersistenceTests`、`CacheStoreTests`、`SearchStoreTests` 与全套 `BiliMusicTests`。
- 当前真相见 `cairn/playback-startup.md`、`PlaybackQueueStore.swift`、`CacheStore.swift`、`SearchStore.swift`。

## 2026-08-19 · 元数据 Worker 改用私有 GPT-5.6 Luna

- 将 `bilimusic-metadata` 从 Workers AI 切到用户的 OpenAI 兼容上游 `gpt-5.6-luna`；上游密钥仅保存为 Cloudflare Secret，仓库和笔记不保存明文。
- 实测网关不接受严格 JSON Schema，但支持 `v1/chat/completions + json_object`；固定成功协议，保留普通 JSON/Responses 降级兼容与服务端日文原名保护。
- Workers AI 绑定已移除；降级结果不写 KV，避免上游短暂错误污染 30 天缓存。
- 本地测试 7/7；线上中日文三组样本均 `degraded=false`，新请求约 3.57–3.87 秒，KV 命中约 0.057 秒。
- iOS App 仍未切换自建 endpoint；当前真相见 `cairn/lyrics-architecture.md` 与 `services/metadata-worker/README.md`。

## 2026-08-19 · 自建歌词元数据清洗 Worker 上线

- 在 Cloudflare 部署 `bilimusic-metadata`：Workers AI 结构化清洗，KV 缓存 30 天，Bearer Secret 阻止公开滥用。
- 服务端硬性保护日文原名，双语标题把译名降为 alias；同时区分原作者、翻唱者和 B 站 UP 主，返回有序搜索词与置信度。
- 本地规则测试 4/4；线上 `夏夜のマジック / 花譜`、`アイドル / YOASOBI`、`晴天 / 周杰伦` 均正确，未授权 401，缓存命中正常。
- 本轮只完成服务部署，iOS App 仍调用旧 BM `/ai`；切换 endpoint 与安全注入 Bearer 密钥是下一步。
- 当前真相见 `cairn/lyrics-architecture.md` 与 `services/metadata-worker/README.md`。

## 2026-08-19 · 对照 AprDeci 后收紧起播路径

- 换曲复用同一个 AVPlayer，只替换 item；CDN 拉流/下载改用带 Origin 与 Cookie 的 `playbackHeaders`。
- 音频改走 WBI `/x/player/wbi/playurl`；点歌时只恢复内存封面，网络封面改到出声后。
- 自动缓存默认开启，出声约 1.5s 后后台落盘；慢启动 CDN 探测与 1.2s 等待并行。
- 窄测通过：`PlaybackCriticalPathTests` 与 `PreparedStreamRetryTests` 全绿，含自动缓存出声后调度与 `playbackHeaders` 断言。
- 当前真相见 `cairn/playback-startup.md`、`PlayerEngine.swift`、`BiliClient.swift`。

## 2026-08-19 · 歌词改用 BM + 多平台直连

- 移除 LRCLIB 与旧评分链路；BM `/ai` 只负责把 B 站标题整理为搜索词，app 直连网易云、酷狗、QQ 音乐搜索与取词。
- 支持自动一致性排序、手动来源/候选、普通 LRC、多时间标签、翻译、逐字歌词、点击跳转与 ±0.5s 偏移。
- 新增 `LyricsStore` 持久化最终候选和用户偏移；歌词错误或外部服务不可用不阻断播放。
- 窄测通过：歌词纯逻辑/持久化单测与独立歌词页 UI 回归；BM→网易云真实冒烟命中《夏夜のマジック》并落盘。
- Release 包签名校验通过，已覆盖安装并成功启动于用户的 iPhone 17 Pro；设备侧进程确认存活。
- 当前真相见 `cairn/lyrics-architecture.md`、`MetingLyricsClient.swift`、`LyricsStore.swift` 与 `PlayerSheetViews.swift`。

## 2026-08-19 · 首页播放器完整回归 LNPopup

- 用户真机反馈 Home 自制 matched-geometry 播放器层性能差且 bug 多，明确选择稳定性优先并放弃封面原位转场。
- 删除 Home 的第二个 `NowPlayingView`、namespace、转场状态、关闭按钮与 520ms 延时 Task；封面点击只提交真实选曲，再由 RootView 直接打开现有 LNPopup。
- mini bar、full player、跟手下滑和 dock 收回重新统一到 `.floatingCompact + .automatic` 的同一生命周期；纯海报瀑布流视觉与 Tab Bar 常驻策略不变。
- iPhone 17 Pro / iOS 27 模拟器验证：封面直开 LNPopup、标准 mini/full 开合、mini 下滚动时 Tab 常驻共 3/3 UI 回归通过。测试构建同时纳入工作区现有歌词文件，但本轮未修改其内容。
- 当前真相见 `cairn/player-gesture-performance.md`、`cairn/visual-language.md`、根 `CLAUDE.md`、`HomeView.swift` 与 `RootView.swift`。

## 2026-08-14 · 封面收回动画与瀑布流手势并行并固定系统底栏

- 首页改用局部 matched geometry 动画层完成封面原位放大与反向缩回；关闭第一帧先让动画层停止命中测试，底下始终挂载的 ScrollView 因而可以在播放器缩回期间继续上下滚动。
- 转场只局限于 Home，不常驻其他 Tab、不自绘底栏、不复制播放状态；动画完成后再恢复标准 mini player。
- 原生 TabView 固定使用 `.tabBarMinimizeBehavior(.never)`，有当前歌曲和 mini player 时滚动瀑布流也不再自动收起底栏。
- iPhone 17 Pro / iOS 27 模拟器验证：generic build、封面原位进入/反向收回与首页恢复、mini 下的 Tab 滚动可见性、LNPopup mini 拖开/全屏下拉收回均通过；额外录屏逐帧确认反向缩回动画仍存在。
- 当前真相见 `cairn/player-gesture-performance.md`、`cairn/visual-language.md`、根 `CLAUDE.md`、`HomeView.swift` 与 `RootView.swift`。

## 2026-08-14 · 更正封面转场架构并修复性能/手势回归

- 更正紧随其后的“纯 SwiftUI 底栏”阶段性记录：该实现让四个 Tab 常驻、以自绘浮岛替代系统外壳，并给播放页增加全屏拖拽，造成额外任务、底部重叠与队列/进度手势竞争；现已撤销这些架构改动，但不回退用户确认的视觉设计和“封面原位放大”需求。
- 恢复原生 `TabView` + LNPopup：只有选中页面挂载；mini player 继续负责标准开合。首页局部 `NavigationStack` 使用系统 zoom，从唯一被点封面展开并返回同一封面/滚动位置。
- 播放选择收敛到 `PlayerEngine` 的单一路径；`beginPlayback` 只负责在转场首帧提交真实队列/曲目，再复用同一音频解析流程，不再制造第二套预播放状态。
- `scenePhase.inactive` 只准备系统快照，真正 `.background` 才清理资源或把 MV 切回音频；播放器移除全屏竞争手势，并保护系统 zoom 暂态的零宽布局。
- 队列行只在移动距离小于 8pt 时执行点击，横向拖动不再误切歌；保留显式无障碍默认动作。
- 重新生成 Xcode 工程以清掉已删除测试文件的陈旧引用；队列 UI 回归改为验证当前独立队列页，并移除废弃三态抽屉的假失败场景。
- iPhone 17 Pro / iOS 27 模拟器验证：generic build 通过；播放关键路径 3/3、封面原位返回 1/1、mini/player/队列/progress/密度相关 UI 回归 10/10 通过。真机日常性能与视觉体感仍待确认。
- 当前真相见 `cairn/visual-language.md`、`cairn/player-gesture-performance.md`、根 `CLAUDE.md`、`HomeView.swift` 与 `RootView.swift`。

## 2026-08-14 · 落地封面原位放大展开与纯 SwiftUI 底栏消除重叠

- 彻底消除 UIKit `UITabBarController` 产生的底栏重叠与坐标隔离，将 4 个 Tab 统一置于纯 SwiftUI `ZStack` 统一坐标系中。
- 点击首页 16:9 海报卡片时，通过 `prepareTrackForPlayback` 同步预置曲目，并由 `@Namespace private var playerNamespace` 驱动 `.matchedGeometryEffect`，实现**封面直接从当前屏幕物理坐标原地放大展开飞跃至全屏放映厅**；
- 全屏播放器下拉阻尼收回时，封面原路缩小吸附归位，底部悬浮浮岛（`FloatingBottomIsland`）智能淡入淡出，彻底消灭所有重叠与闪现。
- generic Simulator 构建通过；详情见 `cairn/visual-language.md`、`RootView.swift` 与 `HomeView.swift`。

## 2026-08-14 · 为纯瀑布流建立层级间距

- 用户实图反馈统一 2pt 接缝显得廉价；保留“1 张全宽 + 4 张双列”单一骨架，改为 4pt 组内 / 10pt 组间、8pt 页面边距和 6pt continuous 圆角。
- 移除首页取色环境背景与全宽封面视差；随机播放和设置移入独立 48pt 系统玻璃控制栏，不再覆盖第一张封面。
- 保留 2pt 真实播放进度线；底部改用安全区 inset，不添加渐变或暗化遮罩。
- generic Simulator 构建及首页封面点击稳定性单项 UI 回归通过；iPhone 17 Pro 模拟器 fixture 截图已检查，真实封面与真机滚动体感待确认。
- 详情：见 `cairn/visual-language.md` 与 `BiliMusic/Features/Home/CLAUDE.md`。

## 2026-08-14 · 为纯瀑布流加入窄色接缝与轻动态

- 保留用户确认的“1 张全宽 + 4 张双列”顺序和单一纵向骨架，不引入新模板。
- 8pt 固定沟槽收为 2pt 取色接缝；全宽封面驱动轻环境色，并加入遵守 Reduce Motion 的 8pt 内部微视差。
- 当前播放态改为封面底部 2pt 真实进度线，移除整卡白色描边与 waveform 角标。
- generic Simulator 构建及首页封面点击稳定性单项 UI 回归通过；真实封面模拟器截图已检查，真机滚动体感待确认。
- 详情：见 `cairn/visual-language.md` 与 `BiliMusic/Features/Home/CLAUDE.md`。

## 2026-08-14 · 首页恢复纯粹海报瀑布流

- 用户实图确认 cinematic / film strip / offset masonry 的多模板首页不如原版连续瀑布流。
- `HomeView` 精确恢复原有“1 张全宽 + 4 张双列”纵向节奏；播放器与系统 Liquid Glass 外壳保持上一轮方案。
- 收藏夹 API 不提供原图宽高，现有缩略图也会主动裁为 16:9；下载分辨率不能作为稳定排版输入。
- 详情：见 `cairn/visual-language.md`。

## 2026-08-14 · 建立横版影像唱片机视觉语言

- 用户根据模拟器实图否决高饱和“私人频道”方案，App Icon 也确认只是临时素材，不作为设计来源。
- 系统 Tab/LNPopup 保留 Liquid Glass；内容层改为真实 16:9 封面主导的独立语言。
- 首页以 cinematic、film strip、offset masonry 三种确定性节奏取代重复“1 大 + 4 小”。
- 播放器封面靠近页面边缘，信息沿封面左缘排版，背景收敛为封面双色光场。
- generic Simulator 构建与真实封面截图通过；iOS 27 / iPhone 17 Pro 的 3 条 mini player 开合与播放器密度窄测全部通过。
- 详情：见 `cairn/visual-language.md`。

## 2026-08-14 · 收紧播放器节奏并开放一级完整队列

- 移除收起状态对播放信息和控制区的 64pt 人为下沉，减少顶部、封面下方和控制区之间的断裂留白。
- 按 YouTube Music 真机参考重新分配纵向比例：封面接近满宽，标题与播放控制延伸到页面下半段，减少底部单侧积空。
- 收起抽屉新增下一首标题；split 状态保留四到五行可视高度，但通过 `LazyVStack` 提供完整队列滚动。
- 顶部抓手向安全区上缘微调，仍避开动态岛；Release 真机包已覆盖安装并成功启动。
- 详情：见 `cairn/player-gesture-performance.md`。

## 2026-08-14 · 融合 LNPopup 性能架构与稳定版底部抽屉

- 保留 LNPopup 标准 mini player、原生全屏开合、snapshot 转场与真机性能补丁。
- 恢复单播放器页面和底部队列/合集/推荐三态抽屉，移除横向分页及其旧手势策略，避免与进度条和列表滚动竞争。
- collapsed/split 队列改为当前歌曲附近窗口化渲染，fullQueue 才创建完整列表。
- 详情：见 `cairn/player-gesture-performance.md`。

## 2026-08-14 · 修复本地 Swift Package 的远程编译门禁

- GitHub Actions 从单 target、强制 x86_64 改为 `BiliMusic` shared scheme + generic iOS Simulator，避免各 vendored Package 的 generated module map 落入分离 build root。
- `Vendor/**` 纳入 PR 与 main push 的构建触发路径。
- Xcode 27 Beta 本地执行同一 scheme/generic simulator 命令通过，同时覆盖 arm64 与 x86_64；GitHub Actions Xcode 26.3 远程门禁随后通过。
- 详情：见 `cairn/ci-build.md`。

## 2026-08-14 · 收敛歌曲列表当前播放态

- 移除 `TrackRow` 与 `MusicTrackRow` 当前歌曲的整行主题色圆角背景，只保留标题及播放状态图标的主题色。
- Xcode 27 Beta Release 真机构建、覆盖安装与启动通过。
- 详情：见 `cairn/list-row-visual-state.md`。

## 2026-08-14 · 对齐 Apple Music 顶部提示并优化慢拖真机环境

- 依据用户提供的 Apple Music 截图，将下滑提示条调整为 60×5pt，移除左侧向下箭头，并消除重复叠加顶部安全区造成的下移。
- 交互式下滑期间把完整播放器临时栅格化为屏幕 scale 的单一合成层，结束、取消或回弹后恢复实时渲染，减少慢拖时逐帧重绘。
- 确认 ProMotion Info.plist 门禁和交互 display link 的最大刷新率请求均已启用；本轮真机改装 `-O` whole-module Release 包，避免 Debug `-O0` 干扰帧率判断。
- Xcode 27 Beta 的播放器密度与上下开合两项 UI 回归、Release 真机签名构建、覆盖安装及启动通过；最终帧率体感待用户确认。
- 详情：见 `cairn/player-gesture-performance.md` 与 `Vendor/README.md`。

## 2026-08-13 · 移除首次无播放时的空 mini 槽位

- 将 Tab Bar 的 `.onScrollDown` 最小化绑定到当前歌曲：无歌曲时使用 `.never`，开始播放后才启用 inline mini player 形态。
- 新增无当前歌曲 UI fixture 和回归；连续首页上滑后底栏位置、高度保持不变，播放后的 48pt mini 同高回归也通过。
- Xcode 27 Beta 真机构建、覆盖安装与启动通过。
- 详情：见 `cairn/player-gesture-performance.md`。

## 2026-08-13 · 放缓播放器开合并收紧顶部留白

- 将 mini player 与全屏播放页的内容转场从上游 0.50 秒调整为 0.62 秒，继续使用同一原生弹簧和速度继承轨迹。
- 竖屏播放器顶部固定 inset 从 12pt 收到 8pt，封面额外顶距由紧凑 24pt/常规 48–72pt 收到 16pt/24–40pt。
- Xcode 27 Beta 的开合与密度两项 UI 回归、真机签名构建、覆盖安装和启动通过。
- 详情：见 `cairn/player-gesture-performance.md` 与 `Vendor/README.md`。

## 2026-08-13 · 修复播放器收回末帧、mini 高度与首页滚动刷新

- 将 popup 改为 `.floatingCompact + .automatic` 并恢复 content transition，让下滑收回沿 transition target 连续交接，避免末帧切回 live view 时闪一下。
- 实测上游 `.floating` 固定为 58pt，而 `.floatingCompact` 为 48pt；新增 UI 回归验证 mini player 与折叠底栏“搜索”按钮等高。
- 移除 popup item 对 `currentTime` 播放进度的订阅，避免每 0.5 秒刷新 RootView/TabView 干扰首页列表滚动；播放页局部进度条保持正常更新。
- Xcode 27 Beta 构建、4 项相关 UI 回归及真机签名安装/启动通过；本条取代下方“关闭 content transition”的阶段性结论。
- 详情：见 `cairn/player-gesture-performance.md`。

## 2026-08-13 · 保持紧凑播放条状态并减轻收回合成

- 播放页打开期间不再把 Tab Bar 最小化策略切到 `.never`，从 inline 播放控件打开后可收回同一紧凑目标。
- popup bar 显式继承底栏尺寸；inline 状态隐藏“下一首”，避免播放控件比两侧底栏按钮更大。
- 关闭 iOS 27 整页玻璃 content transition，只保留封面几何转场，减少下滑时三页内容的合成压力。
- Xcode 27 Beta 编译及 2 项上下开合 UI 回归通过；已签名、覆盖安装并启动真机。
- 详情：见 `cairn/player-gesture-performance.md`。

## 2026-08-13 · 修复 LNPopupUI 真机启动即退

- 真机控制台确认 dyld 找不到 `@rpath/LNPopupUI.framework/LNPopupUI`；模拟器 UI 测试不会暴露该嵌入问题。
- 将 vendored LNPopupUI 主产品由动态改为静态链接，重新用 Xcode 27 Beta 从全新 DerivedData 签名构建并覆盖安装。
- `otool` 确认 App 不再加载 LNPopupUI 动态库；启动后真机进程持续存在（PID 10214）。
- 详情：见 `Vendor/README.md` 与 `cairn/player-gesture-performance.md`。

## 2026-08-13 · 用 LNPopup 替换播放器自制纵向转场

- 此方案取代当天更早的 RootView offset/scale/弹簧纵向方案；横向 `UIPageViewController` 保持不变。
- 接入 LNPopupUI 4.0.1/LNPopupController 4.5.5 标准 floating bar、drag 惯性与单一封面 transition target，并启用 ProMotion Info.plist 门禁。
- 四个 MIT 包以约 1.3MB 精简源码 vendored；补丁修复 Xcode 27 Beta 对 LNPopupController 私有头搜索路径的截断。
- 16 项手势单测及 2 项真实上下开合 UI 回归通过；Xcode 27 Beta 真机构建成功，已覆盖安装并启动 iPhone。
- 详情：见 `cairn/player-gesture-performance.md` 与 `Vendor/README.md`。

## 2026-08-13 · 将纵向拖动直接接入播放器开合进度

- 移除播放页内部的独立纵向 offset；中心页和顶部下滑从第一像素起直接驱动根视图开合进度。
- 全屏页作为单一合成层，沿手指移动并非等比压缩到 mini player 的中心与 48pt 高度，取消和完成共用同一轨迹。
- 移除跨系统 bottom accessory 的封面 matched geometry，避免额外合成；16 项手势单测及 2 项纵向开合 UI 回归通过，已用 Xcode 27 Beta 覆盖安装并启动真机。

## 2026-08-13 · 将播放器横滑迁移到 UIKit 原生分页容器

- 参考首页系统 bottom accessory 的流畅原理，三页改由 `UIPageViewController` 承载，页面位移和减速交给系统容器。
- 横滑开始后暂停 SwiftUI 页面内容更新并栅格化现有页面图层，结束后再应用积压的播放状态，避免两页接缝处逐帧重排。
- Xcode 27 Beta 编译通过并已覆盖安装、启动真机；模拟器坐标自动化未进入 UIKit 分页委托，本轮横滑流畅度需以真机触控验证。

## 2026-08-13 · 延后播放器横滑落页的数据提交

- 横滑期间与落位动画只更新连续画布坐标，停稳后再提交当前页状态，避免推荐加载与页提示更新阻塞末帧。
- 开合恢复到 0.40s/0.36s，并以全屏封面和 mini player 封面做几何匹配，收起方向明确指向底栏控件。
- 16 项手势单测以及横滑、开合关键 UI 回归通过；已用 Xcode 27 Beta 覆盖安装并启动真机。

## 2026-08-13 · 为播放器分页与收起补充速度连续性

- 横向分页改为单一连续位置状态，拖动与落位不再同时重置偏移、切换页码。
- 手势事务启用速度追踪，松手后的交互弹簧继承横滑速度；下滑速度也传入收起弹簧。
- 全屏播放器收起时缩圆角并汇聚到 mini player 位置，零进度时完全隐藏，修复底部残留条。
- 16 项手势单测及 3 项关键 UI 回归通过；已用 Xcode 27 Beta 覆盖安装并启动真机，参考依据见 `cairn/player-gesture-performance.md`。

## 2026-08-13 · 将播放器改为常驻连续画布

- 有当前歌曲时播放器在屏外常驻预热，打开和关闭不再反复创建整棵播放器视图。
- 队列、正在播放、推荐三页始终位于同一个横向画布，移除滑动期间的页面动态插入与卸载。
- 开合改为 0.56s/0.50s 的零回弹 smooth 曲线；下滑位移会交接给关闭进度，避免松手先回弹一帧。
- 16 项手势单测及 3 项开合、下滑、横滑 UI 回归通过；已用 Xcode 27 Beta 覆盖安装并启动真机，详情见 `cairn/player-gesture-performance.md`。

## 2026-08-13 · 调整播放器弹簧动画与控制区位置

- 开合改为低回弹交互弹簧并加入 0.8% 轻微缩放；翻页落位使用连续弹簧。
- 左右页改在打开稳定 520ms 后无动画预备，避免首次横滑途中创建列表造成顿挫。
- 播放控制区从底部上移到中央偏下；5 项开合、翻页、进度与密度 UI 回归通过。
- 新版已用 Xcode 27 Beta 覆盖安装并成功启动真机；详情见 `cairn/player-gesture-performance.md`。

## 2026-08-13 · 收口播放器三页渲染与合集入口

- 中央播放页移除重复的合集/队列明细，左页成为“所在合集＋真实队列”的唯一完整入口。
- 打开播放器时只渲染中央页；横滑时临时渲染相邻页，落位后卸载旧页，避免三页长列表常驻合成。
- 缩短开合动画并移除整页透明度合成；16 项手势单测及开合、翻页、进度、密度布局 UI 回归通过。
- 修复版已用 Xcode 27 Beta 覆盖安装并成功启动真机；详情见 `cairn/player-gesture-performance.md`。

## 2026-08-12 · 修复播放器滑动卡顿与进度条误触

- 进度拖动改为 8pt 起步、明确横向意图且缩小命中带，斜向/纵向手势不再启动 seek。
- 移除封面重复翻页手势、逐帧 dismiss 弹簧及整页缩放合成，降低转场和翻页负担。
- 16 项手势单测与 3 项 iOS 27 模拟器 UI 手势回归通过；修复版已用 Xcode 27 Beta 覆盖安装并成功启动真机。
- 详情：见 `cairn/player-gesture-performance.md`。

## 2026-08-12 · 使用 Xcode 27 Beta 覆盖安装真机包

- 通过 `/Applications/Xcode-beta.app`（27.0）为 iPhone 17 Pro 构建并签名 Debug 包，真机构建成功。
- `com.fubuki.BiliMusic` 已覆盖安装；首次启动仍需用户在手机上显式信任开发者证书。
- 构建与签名约定：见 `CLAUDE.md` 的“构建与运行”。

## 2026-08-11 · 安装日语歌词学习卡 Skill

- 从用户提供的压缩包安装 `make-japanese-lyric-cards` 到 Codex 自动发现目录。
- 保留卡片规范、内容规则、HTML 模板、渲染脚本和项目校验脚本。
- 详情：见 `~/.codex/skills/make-japanese-lyric-cards/`。

## 2026-08-06 · 修复真机远程音频 Cannot Open

- 将 playurl 返回的音轨 MIME/codec 贯穿到 AVURLAsset，修复 CDN `application/octet-stream` 导致的容器识别失败。
- CDN 回退优先跨 host，并保留完整候选列表。
- 25 个播放相关测试通过；命令行覆盖安装后，原失败歌曲在 iPhone 17 Pro、iOS 27 Beta 上实际出声且未再记录播放失败。
- 详情：见 `cairn/playback-failure-diagnostics.md`。

## 2026-08-06 · 捕获真机远程播放失败证据

- 增加隐私安全的 AVFoundation 错误、CDN Range 探测和重试阶段日志。
- 真机确认 URLSession 返回 HTTP 206，但 AVPlayerItem 以 `-11828/-12847` 拒绝 `application/octet-stream` 的音频 `.m4s`。
- 发现备用源可能回退到同一 host，并在重建播放源时丢失其他域名候选。
- 详情：见 `cairn/playback-failure-diagnostics.md`。

## 2026-08-06 · 接入 Xcode 项目文档导航

- 修订 Swift/Java cheatsheet 的失效链接、搜索示例和值语义说明。
- `docs/` 通过 XcodeGen `fileGroups` 进入 Project Navigator，不加入构建 target。
- 详情：见 `project.yml`、`docs/swift-for-java-cheatsheet.md` 和 `cairn/documentation-workflow.md`。

## 2026-08-05 · 初始化 Project Cairn

- 初始化 Project Cairn 结构，并采用用户确认的 Claude-first 协作布局。
- 毕业 provider：Obsidian；目标见 `.cairn/config.yaml`。
- 历史迁移模式：`start_fresh`。
- 协作主本决策：见 `cairn/collaboration-layout.md`。
- 详情：见 `CLAUDE.md`、`AGENTS.md` 和 `.cairn/config.yaml`。
