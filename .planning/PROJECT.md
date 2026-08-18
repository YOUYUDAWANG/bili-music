# Bilibili Music

## What This Is

Bilibili Music 是一个个人自用的 iPhone 音乐客户端，从 B 站收藏夹和内容里提取适合听歌的音频、MV 与合集。系统交互沿用 Apple Music 的成熟模型，内容视觉由 B 站 16:9 封面驱动。它不是完整的 B 站第三方客户端，也不把薄弱的推荐算法作为主体验；打开 app 后直接进入纯粹的私人海报瀑布流，重点是听歌、本地缓存、搜索、收藏、歌词和队列。

当前代码已经是一个可运行的 SwiftUI iOS app，接入了 Bilibili 私有 Web API、AVPlayer、本地缓存、收藏夹、歌词和播放器 UI。v1 稳定化已经覆盖首播、搜索、推荐刷新、图片内存、播放器滑动动画和主要手势冲突；Phase 4 又完成了一轮窄范围 UI 收口，让搜索、列表、播放器工具栏和品牌色更统一。下一步应先做最终真机确认，再决定是否进入 v2 的 API/auth/cache/音乐功能打磨。

## Core Value

让音乐尽快、稳定地响起来；当功能冲突时，播放启动速度和不中断播放优先于推荐、歌词、MV、UI 动效和其他增强体验。

## Requirements

### Validated

- [x] iOS SwiftUI app 已建立，使用单一 app-wide `PlayerEngine` 管理播放状态和播放器展示。
- [x] 可以通过 Bilibili API 解析视频信息、音频流、MV 视频流、搜索结果、相关推荐、收藏夹和合集。
- [x] 音频播放走 AVPlayer，并支持后台音频、锁屏信息和远程控制。
- [x] 已有本地缓存体系，可以下载完整音频文件并从缓存优先播放。
- [x] 已有封面音乐库首页、搜索页、收藏夹、缓存库、设置页和播放器页。
- [x] 已有音乐内容过滤、搜索分页、搜索历史、播放历史、播放次数、队列、相关推荐和播放模式的基础实现。
- [x] 已移除 LRCLIB，使用 BM 整理 B 站标题并直连网易云/酷狗/QQ 音乐；支持自动匹配、手动候选、翻译、逐字歌词和用户偏移持久化。
- [x] 自建 Cloudflare 元数据清洗 Worker 已部署并通过中日文线上样本验证；iOS App 接入仍待完成。
- [x] 已有音乐/MV 切换、Wi-Fi 优先 MV、音频质量和下载质量偏好。
- [x] 已有代码库地图和架构文档，后续规划可基于 `.planning/codebase/` 继续推进。
- [x] 播放启动关键路径已测试保护：点歌后先设置当前曲目，只等待缓存、已准备音频或一次新音频流解析，然后请求 AVPlayer 播放。
- [x] 首次观察到播放后只调度历史、封面和歌词；MV 预取、推荐、队列预取和自动缓存不再由首播路径触发。
- [x] 已准备的远程音频流失败时会失效内存缓存并自动重试一次新音频流，失败后不会循环。
- [x] 搜索聚焦和普通输入不再触发 Bilibili 搜索、WBI 预热或结果预加载；网络搜索保留在显式提交、重试、更多结果和分页路径。
- [x] 空搜索页可以只用本地数据展示搜索历史、最近播放和已缓存歌曲。
- [x] 首页不再生成推荐；封面快照、本地缓存和播放历史会先于收藏夹网络同步显示，点歌不会清空或重排封面墙。
- [x] 首页收藏夹封面持久化并设置 15 分钟刷新窗口；切换收藏夹、登录态变化和手动下拉才强制同步。
- [x] 图片加载按 URL + 目标像素尺寸缓存和合并请求，列表、mini-player、播放页和锁屏封面不会无目标地保留完整大图解码。
- [x] 后台和内存警告会释放可重载的解码图片，并通过测试确认不会清空当前播放歌曲、队列或队列位置。
- [x] 播放器基础手势阈值已有纯逻辑和 UI 回归保护：mini-player 上滑打开、微小拖动不误开、顶部下拉收起、列表区域拖动不误收起。
- [x] 搜索结果按请求身份、查询词和搜索模式隔离；旧请求不能覆盖当前结果。
- [x] 搜索分页保留已有结果、分页失败可重试，并且每一页都继续应用音乐过滤。
- [x] 播放器推荐列表点击歌曲后保持当前可见列表稳定，Home 与 Now Playing 推荐刷新状态分离。
- [x] 搜索和推荐默认展示面会继续过滤明显非音乐内容。
- [x] 播放器下滑最小化、当前独立队列页滚动和进度条 scrub 已有显式手势所有权规则和 compact/modern UI 回归保护。
- [x] 播放器布局密度已有 `iPhone SE (3rd generation)` 与 `iPhone 16` 的元素存在、顺序、重叠和底部空白边界检查。
- [x] 搜索页已移除可见 MV/扩展搜索 scope；聚焦空搜索框时只显示搜索历史或历史空状态。
- [x] 搜索结果行扩大了点击反馈，结果展示合并为最佳匹配和音乐结果。
- [x] 工具页强调色已从粉色调整为更克制的 B 站蓝青；沉浸式首页和播放器改由真实封面主导。
- [x] 首页保留用户确认更好看的“1 张全宽 + 4 张双列”连续海报瀑布流，不加入横向滚动或多模板切换。
- [x] 首页在不改变上述骨架的前提下，以 8pt 页面边距、4pt 组内 / 8pt 组间和 4pt 圆角建立层级；移除取色接缝与封面视差，以单一 3pt 真实进度轨表达当前播放。
- [x] 播放器保持 16:9；首页封面点击、mini player 和 full player 统一使用 LNPopup 原生开合，不再维护 Home 自制 matched-geometry 转场；封面接近屏幕边缘，字幕沿封面左缘排布，背景收敛为封面双色光场。
- [x] 列表标题清洗已改为高置信结构才展示清洗结果，避免纯噪声去除导致错标题。
- [x] 播放器工具栏改为更接近 Apple Music 的紧凑分组动作区，MV/音乐切换保留在同一组内。

### Active

- [ ] 稳定播放与性能：首播要尽快出声，避免启动播放时被推荐刷新、歌词、MV、图片、预加载或历史写入阻塞。
- [ ] 搜索交互性能：第一次点搜索框不能卡顿，后续需要继续做真实设备交互体验验证。
- [ ] 最终真机确认：v1 的首播、搜索、推荐稳定性、图片内存、播放器手势和布局已过自动化验证，但仍需要用户自己的 iPhone 做一轮日常路径确认。
- [ ] 音乐内容质量：合集入口和少数边界内容仍需继续打磨；搜索默认面继续音乐过滤，首页内容质量由用户指定的音乐收藏夹保证。
- [ ] 队列和推荐模型：当前独立队列页统一展示 Queue 与 AutoPlay 推荐；电台模式和普通播放列表必须有明确差异，历史三态抽屉不再作为当前交互模型。
- [ ] 收藏夹与合集：收藏支持默认收藏夹和长按选择收藏夹；播放合集内歌曲时识别合集、定位当前歌曲，并可切换队列到该合集。
- [ ] 缓存可靠性：缓存页面继续作为缓存库而不是历史页，后续补缓存配额、删除、失败提示和离线播放验证。
- [ ] 认证生命周期：401/登录失效要被识别并引导重新登录，不能只显示泛化接口错误。
- [ ] 回归测试：关键修复至少覆盖搜索 store、播放器 chrome、推荐刷新稳定性和队列/播放模式的可测试逻辑。

### Out of Scope

- App Store 上架和公开分发 — 这是个人自用 sideload app，审核合规不是当前目标。
- 完整 B 站客户端 — 不做动态、评论、弹幕、社交、私信、投稿、直播、会员中心等非音乐核心功能。
- 自建后端服务 — 当前优先保持单机 iOS app，减少运维和账号安全面。
- 复杂社交歌单系统 — 优先复用 B 站收藏夹、合集和本地队列，不做公开分享生态。
- 完整无损/大会员能力承诺 — 可以支持账号可访问的最高音质，但不承诺绕过 B 站限制。
- Android、macOS、Web 版本 — 当前只面向用户自己的 iPhone。
- 视觉营销页或落地页 — app 打开后应直接进入可用的音乐体验。

## Context

项目最初目标是模仿 YouTube Music 做一个 Bilibili Music，后续根据个人开发者实现成本和系统风格，播放器与系统交互转向 Apple Music。由于 B 站推荐内容质量无法稳定达到音乐产品标准，首页进一步改为封面驱动的私人音乐库：收藏封面负责发现，播放器负责沉浸，相关推荐只作为续播和电台的次级能力。

代码层面已经有不少功能，但几个核心类型过大：`PlayerEngine` 集中处理播放、队列、MV、歌词、推荐预加载、历史、远程控制；`NowPlayingView` 集中处理播放器布局和大量交互；`BiliClient` 同时承载多个 Bilibili API 域。后续性能修复要避免继续把所有副作用塞进播放启动路径。

已有验证结论：

- Bilibili playurl 能拿到 DASH 音频流，m4a 带 Referer 和 UA 可播放/下载。
- 搜索和推荐接口依赖 WBI 签名，已有 Swift/Python 验证与 app 内实现。
- 音频流 URL 有时效性，不能持久化 URL，只能持久化 bvid/cid 和缓存文件。
- 未登录可以播放不少内容，但高音质、收藏夹、个性化推荐和收藏写入依赖 Cookie。
- B 站字幕常常不是歌词；歌词由 BM 整理搜索词后从音乐平台取得，自动失败时仍保留手动搜索入口，不 fallback 到 B 站自动字幕。

## Constraints

- **Tech stack**: SwiftUI + Swift 5.10 + iOS app target；继续沿用现有工程，不引入不必要的第三方依赖。
- **Platform**: 面向用户自己的 iPhone；安装方式围绕 sideload/AltStore，而不是 App Store 审核。
- **Playback priority**: 播放启动必须先于歌词、推荐、图片预热、MV 切换、自动缓存等增强任务。
- **API dependency**: Bilibili 私有 API 和 WBI 签名可能变化；所有 endpoint 变化应隔离在 API 边界。
- **Auth**: Cookie 存 Keychain；任何 401/失效状态都应转换成清晰的重新登录路径。
- **Offline cache**: 缓存文件在 app Documents 下，不能只维护 JSON 索引而忽视孤儿文件、磁盘空间和失败恢复。
- **UI**: Apple Music 只作为系统交互参考；原生 Tab Bar 与 LNPopup mini/full 开合保持 Liquid Glass，首页和播放器使用横版影像唱片机视觉。稳定性和手势一致性高于封面原位转场；搜索、缓存等工具页保持高效率，播放器必须适合单手触控和反复使用。
- **Testing**: 对播放、搜索、推荐和缓存这类高风险逻辑，优先补可稳定运行的单元测试和少量关键 UI 测试。

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| 个人自用 iPhone app，而不是公开第三方客户端 | 降低审核、合规、后端和跨平台成本，聚焦真实使用体验 | Good so far |
| 系统交互从 YouTube Music 转向 Apple Music | Apple Music 的开合、队列与系统导航更贴近 iOS 原生音乐使用习惯；不再把它当作内容视觉模板 | Implemented |
| 工具页强调色从粉色换为 B 站蓝青 | 蓝青适合搜索、缓存、设置和普通列表；沉浸内容不受固定品牌色约束 | Implemented |
| 系统玻璃做外壳，内容由真实横版封面主导 | 实图验证高饱和生成撞色和多模板首页都会削弱真实封面的连续性；首页保留纯瀑布流，播放器使用电影字幕与双色光场 | Implemented, needs device feel check |
| 播放器开合统一由 LNPopup 管理 | Home 自制转场在真机暴露性能差和多处 bug；用户明确选择放弃封面原位转场，首页点击、mini/full 开合回归同一 LNPopup 生命周期 | Implemented and simulator-regression-tested |
| 播放启动优先于所有增强体验 | 用户明确要求“让音乐响起来是第一优先级” | Good so far |
| 复用 B 站收藏夹和合集，而不是先做自建歌单系统 | 减少数据模型复杂度，利用已有内容组织方式 | Pending stabilization |
| 歌词优先用在线歌词 API，B 站字幕不作为可靠歌词源 | B 站自动字幕容易出现错误内容和非歌词标记 | Good so far |
| 音频质量和下载质量分开 | 在线播放和缓存占用的用户需求不同 | Implemented, needs UI/verification |
| 推荐必须音乐化 | B 站默认推荐容易混入非音乐内容，不符合产品目标 | Active |
| 首页退出推荐竞争，改为收藏封面墙 | 推荐质量不可控，而用户自己的音乐收藏夹稳定、可解释，也更适合本地播放器式体验 | Implemented |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `$gsd-transition`):
1. Requirements invalidated? Move to Out of Scope with reason.
2. Requirements validated? Move to Validated with phase reference.
3. New requirements emerged? Add to Active.
4. Decisions to log? Add to Key Decisions.
5. "What This Is" still accurate? Update if drifted.

**After each milestone** (via `$gsd-complete-milestone`):
1. Full review of all sections.
2. Core Value check: still the right priority?
3. Audit Out of Scope: reasons still valid?
4. Update Context with current state.

---
*Last updated: 2026-08-14 after preserving the approved UI and repairing the cover-transition architecture*
