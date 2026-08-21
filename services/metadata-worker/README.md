# BiliMusic Metadata Worker

Cloudflare Worker for normalizing Bilibili music titles before querying lyric providers.

Production: `https://bilimusic-metadata.mercari-email-sale-worker.workers.dev`。2026-08-21 已核对的部署版本为 `79c3d38c-363f-4c5d-b76b-625c16b3bdf1`，实时 `/health` 列出 normalize、V1、V2、V3、V4 与 embellishment，V3/V4 feature switch 均为 enabled。全链路上游为 `https://cpa.hachi-mi.uk` 的 `gemini-3.7-flash-high`；CPA 使用独立 Cloudflare Secret，旧 `UPSTREAM_API_KEY` 保留供版本回滚。上一 V4 版本为 `14834316-d27d-4c15-8bbb-435c3e7fae5c`；V4 上线前的回滚版本为 `52cc64da-2efd-4ce6-84ad-df1472b9e692`；切换 CPA 前、已含 55/60 秒 V3 预算的回滚版本为 `060adf92-75b7-4719-a55c-3936ce5e727e`；V3 上线前、已包含 embellishment 的独立回滚基线为 `1b07471b-49e4-48cf-adb1-c3ca591db573`。V2 将 style bible 与最多 4 段 scene 并行，避免超过现有 iOS 客户端 45s 无首包超时。密钥不记录在本文档。

## API

`POST /v1/music/normalize`

`POST /v1/lyrics/direct` keeps the compatible `lyric-performance-v4` envelope and adds a v5 stage layer. A first whole-song pass creates a bounded `stageBible` (concept, motif, intensity arc); detailed segments then return `stageDirectives` for the local kinetic-typography compiler while continuing to return v4 compositions/scenes/word cues. Failed stage-bible generation falls back to the existing segmented path. The production director version is `luna-lyric-director-v6-stage-gemini-3.7-flash`.

`POST /v2/lyrics/direct` returns the independent `lyric-stage-v2-events` contract: StyleSheet, Section, Scene, Actor and relative-time Event data for the V5.1 compiler. It uses a separate `director-v2:` KV prefix and reports an empty or wholly invalid scene result as degraded instead of caching a false success. The production director version is `luna-lyric-director-v2-events-gemini-3.7-flash`.

`POST /v3/lyrics/direct` is an additive whole-song contract for the generic V5.3 choreography compiler. It returns `lyric-stage-v3-choreography`: track/lyrics/audio-summary identity, one Stage Bible, continuously covering sections, and sparse scenes using the eleven V5.3 compositions. The App remains responsible for complete local fallback, word reveal timing, layout and rendering. V3 accepts the compact `LyricStageAudioSummaryV3` shape (including `lines` or legacy `lineFeatures`) but never accepts or proxies audio. Its KV key is isolated by `director-v3:`, director version, grammar version and audio-summary hash. Only validated, non-degraded output is cached, and the KV write completes before the response. `LYRIC_DIRECTOR_V3_ENABLED` is a fail-closed deployment switch and is enabled in the current production config; disabling it returns 503 without touching the old endpoints.

`POST /v4/lyrics/direct` is the additive `lyric-stage-v4-scene-recipe` contract. It accepts complete lyric lines plus a bounded, quantized `audioScore`, while the App-supplied 64-hex `audioScoreHash` remains the cross-language identity echoed in the response. Gemini sees only the compact score semantics, confidence, section/line facts, optional contours and stable structural-moment IDs; map/audio fingerprints, raw beat/onset arrays, secrets and device identity never enter the model prompt. The response contains a typed primary/optional secondary motif and sparse recipes for `railHandoff`, `semanticLens`, `chorusMemory`, and `silenceAperture`. The Worker repairs each compatible field independently, drops only the invalid scene, fills continuous section coverage, and enforces the 45% sparse ceiling plus the two-line high-motion ceiling. V4 uses its own `director-v4:` KV prefix, grammar/director versions and `LYRIC_DIRECTOR_V4_ENABLED` kill switch. Only non-degraded output is cached. V4 is enabled in the current production config; disabling its switch stops only V4 and leaves V1–V3/embellishment unchanged.

The first production V4 canary used 12 complete word-timed lines plus quantized tempo, section, per-line contour and four structural moments. The cold request returned `200`, `degraded=false`, `model=gemini-3.7-flash-high`, two continuous sections and four valid Scene Recipes in 9.10s. The identical request returned `cache=hit` in 83ms. The same deployment advertised every older route and each unauthenticated V1/V2/V3/embellish/normalize probe preserved the 401 boundary.

The current deployment additionally preserves every V4 lyric line exactly within the existing 98,304-byte body limit instead of inheriting the legacy 500-code-unit prompt cap; V1–V3 behavior is unchanged. A fresh four-line post-deploy request returned non-degraded Gemini output with a valid `chorusMemory` recipe, and the identical request hit the independent V4 KV cache. Normalize, V1, V2, V3, V4 and embellish all preserved the unauthenticated 401 boundary. Worker tests pass 54/54.

2026-08-21 production verification used a 12-line repeated-hook/duet/audio-summary fixture: cache miss returned in 23.35s with 5 continuous sections, 5 valid sparse scenes, `degraded=false`; the identical request hit KV in 53ms. V1, V2, embellish and normalize all returned 200/non-degraded in the same deployment, and an unauthenticated V3 request returned 401.

`POST /v1/lyrics/embellish` returns bounded semantic word/line embellishment cues. It remains independent from the whole-song V3 choreography contract.

All JSON POST routes enforce the actual streamed body size, not only `Content-Length`. V3 uses one compact whole-song upstream call with a total compatibility-fallback deadline; it does not repeat V2's parallel heuristic-bible scene generation.

After a real App request exhausted the original 38-second V3 deadline, the V3-only upstream budget was raised to 55 seconds per request and 60 seconds across compatibility fallbacks. The iOS client continues to allow up to 120 seconds, so the Worker remains the authoritative bounded timeout; V1, V2 and embellishment retain their existing shorter budgets.

The deployed timeout fix was verified with a fresh 12-line repeated-hook/duet/audio-summary cache key: the cold request completed in 18.22 seconds with 3 continuous sections, 5 valid scenes and `degraded=false`; the identical request hit KV in 71.8ms.

The global Gemini migration bumps the normalization, V1, V2, V3 and embellishment cache/director versions so repeated real songs do not silently reuse output from the previous model. Fresh production misses all returned `model=gemini-3.7-flash-high`, `upstreamProtocol=chat-json-object` and `degraded=false`: normalize 4.63s, V1 14.79s, V2 19.63s, V3 6.50s and embellishment 5.95s. V2 produced 4 sections / 5 scenes / 7 actors / 18 events; V3 produced 3 sections / 4 scenes, and its second request hit the new KV in 321ms.

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

The response keeps the original-script canonical title and a layered identity: `canonicalTitle`, `originalArtists`, `coverPerformers`, `uploader`, `aliases`, `lyricSearchQueries`, `isCover`, `confidence`, and `needsReview`. Lyric queries use the cleaned original-script title with original-artist and cover-performer forms; translation aliases stay on `aliases` for matching, not as search keywords. For explicit covers, the model may supply an original artist from reliable catalog knowledge only at high confidence; uncertain attributions remain empty and are marked for review. Deterministic post-processing prevents Japanese titles from being replaced by translations or a cover performer from being mislabeled as the original artist. KV caches identical requests for 30 days. The current prompt version is `music-metadata-v8-gemini-3.7-flash`.

The current upstream API key is stored only as the Cloudflare secret `CPA_UPSTREAM_API_KEY`; the legacy `UPSTREAM_API_KEY` remains available only for version rollback. The public base URL and model ID are configuration variables. The Worker tries OpenAI-compatible Chat Completions first and Responses API when the chat endpoint reports a compatibility status. If the upstream is unavailable or incompatible, it returns deterministic normalization with `degraded: true`, does not cache that degraded result, and never calls Workers AI.

The service intentionally does not fetch or proxy lyrics.
