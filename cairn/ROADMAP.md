# Bilibili Music 路线图

**当前焦点**：Phase 06 的 06-06 已完成实现、自动门与 Director v2 部署：Stage-first Now Playing、真实封面/进度/权威运输控制、三层 Reading、稀疏 Hero/Duet/Aperture、Performance Direction Skill 与双端 EffectRecipe 验证均已落地。最新 `extension-dist` 已在 Chrome 重载，并修复 YTM 复用媒体内部轴导致的混合时钟；仍需关闭真实歌曲视觉/seek/换歌门。iOS 日用路径与 LDDC/高精度歌词只保留剩余真机 UAT。指针见 `06-06-DESIGN.md`、`06-06-AMLL-ADR.md` 与 `cairn/lyricstage-platform-architecture.md`。

> 本文件只提供跨会话的精简导航；执行阶段、完整范围和需求追踪以 `.planning/ROADMAP.md`、`.planning/STATE.md` 与 `.planning/REQUIREMENTS.md` 为准。

## 里程碑

- [x] 完成 v1 四个阶段的自动化稳定性与界面收口工作。
- [x] 确认并启动 Phase 06：冻结来源无关合同与 golden fixtures，建立本地音频 + 时间轴歌词的全屏 Web Stage；不先复制完整 BiliMusic Web 客户端。
- [ ] 完成 06-01/06-02 剩余门禁：AudioStructure schema、真实本地音频/LRC、20 次 seek、1080p 大屏视觉与整段 rAF 性能。
- [ ] 关闭 06-06 最后真实 Chrome 门；实现、自动测试、性能预算、AGPL/NOTICE 与 OCI Director 1.2.0 部署已完成。
- [x] 在真实 Chrome 验证原生 Lyrics direct Shadow Column：无自定义 tab/overlay、React ready 后接管、切出恢复、切回唯一 host，且新版无 LyricStage 运行错误。
- [ ] 继续 YTM 真实验收：严格自动歌词/候选、全屏进出、暂停、seek、换歌撤词、多标签择主与关闭来源断连。
- [ ] 重新加载扩展后确认《You & 合図》同版本自动装入，以花譜《修羅》确认 `by` 清洗/原唱回退，并以存流《泥中に咲く》确认「歌名 - 原唱 covered by 翻唱者」拆解与翻唱同版本优先；同时复验缓存恢复、歧义候选手选、失败手动导入，以及 LDDC 优先和关闭后的 LRCLIB/酷狗回退。
- [ ] 在用户自己的 iPhone 上完成首播、搜索、推荐、图片内存、播放器手势和布局的最终日常路径确认。
- [ ] 在真实收藏夹与长标题场景确认纯海报瀑布流的浏览密度，以及播放器双色光场在音乐/MV 两态的稳定性。
- [ ] 在真机确认首页点击直接打开 LNPopup、mini/full 跟手开合和长时间跨 Tab 使用时的内存/流畅度。
- [ ] 用真实收藏歌曲验证 BM 标题整理与网易云/酷狗/QQ 候选质量，并确认歌词翻译、逐字高亮和偏移校准的日常体感。
- [ ] iOS App 改用自建 `/v1/music/normalize`，从本地非提交配置注入 Bearer 密钥；BM 仅在明确决定保留回退时存在。
- [x] 经用户明确授权部署 `/v1/lyrics/direct` v3，完成逐行 1–3 行文本构图、九种稀疏动效、完整长句 UI、KV 命中、鉴权与旧 normalize 端点回归。
- [x] 将歌词导演升级为 v4：真实逐字 Sweep、稀疏 Impact / Stretch / Echo Trail、双端范围校验和逐字指纹失效已上线，Debug 真机包已安装。
- [x] 修复 Luna 真实长歌词的 25 秒整请求超时：v4.2 保留全曲 outline、详细逐字时间分段并行生成；iPhone 当前「千鳥」42 行 / 407 word 的线上请求已非降级完成。
- [x] 部署 Luna v5 两阶段导演：全曲 Stage Bible 与分段 stageDirectives 已在线返回；包含 V5 舞台的 Debug 包已覆盖安装并启动于 iPhone 17 Pro。
- [x] 经用户授权部署 Luna V5.1 `/v2/lyrics/direct`：精确 Actor/Event 合同与空场景降级已上线，真实鉴权请求及旧 V1 回归通过；真机包安装与四首视觉 A/B 仍分开验收。
- [x] 修复真机选择 V5.1 后无动画：无缓存时自动请求线上导演，基线 hold 呼吸不再被 Section 预算删除；修正版 Debug 包已覆盖安装并启动。
- [x] 用「You＆合図」真实逐字轴与 AAC 特征完成 176.518 秒 V5.2 专曲全曲舞台：全曲 beat/downbeat/onset/energy 驱动事件与物理场；精确逐字轴独占 reveal，音频 accent 不再延后歌词。14 个跨全曲关键帧检查通过。下一步先由用户真机判断，再抽象通用 iPhone 分析器和 Luna 调度合同。
- [x] 以「You＆合図」作为基准曲实现 V5.3 通用全曲编舞：无 BVID/标题/绝对秒/固定行号分支，重复 Hook 簇自动 call→echo→converge→lock，普通段落使用七种通用构图；规则 19/19、10 关键帧 UI 1/1，签名包已安装启动。下一步由用户真机 A/B，再把真实音频结构与 Luna Stage Bible 接到同一规划合同。
- [x] 曾在 iPhone 17 Pro 接入 Qwen3 0.6B 4-bit；后续真实操作出现两次 MLX Metal 完成队列 `SIGABRT`，用户入口现已停用，设置只保留删除模型。算法代码仅作 smoke test 资产。
- [x] 修复日语逐字轴坍缩、局部行首漂移与整曲 LRC 错位：逐字生成前以 ASR 多行稠密共识估计全局平移，重复副歌离群和非线性漂移不写入；「You＆合図」真机得到 -6.241 秒通用校准且无单曲手工 offset。
- [x] 在 RTX 5070 Ti Windows 主机部署高精度来源：人声分离＋Qwen BF16 两遍局部对齐＋WhisperX CTC 复核经认证异步接口接入 App；「You＆合図」真实 API 闭环、缓存复用、质量门禁、Windows 登录自启与 iPhone 17 Pro 包安装均已验证。
- [x] 实现独立 LDDC 私有聚合服务与 Swift 客户端；真实收藏 PoC 由 2/20 提升到 13/20 精确逐字，服务/App 双重门禁、直连回退和本机真请求已验证。
- [x] 在 Mac mini Tailscale 私网部署 LDDC 服务，用钥匙串注入 App Bearer，并完成远程 health/401/真实逐字候选验证与 iPhone 覆盖安装；Windows 临时部署已停用并保留可恢复目录。
- [ ] 在 iPhone App 内对翻唱同版本、原唱参考和直连回退路径分别验收。
- [ ] 再用至少两首不同结构歌曲验证 Windows 共识门禁与听感；当前已验证「You＆合図」和《青い珊瑚礁》，并行声部明确拒绝主机覆盖。
- [ ] 在 iPhone 17 Pro Debug 对真实歌曲启用 V5 舞台并重新生成 Luna 演出，确认原生 directive 体感、重启缓存与本地导演 A/B；Release 真机确认 120Hz、LNPopup 开合和长时间播放帧率。
- [ ] 用固定四首样本做 V5 vs V5.1 vs 本地导演 A/B；V2 已部署但不替换默认舞台，只有 V5.1 明显更好才考虑改默认。
- [ ] 真机整首比较 V5.2 专曲舞台与 V5.3 通用舞台；若 V5.3 的段落对比和 Hook 递进成立，再以至少两首不同结构歌曲检验构图语法，不为基准曲增加专用分支。
- [ ] 根据真机结果决定是否默认启用 V5.1，并为 API、认证、缓存或音乐功能选择下一项明确范围。

## 开放问题

1. Stage Alpha 的 Rail Handoff / Chorus Memory 是否真正使用了整块画幅，而不是形成新的桌面窄列？
2. 用真实 Hi-Res 曲目验证 MIME、解码和音质标识；将尚未解析的 `dash.dolby` 作为独立功能接入并验证。
3. 最终真机使用是否还存在其他会阻断日常听歌路径的 v1 问题？
4. 若继续 iOS backlog，API/认证、缓存可靠性和音乐功能中哪一项应最先启动？
5. App 切换自建服务后，BM 是否完全移除，还是只保留为关闭默认的诊断回退？
6. 原生感收敛与歌词重构（Phase 05）已按 05-01…05-05 落地；真机确认歌词页、队列往返和浅色首页顶部后关闭。
