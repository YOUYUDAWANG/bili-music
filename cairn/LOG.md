# Project Cairn 日志

本文件按反向时间顺序记录实质进展——最新记录放在本行下方最顶部。每条记录保持简短，只写摘要与指针；稳定结论沉淀到 `cairn/<topic>.md`。

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
