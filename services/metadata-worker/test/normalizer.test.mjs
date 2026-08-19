import test from "node:test";
import assert from "node:assert/strict";
import {
  deterministicFallback,
  finalizeNormalization,
  quotedAlternatives,
  sanitizeInput,
} from "../src/normalizer.js";
import {
  buildChatJSONBody,
  buildChatPlainBody,
  buildResponsesPlainBody,
  parseChatCompletionsResponse,
  parseResponsesResponse,
} from "../src/provider.js";
import {
  compactDirectorPromptInputs,
  compactStageBiblePromptInput,
  finalizePerformanceScore,
  mergeDirectorOutputs,
  sanitizeDirectorInput,
  sanitizeStageBible,
} from "../src/director.js";

test("keeps the Japanese side of a bilingual quoted title", () => {
  const input = sanitizeInput({
    title: "【花譜】日文翻唱《夏夜のマジック/夏夜的魔法》",
    uploader: "花譜 - KAF",
  });
  const fallback = deterministicFallback(input);
  assert.equal(fallback.canonicalTitle, "夏夜のマジック");
  assert.deepEqual(fallback.aliases, ["夏夜的魔法"]);
  assert.deepEqual(fallback.performers, ["花譜"]);
});

test("server guard rejects an AI translation of Japanese canonical text", () => {
  const input = sanitizeInput({ title: "YOASOBI「アイドル」Official Music Video" });
  const result = finalizeNormalization(input, {
    canonicalTitle: "偶像",
    artists: ["YOASOBI"],
    performers: [],
    aliases: [],
    language: "zh",
    confidence: 0.99,
    needsReview: false,
    evidence: ["model"],
  });
  assert.equal(result.canonicalTitle, "アイドル");
  assert.equal(result.language, "ja");
  assert.equal(result.needsReview, false);
  assert.ok(result.evidence.includes("japanese-original-guard"));
});

test("separates an explicit artist and title", () => {
  const input = sanitizeInput({ title: "ヨルシカ - だから僕は音楽を辞めた (Official Video)" });
  const result = deterministicFallback(input);
  assert.equal(result.canonicalTitle, "だから僕は音楽を辞めた");
  assert.deepEqual(result.artists, ["ヨルシカ"]);
});

test("keeps a cover performer separate and prioritizes the inferred original artist for lyrics", () => {
  const input = sanitizeInput({
    title: "【花譜】日文翻唱《夏夜のマジック/夏夜的魔法》",
    uploader: "花譜 - KAF",
  });
  const result = finalizeNormalization(input, {
    canonicalTitle: "夏夜のマジック",
    artists: ["土岐麻子"],
    performers: ["花譜"],
    aliases: ["夏夜的魔法"],
    language: "ja",
    confidence: 0.94,
    needsReview: false,
    evidence: ["catalog-original-artist", "explicit-cover-performer"],
  });

  assert.deepEqual(result.artists, ["土岐麻子"]);
  assert.deepEqual(result.originalArtists, ["土岐麻子"]);
  assert.deepEqual(result.performers, ["花譜"]);
  assert.deepEqual(result.coverPerformers, ["花譜"]);
  assert.equal(result.isCover, true);
  assert.deepEqual(result.lyricSearchQueries, [
    "夏夜のマジック 土岐麻子",
    "夏夜のマジック",
    "夏夜のマジック 花譜",
  ]);
  assert.equal(result.lyricSearchQueries.some((query) => query.includes("夏夜的魔法")), false);
  assert.equal(result.needsReview, false);
});

test("rejects a cover performer mislabeled as the original artist", () => {
  const input = sanitizeInput({ title: "Ado - unravel 歌ってみた", uploader: "Ado" });
  const result = finalizeNormalization(input, {
    canonicalTitle: "unravel",
    artists: ["Ado"],
    performers: ["Ado"],
    aliases: [],
    language: "en",
    confidence: 0.92,
    needsReview: false,
    evidence: ["explicit-cover-performer"],
  });

  assert.deepEqual(result.artists, []);
  assert.deepEqual(result.originalArtists, []);
  assert.deepEqual(result.performers, ["Ado"]);
  assert.equal(result.isCover, true);
  assert.equal(result.needsReview, true);
});

test("does not treat an official YOASOBI upload as a cover", () => {
  const input = sanitizeInput({ title: "YOASOBI「アイドル」Official Music Video", uploader: "YOASOBI" });
  const result = finalizeNormalization(input, {
    canonicalTitle: "アイドル",
    artists: ["YOASOBI"],
    performers: [],
    aliases: [],
    language: "ja",
    confidence: 0.97,
    needsReview: false,
    evidence: ["quoted-title", "explicit-original-artist"],
  });

  assert.equal(result.isCover, false);
  assert.deepEqual(result.originalArtists, ["YOASOBI"]);
  assert.equal(result.lyricSearchQueries[0], "アイドル YOASOBI");
  assert.equal(result.needsReview, false);
});

test("leaves original artists empty when a cover title has no reliable catalog match", () => {
  const input = sanitizeInput({ title: "夏夜のマジック", uploader: "匿名翻唱UP" });
  const result = finalizeNormalization(input, {
    canonicalTitle: "夏夜のマジック",
    artists: ["土岐麻子"],
    performers: [],
    aliases: [],
    language: "ja",
    confidence: 0.4,
    needsReview: true,
    evidence: ["catalog-original-artist"],
  });

  assert.equal(result.isCover, false);
  assert.deepEqual(result.originalArtists, []);
  assert.equal(result.lyricSearchQueries[0], "夏夜のマジック");
  assert.equal(result.needsReview, true);
});

test("recognizes acoustic cover and Chinese lyric-rewrite markers", () => {
  const acoustic = sanitizeInput({ title: "unravel acoustic cover", uploader: "Ado" });
  assert.equal(finalizeNormalization(acoustic, { canonicalTitle: "unravel", artists: [], performers: ["Ado"] }).isCover, true);

  const rewrite = sanitizeInput({ title: "晴天 中文填词", uploader: "花譜" });
  assert.equal(finalizeNormalization(rewrite, { canonicalTitle: "晴天", artists: ["周杰伦"], performers: ["花譜"] }).isCover, true);
});

test("extracts multiple quote styles without translating", () => {
  assert.deepEqual(quotedAlternatives("ずっと真夜中でいいのに。『秒針を噛む』MV"), ["秒針を噛む"]);
});

test("parses an OpenAI-compatible structured chat response", () => {
  const result = parseChatCompletionsResponse({
    choices: [{ message: { content: '{"canonicalTitle":"アイドル"}' } }],
  });
  assert.equal(result.canonicalTitle, "アイドル");
});

test("parses an OpenAI Responses API fallback", () => {
  const result = parseResponsesResponse({
    output: [{ content: [{ type: "output_text", text: '{"canonicalTitle":"アイドル"}' }] }],
  });
  assert.equal(result.canonicalTitle, "アイドル");
});

test("builds compatibility requests without advanced parameters", () => {
  const jsonBody = buildChatJSONBody("gpt-5.6-luna", "normalize", { title: "晴天" });
  assert.equal(jsonBody.response_format.type, "json_object");
  assert.equal(jsonBody.reasoning_effort, undefined);

  const chatBody = buildChatPlainBody("gpt-5.6-luna", "normalize", { title: "晴天" });
  assert.equal(chatBody.response_format, undefined);
  assert.equal(chatBody.messages.length, 2);

  const responsesBody = buildResponsesPlainBody("gpt-5.6-luna", "normalize", { title: "晴天" });
  assert.equal(responsesBody.text, undefined);
  assert.equal(responsesBody.model, "gpt-5.6-luna");
});

test("sanitizes lyric director input without rewriting lyric text", () => {
  const input = sanitizeDirectorInput({
    trackID: "BV1#42",
    title: "アイドル",
    artist: "YOASOBI",
    duration: 210,
    lyricsHash: "a".repeat(64),
    target: { device: "iPhone 17 Pro", os: "iOS 27" },
    lines: [
      {
        index: 0,
        from: 0,
        to: 4.2,
        text: "無敵の笑顔で荒らすメディア",
        voiceRole: "duetA",
        layerID: "vocal-a",
        overlapGroup: "chorus",
        words: [
          { index: 0, from: 0, to: 0.4, text: "無" },
          { index: 1, from: 0.4, to: 0.8, text: "敵" },
        ],
      },
      { index: 1, from: 4.2, to: 7.8, text: "知りたいその秘密ミステリアス" },
    ],
  });
  assert.equal(input.lines[0].text, "無敵の笑顔で荒らすメディア");
  assert.equal(input.lines[0].words[1].text, "敵");
  assert.equal(input.lines[0].voiceRole, "duetA");
  assert.equal(input.lines[0].overlapGroup, "chorus");
  assert.equal(input.target.device, "iPhone 17 Pro");
});

test("builds and bounds a whole-song stage bible input", () => {
  const input = sanitizeDirectorInput({
    trackID: "BVSTAGE#1",
    title: "Stage",
    artist: "Artist",
    duration: 30,
    lyricsHash: "9".repeat(64),
    lines: [
      { index: 0, from: 0, to: 3, text: "left", voiceRole: "duetA", overlapGroup: "duet" },
      { index: 1, from: 0, to: 3, text: "right", voiceRole: "duetB", overlapGroup: "duet" },
    ],
  });
  const compact = compactStageBiblePromptInput(input);
  assert.deepEqual(compact.track, ["Stage", "Artist", 30]);
  assert.deepEqual(compact.outline[0], [0, 0, 3, "left", "duetA", "duet"]);
  assert.deepEqual(sanitizeStageBible({
    concept: " opposing voices ",
    motif: "converging rails",
    intensityArc: "quiet to united",
  }), {
    concept: "opposing voices",
    motif: "converging rails",
    intensityArc: "quiet to united",
  });
});

test("compacts long word-timed director input without losing timing or indices", () => {
  const raw = {
    trackID: "BVCOMPACT#1",
    title: "千鳥",
    artist: "ヨルシカ",
    duration: 257,
    lyricsHash: "f".repeat(64),
    lines: Array.from({ length: 42 }, (_, lineIndex) => ({
      index: lineIndex,
      from: lineIndex * 4.001,
      to: lineIndex * 4.001 + 3.999,
      text: "風がおもてで呼んでいる",
      words: Array.from({ length: 10 }, (_, wordIndex) => ({
        index: wordIndex,
        from: lineIndex * 4.001 + wordIndex * 0.2,
        to: lineIndex * 4.001 + wordIndex * 0.2 + 0.18,
        text: "風",
      })),
    })),
  };
  const input = sanitizeDirectorInput(raw);
  const compact = compactDirectorPromptInputs(input);

  assert.equal(compact.length, 4);
  assert.deepEqual(compact[0].track, ["千鳥", "ヨルシカ", 257]);
  assert.deepEqual(compact[0].segment, [0, 11, 42]);
  assert.equal(compact[0].outline.length, 42);
  assert.deepEqual(compact[0].lines[0].slice(0, 4), [0, 0, 3.999, "風がおもてで呼んでいる"]);
  assert.deepEqual(compact[0].lines[0][4][2], [2, 0.4, 0.58, "風"]);
  assert.deepEqual(compact[3].lines[5][4][9], [9, 165.841, 166.021, "風"]);
  assert.ok(Math.max(...compact.map((segment) => JSON.stringify(segment).length)) < JSON.stringify(input).length * 0.45);
});

test("merges successful director segments before one global validation pass", () => {
  const merged = mergeDirectorOutputs([
    {
      mood: "quiet",
      compositions: [{ lineIndex: 0, textLineIndices: [0, 1] }],
      scenes: [{ lineIndex: 0, effect: "breathe" }],
      wordCues: [],
    },
    {
      mood: "climax",
      compositions: [],
      scenes: [{ lineIndex: 12, effect: "impact" }],
      wordCues: [{ lineIndex: 12, startWordIndex: 0, endWordIndex: 2, effect: "impact" }],
    },
  ]);

  assert.equal(merged.mood, "quiet");
  assert.equal(merged.compositions.length, 1);
  assert.deepEqual(merged.scenes.map((scene) => scene.lineIndex), [0, 12]);
  assert.equal(merged.wordCues.length, 1);
});

test("director score drops unknown scenes and clamps performance parameters", () => {
  const input = sanitizeDirectorInput({
    trackID: "BV1#42",
    title: "Song",
    artist: "Artist",
    duration: 120,
    lyricsHash: "b".repeat(64),
    lines: [
      { index: 0, from: 0, to: 3, text: "again again" },
      { index: 1, from: 3, to: 7, text: "where are you?" },
    ],
  });
  const score = finalizePerformanceScore(input, {
    mood: "dramatic",
    compositions: [
      { lineIndex: 0, textLineIndices: [1, 0, 1, 99] },
      { lineIndex: 1, textLineIndices: [0] },
    ],
    scenes: [
      { lineIndex: 0, effect: "echo", alignment: "center", direction: -5, intensity: 9, fontScale: 4, trackingScale: 0 },
      { lineIndex: 0, effect: "impact", intensity: 1 },
      { lineIndex: 1, effect: "unknown" },
      { lineIndex: 99, effect: "rise" },
    ],
  }, "director-test-v1");
  assert.equal(score.version, "lyric-performance-v4");
  assert.equal(score.lineCount, 2);
  assert.deepEqual(score.compositions, [
    { lineIndex: 0, textLineIndices: [1, 0] },
    { lineIndex: 1, textLineIndices: [1] },
  ]);
  assert.equal(score.scenes.length, 1);
  assert.deepEqual(score.scenes[0], {
    lineIndex: 0,
    effect: "echo",
    alignment: "center",
    direction: -1,
    intensity: 1.25,
    fontScale: 1.18,
    trackingScale: 0.5,
  });
});

test("director score accepts expanded effects and rejects cascade on a solo composition", () => {
  const input = sanitizeDirectorInput({
    trackID: "BVEXPANDED#1",
    title: "Expanded",
    artist: "Artist",
    duration: 40,
    lyricsHash: "c".repeat(64),
    lines: [
      { index: 0, from: 0, to: 4, text: "quiet truth" },
      { index: 1, from: 4, to: 8, text: "turn" },
      { index: 2, from: 8, to: 12, text: "open wide" },
      { index: 3, from: 12, to: 16, text: "answer arrives" },
    ],
  });
  const score = finalizePerformanceScore(input, {
    mood: "expanding",
    compositions: [
      { lineIndex: 0, textLineIndices: [0] },
      { lineIndex: 1, textLineIndices: [1] },
      { lineIndex: 2, textLineIndices: [2] },
      { lineIndex: 3, textLineIndices: [2, 3] },
    ],
    scenes: [
      { lineIndex: 0, effect: "cascade" },
      { lineIndex: 0, effect: "focus" },
      { lineIndex: 1, effect: "drop" },
      { lineIndex: 2, effect: "stretch" },
      { lineIndex: 3, effect: "cascade" },
    ],
  }, "director-expanded-v1");

  assert.deepEqual(score.scenes.map((scene) => scene.effect), ["focus", "drop", "stretch", "cascade"]);
});

test("director score accepts one bounded word cue per timed line and drops invalid ranges", () => {
  const input = sanitizeDirectorInput({
    trackID: "BVWORD#1",
    title: "Word Stage",
    artist: "Artist",
    duration: 20,
    lyricsHash: "d".repeat(64),
    lines: [
      {
        index: 0,
        from: 0,
        to: 3,
        text: "まだ歌える",
        words: [
          { index: 0, from: 0, to: 0.4, text: "ま" },
          { index: 1, from: 0.4, to: 0.8, text: "だ" },
          { index: 2, from: 0.8, to: 1.2, text: "歌" },
          { index: 3, from: 1.2, to: 1.6, text: "え" },
          { index: 4, from: 1.6, to: 2, text: "る" },
        ],
      },
      { index: 1, from: 3, to: 6, text: "plain", words: [] },
    ],
  });
  const score = finalizePerformanceScore(input, {
    mood: "rising",
    compositions: [
      { lineIndex: 0, textLineIndices: [0] },
      { lineIndex: 1, textLineIndices: [1] },
    ],
    scenes: [{ lineIndex: 0, effect: "rise" }],
    wordCues: [
      { lineIndex: 0, startWordIndex: 2, endWordIndex: 4, effect: "stretch", intensity: 2, direction: -1 },
      { lineIndex: 0, startWordIndex: 0, endWordIndex: 1, effect: "impact" },
      { lineIndex: 1, startWordIndex: 0, endWordIndex: 0, effect: "sweep" },
      { lineIndex: 0, startWordIndex: 4, endWordIndex: 2, effect: "echoTrail" },
    ],
  }, "director-word-v1");

  assert.deepEqual(score.wordCues, [{
    lineIndex: 0,
    startWordIndex: 2,
    endWordIndex: 4,
    effect: "stretch",
    intensity: 1.25,
    direction: -1,
  }]);
});

test("director score accepts bounded v5 stage directives without weakening v4", () => {
  const input = sanitizeDirectorInput({
    trackID: "BVSTAGE#2",
    title: "Stage",
    artist: "Artist",
    duration: 20,
    lyricsHash: "8".repeat(64),
    lines: [
      { index: 0, from: 0, to: 4, text: "fall" },
      { index: 1, from: 4, to: 8, text: "answer", voiceRole: "backing" },
    ],
  });
  const score = finalizePerformanceScore(input, {
    mood: "kinetic",
    compositions: [],
    scenes: [],
    stageBible: { concept: "gravity", motif: "fall and gather", intensityArc: "1<2" },
    stageDirectives: [
      { lineIndex: 0, behavior: "gravityDrop", alignment: "center", intensity: 9, fontScale: 4, glyphStagger: 1, paletteRole: "warm" },
      { lineIndex: 1, behavior: "echo", alignment: "bad", intensity: 0, fontScale: 0, glyphStagger: -1, paletteRole: "secondary" },
      { lineIndex: 1, behavior: "unknown" },
    ],
  }, "director-stage-v5");

  assert.deepEqual(score.stageBible, {
    concept: "gravity",
    motif: "fall and gather",
    intensityArc: "1<2",
  });
  assert.deepEqual(score.stageDirectives, [
    { lineIndex: 0, behavior: "gravityDrop", alignment: "center", direction: 1, intensity: 1.25, fontScale: 1.22, glyphStagger: 0.14, paletteRole: "warm" },
    { lineIndex: 1, behavior: "echo", direction: 1, intensity: 0.35, fontScale: 0.78, glyphStagger: 0, paletteRole: "secondary" },
  ]);
});
