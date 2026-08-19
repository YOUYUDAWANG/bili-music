[根目录](../../../CLAUDE.md) > [Features](../) > **Home**

## 模块职责

封面驱动的私人音乐库。指定收藏夹是旧歌来源；发现新歌来自会换页的首页推荐流，和旧封面混在同一条 1+4 瀑布流里。

## 入口与启动

- 文件: `HomeView.swift`, `CoverLibrarySnapshotStore.swift`, `HomeCoverMixer.swift`
- 页面出现时先读取持久化封面快照（含上次发现曲），收藏夹网络刷新在后台完成；有夹之后不再把缓存/历史拼进墙。发现推迟约 2 秒，点封面会取消，避免和起播抢网。收藏条目带 cid 时写入 `Track`；快照按 bvid 去重并优先保留已解析 cid。

## 对外接口

### HomeView

- 封面墙按原始顺序连续重复“1 张全宽 + 4 张双列”，形成单一纵向海报瀑布流；不插入横向滚动区域或其他模板。
- 不在封面上叠标题，不生成替代封面的高饱和色块。
- 页面左右留 8pt；每组内部使用 4pt 间距，每组之间使用 8pt 间距，卡片为 4pt continuous 圆角，以 1:2 的基础节奏维持连续感和 1+4 分组。
- 首页沟槽与背景固定使用 `AppTheme.background`，不再从封面取环境色；所有封面保持静止，不做内部视差裁切。
- 当前播放封面底部使用单一 3pt 高对比真实进度线，不再添加白色描边、渐变或状态角标。
- 随机播放与设置在右上角共用一块 34pt 高的 Liquid Glass 胶囊；封面在其下方连续滚动，顶部 72pt 静态暗色渐变只保护状态栏与按钮对比度且不拦截手势。
- 第一张封面在静止状态与顶部胶囊保持呼吸空间；ScrollView 依赖 LNPopup 动态安全区，并额外保留 8pt resting buffer。
- 点击封面直接播放；长按可电台播放、随机播放资料库或加入队列。
- 点击封面时，`PlayerEngine.beginPlayback` 在同一帧提交唯一真实选曲，随后由 RootView 打开同一个 LNPopup 播放器。Home 不再挂载 `NowPlayingView`、matched geometry、关闭延时 Task 或第二套关闭按钮；mini/full 开合全部由 LNPopupController 管理。
- 下拉刷新会重新同步指定收藏夹，并换一批发现曲。
- 封面快照保存在 `Documents/cover-library.json`，15 分钟内冷启动不重复请求收藏夹；发现曲一并写入，冷启动可立刻混排。
- 发现去重看 `RecommendationMemory`（`recommendation-memory.json`，6 小时）。

## 关键依赖与配置

- `CacheStore` / `PlaybackHistoryStore` — 收藏夹还没准备好时的离线兜底。
- `BiliClient.favFolders()` / `favItems()` — 指定收藏夹的封面来源。
- `ListeningTaste` + `BiliClient.search` — 按常听歌手找新歌。
- `BiliClient.homeFeed(freshIndex:)` — 只补新鲜度；related 只用常听种子。
- 首页收藏夹沿用 `UserDefaults.integer(forKey: "recommendFolderId")`，避免升级后丢失原选择。

## 数据模型

- 首页使用的是 `Track`（定义在 PlayerEngine 同文件）。
- 持久化快照：收藏夹 id、保存时间、最多 480 首收藏封面，以及最多 48 首发现曲。

## 相关文件清单

- `HomeView.swift`
- `CoverLibrarySnapshotStore.swift`
- `HomeCoverMixer.swift`

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-08-19 | 首页重新混入发现曲：收藏夹与推荐流新旧穿插，并记住已展示 BV。 |
| 2026-08-19 | 收藏夹封面快照写入 cid，按 bvid 去重时优先保留已有 cid。 |
| 2026-08-19 | 撤销 Home 自制 matched-geometry 播放器层；封面点击、mini/full 开合统一回归 LNPopup。 |
| 2026-06-24 | 初始文档创建。 |
| 2026-08-14 | 首页从推荐列表改为封面驱动的私人音乐库。 |
| 2026-08-14 | 模拟器实图确认多模板节奏不如原版纯粹，恢复“1 张全宽 + 4 张双列”的连续海报瀑布流。 |
| 2026-08-14 | 在不改变 1+4 骨架的前提下加入窄色接缝、轻环境色、全宽微视差和播放进度线。 |
| 2026-08-14 | 真机比例实图确认统一 2pt 接缝显得廉价，改为 4pt 组内 / 10pt 组间层级，并移除环境色接缝与视差。 |
| 2026-08-14 | 最终收敛为 8pt 外边距、4pt 组内、8pt 组间、4pt 圆角、3pt 进度轨，并把顶部操作合为右侧 Liquid Glass 胶囊。 |
