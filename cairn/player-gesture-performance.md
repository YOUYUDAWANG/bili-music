---
type: project_topic
status: active
summary: "记录播放器翻页与收起动画的性能约束，以及进度条手势所有权规则。"
tags: [player, gesture, performance, swiftui]
contains: [decision, lesson]
created: "2026-08-12"
updated: "2026-08-14"
related: ["BiliMusic/Features/Player/NowPlayingView.swift", "BiliMusic/Features/Player/PlayerControlViews.swift", "BiliMusic/Features/RootView.swift"]
authoring_mode: ai_generated
---
# 播放器手势与转场性能

## 当前结论

- 进度条不能用 `minimumDistance: 0` 抢占整行触控；当前要求至少移动 8pt 且横向位移大于纵向位移的 1.6 倍，才进入 scrub。
- 进度条交互带保持 24pt，外层翻页只排除该窄区域附近的起点。纵向或明显斜向手势即使从进度条附近开始，也不应 seek。
- 页面翻页手势只挂在三页容器上。封面不重复挂同一手势，避免同一次拖动触发多套状态更新。
- 纵向开合不再由 RootView 自制 offset/scale/弹簧状态机；标准紧凑浮动播放条和全屏页统一交给 LNPopupController 的 `.floatingCompact + .automatic` 交互管理。`.automatic` 在打开时使用 snap/transition target，在已展开的下滑关闭阶段保持跟手 drag。
- 封面容器是播放页中唯一的 `.popupTransitionTarget()`；展开和收回沿同一条原生交互轨迹在播放条封面与全屏封面之间连续变形。
- `CADisableMinimumFrameDurationOnPhone=true` 已开启，LNPopupController 的交互 display link 也请求 `UIScreen.main.maximumFramesPerSecond`；ProMotion 门禁不是当前慢拖掉帧的根因。低电量模式或系统“限制帧率”仍可能将刷新率封顶。
- 有当前歌曲时播放器在屏外常驻预热；队列、正在播放、推荐三页由 UIKit `UIPageViewController` 分别承载，翻页位移与减速不再依赖 SwiftUI `HStack.offset`。
- UIKit 分页开始交互时冻结 `UIHostingController.rootView` 更新并临时栅格化三页；转场完成后解除栅格化、提交页码并应用积压内容，避免播放进度和推荐状态在两页接缝处触发逐帧布局。
- 中央页只承担封面、元数据、进度和播放操作；合集与队列明细只在左页出现，避免重复信息和重复列表渲染。
- 播放页自身不再挂中心区/顶部纵向 dismiss 手势，避免和 popup controller 的惯性、取消及横向分页竞争；顶部向下箭头已移除，整页下滑只由同一个 popup controller 接管。
- mini player 使用 LNPopupUI 标准 bar 而不是 custom bar，以保留上游多年打磨的 docking、安全区、惯性、玻璃样式和收回细节。
- Tab Bar 的 `.onScrollDown` 最小化策略在 popup 打开期间必须保持不变；切换到 `.never` 会改变关闭目标几何，使播放页无法收回打开前的 inline 控件。
- `.onScrollDown` 只在存在当前歌曲时启用；首次启动尚未播放时使用 `.never`。否则系统底栏虽没有 popup bar，滚动后仍会切换到为 inline accessory 预留中央槽位的形态，形成空白 mini player 占位。
- popup bar 使用固定 48pt 的 `.floatingCompact` 并继承 bottom bar metrics；inline 状态只保留播放/暂停按钮并隐藏下一首，使播放控件与两侧折叠底栏按钮等高。普通 `.floating` 固定为 58pt，不能用于该布局。
- iOS 27 开启 popup content transition，使展开与收回末帧由 snapshot 连续交接到 live view，避免收进底栏时的闪切；三页重内容仍由横向分页容器在交互时冻结与栅格化。
- popup item 不暴露进度值；播放进度只由全屏页的局部 `PlayerProgressBar` 订阅，避免 0.5 秒一次的 `currentTime` 更新使 RootView、TabView 和首页滚动树同步刷新。
- popup 内容开合使用 0.62 秒弹簧时长（上游默认 0.50 秒），保留速度继承但让 mini player 与全屏页之间的几何变化更容易被视觉连续追踪；这是 vendored LNPopupController 的项目级补丁。
- 慢速交互式下滑开始后，LNPopupController 将完整播放器内容控制器按当前屏幕 scale 临时栅格化，手指移动时只合成一个缓存层；收起、取消或回弹完成后立即关闭栅格化，恢复实时进度与控件渲染。
- LNPopupUI 4.0.1、LNPopupController 4.5.5 及两个小型传递依赖以 MIT 源码精简 vendored；LNPopupController 清单的递归私有头路径加 `./`，规避 Xcode 27 Beta 路径截断。
- LNPopupUI 主 product 必须静态链接；动态 product 在当前 XcodeGen 工程中不会自动进入真机 App 的 `Frameworks`，会导致 dyld 启动即退。
- 移除中央列表后，播放控制区通过底部保留 54pt（紧凑）/88pt（常规）空间，上移到中央偏下位置。参考 Apple Music，顶部安全区底部放置 60×5pt 下滑提示条；`safeAreaInset` 自行消费系统顶部安全区，不再额外叠加 `safeAreaTop`。竖屏顶部栏后的固定 inset 为 4pt，封面额外顶距为紧凑 12pt、常规 18–32pt，避免顶部空旷。

## 决策记录

- 保留既有三页内容结构，横向由 `UIPageViewController` 管理，纵向由 LNPopupController 管理，两轴各有唯一原生手势所有者。
- 用户明确拒绝近似的自制定时曲线后，纵向架构以 Apple Music 同类开源容器替换，不再继续调参模拟。
- 用纯逻辑测试保护进度横向意图，用 UI 测试分别覆盖正常 scrub、纵向拖动不 scrub、横向翻页不 dismiss。
- “所在合集”和实际播放队列统一归入左侧上下文页；中央页不再用紧凑列表重复展示同一批歌曲。

## 经验与教训

- 手势误触不能只靠外层识别区域规避；子手势若以零距离和最高优先级启动，会在外层判断之前取得所有权。
- SwiftUI 中对连续手势状态添加隐式动画会制造拖尾和掉帧感，即使最终动画参数本身看似平滑。
- 同一拖动手势重复挂在父子视图上，会增加状态写入与竞争；优先保留单一所有者，再为真正独立的控件设置窄范围高优先级手势。
- `HStack` 被裁剪到单屏并不代表屏外子树不参与创建；三页各含滚动列表时，需要显式按当前页/相邻页控制重内容生命周期。
- 当需求是 Apple Music 的连续几何转场、速度继承和 dock 收回时，继续堆叠 SwiftUI offset/scale/matched geometry 只会复制表象；应使用统一拥有 bar 与 content 生命周期的容器。
- Xcode 27 Beta 会错误截断 LNPopupController 4.5.5 中由清单递归生成、且首段重复 target 名称的头文件路径；显式 `./` 前缀可稳定消除该截断。
- “模拟器可启动、UI 测试通过”不能证明 Swift Package 动态库已嵌入真机包；真机交付前需检查 `otool -L` 并实际确认进程在启动后持续存在。
- 主观评估 120Hz 手指跟随动画必须安装 Release 真机包；Debug 的 Swift/ObjC `-O0` 会放大布局与合成开销。本项目继续用 Debug 跑自动化，但每次帧率交付用 Xcode Beta 的 `-O` whole-module Release 包确认。
