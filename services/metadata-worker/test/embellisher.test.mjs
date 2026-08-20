import test from "node:test";
import assert from "node:assert/strict";
import {
  sanitizeEmbellisherInput,
  finalizeEmbellisherOutput,
  deterministicFallbackEmbellishment,
  ALLOWED_STYLES,
} from "../src/embellisher.js";

test("sanitizeEmbellisherInput validates track and line structures", () => {
  const raw = {
    trackID: "BV123_1",
    title: "夜に駆ける",
    artist: "YOASOBI",
    duration: 260,
    lyricsHash: "hash123",
    lines: [
      { index: 0, text: "沈むように溶けてゆくように", words: [{ index: 0, text: "沈むように" }] },
    ],
  };
  const input = sanitizeEmbellisherInput(raw);
  assert.equal(input.trackID, "BV123_1");
  assert.equal(input.title, "夜に駆ける");
  assert.equal(input.lines.length, 1);
  assert.equal(input.lines[0].words.length, 1);
});

test("finalizeEmbellisherOutput filters invalid styles and clamps line indices", () => {
  const input = {
    trackID: "BV123_1",
    lyricsHash: "hash123",
    lines: [
      { index: 0, text: "夜空に光る星", words: [{ index: 0, text: "夜空に" }, { index: 1, text: "光る" }, { index: 2, text: "星" }] },
      { index: 1, text: "静かに息を潜めて", words: [] },
    ],
  };

  const aiOutput = {
    mood: "Mysterious & Radiant",
    cues: [
      { lineIndex: 0, wordIndex: 2, style: "shimmer", note: "star" },
      { lineIndex: 0, wordIndex: 99, style: "shimmer" }, // invalid word index, will be sanitized to wordIndex: null or dropped if invalid
      { lineIndex: 1, style: "whisper", note: "quiet" },
      { lineIndex: 5, style: "impact" }, // out of bounds line
      { lineIndex: 0, style: "invalid_style" }, // invalid style
    ],
  };

  const output = finalizeEmbellisherOutput(aiOutput, input);
  assert.equal(output.mood, "Mysterious & Radiant");
  assert.equal(output.cues.length, 2);
  assert.equal(output.cues[0].lineIndex, 0);
  assert.equal(output.cues[0].wordIndex, 2);
  assert.equal(output.cues[0].style, "shimmer");
  assert.equal(output.cues[1].lineIndex, 1);
  assert.equal(output.cues[1].style, "whisper");
});

test("ALLOWED_STYLES covers all 12 styles", () => {
  const expected = [
    "whisper",
    "shimmer",
    "impact",
    "floating",
    "digital",
    "ripple",
    "neon",
    "blaze",
    "crystallize",
    "heartbeat",
    "vintage",
    "sway",
  ];
  for (const style of expected) {
    assert.ok(ALLOWED_STYLES.has(style), `Missing style: ${style}`);
  }
});

test("deterministicFallbackEmbellishment handles fallback gracefully", () => {
  const input = {
    trackID: "BV1",
    lyricsHash: "h1",
    lines: [
      { index: 0, text: "Jump!", words: [] },
      { index: 1, text: "Where?", words: [] },
    ],
  };
  const fallback = deterministicFallbackEmbellishment(input);
  assert.equal(fallback.cues.length, 2);
  assert.equal(fallback.cues[0].style, "impact");
  assert.equal(fallback.cues[1].style, "floating");
});
