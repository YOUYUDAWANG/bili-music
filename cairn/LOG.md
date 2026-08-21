# Project Cairn 日志

本文件按反向时间顺序记录实质进展——最新记录放在本行下方最顶部。每条记录保持简短，只写摘要与指针；稳定结论沉淀到 `cairn/<topic>.md`。

## 2026-08-22 · 轻量逐字加入本地人声感知节奏修正

- 纯文本估算在日语连续字符上容易近似匀速；现新增滚动 `VocalTimingMapV1`，在宿主标签页本地约 20Hz 提取中置人声存在度、起音与置信度，用有界时间扭曲修正 Column 的 `estimated` 逐字。低覆盖或低置信度会逐点精确回退原估算，原生 word timing 始终优先且不受影响。
- Column 波形按钮显式启停该能力；Chrome 要求当前页先由用户调用扩展，故首次启动失败会给出 15 秒授权提示，打开 LyricStage popup 后自动续接。只保留最长约 20 秒、最多 640 个归一化样本，不保存或发送 PCM、频谱、媒体 URL，也不把估算轴发送给 Director 或 Fullscreen。
- 聚焦测试 42/42、typecheck、extension 双构建与 MV3 CSP 通过。扩展已重载；真实 Chrome 中首次提示、popup“人声增强已启动”、Column“人声增强”三步闭环成立，播放按钮持续为“一時停止”（正在播放）。稳定边界见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-22 · Chrome AI Director 客户端闭环

- 经用户明确授权，现有 OCI Director Bearer 已写入 LyricStage 当前 Chrome 配置；值只保存在扩展本地存储，未进入仓库、构建产物、命令输出或项目笔记，注入时使用的临时内存副本已清除。
- 真实 YTM《non-reflection (Cover Live)》从 Column 的“AI 导演 · 下一段接管”进入全屏后显示“AI 导演 · 已接管”；Chrome 同时保持 `Audio playing`，播放时钟继续前进，证明语义导演接管与 tabCapture 回接音频可共存。退出全屏后 Column 仍保持 AI 计划状态；MusicMap 增强仍按既有覆盖门槛与下一 section 边界接管，不上传或落盘原始音频。
- 扩展配置页明确显示“已启用；歌曲稳定后后台生成，下一结构段接管”。本轮只关闭客户端认证和真实接管门，未修改其他扩展、Tunnel、防火墙或 OCI 服务配置；多扩展并存导致的原生 side panel 偶发 loading 仍需单独隔离验收。

## 2026-08-22 · 全屏切歌改为持续舞台过渡

- 旧实现虽然不再退出浏览器 Fullscreen，但会整棵卸载 `StageCanvas`、换成独立的居中加载页，再装回 30/70 舞台；一次切歌仍产生两次明显的几何跳变。
- Fullscreen host 现常驻同构的 Stage-first 30/70 过渡底层：新曲封面、标题、艺人、进度和左右分栏保持原位，只撤掉上一首歌词事实；右侧歌词区显示轻量匹配状态，新 `StageCanvas` 在同一区域以 380ms 淡入覆盖。候选等待、未命中和错误仍不会保留旧歌词或退出全屏。
- 聚焦测试 11/11、typecheck、extension 双构建与 MV3 CSP 通过，本机扩展已重载。真实 YTM 从《non-reflection (Cover Live)》全屏切到《奏（かなで） (Cover Live)》，切歌瞬间仍在全屏并保留同一左右结构，状态明确为“舞台保持中 / 正在匹配歌词”；稳定边界见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-22 · 本地音频 MusicMap 与 Gemini 3.7 Director 1.3.4 上线

- 扩展新增用户手势触发的 `tabCapture + offscreen` 分析：捕获流立即重新接回音频输出，约 30Hz 特征只在本机编译为有界 `MusicMapV1`，不上传/落盘 PCM、视频或媒体 URL。AI 先按歌词生成，覆盖达到门槛后带 MusicMap 二次生成，仍只在下一 section 边界接管。
- YTM 新播放器布局不再要求旧 `ytmusic-player-bar` 内必须有标题；曲目信息分层回退到 MediaSession/页面，同时保留播放器栏权威时钟。真实 Chrome popup 从“先播放歌曲”恢复为正确曲名/艺人，全屏播放继续前进且未静音，封面和三层歌词完整落在安全区。当前同时启用的其他歌词增强扩展会令原生 side panel 偶发 loading，未擅自停用。
- Web 聚焦 6 文件 74/74、typecheck、extension 双构建/MV3 CSP 与 Director 13/13 通过。OCI Director 1.3.4 已在原 `127.0.0.1:8092` + 既有 Tunnel 原位部署，镜像 `f40e48…92797`；旧 1.3.3 镜像、Quadlet/env 备份保留，密钥/缓存/Tunnel/防火墙未改。loopback/public health 为 `gemini-3.7-flash / musicmap-v5`，无认证 401；MusicMap canary 非降级返回 2 sections、4 directives、1 grounded effect，公网复打 cache hit。

## 2026-08-22 · Column 逐字高亮取消提前漏光

- 截图中的“未到字先变白一点”不是时间轴提前，而是 CSS 在进度头部额外绘制了向前 0.28em 的白色光带，已完成 token 的白色 `drop-shadow` 和活动行白色 text-shadow 又会溢到相邻未到字。
- 逐字层现只保留严格停在 `--word-progress` 的白/暗硬边界，native 与 estimated token 均取消白色外溢；活动逐字行覆盖为仅黑色基线阴影，未到字在进度进入前保持同一暗色。
- `timedLineText` 聚焦测试 8/8、typecheck、extension 双构建与 MV3 CSP 通过；本机扩展已重载。真实 YTM 在《感情グラス》暂停并跳到 0:24 行首后，整行未到字保持统一暗色，随后已恢复播放。稳定边界见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-22 · 全屏切歌不再退出舞台

- 根因是曲目 identity 变化时旧歌词会先失效，旧门禁把 `hasMatchingLyrics=false` 直接解释为退出条件并主动调用 `document.exitFullscreen()`；对应测试也固化了该错误生命周期。
- 浏览器 Fullscreen 现由用户退出动作独占 ownership：切歌只在稳定的 fullscreen host 内把 StageCanvas 暂时换成带新曲封面/标题的“正在切换舞台”状态，匹配完成后原位装入新舞台；未命中或候选待选也保持全屏并提供显式退出按钮。
- 聚焦测试 3/3、typecheck、extension 双构建与 MV3 CSP 通过；Chrome 已重载。真实 YTM 从《夏祭り》全屏点下一首到《私論理(いよわ Remix)》，过渡态与新歌词舞台均保持浏览器全屏，最后以 Esc 正常回到 Column。稳定边界见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-22 · 估算逐字接入 Director 低置信上下文

- Column 与 Director 请求现复用同一个 `estimateWordTimingV1`，避免屏幕扫亮和导演看到两套估算。真实逐字继续放在 `words + timingPrecision=word`；line-only 估算单独放在 `estimatedWords + timingPrecision=estimated`，旧服务会忽略独立字段，不能误当真实轴。
- 新服务合同分别校验 native/estimated cues，拒绝两者并存、空 precision、越界/倒序/超量；Director prompt 会收到完整 compact cues、`estimatedWordTiming=true` 和低置信声明。Skill/system prompt 明确估算只用于词组级视觉 pacing，不能作为精确 reveal、beat/onset 或结构证据；fallback 的估算 glyph stagger 也低于真实逐字。
- Web 聚焦 37/37、Director 13/13、typecheck、extension 双构建与 MV3 CSP 通过；本机扩展已重载。经用户授权，OCI Director 1.3.3 已在原 `127.0.0.1:8092` + 既有 Tunnel 原位部署：新镜像 `b25ffd…3667` 运行中，1.3.2 镜像与旧 Quadlet 备份保留，未改 env/Tunnel/防火墙。loopback/public health 正常、公网未授权 401；新容器合同探针为 `estimated=true / real=false`，授权 canary 经 loopback 与公网均 200、`degraded=false`、4 directives、1 effect。稳定边界见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-22 · Column 加入零模型轻量逐字试验

- 普通逐行歌词在 Column 渲染边界使用浏览器 `Intl.Segmenter` 做日语词组切分，并按假名/促音/长音、拉丁元音、数字、空白和标点权重在可信行区间内分配连续扫亮；保留一小段行尾呼吸，不下载模型、不读取音频、不改写 `LyricDocument`。
- 原生 LDDC/QRC/KRC word timing 继续标为 `native` 且绝对优先；估算节点只标为 `estimated`，只存在于 Column 预计算结果，不缓存、不发送给 Director、不进入 Fullscreen 的字符出现时刻。短于 400ms、空白、无法安全切分或异常长的行保持 plain。
- 聚焦测试 8/8、typecheck、extension 双构建和 MV3 CSP 通过；Chrome 已重载。真实《Re:Re: (Live Cover)》54 行 line-only 生成 318 个估算词组，Column 显示“轻量逐字”，同一活动行观测到 `んで` 3.9% 后继续推进到 `を` 43.1%，新脚本挂载后无新增 LyricStage 错误。稳定边界见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-22 · 默认 Reading 改为流动歌词栈并建立 MusicMapV1

- 默认三层 Reading 从三个居中漂浮标题块改为统一 9% leading axis：上一句/当前句/下一句沿同一阅读轴，以 0.23/1/0.35 的稳定层级显示；换句是 760ms 可任意 seek 的整栈上移，唱词期间 `settle` 不再散字、缩放或漂移，reduce-motion 直接落稳。日文本地基线固定 `jpGothic + monument + leading`，明朝体与破轴构图只留给有证据的 AI 段落。
- 预排版新增短 CJK/短 Latin 单行优先：在换行前按真实浏览器字体测量缩字，避免 `11+2` 或单字孤行；长句仍走完整安全区换行，不裁切正文。1920×1080 真实浏览器关闭稳定帧和换句中间帧，短日文三层均完整单行、无重叠。
- 新增 `MusicMapV1` 严格合同与确定性 compiler：最多 96 个压缩段、256 个地标，保存归一化 energy/bass/mid/treble/brightness/flux/onsetDensity/stereoWidth、节拍可信度与结构地标；30Hz feature frame 可编译为该地图。客户端和 Director 双端拒绝越界、倒序和不可信字段，并剥离 raw audio/未知字段；Web 聚焦 40/40、Director 12/12、typecheck、extension 双构建与 MV3 CSP 通过。尚未增加 `tabCapture/offscreen` 权限，真实音频接入是下一切片。

## 2026-08-22 · YouTube Music 单曲权威时钟改由播放器栏拥有

- 真实截图中宿主为 `0:50 / 4:19`，LyricStage 却为 `3:13 / 4:42`；现场 DOM 又证明 YTM 会让唯一活动 `<video>` 处于 `6:41 / 7:52`，同时播放器栏显示另一首歌的 `0:43 / 3:31`。因此媒体元素不是可靠的单曲绝对轴，旧实现把当前 player-bar 元数据与复用媒体的时间拼成了混合快照。
- Content script 现从 `ytmusic-player-bar .time-info` 取得单曲绝对时间与总时长；媒体元素仅提供播放/暂停、倍速和两个整秒锚点间的亚秒增量。大幅 seek、换媒体或轴不一致会重建锚点，不能再让媒体内部总时长覆盖宿主单曲时长。
- 生命周期聚焦测试 25/25、TypeScript、extension 双构建与 MV3 CSP 通过；`extension-dist/content.js` 与源文件 SHA-256 一致。Chrome 已重载 LyricStage 并刷新现有 YTM，content marker 正常、无 LyricStage error/warn；原复现曲的再次播放听感仍由用户确认。稳定边界见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-22 · 全屏 AI 世界与整曲导演协议首个垂直切片

- `DirectorPlanV1` 新增 song-wide `world`：空间模式、运动法则、封面角色、材质与四个连续物理参数；Stage 不再把 AI 仅当逐行行为列表，而会切换全屏构图、封面角色和环境运动。Effect Grammar 从 13 个 primitive / 12 张 card 扩为 20 / 17，新增 ribbon、prism、rain、orbit、memory trail、cover portal 与 bloom，并继续受 evidence、cost、conflict、Hero budget 和 reduce-motion 门禁约束。
- 导演请求对精确 11 位 YTM video ID 附带公开 YouTube URL；本地服务使用 Gemini 3.7 Flash 的整曲视频上下文读取结构、能量、音色、情绪与歌词—音频关系，失败时安全回退到纯文本请求，不上传 PCM、Cookie 或私有媒体地址。AI 成功门提高为完整连续 section、足量 line directive、有效 world 和至少一个有证据的 effect；空导演稿不得显示“已接管”。
- 真实本地浏览器在 1920×1080 关闭 `cinematic / flow / portal / mist` world、`field.ribbon` 与完整歌词安全区；CSS 连续参数改为 React 预计算，避免不受支持的 CSS 乘法导致静止。Web 聚焦 35/35、Director 11/11、typecheck、extension 双构建和 MV3 CSP 通过；只生成本地 `extension-dist`，OCI 协议尚未部署，真实 YTM 整曲 UAT 与后续 tabCapture `MusicMapV1` 仍待继续。

## 2026-08-22 · Web 直接消费 LDDC 原生逐字轴

- `LyricsCandidateV0` 新增受合同校验的 `timingKind` 与可选 `wordTimedDocument`；LDDC adapter 不再把 `lyricLines[].words` 压成普通 LRC，真实 QRC/KRC/YRC 行/字毫秒轴可直接进入 Column 与 Fullscreen。普通 LRC 继续保留作兼容回退；逐字越界、倒退、空值、单行 >300 或总量 >12000 会拒绝，不平均分字、不增加音频上传/Forced Aligner。
- 歌词缓存升到 `lyricstage-youtube-music-lyrics-v8`，避免复用开发中间态和旧 line-only 命中；LDDC Bearer 从 macOS 钥匙串恢复到本机扩展存储，临时凭据文件已删除。聚焦 6 文件 26/26、typecheck、extension 双构建与 MV3 CSP 通过。
- 真实 Chrome 闭环：鹿乃《心拍数#0822》由酷狗/QQ 返回 50 行、481 个逐字时间点，Column 实际生成 481 个 timed nodes，并观测到单字 69.17% / 96.93% 连续扫亮中间态；同轮 `You & 合図` 当前只返回 line timing，页面保持逐行，证明未伪造逐字。稳定边界见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-22 · 手动歌词搜索与联网原唱后备已部署

- Column 工具栏新增手动搜索：可改歌名、歌手可留空，后台绕过旧自动缓存重跑 LDDC/LRCLIB/酷狗；结果无论是否精确命中都只作为最多 5 个候选，显示来源/艺人/时长，用户选择后才绑定当前 track 并写入缓存。Chrome 已重载当前 `extension-dist`，真实 YTM `Flowering / 理芽 with Misumi` 手动请求返回 5 个候选；输入限长、响应合同、候选签发、换歌失效和本地导入边界保持不变。
- Google Cloud 已启用 Gemini API，并新建只允许 Gemini API 的独立 key；原 Vertex/Agent Platform key 未扩大权限，key 值只保存在 OCI 0600 env。Gemma 4 主请求当前明确返回 `RESOURCE_EXHAUSTED: prepayment credits are depleted`，因此 Director 1.3.2 仅在主请求不可用时切到现有 Vertex `gemini-3.5-flash`，仍强制 Google Search、结构化角色和 grounding 门；Gemma 通道与模型名保留，补充预付余额后会自动恢复为主路由。
- 手动搜索/歌词聚焦 5 文件 28/28、Director 9/9、typecheck、extension build/MV3 CSP 通过。OCI 1.3.2 已在原 `127.0.0.1:8092` + 既有 Tunnel 原位部署；loopback/public health 正常，公网授权 200、未授权 401。《死別》正式 canary grounded 为明石繆 → シャノン，《春を告げる》grounded 为鹿乃 → yama；两者均返回搜索查询与 grounding entry point，未改 Tunnel/防火墙。稳定边界见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-22 · 全屏舞台完成减法视觉审计与封面智能取色

- 删除截图中两个大面积对称空面板及其重复 Environment 结构层；普通 Reading 不再默认画汇聚射线、网格、轨道、满屏旋转卡片或科技粒子汤。`monoImpact` 只保留低对比局部光场，`paperCut` 改为少量材质弧线，`editorialKinetic` 只做封面色洗；环境层仅在 Director 明确选择 rail 方向时显示轨道。
- 新增浏览器本地 32×32 中心采样与 OKLCH 色板编译，封面、背景、歌词 ink、环境光和效果几何共享可读颜色关系；YouTube maxres 封面实查允许跨域采样，失败仍有中性 fallback。9 个 Web 文件 74/74、typecheck、0.2.1 extension build/MV3 CSP 通过，固定 fixture 实图已无大面板与默认科技结构。
- Performance Direction Skill 升级 v3，明确封面/歌词/排版为锚点，拒绝无证据的对称空面板、持续网格/轨道、扫描线、汇聚射线和 particle soup。OCI 已在原 loopback/Tunnel 路径原位升级 Director 1.3.1；真实安静歌曲 canary `degraded=false`、强度 0.3、无 effects，未改 Tunnel、防火墙或 token。最新扩展仍待 Chrome 手动 reload 做实际封面取色与整首用户视觉门。

## 2026-08-22 · 更正：翻唱标题改为通用角色语法，不再按候选猜原唱

- 用户指出把鹿乃格式称为“特例”本身就是错误；现把清洗重构为 cover marker → 翻唱者 credit → 版本包装 → 明确原唱 credit → 规范歌名的角色顺序，统一支持 `【/〖歌ってみた】歌名 / covered by 歌手`、`Cover:`、`Vocal:`、`歌名（原唱）/ acoustic cover`、`歌名 / 原唱 - covered by 歌手` 与全半角分隔符，不增加单曲分支。
- 删除“原唱未知时按歌词候选多数艺人自动回退”的不安全逻辑。真实《死別》LRCLIB 候选全部是 `saewool` 的另一翻唱，旧逻辑可能误标原唱；现在标题未写原唱时必须等待 Gemma 4 搜索证据，否则只列候选。无明确原唱的 cover 会并行启动 AI 身份解析与首轮歌词查询，减少串行等待。
- 真实视频 `ztU-ROG3d9E` 元数据为 `【歌ってみた】死別 / covered by 明石繆`、214 秒；公开 credit 确认 Lyrics & Music 为シャノン、Vocal 为明石繆。新本地解析输出 `死別 / 明石繆 / 原唱未知` 且不自动采用 saewool；注入有来源的 `シャノン` 身份后，真实酷狗查询返回 `match / originalFallback / シャノン / 214s`。歌词聚焦 22/22、typecheck、extension build/MV3 CSP 通过，缓存升到 `lyrics-v6`；稳定边界见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-22 · 鹿乃《春を告げる》括号原唱 credit 修正

- 真实标题 `春を告げる（yama）/ acoustic cover.` 暴露括号 credit 盲区：旧清洗保留 `（yama）` 在歌名中，又可能把 `/ acoustic cover` 当成艺人段，导致规范曲名与原唱查询均错误。现将紧邻 cover 包装的括号内容提取为原唱提示，并把 acoustic/piano cover 只当版本包装；输出固定为歌名 `春を告げる`、翻唱者 `鹿乃`、原唱 `yama`。
- 公开视频 `X8ZKPqsAvAc` 与说明确认 Music 为 yama、Vocal 为鹿乃、时长 2:58；LRCLIB 实查鹿乃精确候选为空，但 yama 有多条同步歌词。修正后用同一真实 track metadata 完整跑 LRCLIB/酷狗，6.1 秒返回 `match / originalFallback / yama / 春を告げる`；歌词聚焦 18/18、typecheck、extension build/MV3 CSP 通过。缓存升到 `lyrics-v5` 淘汰旧 miss，最新产物仍需 Chrome reload。稳定边界见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-22 · 歌词身份解析升级为 Gemma 4 联网原唱确认

- 确定性标题清洗降级为不可信搜索提示：首轮未命中当前录音时，新 `/v1/music/identity` 使用 `gemma-4-26b-a4b-it` minimal thinking + Google Search，结构化区分当前演唱者、原唱与词曲/制作角色；服务端只从 grounding metadata 取引用，无来源、低于 0.65、演唱者不一致、角色混淆或翻唱无原唱均拒绝进入歌词检索。
- 扩展复用本机 Director Bearer，AI 结果过本地合同后用标准曲名/别名/当前翻唱者/原唱重跑 LDDC、LRCLIB 与酷狗，翻唱同录音仍优先、原唱仍次选；缓存升到 `lyrics-v4`，配置 Bearer 时主动清旧 miss。服务端 8/8、歌词聚焦 8/8、typecheck、0.2.1 extension build/MV3 CSP 通过。
- 当前公网 health 仍报告 Director 1.2.0 且仅列 `/v1/fullscreen/direct`；1.3.0 代码和产物已就绪但尚未写入 OCI，也未验证真实 Gemma API Key/线上样例。部署前需显式授权，并保持 loopback + 现有 Tunnel、无防火墙变更。稳定边界见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-22 · 翻唱标题模板从单点修正扩为原唱 credit 拆解

- 用户 reload 后以 `【歌ってみた】泥中に咲く - ウォルピスカーター covered by 存流` 复现仍 miss；现场身份输出证明旧清洗只去掉 `covered by 存流`，却把「泥中に咲く - ウォルピスカーター」整体当歌名。现统一拆解 `歌名 - 原唱 covered by 翻唱者`、斜线变体、日中英 Cover 标记与 `歌唱/Vocal` 尾注，保留规范标题、原唱提示和翻唱者三层身份。
- 查询顺序扩为 LDDC 翻唱 → LRCLIB 翻唱/原唱/标题 → LDDC 原唱补查 → 酷狗标题/翻唱/原唱；翻唱同版本门仍优先，原唱只作为既有显式次选。歌词缓存升到 `lyrics-v3`，主动淘汰 reload 后产生的旧 miss。
- 真实公开源闭环：存流《泥中に咲く》命中酷狗同版本 288s，原唱候选同时保留；《鏡面の波》270s、《残響散歌》185s 也均命中存流同版本。歌词聚焦 5 文件 24/24、typecheck、0.2.1 extension build/MV3 CSP 通过；因当前 YTM 标签被另一浏览器控制会话占用，最新产物仍需再次手动 reload 做页面内确认。稳定边界见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-22 · 06-06 Stage-first Runtime 与 Director Skill v2 已落地

- 全屏改为真实封面锚定的 30/70 Now Playing：标题/艺人、常驻细进度和 YTM Bridge 权威运输控制留在封面列，顶部/底部无浮动 chrome；唯一 Canvas glyph owner 实现三层 Reading、单句窗口 Hero 缩岛、Duet、Aperture 和按词换行的长 Latin。AMLL 0.5.2 spike 选择算法原则 + 单 renderer，ADR、根 AGPL-3.0-only 与第三方 NOTICE 已补齐。
- `web/packages/performance` 新增 13 个 typed primitives、12 张 effect cards、三层 evidence、成本/互斥/reduce-motion grammar；`services/lyricstage-director/skills/performance-direction-v1` 与 v2 JSON Schema 直接约束 Gemini。服务端用 repetition/gap/overlap/voice/density/final 事实验证，扩展再次验证并在下一 section handoff；未知代码/primitive、低证据 Hero 与坏身份 fail closed。
- OCI Director 1.2.0 已在原 `127.0.0.1:8092` 原位部署，公网 v2 health/401、生产 Gemini `degraded=false` canary 和 duet/final EffectRecipe 通过；未改 Tunnel/防火墙，1.1.0 镜像与 Quadlet/env 备份保留。Web 发布门 9 文件 70/70、typecheck、extension build/CSP、Director 5/5；浏览器 240 帧 P95/P99 0.30ms。最新扩展仍待 Chrome 手动 reload 后关闭真实 YTM 最后一门。稳定边界见 `cairn/lyricstage-platform-architecture.md` 与 `06-06-AMLL-ADR.md`。

## 2026-08-21 · 批准 06-06 专业 UI / Motion 方案与 Director Skill

- 用户要求代理不机械接受外行意见，而以 UI 与动效负责人标准明确赞成、修改和否决。新 `06-06-DESIGN.md` 冻结 Stage-first Now Playing：28–32% 真实封面锚点、三层常态歌词、常驻细进度、仅 Bridge 权威运输控制、无顶部/底部浮动 chrome；Hero Line 稀疏使用，封面每幕可申请缩岛但必须通过结构证据和稳定门禁。
- Performance Direction Skill 被定义为版本化知识包而非特效清单：小而稳定的 typed primitives、首批 12 个 evidence-bearing effect cards、开放组合路径和本地能力/预算/可读性编译；每个强效果必须具备 song motif / section / line 三层证据，未知新原语只进 Performance Lab 建议，不允许模型输出任意代码。
- AMLL AGPL-3.0 已获用户接受，06-06 先做双 renderer 与单 glyph renderer spike，默认倾向复用 AMLL 算法/解析/背景而保持单一 LyricStage renderer；`react-full` 不接管外壳、YTM Bridge、AI 分幕或 fallback。新增 `WEB-09/10`、`TEST-07`、六项实施计划与真实五类歌曲 UAT；本轮只写方案，未修改运行代码、后端或部署。见 `.planning/phases/06-lyricstage-platform-and-web-reference/06-06-DESIGN.md` 与 `06-06-PLAN.md`。

## 2026-08-21 · YTM 翻唱清洗升级为翻唱优先、原唱次选

- `web/packages/lyrics` 现在会把 `【歌ってみた】修羅 by 花譜` 清为「修羅」并保留花譜为翻唱者；`by / covered by / sung by / 歌唱 / vocal` 尾注与更多包装可确定性移除。候选先过标题与 30 秒时长相关性门，酷狗不再把《邂逅》等花譜其他歌曲送进选择器。
- 自动采用固定为同标题/翻唱者/≤4 秒的翻唱录音优先；翻唱缺失时，精确标题、≤15 秒且唯一或多数一致的原唱可作为显式 `originalFallback` 次选，界面说明使用了原唱；同名艺人平票继续手选。缓存 namespace 升到 `lyrics-v2`，旧错候选不会复用。
- 花譜《修羅》真实多源请求已返回 `match / originalFallback / ヨルシカ / 236s`，DOES 同名异曲因时长门被排除。歌词聚焦 4 文件 16/16、typecheck、0.2.1 extension build 与 MV3 CSP 通过；最新 `extension-dist` 仍需 Chrome 手动 reload 后做页面内确认。稳定边界见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-21 · Fullscreen 前端不再降维 AI 导演稿

- 保留独立 Director 1.1.0 与完整 `DirectorPlanV1` 不动；`StageCanvas` 删除 `directorPlanToRecipeV0 -> PerformancePlanV0` 的生产降维路径，改由新 `PreparedDirectedStageV1` 直接消费每个 section 与每行 directive。旧 V0 renderer 仅作兼容，不再决定全屏视觉。
- 全屏现按五层绘制：Pixi environment、六种 section structural field、九种 directive 主歌词动作、前句/Hook/重叠声部 memory-counterpoint、section transition veil；layout、typography、paletteIndex、alignment、direction、intensity、fontScale、glyphStagger、paletteRole 均有独立可见作用，12 套色板随 section 切换。真实 word/line reveal 仍只由歌词轴决定，reduced-motion 保留构图与色板但关闭位移动作。
- 本地浏览器 16:9 实图确认新路径已显示分栏网格、环境粒子/轨道、主句、Hook 残影与切幕层，观众 Canvas 不再绘制 recordingID/time debug；typecheck、renderer/director 聚焦 9/9 与 0.2.1 extension build/MV3 CSP 通过。最新 `web/extension-dist` 仍需 Chrome 手动 reload 后关闭真实 YTM 云端导演视觉门。见 `cairn/lyricstage-platform-architecture.md` 与 `web/apps/youtube-music-companion/RELEASE-CANDIDATE.md`。

## 2026-08-21 · 独立 Fullscreen Director 切到官方 Vertex 并关闭真实接管门

- 用户否决复用手机端 Luna/Metadata Worker 合同；新增 `services/lyricstage-director`，只为 16:9 Web Performance Runtime 输出 `lyricstage-fullscreen-director-v1`：song-specific concept/motif/intensity arc、连续 section 的 art/layout/typography/palette 和每行完整 directive。服务端严格限制 enum/range/连续覆盖/45% 高动作预算，响应不回传歌词正文；坏输出标记 degraded，扩展继续本地完整 plan。
- OCI `oci-macmini-services` 以 Podman Quadlet 运行 `localhost/lyricstage-director:1.1.0`，仅监听 `127.0.0.1:8092`，持久缓存位于 `/var/lib/lyricstage-director`；现有 `hachi-mi-oci` Tunnel 暴露 `director.hachi-mi.uk`，未开放 OCI 防火墙端口。客户端 Bearer 只存 macOS Keychain/扩展本地存储，Google Key 只在 OCI 0600 环境文件，值不入仓库、构建层或笔记。
- 上游已按用户要求从 CPA 切到 Google 官方 Vertex AI Express Mode，使用 `gemini-3.5-flash` 的 `generateContent`、`application/json` 与 response JSON Schema。官方-key 四行 canary 6.4 秒返回 `degraded=false`；真实 YTM `Hew46pJkFW0` 方案进入有效磁盘缓存，Chrome 全屏从 `LS / LOCAL` 在下一结构段无中断切到 `LS / DIRECTED`。Web 18 文件 93/93、Director 4/4、typecheck、0.2.1 extension build/MV3 既有门保持通过。见 `cairn/lyricstage-platform-architecture.md` 与 `web/apps/youtube-music-companion/RELEASE-CANDIDATE.md`。

## 2026-08-21 · LyricStage Web Performance 0.2.0 上线候选

- Performance Lab 语义正式进入生产全屏但不进入 Column：新增严格 `DirectorPlanV1`、完整本地 fallback、按歌词空隙/六行上限划分 section、重复 Hook/二重唱导演、受控字体/布局/调色与 Legacy `/v1/lyrics/direct` 适配；AI degraded、partial、身份错误、越界或末段无后续边界时均保持本地计划。
- `StageCanvas` 现以 PixiJS WebGL 环境 + Canvas2D CJK/逐字正文双层渲染，封面不再直接显示；标题/歌手仅开场短暂出现。AI 计划只在下一 section 起点接管；GPU init/draw/context-loss 失败只降级环境，不撤掉歌词。轻量/reduced-motion 优先于显式个人 VJ 模式。
- 后台新增固定 Metadata Worker 自动导演、70 秒 timeout、同请求去重、30 天/100 首严格身份缓存和本机 Bearer 配置。请求只含标题/歌手/时长/完整歌词与行词时轴，不含音频、封面、媒体 URL；超过 180 行或 90KB fail closed。Worker health 当前在线且无令牌 `/v1/lyrics/direct` 保持 401，未部署或修改云端。
- 真实 Chrome 以 2226×1252 backing store 连续运行 WebGL + Canvas 240 帧，Canvas draw P95 0.70ms、无 console issue。12 个相关测试文件 76/76、typecheck、0.2.0 extension 双构建、CSP、无音频捕获/DEV Studio、1.2MB content runtime 上限和源码产物一致性门通过；`content-ui.js` 814KB。用户 reload 后的真实 YTM UAT 已关闭：Column/Related/Lyrics 单实例恢复、按钮与 `F` 入场、`Esc` 回 Column、GPU 本地舞台、点击歌词双向 seek、暂停冻结/恢复、换歌清旧态、页面重连与 VJ 偏好持久化均通过，且无新版 console warning/error。AI Director Bearer 实测仍是可选门，不阻塞本地完整演出候选。见 `web/apps/youtube-music-companion/RELEASE-CANDIDATE.md`。

## 2026-08-21 · Performance Lab 接入 PixiJS GPU 环境与 Theatre authoring

- `web/packages/performance` 新增 `EnvironmentSceneV1`：按 recordingID 确定性编译调色板、42 粒子、7 rail 与 4 orb，任意 seek 均可重采样；结构能量和受控 intensity/bloom/drift/railOpacity 只影响环境，不修改歌词几何或同步。
- Lab 以 PixiJS 8.20.0 WebGL 渲染环境层，DOM/CJK 正文保持独立；Theatre.js 0.7.2 只在 `import.meta.env.DEV` 动态接入，可实时编排四项环境参数、跟随毫秒 playhead、显隐 Studio 并导出 project state。production bundle 静态确认不含 Theatre/Studio。
- 真实浏览器捕获并修复了 Pixi 异步 init 遇到 React StrictMode 提前 destroy，以及 Theatre CJS default/初始化与重复 object config 竞态。最终 680×383 CSS 画布以 1360×766 WebGL backing store 渲染；切到二重唱 15000ms 后双声部、seed `972918288` 与 authoring 联动均正确，修复后无运行错误（隐藏 Studio 会产生其官方提示 warning）。
- 聚焦测试扩为 9/9，typecheck、独立 production build、package-lock JSON 与 Theatre 生产排除门通过。Pixi 当前令 Lab 主 chunk 约 739KB min / 210KB gzip，正式 Stage 集成前需做按层 lazy loading/裁剪；仍未实现 Director Plan、AI cache、结构边界热切换或 YTM 全屏接入。见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-21 · LyricStage Performance Lab 第一切片

- 新增完全独立于 YouTube Music 产品路径的 `web/apps/performance-lab` 与 `web/packages/performance`：`TimedTextIndexV1` 提供 phrase / word / character 时间层级、重叠声部、O(log n) 任意时刻采样和 seek 前后差分；无逐字轴时不伪造 word/character timing。
- 新增可确定性任意时间采样的 `MotionClipV1`，首批包含 editorial rise、rail cut、memory bloom；Lab 可切六组既有 fixture/clip，以毫秒、滑杆或单帧步进排练 16:9 全屏构图，并查看时间索引与动作参数。
- 真实 Chrome 验证：逐字混排在 2900ms 正确命中 `trace` 及其字符；重叠二重唱在 15000ms 同时显示日英两声部且不编造词级时轴；控制台无 warn/error。聚焦测试 5/5、typecheck、`build:performance` 均通过。
- 此切片尚未接入 YTM、AI 导演、PixiJS 或 Theatre.js，也未改变现有 Column/Fullscreen；下一切片才建立 GPU 环境层与开发期关键帧编排。稳定边界见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-21 · YTM 自动歌词升级为身份清洗与分层多源

- Companion 不再把 YTM 原始标题/首个歌手直接锁死在一次 LRCLIB 查询：新增 Topic/Official/Cover 等包装清洗、原文标题/别名、翻唱者/原唱分层；LRCLIB 严格查询失败后按标题与别名做无歌手回退。
- 新增酷狗公开只读搜索→候选→LRC 完整链；单源失败不阻塞其他来源。旧单源 miss 通过 `lyrics-v1` cache namespace 失效。
- 现有 Mac mini LDDC 可从扩展弹窗显式配置；Bearer 只保存在本机扩展 storage，bundle/源码不含密钥，optional host 只限当前 Tailscale 服务。翻唱命中原唱仍只列候选。
- 聚焦 10 个测试文件 28/28、歌词包 16/16、typecheck 与 extension 双构建/CSP 通过；已实时验证酷狗 HTTP 搜索与 LRC 下载。Chrome 内部扩展页不可由浏览器控制接管，真实 reload、LDDC 配置和 YTM 命中仍为人工门。见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-21 · YTM 原生 Lyrics direct Shadow Column 真实验收

- 真实 Chrome 证明 extension iframe 即使资源可读也无法在 YTM 内完成 ready；改为 production IIFE `content-ui.js` 直接挂入 Shadow DOM，两个隔离脚本通过 DOM marker 与 attempt-scoped ready/error/dispose 事件握手。
- 接管改为事务：React ready 前原生歌词保持可见；runtime 缺失、渲染错误、超时、tab/renderer 切换或迟到 ready 均恢复/保留原生节点。renderer 只认自身 `page-type`；tab 歧义只由真实点击消歧。
- 修复 React bundle 残留 `process.env.NODE_ENV` 的启动崩溃，并把 `process.env`、bundle 加载顺序、资源存在与源码/产物一致性加入构建门禁。
- Chrome 实测 direct Column 可见；Up next 时 host=0 且原生恢复；切回 Lyrics 时 host=1 且无新版 LyricStage error/warn。旧 Errors 面板的 `allowfullscreen` 是已删除 iframe 版本的历史条目。
- 聚焦 4 文件 25/25、typecheck、extension 双构建、CSP/语法/产物一致性通过。自动命中歌词、全屏与 seek/换歌/多标签继续保留为后续门。见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-21 · YouTube Music Companion 改造为增强原生歌词

- 原生 Lyrics 是唯一入口：新增 MAIN-world `page-bridge.js` 从 Polymer data 识别 `MUSIC_PAGE_TYPE_TRACK_LYRICS` 并写入 DOM marker；隔离世界 `content.js` 只消费 marker，在原生 Lyrics 激活时挂载于原生 renderer 内部；删除自定义 `LYRICSTAGE` 标签与 sibling panel；原生歌词节点仅隐藏（精确保存与恢复 display/hidden/aria-hidden/inert）。
- 宿主替换与异步激活：切换新 renderer 时清理旧 host、旧 probe 并恢复旧节点；Popup/Open 激活增加有界异步重试与响应通道。
- Column 视觉重做：iframe / body / Column 根背景透明融入 YTM 面板，采用 YouTube Sans / Roboto 自适应字号、柔和临近行、连续渐变逐字扫亮与紧凑工具栏（状态/版本/导入/全屏）。
- 键盘与错误边界：Column `Esc` 不切走标签，全屏 `Esc` 只回退侧栏，`F` 触发全屏（带修饰键/输入框保护）；新增 React 根级 `ColumnErrorBoundary` 与静态 boot 联动避免纯黑面板。
- 源码实现与自动检查完成；真实 Chrome 运行验收待完成。见 `cairn/lyricstage-platform-architecture.md`、`web/apps/youtube-music-companion/README.md`。

## 2026-08-21 · 终审返修：完整正文 / iframe Esc / error 导入 / 版本保留

- BLOCKER：word-timed 行以 `line.text` 为唯一正文，words 只锚定时间；对齐失败回退整行。Column Esc 经校验 `event.source === iframe.contentWindow` 的 `lyricstage-request-hide` 通知父脚本隐藏；全屏 Esc 仍先回 Column。
- MEDIUM：error 与 miss 同样提供 LRC/JSON 导入；footer「版本」在 singing 也可打开候选面板，选择后保留完整候选集，换歌清空。
- 新增 `timedLineText` 与 content hide 源校验测试。真实 Chrome 门未关。见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-21 · 返修 Column Stage 五项运行风险

- 更正：Fullscreen API 必须在按钮/`F` 用户手势栈内 `requestFullscreen`，成功后才切 `presentation`；失败留在 Column，侧栏不再挂 StageCanvas/demo 预览。无逐字时 active 行整行高亮，不做 line-duration mask。content.js 在 stop/重挂时清理 readyWatcher 与 2s timeout。自动滚动仅在 active line key 变化时触发。
- Vitest / typecheck / build:extension / CSP 需继续通过；真实 Chrome reload 验收仍开放。见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-21 · YTM Column Stage + Fullscreen 双模式落地

- 按 V1.0 规格：同级 LyricStage tab 保留；侧栏改为 React DOM `ColumnStageView`（header/stream/footer/state-card），不再把 `StageCanvas` 塞进窄栏；全屏按钮/`F` 挂载现有 Canvas，`Esc` 回 Column。
- 去黑：`stage.html` 静态 boot、扩展 `base:'./'` 相对资源、iframe ready 探测与资源故障条（区别于 miss）；生命周期状态可见。
- 复用既有 YTM 桥/时钟/歌词 resolve；contracts 未改。Vitest 28、typecheck、`build:extension`、CSP 通过。真实浏览器 reload 验收仍为人工门。见 `cairn/lyricstage-platform-architecture.md`、`web/apps/youtube-music-companion/README.md`。

## 2026-08-21 · LyricStage 进入 YouTube Music 原生同级标签区

- 用户要求不再使用额外页面或全屏覆盖层。YTM content script 现把 `LyricStage` 作为 Up next / Lyrics / Comments / Related 的 peer tab 注入原生 tablist，并把隔离的 extension Stage iframe 作为 `ytmusic-tab-renderer` 的 sibling panel；原生歌词 DOM 与播放链路不删除、不接管。
- 进入 LyricStage 时才取得原生 renderer 所有权并精确快照 inline display 与 `aria-hidden`；点击任一原生 tab、按 `Esc` 或停止脚本时恢复一次，隐藏态 heartbeat 不再改写宿主。Polymer 重绘由幂等挂载、MutationObserver、`yt-navigate-finish` 与 500ms 心跳兜底，extension context 失效时会清理并恢复宿主。
- companion 聚焦测试 7/7、TypeScript typecheck、extension build 与 MV3 CSP 门通过；源码与生成 content script 字节一致，旧 overlay/launcher 静态命中为 0。Manifest 只保留 `storage` 权限，YTM tab 定位改为 host-permission 范围内的 URL query。最终窄审计无残留代码问题；真实扩展 reload 后的同级标签、响应式布局与切入/切回仍是人工验收门。当前真相见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-21 · LyricStage 改为 YouTube Music 页内舞台

- 用户明确不想另开 Stage 标签页。YTM content script 现以 Shadow DOM 注入 `LYRIC STAGE` 按钮与同页全屏覆盖层；覆盖层加载 extension-origin 的 `embedded=1` Stage，只显示整屏 Canvas。扩展弹窗也改为唤起当前权威 YTM 标签页里的同一覆盖层。
- `Esc` 与右上角关闭按钮只撤下视觉层，YouTube Music 继续拥有音频、播放控制和唯一时钟。歧义歌词候选与搜索错误可在嵌入层内处理；严格自动命中时状态层自动消失。
- Manifest 只额外公开 Stage HTML/构建资产给 `music.youtube.com`，没有扩大到任意站点。content script reload 终止时会一并移除注入根、runtime listener 与键盘监听。
- Vitest 25/25、TypeScript typecheck、extension build、CSP 与三份脚本语法检查通过；真实 YTM 页内覆盖层仍需用户 reload/刷新后确认。当前真相见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-21 · YouTube Music 自动歌词第一版

- 用户明确要求 Web Stage 像手机端一样自动搜索歌词。YTM 换歌现以 `videoID + 标题 + 歌手 + 时长` 触发独立歌词任务：先查扩展本地缓存，再由 Service Worker 请求公开 LRCLIB；歌词请求不读取 Cookie/音频，也不进入宿主播放链路。
- 只有标题、歌手匹配、时长差 ≤4 秒且含同步轴的结果才自动装入 `LyricDocumentV0`。最多 5 个歧义候选显示在 Stage 供显式选择；miss/错误继续保留手动 LRC/JSON。换歌、切本地或手动导入都会拒绝旧任务回写。
- 缓存按 YTM track ID + 当前元数据指纹隔离：match 30 天、candidate 1 天、miss 6 小时，最多 100 首。Manifest 新增 `storage` 与 `https://lrclib.net/*`，没有新增服务密钥。
- 真实 LRCLIB `/api/get` 已用《You & 合図》验证：`35193797` / 音乃瀬奏 / 159 秒 / 非纯音乐 / 41 条时间戳，与当前 YTM 159 秒录音严格一致。Vitest 25/25、TypeScript typecheck、extension build、CSP 与脚本语法检查通过；真实扩展自动显示仍需用户 reload 后确认。当前真相见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-21 · 修复 YouTube Music 扩展 Stage 白屏

- 真实 YTM 验收已播放《You & 合図》（`ZmCRFGcON-I`，159 秒）并成功打开扩展 Stage；随后用户确认 Stage 整页空白。根因不是安装或 YTM 连接，而是合同层在扩展页面启动时用 Ajv 动态生成校验函数，触发 Manifest V3 CSP 拦截。
- 合同 validator 现由构建脚本预生成静态 ESM；扩展产物新增 CSP 门禁，出现 `eval`、`new Function` 或 CommonJS `require` 会直接令构建失败。运行时仍保留同一 schema 与业务门禁，不放宽歌词合同。
- 重新加载扩展后，原 YTM 标签页里的旧 content script 会失去 extension context；旧实现仍按 500ms 心跳调用 `sendMessage`，因此刷出 `Extension context invalidated`。脚本现会捕获同步失效、撤销媒体监听/MutationObserver/定时器并静默停止；刷新 YTM 后由 Chrome 注入新版。
- Web Vitest 21/21、普通 Web build、extension build、脚本语法与 `git diff --check` 通过；扩展产物 CSP 扫描通过。用户仍需在 `chrome://extensions` 重新加载、刷新 YTM 并复看真实 Stage，才能关闭端到端 UI 验收。当前真相见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-21 · YouTube Music 成为首个 Web 在线来源

- 新增 `web/apps/youtube-music-companion` Manifest V3 扩展：YTM content script 只读取当前页面展示元数据与 HTMLMediaElement 播放快照，Service Worker 把单一权威来源送给独立 Stage；不读取 Cookie、不保存媒体 URL、不下载或转发音频。
- Web Stage 新增 `PlaybackClockV0` 与版本化 companion contract。本地模式仍由唯一 `<audio>` 拥有时钟；YTM 模式在两次权威快照间按 playbackRate 平滑采样并持续重校准。暂停冻结、过期快照拒绝、多标签择主和来源断连都有纯逻辑门禁。
- Stage 默认从扩展打开时选择 YouTube Music，普通网页仍默认本地音频；切歌立即撤下旧歌词，避免错词继续演出。第一版播放/暂停/seek 仍由 YTM 标签页拥有，Stage 只提供返回入口。
- TypeScript typecheck、19 项 Vitest、普通 Web build、extension build、Manifest/脚本静态检查均通过；本地 Stage HTTP 200 并已打开预览。真实加载扩展后的 YTM 页面验收尚未执行。当前真相见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-21 · Phase 06 启动并落地全屏 Web Stage Alpha

- 新增独立 `web/` TypeScript/Vite 工程：React 只管理排练控制，本地 `<audio>` 拥有唯一时钟；Canvas 2D prepared runtime 支持完整换行、逐行/真实逐字 reveal、双声部、static-first fallback、Rail Handoff 与 Chorus Memory，并可进入单窗口 Fullscreen。
- 来源无关合同已有 Recording/Lyric/Director/Manifest JSON Schema、Ajv 双层门禁与六组无版权 fixtures；本地 LRC 不伪造逐字。Swift 测试 target 直接打包同一 fixtures，iPhone 17 Pro / iOS 27 聚焦 3/3；TypeScript/Vitest 14/14，typecheck 与生产 build 通过，本地 preview HTTP 200。
- 当前只完成实现与自动检查，未做浏览器视觉/交互 QA、真实音频/LRC 的 20 次 seek、1080p 整段 rAF 性能或 Windows Edge 验收；AudioStructure schema 也仍待补。没有修改 iOS 播放路径、Worker 或线上服务，没有部署。当前真相见 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-21 · 写出来源无关 LyricStage 与全屏 Web Stage 第一版计划

- 用户把长期目标从单一 Bilibili iPhone 客户端扩展为可承接 Bilibili、YouTube Music、其他播放器与本地音频的歌词可视化演出生态，并明确 Web 应使用整个屏幕，而不是受手机小窗口限制；第二屏/投影是本计划提出的 v0 形态。
- 新 Phase 06 草案把 v0 建议定义为「本地音频 + 时间轴歌词 -> 排练/可选 Luna -> 第二屏 1080p 全屏 -> 断网完整演出」。共享歌词/音频结构/Recipe 语义，布局和预算按 `fullscreen16x9` 单独编译；正文继续 static-first。
- 计划分 M0 基线、M1 合同/fixtures、M2 全屏本地 Stage、M3 音频事实、M4 Luna/演出包、M5 Show Mode；建议确认后只先启动 M0–M2。当前仅文档草案，未创建 Web 工程、未改变 `.planning/STATE.md`、未改 iOS/Worker/线上服务。见 `.planning/phases/06-lyricstage-platform-and-web-reference/` 与 `cairn/lyricstage-platform-architecture.md`。

## 2026-08-21 · V4 音频结构导演与四种 Scene Recipe 上线

- 新增独立 V4 链路：已缓存音频编成有界 `AudioStructureScoreV4`，Gemini 只返回 typed motif 与 sparse Scene Recipe，本地继续拥有歌词正文、逐行/逐字 reveal、精确音频地标和完整 V5.3 fallback。首发 Rail Handoff、Semantic Lens、Chorus Memory、Silence Aperture；结构时钟与歌词 offset 分离，未揭示文字严格不可见，长句完整换行。
- Debug Now Playing 已有显式 V4 生成、摘要、清除和缓存恢复；请求以 88KiB 软预算确定性减少细节，绝不截歌词。V4 独立 App store、Worker KV、grammar/director version 与 kill switch，不覆盖 V1–V3。
- 用户指出默认歌词持续跳动后，运动 ownership 收口为「静止是常态」：普通词只在落点后短暂 1.5% 轻触，36% 进度后严格归零；Cosmic Drift 与 tracking breath 都变成一次性入场；普通 beat/onset 不再缩放 V3/V4 正文，只允许强事件点亮段落装饰。明确的 Impact、Heartbeat 与结构转场保留。
- Worker `79c3d38c-363f-4c5d-b76b-625c16b3bdf1` 已启用 `/v4/lyrics/direct`，并在 98KB 门限内完整保留 V4 单行歌词，不再继承旧 500 字符静默裁剪；Worker 54/54。首个 12 行 canary 冷请求 9.10s、2 Section / 4 Recipe、非降级，复打 83ms KV hit；最终部署的新 4 行请求同样非降级并产出有效 `chorusMemory`，复打命中独立 KV，六条路由无令牌均保持 401。iPhone 17 Pro / iOS 27 模拟器 V4 24/24，默认歌词与 V4 UI 各 1/1；专用 V4 fixture 的最新 240 帧 Canvas draw p50 0.93ms、p95 3.30ms、p99 5.56ms、最大 12.01ms，0 帧超过 16.67ms。设计、回滚与证据见 `cairn/lyric-stage-v4-scene-recipe.md`、`cairn/lyric-performance-director.md`。

## 2026-08-21 · V3 通用歌词舞台完成本地事实层、线上导演与模拟器性能验收

- V5.3 收束为单一链路：真实歌词时轴与声部 + 已缓存音频的 `AudioPerformanceMapV2` + 可选 Luna V3，最终编译为预准备运行时；Luna 与音频都不能改歌词正文或 reveal 时间。默认播放不联网，V5.1/V5.3 生成都只存在于明确的 Debug 操作；长歌词完整换行、无省略号。
- Cloudflare Worker 首个 V3 生产版本 `414458cf-77d5-4bc8-ba10-ff6a6aebbb6a` 已启用 `/v3/lyrics/direct`；真实线上请求 23.35s miss / 53ms hit，旧 normalize、V1、V2、embellish 回归正常。含 embellish、无 V3 的回滚基线为 `1b07471b-49e4-48cf-adb1-c3ca591db573`。
- 用户一次真实 App 请求耗尽原 38 秒 V3 预算后，只将 V3 Luna 单次/总预算放宽到 55/60 秒并部署 `060adf92-75b7-4719-a55c-3936ce5e727e`；全新冷请求 18.22 秒非降级，复打 71.8ms hit。上一 V3 版本 `414458cf-77d5-4bc8-ba10-ff6a6aebbb6a` 保留为直接回滚点。
- 放宽预算后用户在真实 App 完成首次约 3 分钟生成：设备缓存确认 176.47 秒音频图有效，40 行 V3 演出于 01:54:54 JST 通过本地门禁并写入，得到 7 Section / 16 Scene；首次总耗时包含本地整曲分析，后续同输入可复用两层缓存。
- 经用户指定，normalize、V1、V2、V3、embellish 全链路切换到 CPA `gemini-3.7-flash-high`，独立 CPA Secret 与旧 Secret 并存；所有缓存/导演版本已 bump。生产 `52cc64da-2efd-4ce6-84ad-df1472b9e692` 五条冷请求均非降级，分别为 4.63 / 14.79 / 19.63 / 6.50 / 5.95 秒，V3 复打 321ms hit；Worker 44/44。
- iPhone 17 Pro / iOS 27 模拟器聚焦测试 26/26；Worker 43/43；Python 合同 2/2。Hook、Dialogue、Final 各 240 帧的 Canvas draw 均无超过 16.67ms 的帧，最重 p99 7.04ms、最大 12.87ms；冷编译 17.18–24.01ms。当前真相与边界见 `cairn/lyric-performance-director.md`。

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
