# 歌词架构

## 当前链路

1. `TrackTitleParser` 在本地保留安全的标题/歌手结构，用于显示和 BM 不可用时的搜索词回退。
2. `MetingLyricsClient` 把 B 站原始标题 POST 到 `https://bm.126386.xyz/ai`，取得“歌名-歌手”关键词。
3. app 根据关键词选择网易云、酷狗或 QQ 音乐，直接搜索候选并读取歌词；BM 不代理歌词内容。
4. 自动路径对候选做轻量标题/歌手一致性排序，再取第一份有歌词的候选；LRCLIB 及其时长/相似度评分已移除。
5. `LyricsParser` 统一普通 LRC、多时间标签、翻译和逐字格式；`PlayerEngine` 暴露当前行、逐字时间、平台、候选和用户偏移。
6. `LyricsStore` 把最终选择和偏移保存在 `Documents/lyrics-library.json`，换曲先读本地。

> 当前 iOS App 仍使用上述 BM `/ai` 链路；以下自建服务已经上线，但尚未接入 App。

## 自建元数据清洗服务

- Cloudflare Worker：`https://bilimusic-metadata.mercari-email-sale-worker.workers.dev`
- 接口：`POST /v1/music/normalize`；健康检查：`GET /health`。
- 请求使用 Bearer 密钥；生产密钥只保存在 Cloudflare Worker Secret 和开发 Mac 系统钥匙串，不进入仓库或项目笔记。
- Worker 通过私有 OpenAI 兼容上游调用 `gpt-5.6-luna`；实际兼容协议为 `v1/chat/completions + json_object`。确定性后处理保护日文原名、拆分中文译名、区分原作者/翻唱者/UP 主并构造有序搜索词。
- 日文书名号内存在“原文/译名”时，原文固定为 `canonicalTitle`；即使模型返回译名，服务端也会强制恢复日文原文。
- KV 使用输入和 prompt 版本的 SHA-256 作为 key，缓存 30 天；模型失败时返回确定性降级结果，不让清洗失败阻断歌词搜索。
- 当前 prompt 版本为 `music-metadata-v5-gpt56luna`；Workers AI 绑定已移除，不再消耗 Cloudflare Neurons。实现与接口契约位于 `services/metadata-worker/`。

## UI 行为

- 当前行自动居中并逐字高亮；有翻译时可显示/隐藏。
- 点击歌词行跳转播放进度；底部控件以 500ms 步进调整偏移并持久化。
- 自动匹配为空或错误时仍能打开歌词页，手动选择网易云、酷狗或 QQ 的候选。

## 验证与风险

- 单元测试覆盖平台路由、候选排序、LRC/翻译/逐字解析和持久化偏移。
- iPhone 17 模拟器 UI 回归覆盖歌词页打开、原文/翻译显示和偏移控件；截图人工检查通过。
- 真实冒烟：B 站标题经 BM 得到关键词后，网易云候选可取得并持久化正确歌曲歌词。
- Release 真机包已完成签名校验、覆盖安装并在用户的 iPhone 17 Pro 上成功启动；同 bundle 安装保留现有 app 数据。
- 自建 Worker v5 已部署；未授权请求返回 401。`gpt-5.6-luna` 线上样本验证通过：`夏夜のマジック / 花譜`、`アイドル / YOASOBI`、`晴天 / 周杰伦`，均为 `degraded=false`；新请求约 3.57–3.87 秒，KV 命中约 0.057 秒。
- BM 是外部公共服务；三个歌词平台也都是非官方接口。协议、限流或服务可用性变化应被视为可降级依赖，自动失败不能阻断播放。
