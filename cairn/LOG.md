# Project Cairn 日志

本文件按反向时间顺序记录实质进展——最新记录放在本行下方最顶部。每条记录保持简短，只写摘要与指针；稳定结论沉淀到 `cairn/<topic>.md`。

## 2026-08-14 · 收紧播放器节奏并开放一级完整队列

- 移除收起状态对播放信息和控制区的 64pt 人为下沉，减少顶部、封面下方和控制区之间的断裂留白。
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
