import test from "node:test";
import assert from "node:assert/strict";

import worker from "../src/index.js";

const origin = "https://worker.example";

class MemoryKV {
  constructor() {
    this.values = new Map();
    this.puts = 0;
  }

  async get(key, type) {
    const value = this.values.get(key);
    if (value === undefined) return null;
    return type === "json" ? JSON.parse(value) : value;
  }

  async put(key, value) {
    this.values.set(key, value);
    this.puts += 1;
  }
}

function v3Payload() {
  return {
    trackID: "BV-route:1",
    title: "Route song",
    artist: "Artist",
    duration: 30,
    lyricsHash: "a".repeat(64),
    audioSummaryHash: "b".repeat(64),
    lines: [
      { index: 0, from: 0, to: 2, text: "hello", voiceRole: "lead", layerID: "line-0", words: [] },
      { index: 1, from: 2, to: 4, text: "world", voiceRole: "lead", layerID: "line-1", words: [] },
    ],
    audioSummary: {
      version: "audio-v3",
      summaryHash: "b".repeat(64),
      confidence: { overall: 0.8 },
      sections: [{ index: 0, from: 0, to: 4, lineFrom: 0, lineTo: 1, meanEnergy: 0.5 }],
      lines: [{ lineIndex: 0, from: 0, to: 2, meanEnergy: 0.4 }],
    },
  };
}

function v4Payload() {
  const lines = ["hello", "world", "hello", "again"].map((text, index) => ({
    index,
    from: index * 2,
    to: index * 2 + 1.8,
    text,
    voiceRole: "lead",
    layerID: `line-${index}`,
    overlapGroup: null,
    words: [],
    tokens: [{ index: 0, text }],
    hasRealWordTiming: false,
  }));
  return {
    trackID: "BV-route-v4:1",
    title: "Route V4 song",
    artist: "Artist",
    duration: 8,
    lyricsHash: "c".repeat(64),
    audioScoreHash: "d".repeat(64),
    lines,
    audioScore: {
      version: "lyric-stage-audio-structure-score-v4",
      availability: "ready",
      semantics: {
        energy: "trackRelativePercentile",
        brightness: "zeroCrossingRateProxy",
        pitch: "dominantMixMIDIAutocorrelation",
        vocalActivity: "energyPitchConfidenceProxy",
        downbeat: "heuristicFourBeatBar",
        quantization: "q8Milliseconds",
      },
      confidence: {
        beat: 200, downbeat: 180, onset: 205, energy: 220,
        pitch: 170, sections: 210, overall: 210,
      },
      durationMilliseconds: 8_000,
      tempoSegments: [[0, 8_000, 1_200, 200]],
      sections: [[
        0, 0, 8_000, 0, 3, 220, 130, 210, 20, 110,
        150, 100, 8, 170, 55, 180, 0, 100,
      ]],
      lineFacts: lines.map((line) => [
        line.index, 0, 128, 20, -40, 16, 100, 190, 10, 2, 180, 0, 0,
      ]),
      lineDetails: [],
      moments: [["start-0", "sectionStart", 0, 100, 230, 220, 0]],
    },
  };
}

function request(path, body, apiKey = "test-key") {
  return new Request(`${origin}${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(apiKey ? { authorization: `Bearer ${apiKey}` } : {}),
    },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

function environment(overrides = {}) {
  return {
    API_KEY: "test-key",
    UPSTREAM_API_KEY: "upstream-key",
    UPSTREAM_BASE_URL: "https://upstream.example",
    MODEL: "test-luna",
    PROMPT_VERSION: "metadata-test",
    LYRIC_DIRECTOR_V3_VERSION: "director-v3-test",
    LYRIC_DIRECTOR_V3_ENABLED: "true",
    LYRIC_DIRECTOR_V4_VERSION: "director-v4-test",
    LYRIC_DIRECTOR_V4_ENABLED: "true",
    METADATA_CACHE: new MemoryKV(),
    ...overrides,
  };
}

test("health advertises every additive route and reports the independent V3/V4 kill switches", async () => {
  const response = await worker.fetch(new Request(`${origin}/health`), environment({
    LYRIC_DIRECTOR_V3_ENABLED: "false",
    LYRIC_DIRECTOR_V4_ENABLED: "false",
  }), {});
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.deepEqual(body.endpoints, [
    "POST /v1/music/normalize",
    "POST /v1/lyrics/direct",
    "POST /v2/lyrics/direct",
    "POST /v3/lyrics/direct",
    "POST /v4/lyrics/direct",
    "POST /v1/lyrics/embellish",
  ]);
  assert.equal(body.features.lyricDirectorV3.enabled, false);
  assert.equal(body.features.lyricDirectorV4.enabled, false);
  assert.equal(body.features.lyricDirectorV4.grammarVersion, "scene-recipe-grammar-v1");
});

test("all legacy, V3, and V4 POST routes keep Bearer authentication", async () => {
  for (const path of [
    "/v1/music/normalize",
    "/v1/lyrics/direct",
    "/v2/lyrics/direct",
    "/v3/lyrics/direct",
    "/v4/lyrics/direct",
    "/v1/lyrics/embellish",
  ]) {
    const response = await worker.fetch(request(path, {}, null), environment(), {});
    assert.equal(response.status, 401, path);
  }
});

test("actual-body parsing still dispatches every legacy handler", async () => {
  const env = environment({ UPSTREAM_API_KEY: undefined });
  const context = { waitUntil() {} };
  const cases = [
    ["/v1/music/normalize", { title: "「曲名」", uploader: "Artist", duration: 120 }],
    ["/v1/lyrics/direct", v3Payload()],
    ["/v2/lyrics/direct", v3Payload()],
    ["/v1/lyrics/embellish", v3Payload()],
  ];
  for (const [path, payload] of cases) {
    const response = await worker.fetch(request(path, payload), env, context);
    assert.equal(response.status, 200, path);
    assert.equal((await response.json()).degraded, true, path);
  }
});

test("V3 kill switch fails closed after authentication and before upstream work", async () => {
  const response = await worker.fetch(
    request("/v3/lyrics/direct", v3Payload()),
    environment({ LYRIC_DIRECTOR_V3_ENABLED: "false" }),
    {},
  );
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, "temporarily_disabled");
});

test("V4 kill switch fails closed independently after authentication", async () => {
  const response = await worker.fetch(
    request("/v4/lyrics/direct", v4Payload()),
    environment({ LYRIC_DIRECTOR_V4_ENABLED: "false" }),
    {},
  );
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, "temporarily_disabled");
});

test("router enforces actual body bytes for V3 and V4 without relying on Content-Length", async () => {
  const oversized = JSON.stringify({ padding: "x".repeat(99_000) });
  for (const path of ["/v3/lyrics/direct", "/v4/lyrics/direct"]) {
    const oversizedRequest = request(path, oversized);
    assert.equal(oversizedRequest.headers.has("content-length"), false);
    const response = await worker.fetch(oversizedRequest, environment(), {});
    assert.equal(response.status, 413, path);
    assert.equal((await response.json()).error, "payload_too_large", path);
  }
});

test("router reports malformed JSON as a bounded invalid request", async () => {
  const response = await worker.fetch(request("/v3/lyrics/direct", "{"), environment(), {});
  assert.equal(response.status, 400);
  assert.equal((await response.json()).error, "invalid_request");
});

test("V3 returns the frozen contract and awaits KV before a cache hit", async (context) => {
  const originalFetch = globalThis.fetch;
  context.after(() => { globalThis.fetch = originalFetch; });
  let upstreamCalls = 0;
  globalThis.fetch = async () => {
    upstreamCalls += 1;
    return Response.json({
      choices: [{
        message: {
          content: JSON.stringify({
            stageBible: { concept: "signals", motif: "approach", intensityArc: "quiet to clear" },
            sections: [{
              id: "whole", lineFrom: 0, lineTo: 1, kind: "verse",
              intensity: 0.4, motifPhase: "introduce",
            }],
            scenes: [{
              lineIndex: 0, composition: "leadingAnchor",
              companionLineIndices: [], intensity: 0.6, motifRef: "approach",
            }],
          }),
        },
      }],
    });
  };

  const env = environment();
  const firstResponse = await worker.fetch(request("/v3/lyrics/direct", v3Payload()), env, {});
  assert.equal(firstResponse.status, 200);
  const first = await firstResponse.json();
  assert.equal(first.version, "lyric-stage-v3-choreography");
  assert.equal(first.audioSummaryHash, "b".repeat(64));
  assert.equal(first.partial, false);
  assert.equal(first.degraded, false);
  assert.equal(first.cache, "miss");
  assert.equal(env.METADATA_CACHE.puts, 1);

  const secondResponse = await worker.fetch(request("/v3/lyrics/direct", v3Payload()), env, {});
  const second = await secondResponse.json();
  assert.equal(second.cache, "hit");
  assert.equal(upstreamCalls, 1);
  assert.equal(env.METADATA_CACHE.puts, 1);

});

test("V3 invalid model output is degraded and never cached", async (context) => {
  const originalFetch = globalThis.fetch;
  context.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async () => Response.json({
    choices: [{ message: { content: JSON.stringify({ stageBible: {}, sections: [], scenes: [] }) } }],
  });
  const env = environment();
  const response = await worker.fetch(request("/v3/lyrics/direct", v3Payload()), env, {});
  const body = await response.json();
  assert.equal(body.degraded, true);
  assert.equal(body.degradedReason, "empty_or_invalid_scenes");
  assert.equal(body.partial, false);
  assert.equal(env.METADATA_CACHE.puts, 0);
});

test("V4 returns the frozen recipe contract and only then writes its independent cache", async (context) => {
  const originalFetch = globalThis.fetch;
  context.after(() => { globalThis.fetch = originalFetch; });
  let upstreamCalls = 0;
  globalThis.fetch = async () => {
    upstreamCalls += 1;
    return Response.json({
      choices: [{
        message: {
          content: JSON.stringify({
            stageBible: {
              concept: "a remembered rail",
              intensityArc: "quiet, transform, resolve",
              primaryMotif: { signature: "rail", axis: "horizontal", cadence: "phrase" },
            },
            sections: [{
              id: "whole", lineFrom: 0, lineTo: 3, kind: "verse",
              intensity: 0.5, motifPhase: "develop",
            }],
            scenes: [{
              lineIndex: 1,
              family: "railHandoff",
              topology: "relay",
              entrance: "slide",
              focus: "wholeLine",
              sustain: "railTravel",
              continuity: "handoff",
              driver: "lyricReveal",
              landmarkIDs: [],
              companionLineIndices: [0],
              motifPhase: "develop",
              intensity: 0.65,
            }],
          }),
        },
      }],
    });
  };

  const env = environment();
  const firstResponse = await worker.fetch(request("/v4/lyrics/direct", v4Payload()), env, {});
  assert.equal(firstResponse.status, 200);
  const first = await firstResponse.json();
  assert.equal(first.version, "lyric-stage-v4-scene-recipe");
  assert.equal(first.grammarVersion, "scene-recipe-grammar-v1");
  assert.equal(first.audioScoreHash, "d".repeat(64), "App identity is echoed rather than recomputed");
  assert.equal(first.scenes[0].family, "railHandoff");
  assert.equal(first.degraded, false);
  assert.equal(first.cache, "miss");
  assert.equal(env.METADATA_CACHE.puts, 1);

  const secondResponse = await worker.fetch(request("/v4/lyrics/direct", v4Payload()), env, {});
  const second = await secondResponse.json();
  assert.equal(second.cache, "hit");
  assert.equal(upstreamCalls, 1);
  assert.equal(env.METADATA_CACHE.puts, 1);

  const changedScore = v4Payload();
  changedScore.audioScore.lineFacts[0][2] = 9;
  const changedResponse = await worker.fetch(request("/v4/lyrics/direct", changedScore), env, {});
  assert.equal((await changedResponse.json()).cache, "miss");
  assert.equal(upstreamCalls, 2, "server-side score digest isolates a mismatched App hash");
  assert.equal(env.METADATA_CACHE.puts, 2);
});

test("V4 unavailable or invalid direction is degraded and never cached", async (context) => {
  const originalFetch = globalThis.fetch;
  context.after(() => { globalThis.fetch = originalFetch; });
  let upstreamCalls = 0;
  globalThis.fetch = async () => {
    upstreamCalls += 1;
    return Response.json({
      choices: [{ message: { content: JSON.stringify({ stageBible: {}, sections: [], scenes: [] }) } }],
    });
  };

  const invalidEnv = environment();
  const invalidResponse = await worker.fetch(request("/v4/lyrics/direct", v4Payload()), invalidEnv, {});
  const invalid = await invalidResponse.json();
  assert.equal(invalid.degraded, true);
  assert.equal(invalid.degradedReason, "empty_or_invalid_scenes");
  assert.equal(invalidEnv.METADATA_CACHE.puts, 0);

  const unavailablePayload = v4Payload();
  unavailablePayload.audioScore.availability = "missingCache";
  unavailablePayload.audioScore.lineFacts = [];
  const unavailableEnv = environment();
  const unavailableResponse = await worker.fetch(
    request("/v4/lyrics/direct", unavailablePayload),
    unavailableEnv,
    {},
  );
  const unavailable = await unavailableResponse.json();
  assert.equal(unavailable.degraded, true);
  assert.equal(unavailable.degradedReason, "audio_score_unavailable");
  assert.equal(unavailableEnv.METADATA_CACHE.puts, 0);
  assert.equal(upstreamCalls, 1, "unavailable score never reaches Gemini");
});
