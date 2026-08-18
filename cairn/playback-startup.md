---
type: project_topic
status: active
summary: "记录与 AprDeci 对照后的起播差异，以及本仓库为缩短点歌到出声所做的改动。"
tags: [playback, startup, avplayer, cache, wbi, persistence]
contains: [lesson, decision]
created: "2026-08-19"
updated: "2026-08-19"
related: [".planning/PROJECT.md", "BiliMusic/Player/PlayerEngine.swift"]
authoring_mode: ai_generated
---
# 起播链路

## 当前结论

- AprDeci 更快，主要不是少请求，而是：整文件缓存后本地秒开、media_kit 吃 `.m4s` 更干脆、复用同一个播放器、拉流带 Cookie、WBI playurl，以及杀进程后仍能从本地队列/缓存继续。
- 本仓库仍用 AVPlayer。已做的加速不改视觉：换曲复用同一个 `AVPlayer`、CDN 拉流带 `playbackHeaders`、音频走 WBI playurl、点歌时不抢网拉封面、自动缓存默认开启并在出声约 1.5s 后落盘。
- 冷启动会恢复上次队列、下标、模式和进度，暂停待命并显示 mini player；电台恢复为顺序播放。不持久化流 URL。
- 收藏夹/首页写入 `ugc.first_cid`，封面快照按 bvid 去重时优先保留已有 cid，听过的封面少走 `pageList`。
- 本地音频上限 120 首，按访问 LRU 淘汰，不删正在播放或正在下载的文件。
- 慢启动 CDN 回退改为先探测、满 1.2s 仍未出声再切线，避免「先空等再探路」。
- 自动缓存仍只在首帧之后调度，不回到点歌关键路径。

## 决策记录

- 不引入第二套播放器或 media_kit。先把现有 AVPlayer 路径上能确定的浪费去掉。
- 听过的歌优先走已有 `CacheStore` / `DownloadManager`，不另建缓存体系。
- 封面内存命中仍在点歌帧恢复；网络封面等到出声后再拉。
- 杀进程后不自动续播，只恢复暂停状态，避免后台突然出声。

## 经验与教训

- AVPlayer 能打开 `.m4s` 不等于立刻出声。Cookie、WBI 线路和是否重建 player 都会加在首包前面。
- 出声后立刻整文件下载会和正在播的流抢带宽；留 1.5s 再下，既比原来的 8s 更容易缓存到，也不挡第一声。
- 搜索结果通常没有 cid；收藏列表的 `first_cid` 和首页快照补全后，点封面可以少一次 pageList。

## 开放问题

1. 真机上冷启动新歌与「听过再点」分别还能慢多少，是否还要继续压 AVPlayer 认流？
2. 独立 `CoverTile` 与更小的 1200w 缩略图是否值得做，视觉约束下如何避免糊？
