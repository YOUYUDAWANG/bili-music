import test from "node:test";
import assert from "node:assert/strict";

import {
  compactStageV3PromptInput,
  finalizeStagePlanV3,
  isUsableStageV3Output,
  sanitizeDirectorV3Input,
  STAGE_V3_CONTRACT_VERSION,
} from "../src/director-v3.js";

function requestPayload(lineCount = 10) {
  const texts = [
    "You & 合図", "静かな声", "You & 合図", "You & 合図", "You & 合図",
    "遠くへ", "まだ続く", "光になる", "息を止めて", "さようなら",
  ];
  return {
    trackID: "BV-test:1",
    title: "Generic benchmark",
    artist: "Artist",
    duration: 180,
    lyricsHash: "a".repeat(64),
    audioSummaryHash: "b".repeat(64),
    lines: Array.from({ length: lineCount }, (_, index) => ({
      index,
      from: index * 3,
      to: index * 3 + 2.5,
      text: texts[index] || `line-${index}`,
      voiceRole: "lead",
      layerID: `line-${index}`,
      overlapGroup: null,
      words: [{ index: 0, from: index * 3, to: index * 3 + 1, text: "word" }],
    })),
    audioSummary: {
      version: "audio-performance-summary-v3",
      mapFingerprint: "map-v3",
      summaryHash: "b".repeat(64),
      duration: 180,
      confidence: { overall: 0.84, beat: 0.7 },
      sections: [
        {
          index: 0, from: 0, to: 15, lineFrom: 0, lineTo: 4,
          meanEnergy: 1.4, energyTrend: "rising", onsetDensity: 0.4,
          pitchTrend: "steady", confidence: 0.8,
        },
        {
          index: 1, from: 15, to: 30,
          meanEnergy: 0.3, energyTrend: -0.4, onsetDensity: 0.2,
          pitchTrend: "falling", confidence: 0.6,
        },
      ],
      lines: [
        {
          lineIndex: 0, from: 0, to: 2.5, sectionIndex: 0,
          meanEnergy: 0.7, peakEnergy: 0.9, energyDelta: 0.2,
          onsetCount: 4, nearestBeatDistance: 0.1,
          pitchStart: 220, pitchEnd: 260, pitchTrend: 30, pitchConfidence: 0.75,
          silenceBefore: 0.2, silenceAfter: 0.1,
        },
      ],
    },
  };
}

test("V3 sanitizer accepts the rich local audio summary and compacts it", () => {
  const input = sanitizeDirectorV3Input(requestPayload());
  assert.equal(input.audioSummaryHash, "b".repeat(64));
  assert.equal(input.audioSummary.confidence, 0.84);
  assert.equal(input.audioSummary.sections[0].meanEnergy, 1);
  assert.equal(input.audioSummary.sections[1].lineFrom, null);
  assert.equal(input.audioSummary.lineFeatures[0].beatStrength, 0.8);
  assert.equal(input.audioSummary.lineFeatures[0].pitchTrend, 30);

  const compact = compactStageV3PromptInput(input);
  assert.equal(compact.audioSummary.sections[0][0], 0);
  assert.equal(compact.audioSummary.lines[0][0], 0);
  assert.equal(compact.audioSummary.lines[0][11], 30);
  assert.equal(compact.outline[0][3], "You & 合図");
  assert.deepEqual(compact.repeatClusters[0].lineIndices, [0, 2, 3, 4]);
  assert.equal(JSON.stringify(compact).includes('"words"'), false);
});

test("V3 requires contiguous zero-based line indices", () => {
  const payload = requestPayload(2);
  payload.lines[1].index = 3;
  assert.throws(() => sanitizeDirectorV3Input(payload), /contiguous from zero/u);
});

test("V3 finalizer emits the frozen contract and repairs section gaps and hook phases", () => {
  const input = sanitizeDirectorV3Input(requestPayload());
  const ai = {
    stageBible: { concept: "two signals", motif: "approach", intensityArc: "quiet to locked" },
    sections: [
      { id: "opening", lineFrom: 0, lineTo: 1, kind: "verse", intensity: -1, motifPhase: "introduce" },
      { id: "ending", lineFrom: 7, lineTo: 9, kind: "outro", intensity: 2, motifPhase: "resolve" },
    ],
    scenes: [
      { lineIndex: 0, composition: "hookLock", companionLineIndices: [1, 99], intensity: 2, motifRef: "signal" },
      { lineIndex: 2, composition: "hookCall", companionLineIndices: [], intensity: 0.7 },
      { lineIndex: 3, composition: "hookCall", companionLineIndices: [], intensity: 0.7 },
      { lineIndex: 4, composition: "hookCall", companionLineIndices: [], intensity: 0.7 },
      { lineIndex: 1, composition: "hero", companionLineIndices: [], intensity: 0.8 },
      { lineIndex: 5, composition: "hero", companionLineIndices: [], intensity: 0.8 },
      { lineIndex: 6, composition: "unknown", companionLineIndices: [], intensity: 0.8 },
    ],
  };
  const score = finalizeStagePlanV3(input, ai, "director-v3-test", "b".repeat(64));

  assert.equal(score.version, STAGE_V3_CONTRACT_VERSION);
  assert.equal(score.audioSummaryHash, "b".repeat(64));
  assert.equal(score.sections[0].lineFrom, 0);
  assert.equal(score.sections.at(-1).lineTo, 9);
  for (let index = 1; index < score.sections.length; index += 1) {
    assert.equal(score.sections[index].lineFrom, score.sections[index - 1].lineTo + 1);
  }
  assert.deepEqual([0, 2, 3, 4].map((lineIndex) => (
    score.scenes.find((scene) => scene.lineIndex === lineIndex)?.composition
  )), ["hookCall", "hookCall", "hookEcho", "hookLock"]);
  const firstHook = score.scenes.find((scene) => scene.lineIndex === 0);
  assert.deepEqual(firstHook.companionLineIndices, []);
  assert.equal(firstHook.intensity, 1);
  assert.equal(score.scenes.filter((scene) => scene.composition === "hero").length, 1);
  assert.equal(score.scenes.length, 5);
  assert.equal(isUsableStageV3Output(ai, score), true);
});

test("V3 rejects a fake hook and treats an empty model result as unusable", () => {
  const input = sanitizeDirectorV3Input(requestPayload());
  const ai = {
    stageBible: { concept: "quiet", motif: "line", intensityArc: "flat" },
    sections: [],
    scenes: [{ lineIndex: 1, composition: "hookCall", intensity: 0.5 }],
  };
  const score = finalizeStagePlanV3(input, ai, "director-v3-test", "b".repeat(64));
  assert.equal(score.sections.length, 2);
  assert.equal(score.sections[0].lineFrom, 0);
  assert.equal(score.sections.at(-1).lineTo, 9);
  assert.deepEqual(score.scenes, []);
  assert.equal(isUsableStageV3Output(ai, score), false);
  assert.equal(isUsableStageV3Output({}, finalizeStagePlanV3(input, {}, "v3", "b".repeat(64))), false);
  const missingArc = {
    stageBible: { concept: "concept", motif: "motif", intensityArc: "" },
    scenes: [{ lineIndex: 5, composition: "leadingAnchor" }],
  };
  assert.equal(
    isUsableStageV3Output(
      missingArc,
      finalizeStagePlanV3(input, missingArc, "v3", "b".repeat(64)),
    ),
    false,
  );
});

test("V3 rejects App-incompatible sparse, long-hero, and companionless scenes", () => {
  const input = sanitizeDirectorV3Input(requestPayload(20));
  const ai = {
    stageBible: { concept: "bounded", motif: "signal", intensityArc: "build" },
    sections: [{
      id: "whole", lineFrom: 0, lineTo: 19, kind: "verse",
      intensity: 0.4, motifPhase: "develop",
    }],
    scenes: [
      { lineIndex: 1, composition: "dialogue", companionLineIndices: [] },
      { lineIndex: 5, composition: "hero", companionLineIndices: [] },
      { lineIndex: 6, composition: "leadingAnchor", companionLineIndices: [] },
    ],
  };
  input.lines[5].text = "this hero line is deliberately much too long";
  const score = finalizeStagePlanV3(input, ai, "director-v3-test", "b".repeat(64));
  assert.deepEqual(score.scenes.map((scene) => scene.lineIndex), [6]);
  assert.equal(isUsableStageV3Output(ai, score), false, "one scene cannot satisfy a 20-line App plan");
});
