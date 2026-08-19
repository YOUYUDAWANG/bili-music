import { deterministicFallback, finalizeNormalization, sanitizeInput } from "./normalizer.js";
import {
  compactDirectorPromptInputs,
  compactStageBiblePromptInput,
  finalizePerformanceScore,
  mergeDirectorOutputs,
  sanitizeDirectorInput,
  sanitizeStageBible,
} from "./director.js";
import {
  compactStageV2BibleInput,
  compactStageV2SceneInput,
  finalizeStageScoreV2,
  heuristicBible,
  sanitizeStyleBible,
  sliceSections,
  STAGE_V2_BIBLE_PROMPT,
  STAGE_V2_SCENE_PROMPT,
} from "./director-v2.js";
import { callOpenAICompatible } from "./provider.js";

const SYSTEM_PROMPT = `You normalize music metadata from Bilibili video titles.
Return only the requested JSON object.
Rules:
1. Never translate, romanize, or replace a Japanese canonical song title. Preserve its original script exactly when it appears in the input.
2. For bilingual forms such as 《日本語曲名/中文译名》, canonicalTitle is the Japanese side and the translation is an alias.
3. Detect cover recordings. artists/originalArtists are the original recording artist(s); performers/coverPerformers are the cover singer(s). Never put a known cover performer or the Bilibili uploader in originalArtists.
4. When a cover is explicit but the original artist is absent from the title, you may identify the original artist from reliable music-catalog knowledge only when highly confident. Add catalog-original-artist to evidence. If uncertain, leave original artists empty and set needsReview=true; never invent a name.
5. uploader is the channel/uploader and is not automatically an artist or performer. A clearly named cover singer may also be the uploader.
6. Remove packaging such as 4K, MV, official, lyrics, subtitles, remastered, 歌ってみた, 翻唱, and resolution markers without deleting meaningful title text.
7. evidence contains short machine-readable reasons such as quoted-title, explicit-original-artist, explicit-cover-performer, catalog-original-artist, or ambiguous-uploader.
8. confidence measures extraction and catalog-attribution confidence.
Return these keys: canonicalTitle (string), artists (string array), performers (string array), aliases (string array), language (ja/zh/ko/en/mixed/und), confidence (0 to 1), needsReview (boolean), evidence (string array).`;

const LYRIC_DIRECTOR_PROMPT = `You are the creative director for a lyric performance on an iPhone 17 Pro music player.
The compact input schema is: track = [title, artist, durationSeconds], segment = [firstLineIndex, lastLineIndex, totalLineCount], outline contains [lineIndex, fromSeconds, text, voiceRole, overlapGroup] for the complete song, each detailed line = [lineIndex, fromSeconds, toSeconds, text, words, voiceRole, layerID, overlapGroup], and each word = [wordIndex, fromSeconds, toSeconds, text]. An empty words array means no real word timing. stageBible contains the whole-song concept, motif, and intensity arc selected by a prior global pass. Direct only the detailed lines while using outline and stageBible to maintain one visual language. Return one JSON object with mood, compositions, scenes, wordCues, and stageDirectives.
Compositions override which real lyric lines are visible at a moment. The app already supplies a one-line composition when an override is omitted, so output compositions only where deliberately showing two or three lines improves phrasing, repetition, anticipation, silence, buildup, or climax. Lyrics are never ellipsized: long text wraps in full, so choose fewer visible lines when their combined length would overcrowd the 340-point-wide lyric stage. Each composition contains lineIndex and textLineIndices, must include its own lineIndex, may reference only existing lines within two positions of it, and may contain at most three unique indices. The array order is the visual top-to-bottom order.
You may use only these effects: rise, impact, drift, breathe, echo, focus, drop, stretch, cascade.
Use scenes to override only lines that benefit from deliberate motion; omit ordinary lines so the local deterministic motion director handles them. Aim to direct roughly 25% to 60% of the lines and shape an arc across verse, repetition, buildup, and climax.
The app always performs a restrained per-word sweep locally when real word timing exists. Use wordCues only for exceptional phrases that deserve additional choreography, roughly 10% to 30% of word-timed lines, with at most one cue per line. Each wordCue contains lineIndex, inclusive startWordIndex and endWordIndex, effect, intensity, and direction. It may reference only word indices supplied on that same line and may span at most 12 words. Use impact for short emphatic phrases, stretch for genuinely sustained phrases, echoTrail only for real repetition or call-and-response, and sweep for an unusually important reveal. Do not invent word timing and omit wordCues for lines whose words array is empty.
Rules:
1. Never rewrite, translate, merge, or split lyric text. Refer to lines only by lineIndex.
2. impact is for brief emphatic or climactic lines; drift for questions or searching motion; breathe for sustained or spacious lines; echo for real repetition; rise for connective motion. focus settles blurred, widely tracked text into clarity for intimate or revealing lines. drop arrives from above for decisive turns. stretch expands compressed typography for opening-up or release. cascade staggers a two- or three-line composition and must not be used on a one-line composition.
3. Avoid choosing the same effect for long uninterrupted runs. Preserve quiet passages and deliberate empty space.
Use the expanded effects where they improve the song-level arc; do not fall back to using only the original five effects.
4. Parameters must stay restrained for a handheld screen: intensity 0.35-1.25, fontScale 0.90-1.18, trackingScale 0.50-1.80, direction -1 or 1, alignment leading/center/trailing. wordCues use only sweep, impact, stretch, or echoTrail.
5. Omit ordinary one-line compositions. Output scenes as objects containing lineIndex, effect, alignment, direction, intensity, fontScale, trackingScale.
6. stageDirectives control the kinetic typography canvas. Use only these behaviors: assemble, gravityDrop, ripple, stretch, echo, drift, focus, converge. Each directive contains lineIndex, behavior, optional alignment, direction, intensity, fontScale, glyphStagger, and optional paletteRole (primary/accent/warm/secondary). Use real voiceRole and overlapGroup: overlapping duet voices should usually converge from opposite sides; backing vocals should remain secondary or echo-like. Direct roughly 35% to 70% of detailed lines and let the local compiler fill the rest.
Return only: mood (short string), compositions (array), scenes (array), wordCues (array), stageDirectives (array).`;

const LYRIC_STAGE_BIBLE_PROMPT = `You are creating the whole-song art direction for an iPhone kinetic-typography lyric stage.
Input track is [title, artist, durationSeconds]. outline entries are [lineIndex, fromSeconds, toSeconds, exactText, voiceRole, overlapGroup]. Do not rewrite lyrics. Identify a coherent visual concept, one repeatable motion motif, and a concise intensity arc that tells later scene directors where to stay quiet and where to climax. Respect lead, backing, duetA, duetB, and together roles. Return only: concept (string), motif (string), intensityArc (string).`;

export default {
  async fetch(request, env, context) {
    const url = new URL(request.url);
    if (request.method === "GET" && (url.pathname === "/" || url.pathname === "/health")) {
      return json({
        ok: true,
        service: "bilimusic-metadata",
        version: env.PROMPT_VERSION,
        endpoints: ["POST /v1/music/normalize", "POST /v1/lyrics/direct", "POST /v2/lyrics/direct"],
      });
    }
    const isNormalize = request.method === "POST" && url.pathname === "/v1/music/normalize";
    const isDirector = request.method === "POST" && url.pathname === "/v1/lyrics/direct";
    const isDirectorV2 = request.method === "POST" && url.pathname === "/v2/lyrics/direct";
    if (!isNormalize && !isDirector && !isDirectorV2) {
      return json({ error: "not_found" }, 404);
    }
    if (!env.API_KEY || request.headers.get("authorization") !== `Bearer ${env.API_KEY}`) {
      return json({ error: "unauthorized" }, 401);
    }

    const contentLength = Number(request.headers.get("content-length") || 0);
    if (contentLength > (isDirector || isDirectorV2 ? (isDirectorV2 ? 98_304 : 65_536) : 8_192)) {
      return json({ error: "payload_too_large" }, 413);
    }

    if (isDirectorV2) {
      return handleLyricDirectionV2(request, env, context);
    }
    if (isDirector) {
      return handleLyricDirection(request, env, context);
    }

    let input;
    try {
      input = sanitizeInput(await request.json());
    } catch (error) {
      return json({ error: "invalid_request", message: error instanceof Error ? error.message : "请求格式错误" }, 400);
    }

    const cacheKey = await digest(`metadata:${env.PROMPT_VERSION}:${JSON.stringify(input)}`);
    const cached = env.METADATA_CACHE ? await env.METADATA_CACHE.get(cacheKey, "json") : null;
    if (cached) return json({ ...cached, cache: "hit" });

    let aiValue = null;
    let upstreamProtocol = null;
    let degraded = false;
    let degradedReason = null;
    try {
      const upstream = await callOpenAICompatible(env, SYSTEM_PROMPT, input);
      aiValue = upstream.value;
      upstreamProtocol = upstream.protocol;
    } catch (error) {
      degraded = true;
      degradedReason = safeDegradedReason(error);
    }

    const normalized = aiValue
      ? finalizeNormalization(input, aiValue)
      : finalizeNormalization(input, deterministicFallback(input));
    const response = {
      version: env.PROMPT_VERSION,
      ...normalized,
      provider: "openai-compatible",
      model: env.MODEL,
      ...(upstreamProtocol ? { upstreamProtocol } : {}),
      degraded,
      ...(degradedReason ? { degradedReason } : {}),
      cache: "miss",
    };

    if (env.METADATA_CACHE && !degraded) {
      context.waitUntil(env.METADATA_CACHE.put(cacheKey, JSON.stringify(response), { expirationTtl: 2_592_000 }));
    }
    return json(response);
  },
};

async function handleLyricDirection(request, env, context) {
  let input;
  try {
    input = sanitizeDirectorInput(await request.json());
  } catch (error) {
    return json({ error: "invalid_request", message: error instanceof Error ? error.message : "请求格式错误" }, 400);
  }

  const directorVersion = env.LYRIC_DIRECTOR_VERSION || "luna-lyric-director-v5-stage-preview";
  const cacheKey = await digest(`director:${directorVersion}:${JSON.stringify(input)}`);
  const cached = env.METADATA_CACHE ? await env.METADATA_CACHE.get(cacheKey, "json") : null;
  if (cached) return json({ ...cached, cache: "hit" });

  let response;
  try {
    let stageBible = null;
    try {
      const bibleResult = await callOpenAICompatible(
        env,
        LYRIC_STAGE_BIBLE_PROMPT,
        compactStageBiblePromptInput(input),
        { maxCompletionTokens: 500, timeoutMilliseconds: 25_000 },
      );
      stageBible = sanitizeStageBible(bibleResult.value);
    } catch {
      // The existing v4 direction path remains usable when the optional
      // whole-song art-direction pass times out.
    }
    const promptInputs = compactDirectorPromptInputs(input).map((segment) => ({
      ...segment,
      ...(stageBible ? { stageBible } : {}),
    }));
    const upstreamResults = await Promise.allSettled(promptInputs.map((promptInput) => callOpenAICompatible(
      env,
      LYRIC_DIRECTOR_PROMPT,
      promptInput,
      { maxCompletionTokens: 2_200, timeoutMilliseconds: 35_000 },
    )));
    const completed = upstreamResults
      .filter((result) => result.status === "fulfilled")
      .map((result) => result.value);
    if (completed.length === 0) {
      const failure = upstreamResults.find((result) => result.status === "rejected");
      throw failure?.reason || new Error("upstream_error");
    }
    const merged = mergeDirectorOutputs(completed.map((result) => result.value));
    if (stageBible) merged.stageBible = stageBible;
    const score = finalizePerformanceScore(
      input,
      merged,
      directorVersion,
    );
    const degraded = score.scenes.length === 0
      && score.wordCues.length === 0
      && score.stageDirectives.length === 0;
    const partial = completed.length !== upstreamResults.length;
    response = {
      ...score,
      provider: "openai-compatible",
      model: env.MODEL,
      upstreamProtocol: [...new Set(completed.map((result) => result.protocol))].join(","),
      degraded,
      ...(degraded ? { degradedReason: "invalid_director_output" } : {}),
      ...(partial ? { partial: true } : {}),
      cache: "miss",
    };
  } catch (error) {
    response = {
      ...finalizePerformanceScore(input, {}, directorVersion),
      provider: "openai-compatible",
      model: env.MODEL,
      degraded: true,
      degradedReason: safeDegradedReason(error),
      cache: "miss",
    };
  }

  if (env.METADATA_CACHE && !response.degraded && !response.partial) {
    context.waitUntil(env.METADATA_CACHE.put(cacheKey, JSON.stringify(response), { expirationTtl: 2_592_000 }));
  }
  return json(response);
}

async function handleLyricDirectionV2(request, env, context) {
  let raw;
  try {
    raw = await request.json();
  } catch {
    return json({ error: "invalid_request", message: "请求格式错误" }, 400);
  }
  let input;
  try {
    input = sanitizeDirectorInput(raw);
    input.tokens = Array.isArray(raw.tokens) ? raw.tokens : [];
  } catch (error) {
    return json({ error: "invalid_request", message: error instanceof Error ? error.message : "请求格式错误" }, 400);
  }

  const directorVersion = env.LYRIC_DIRECTOR_V2_VERSION || "luna-lyric-director-v2-events";
  const cacheKey = await digest(`director-v2:${directorVersion}:${JSON.stringify(input)}`);
  const cached = env.METADATA_CACHE ? await env.METADATA_CACHE.get(cacheKey, "json") : null;
  if (cached) return json({ ...cached, cache: "hit" });

  let response;
  try {
    const heuristic = heuristicBible(input);
    // Existing iOS clients die at 45s with no first byte. Run the style bible
    // and scene slices together so a real song can return before that cutoff.
    const biblePromise = callOpenAICompatible(
      env,
      STAGE_V2_BIBLE_PROMPT,
      compactStageV2BibleInput(input),
      { maxCompletionTokens: 700, timeoutMilliseconds: 18_000 },
    ).then((result) => sanitizeStyleBible(result.value, input))
      .catch(() => heuristic);
    const scenePromise = Promise.allSettled(sliceSections(heuristic).map((section) => callOpenAICompatible(
      env,
      STAGE_V2_SCENE_PROMPT,
      compactStageV2SceneInput(input, section, heuristic),
      { maxCompletionTokens: 1_800, timeoutMilliseconds: 28_000 },
    )));
    const [bible, sceneResults] = await Promise.all([biblePromise, scenePromise]);
    const completed = sceneResults
      .filter((result) => result.status === "fulfilled")
      .map((result) => result.value);
    const batches = completed.map((result) => (
      Array.isArray(result.value?.scenes) ? result.value.scenes : []
    ));
    const score = finalizeStageScoreV2(input, bible, batches, directorVersion);
    const partial = completed.length !== sceneResults.length;
    const degraded = score.scenes.length === 0;
    response = {
      ...score,
      provider: "openai-compatible",
      model: env.MODEL,
      upstreamProtocol: [...new Set(completed.map((result) => result.protocol))].join(","),
      degraded,
      ...(degraded ? { degradedReason: "empty_or_invalid_scenes" } : {}),
      ...(partial ? { partial: true } : {}),
      cache: "miss",
    };
  } catch (error) {
    const bible = sanitizeStyleBible(null, input);
    response = {
      ...finalizeStageScoreV2(input, bible, [], directorVersion),
      provider: "openai-compatible",
      model: env.MODEL,
      degraded: true,
      degradedReason: safeDegradedReason(error),
      cache: "miss",
    };
  }

  if (env.METADATA_CACHE && !response.degraded && !response.partial) {
    await env.METADATA_CACHE.put(cacheKey, JSON.stringify(response), { expirationTtl: 2_592_000 });
  }
  return json(response);
}

function safeDegradedReason(error) {
  if (error instanceof DOMException && (error.name === "TimeoutError" || error.name === "AbortError")) {
    return "upstream_timeout";
  }
  const message = error instanceof Error ? error.message : "upstream_error";
  return /^(?:chat(?:_json|_plain)?_\d{3}|compat_\d{3}_\d{3}_\d{3}|invalid_[a-z_]+|missing_upstream_key|invalid_upstream_url)$/u.test(message)
    ? message
    : "upstream_error";
}

async function digest(value) {
  const data = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(hash)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function json(value, status = 200) {
  return Response.json(value, {
    status,
    headers: {
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}
