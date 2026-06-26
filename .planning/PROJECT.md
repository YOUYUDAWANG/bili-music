# Bilibili Music

## What This Is

Bilibili Music 是一个个人自用的 iPhone 音乐客户端，从 B 站内容里提取适合听歌的音频、MV、收藏夹和合集，用接近 Apple Music 的方式播放和管理。它不是完整的 B 站第三方客户端，重点是听歌、本地缓存、搜索音乐、收藏、歌词、队列和推荐。

当前代码已经是一个可运行的 SwiftUI iOS app，接入了 Bilibili 私有 Web API、AVPlayer、本地缓存、收藏夹、歌词和播放器 UI。下一阶段不是继续堆功能，而是先把首播、搜索、推荐刷新、滑动动画和播放器交互里的卡顿系统性修掉。

## Core Value

让音乐尽快、稳定地响起来；当功能冲突时，播放启动速度和不中断播放优先于推荐、歌词、MV、UI 动效和其他增强体验。

## Requirements

### Validated

- [x] iOS SwiftUI app 已建立，使用单一 app-wide `PlayerEngine` 管理播放状态和播放器展示。
- [x] 可以通过 Bilibili API 解析视频信息、音频流、MV 视频流、搜索结果、相关推荐、收藏夹和合集。
- [x] 音频播放走 AVPlayer，并支持后台音频、锁屏信息和远程控制。
- [x] 已有本地缓存体系，可以下载完整音频文件并从缓存优先播放。
- [x] 已有搜索页、首页推荐、收藏夹、缓存库、设置页和播放器页。
- [x] 已有音乐内容过滤、搜索分页、搜索历史、播放历史、播放次数、队列、相关推荐和播放模式的基础实现。
- [x] 已有 LRCLIB 歌词匹配，找不到歌词时应保持不可点/空状态，而不是显示错误字幕。
- [x] 已有音乐/MV 切换、Wi-Fi 优先 MV、音频质量和下载质量偏好。
- [x] 已有代码库地图和架构文档，后续规划可基于 `.planning/codebase/` 继续推进。
- [x] 播放启动关键路径已测试保护：点歌后先设置当前曲目，只等待缓存、已准备音频或一次新音频流解析，然后请求 AVPlayer 播放。
- [x] 首次观察到播放后只调度历史、封面和歌词；MV 预取、推荐、队列预取和自动缓存不再由首播路径触发。
- [x] 已准备的远程音频流失败时会失效内存缓存并自动重试一次新音频流，失败后不会循环。
- [x] 搜索聚焦和普通输入不再触发 Bilibili 搜索、WBI 预热或结果预加载；网络搜索保留在显式提交、重试、更多结果和分页路径。
- [x] 空搜索页可以只用本地数据展示搜索历史、最近播放和已缓存歌曲。
- [x] 首页推荐在首次点歌时保持可见列表稳定，不会作为播放副作用清空、闪烁或重置。
- [x] 首页推荐调度有显式初始加载/手动刷新触发、种子和请求上限，并低于直接播放启动优先级。

### Active

- [ ] 稳定播放与性能：首播要尽快出声，避免启动播放时被推荐刷新、歌词、MV、图片、预加载或历史写入阻塞。
- [ ] 搜索交互性能：第一次点搜索框不能卡顿，搜索结果不能混入旧结果，加载更多要稳定且结果继续限定为音乐。
- [ ] 推荐刷新稳定性：播放器推荐列表内点歌不应立即刷新列表，Home/Now Playing 推荐状态后续需要继续分离和验证。
- [ ] 播放器交互流畅度：迷你播放器上滑应跟手，下滑最小化只在播放器非列表区域触发，动画不能明显卡顿。
- [ ] 播放器布局密度：减少底部空白，让封面、进度、控制、歌词入口、队列/推荐页面的空间分配更接近 Apple Music。
- [ ] 音乐内容质量：搜索、首页推荐、相关推荐、电台和合集入口都要尽量排除非音乐内容。
- [ ] 队列和推荐模型：播放器左一屏显示当前播放列表，右一屏显示当前歌曲推荐；电台模式和普通播放列表必须有明确差异。
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

项目最初目标是模仿 YouTube Music 做一个 Bilibili Music，后续根据个人开发者实现成本和系统风格，UI 方向改为更接近 Apple Music。用户已经多轮真机测试，反馈集中在：首播慢、搜索框第一次聚焦卡顿、搜索结果非音乐太多、首页推荐大杂烩、播放器布局空、上滑/下滑不跟手、推荐列表刷新时机错误、收藏 401、歌词错配、MV 与音乐双重播放、合集识别不足。

代码层面已经有不少功能，但几个核心类型过大：`PlayerEngine` 集中处理播放、队列、MV、歌词、推荐预加载、历史、远程控制；`NowPlayingView` 集中处理播放器布局和大量交互；`BiliClient` 同时承载多个 Bilibili API 域。后续性能修复要避免继续把所有副作用塞进播放启动路径。

已有验证结论：

- Bilibili playurl 能拿到 DASH 音频流，m4a 带 Referer 和 UA 可播放/下载。
- 搜索和推荐接口依赖 WBI 签名，已有 Swift/Python 验证与 app 内实现。
- 音频流 URL 有时效性，不能持久化 URL，只能持久化 bvid/cid 和缓存文件。
- 未登录可以播放不少内容，但高音质、收藏夹、个性化推荐和收藏写入依赖 Cookie。
- B 站字幕常常不是歌词，歌词应以 LRCLIB 等歌词源为主，找不到则不展示可交互歌词入口。

## Constraints

- **Tech stack**: SwiftUI + Swift 5.10 + iOS app target；继续沿用现有工程，不引入不必要的第三方依赖。
- **Platform**: 面向用户自己的 iPhone；安装方式围绕 sideload/AltStore，而不是 App Store 审核。
- **Playback priority**: 播放启动必须先于歌词、推荐、图片预热、MV 切换、自动缓存等增强任务。
- **API dependency**: Bilibili 私有 API 和 WBI 签名可能变化；所有 endpoint 变化应隔离在 API 边界。
- **Auth**: Cookie 存 Keychain；任何 401/失效状态都应转换成清晰的重新登录路径。
- **Offline cache**: 缓存文件在 app Documents 下，不能只维护 JSON 索引而忽视孤儿文件、磁盘空间和失败恢复。
- **UI**: 以 Apple Music 风格为方向，避免营销页、过度装饰和空旷布局；播放器必须适合单手触控和反复使用。
- **Testing**: 对播放、搜索、推荐和缓存这类高风险逻辑，优先补可稳定运行的单元测试和少量关键 UI 测试。

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| 个人自用 iPhone app，而不是公开第三方客户端 | 降低审核、合规、后端和跨平台成本，聚焦真实使用体验 | Good so far |
| UI 方向从 YouTube Music 转向 Apple Music | Apple Music 的结构更适合个人开发者复刻，也更贴近 iOS 原生音乐使用习惯 | Pending polish |
| 播放启动优先于所有增强体验 | 用户明确要求“让音乐响起来是第一优先级” | Active |
| 复用 B 站收藏夹和合集，而不是先做自建歌单系统 | 减少数据模型复杂度，利用已有内容组织方式 | Pending stabilization |
| 歌词优先用在线歌词 API，B 站字幕不作为可靠歌词源 | B 站自动字幕容易出现错误内容和非歌词标记 | Good so far |
| 音频质量和下载质量分开 | 在线播放和缓存占用的用户需求不同 | Implemented, needs UI/verification |
| 推荐必须音乐化 | B 站默认推荐容易混入非音乐内容，不符合产品目标 | Active |

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
*Last updated: 2026-06-26 after Phase 01 Plan 04*
