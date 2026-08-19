# BiliMusic Metadata Worker

Cloudflare Worker for normalizing Bilibili music titles before querying lyric providers.

Production: `https://bilimusic-metadata.mercari-email-sale-worker.workers.dev`。当前部署版本 `c593e5b3-eb9e-4360-9a1e-8dd1a58ad723`。V2 将 style bible 与最多 4 段 scene 并行，避免超过现有 iOS 客户端 45s 无首包超时；2026-08-20 24 行样本 19.2s 非降级且 KV 命中。密钥不记录在本文档。

## API

`POST /v1/music/normalize`

`POST /v1/lyrics/direct` keeps the compatible `lyric-performance-v4` envelope and adds a v5 stage layer. A first whole-song pass creates a bounded `stageBible` (concept, motif, intensity arc); detailed segments then return `stageDirectives` for the local kinetic-typography compiler while continuing to return v4 compositions/scenes/word cues. Failed stage-bible generation falls back to the existing segmented path. The production director version is `luna-lyric-director-v5-stage-preview`.

`POST /v2/lyrics/direct` returns the independent `lyric-stage-v2-events` contract: StyleSheet, Section, Scene, Actor and relative-time Event data for the V5.1 compiler. It uses a separate `director-v2:` KV prefix and reports an empty or wholly invalid scene result as degraded instead of caching a false success. The production director version is `luna-lyric-director-v2-events`.

Requests require `Authorization: Bearer <API_KEY>`. The production key is stored as a Cloudflare Worker secret and in the developer Mac's system keychain; it is never committed to this repository.

```json
{
  "title": "【花譜】日文翻唱《夏夜のマジック/夏夜的魔法》",
  "uploader": "花譜 - KAF",
  "duration": 245,
  "bvid": "BV...",
  "cid": 123
}
```

The response keeps the original-script canonical title and a layered identity: `canonicalTitle`, `originalArtists`, `coverPerformers`, `uploader`, `aliases`, `lyricSearchQueries`, `isCover`, `confidence`, and `needsReview`. Lyric queries use the cleaned original-script title with original-artist and cover-performer forms; translation aliases stay on `aliases` for matching, not as search keywords. For explicit covers, the model may supply an original artist from reliable catalog knowledge only at high confidence; uncertain attributions remain empty and are marked for review. Deterministic post-processing prevents Japanese titles from being replaced by translations or a cover performer from being mislabeled as the original artist. KV caches identical requests for 30 days. The current prompt version is `music-metadata-v7-layered-identity`.

The upstream API key is stored only as the Cloudflare secret `UPSTREAM_API_KEY`. The public base URL and model ID are configuration variables. The Worker tries OpenAI-compatible Chat Completions first and Responses API when the chat endpoint reports a compatibility status. If the upstream is unavailable or incompatible, it returns deterministic normalization with `degraded: true`, does not cache that degraded result, and never calls Workers AI.

The service intentionally does not fetch or proxy lyrics.
