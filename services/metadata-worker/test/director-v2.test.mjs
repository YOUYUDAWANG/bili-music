import test from "node:test";
import assert from "node:assert/strict";
import {
  finalizeStageScoreV2,
  heuristicBible,
  sanitizeStyleBible,
  sliceSections,
} from "../src/director-v2.js";
import { finalizePerformanceScore, sanitizeDirectorInput } from "../src/director.js";

const input = sanitizeDirectorInput({
  trackID: "fixture",
  title: "Night Signal",
  artist: "Test",
  duration: 180,
  lyricsHash: "a".repeat(64),
  lines: [
    { index: 0, from: 0, to: 2, text: "左声部", voiceRole: "duetA", overlapGroup: "duet", words: [] },
    { index: 1, from: 0, to: 2, text: "右声部", voiceRole: "duetB", overlapGroup: "duet", words: [] },
    { index: 2, from: 2, to: 4, text: "hello world", voiceRole: "lead", words: [
      { index: 0, from: 2, to: 2.8, text: "hello" },
      { index: 1, from: 2.9, to: 4, text: "world" },
    ] },
    { index: 3, from: 4, to: 6, text: "again again", voiceRole: "lead", words: [] },
  ],
});
input.tokens = [
  { lineIndex: 2, id: 0, text: "hello", glyphFrom: 0, glyphTo: 5, kind: "word" },
  { lineIndex: 2, id: 1, text: " ", glyphFrom: 5, glyphTo: 6, kind: "whitespace" },
  { lineIndex: 2, id: 2, text: "world", glyphFrom: 6, glyphTo: 11, kind: "word" },
];

test("heuristic bible sections cover the song without a 12-line machine split", () => {
  const bible = heuristicBible(input);
  assert.equal(bible.paletteStrategy, "coverAnalogous");
  assert.ok(bible.sections.length >= 2);
  assert.equal(bible.sections[0].lineFrom, 0);
  assert.equal(bible.sections.at(-1).lineTo, 3);
});

test("invalid token and glyph targets are dropped while valid scenes remain", () => {
  const bible = sanitizeStyleBible(null, input);
  const score = finalizeStageScoreV2(input, bible, [[
    {
      id: "good",
      lineIndices: [2],
      composition: "singleAnchor",
      actors: [
        { id: "base", target: { kind: "line", lineIndex: 2 }, role: "base", anchor: "center", typeRole: "normal", paletteRole: "primary" },
        { id: "hero", target: { kind: "tokens", lineIndex: 2, tokenIndices: [0] }, role: "protagonist", anchor: "center", typeRole: "hero", paletteRole: "accent" },
        { id: "bad", target: { kind: "tokens", lineIndex: 2, tokenIndices: [99] }, role: "protagonist", anchor: "center", typeRole: "hero", paletteRole: "accent" },
      ],
      events: [
        { actorID: "base", phase: "entrance", verb: "appear", start: 0, duration: 0.3, intensity: 0.5, reason: "structuralTransition" },
        { actorID: "hero", phase: "performance", verb: "pulse", start: 0.4, duration: 0.2, intensity: 1, reason: "actionWord" },
        { actorID: "base", phase: "entrance", verb: "dissolve", start: 0, duration: 0.2, intensity: 1, reason: "structuralTransition" },
        { actorID: "missing", phase: "performance", verb: "drop", start: 0.4, duration: 0.2, intensity: 1, reason: "actionWord" },
      ],
      handoffOut: { kind: "push", direction: "trailing" },
    },
    {
      id: "illegal-duet",
      lineIndices: [3],
      composition: "splitVoices",
      actors: [{ id: "base", target: { kind: "line", lineIndex: 3 }, role: "base", anchor: "center", typeRole: "normal", paletteRole: "primary" }],
      events: [],
    },
  ]], "test-v2");
  assert.equal(score.version, "lyric-stage-v2-events");
  assert.equal(score.scenes.length, 2);
  assert.deepEqual(score.scenes[0].actors.map((actor) => actor.id), ["base", "hero"]);
  assert.equal(score.scenes[0].events.length, 2);
  assert.equal(score.scenes[1].composition, "stacked");
});

test("partial batches keep successful scenes", () => {
  const bible = heuristicBible(input);
  const score = finalizeStageScoreV2(input, bible, [
    [{
      id: "keep",
      lineIndices: [0, 1],
      composition: "splitVoices",
      actors: [
        { id: "a", target: { kind: "line", lineIndex: 0 }, role: "vocalA", anchor: "leading", typeRole: "normal", paletteRole: "accent" },
        { id: "b", target: { kind: "line", lineIndex: 1 }, role: "vocalB", anchor: "trailing", typeRole: "normal", paletteRole: "warm" },
      ],
      events: [
        { actorID: "a", phase: "entrance", verb: "appear", start: 0, duration: 0.3, intensity: 0.7, reason: "vocalOverlap", relation: { kind: "mirrorWith", actorID: "b" } },
      ],
      handoffOut: { kind: "dissolve" },
    }],
    null,
  ], "test-v2");
  assert.equal(score.scenes.length, 1);
  assert.equal(score.scenes[0].composition, "splitVoices");
  assert.equal(score.scenes[0].events[0].relation.kind, "mirrorWith");
});

test("long songs slice sections instead of forcing 12-line chunks", () => {
  const long = sanitizeDirectorInput({
    ...input,
    lines: Array.from({ length: 40 }, (_, index) => ({
      index,
      from: index,
      to: index + 0.8,
      text: `line ${index}`,
      voiceRole: "lead",
      words: [],
    })),
  });
  const slices = sliceSections(heuristicBible(long), 16);
  assert.ok(slices.every((slice) => slice.lineTo - slice.lineFrom < 16));
  assert.ok(slices.length >= 3);
  assert.ok(slices.length <= 4);
});

test("very long songs keep at most four concurrent scene slices", () => {
  const long = sanitizeDirectorInput({
    ...input,
    lines: Array.from({ length: 180 }, (_, index) => ({
      index,
      from: index,
      to: index + 0.8,
      text: `line ${index}`,
      voiceRole: "lead",
      words: [],
    })),
  });
  const slices = sliceSections(heuristicBible(long));
  assert.ok(slices.length >= 1);
  assert.ok(slices.length <= 4);
  assert.ok(slices.every((slice) => slice.lineFrom >= 0 && slice.lineTo <= 179 && slice.lineTo >= slice.lineFrom));
});

test("v1 finalize still returns the legacy envelope", () => {
  const v1 = finalizePerformanceScore(input, {
    mood: "legacy",
    compositions: [],
    scenes: [{ lineIndex: 2, effect: "focus", direction: 1, intensity: 0.8, fontScale: 1, trackingScale: 1 }],
    wordCues: [],
    stageDirectives: [],
  }, "luna-lyric-director-v5-stage-preview");
  assert.equal(v1.version, "lyric-performance-v4");
  assert.equal(v1.lineCount, 4);
  assert.equal(v1.scenes[0].effect, "focus");
});
