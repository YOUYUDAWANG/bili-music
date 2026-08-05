---
type: project_topic
status: active
summary: "记录真机远程音频 Cannot Open 的根因、修复方法与安全诊断经验。"
tags: [playback, avfoundation, cdn, diagnostics]
contains: [lesson, decision]
created: "2026-08-06"
updated: "2026-08-06"
related: [".planning/PROJECT.md", "BiliMusic/Player/PlayerEngine.swift"]
authoring_mode: ai_generated
---
# 远程播放失败诊断

## 当前结论

- iPhone 17 Pro、iOS 27.0 Beta 真机上的 `Cannot Open` 已修复，并由原失败歌曲实际出声验证。
- 原失败为 `AVFoundationErrorDomain -11828`，底层为 `NSOSStatusErrorDomain -12847`。
- 同一批带 Referer、User-Agent 与 `Range: bytes=0-1` 的 URLSession 探测均返回 HTTP 206 且收到数据，因此已排除 URL 过期、设备断网和 CDN 直接返回 403。
- 根因是 CDN 把音频 fragmented MP4 返回为 `application/octet-stream`，导致 AVFoundation 无法识别容器。播放链路现传播 playurl 每条音轨的 `mime_type`/`codecs`，并用公开的 `AVURLAssetOverrideMIMETypeKey` 提供真实 MIME，而不是统一硬编码格式。
- 备用源回退现优先切换不同 host，并在重建播放源后保留完整候选列表。

## 决策记录

- 播放失败诊断作为失败后的旁路任务运行，不阻塞首播或重试。
- Debug 控制台统一输出 `PLAYBACK_FAILURE`、`PLAYBACK_CDN_PROBE`、`PLAYBACK_RETRY`。
- 只记录 bvid/cid、阶段、错误域/码、CDN host、HTTP 状态与 MIME；不得记录签名 URL、Cookie、完整请求头或错误 userInfo。
- 真机排障优先使用无断点控制台日志；LLDB 断点会暂停主线程，不适合交互复现。

## 经验与教训

- `error.localizedDescription` 只有 `Cannot Open`，不足以区分网络拒绝、格式识别与解码失败；必须保留 NSError domain/code、underlying error 和 AVPlayerItem error log。
- CDN “可达”不等于 AVPlayer “可播放”。应同时比较带相同请求头的 Range 探测和 AVFoundation 结果。
- 回退验证必须检查目标 host 是否真的变化，不能只比较带不同签名参数的完整 URL。
- MIME 是容器提示，不决定码率或音质等级；使用接口随音轨返回的真实值可兼容 AAC 与 Hi-Res，而不会把高音质强制改成普通 AAC。

## 开放问题

1. 用实际 Hi-Res 曲目验证接口 MIME、解码和最终音质标识是否完整一致。
2. 当前质量列表虽展示 Dolby Atmos，但 playurl 模型尚未解析 `dash.dolby`；应作为独立功能接入并用真实杜比资源验证，不能把本次 MIME 修复等同于杜比支持。
3. `AVURLAssetHTTPHeaderFieldsKey` 的 Referer 注入在 iOS 27 上是否仍生效？该键不在 Apple 公开初始化选项列表中。
