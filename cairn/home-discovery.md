---
type: project_topic
status: active
summary: "首页用本机常听歌手去音乐区找新歌，再和收藏夹封面混排；related 与首页流只补量。"
tags: [home, recommendation, discovery]
contains: [decision, current]
created: "2026-08-19"
updated: "2026-08-19"
related: ["BiliMusic/Player/ListeningTaste.swift", "BiliMusic/Player/RecommendationEngine.swift", "BiliMusic/Features/Home/HomeView.swift"]
authoring_mode: ai_generated
---
# 首页发现与去重

## 当前真相

- 首页仍是一条 1+4 封面墙，不另开「为你推荐」分区。
- 旧歌来自用户指定收藏夹（先快照、再 `LibraryStore`）。缓存和播放历史只在资料库还是空的时候垫底。
- 新歌主源是常听歌手 + 常听歌名，去 B 站音乐区搜索；同一轮查询会摊到第 1–3 页，避免总停在热门第一页。
- B 站 UP 名不再当成歌手。搜到足够像你的歌时，不再掺首页流和 related。
- `HomeCoverMixer` 每 5 张里大约 2 张新歌、3 张旧歌；偶数大图优先新歌。
- `RecommendationMemory` 记住 6 小时内展示或电台选中的 BV。首页、电台快速路径和播放器推荐面板都排除这些 BV。
- 同一首歌如果出现在多个 related 种子下面，打分扣 hub 惩罚，避免全是那几首热门 MV。
- 发现在封面先出来之后再请求，不挡点歌。

## 不要做

- 不要再把 related 或视频首页推荐流当找歌主源。常听歌手搜索才是这个 App 能落地的品味。
- 不要在点封面的同一帧里等推荐。
- 不要改 1+4 骨架或在封面上叠标题。
