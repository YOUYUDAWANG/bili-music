import test from "node:test";
import assert from "node:assert/strict";

import {
  compactStageV4PromptInput,
  finalizeStagePlanV4,
  isUsableStageV4Output,
  sanitizeDirectorV4Input,
  STAGE_V4_CONTRACT_VERSION,
  STAGE_V4_GRAMMAR_VERSION,
} from "../src/director-v4.js";

function payload(lineCount = 12, repeatedEveryLine = false) {
  const repeated = new Set([0, 4, 8]);
  const lines = Array.from({ length: lineCount }, (_, index) => ({
    index,
    from: index * 3,
    to: index * 3 + 2.6,
    text: repeatedEveryLine || repeated.has(index) ? "同じ合図" : `line ${index}`,
    voiceRole: index === 6 ? "backing" : "lead",
    layerID: `line-${index}`,
    overlapGroup: index === 6 || index === 7 ? "duet-1" : null,
    words: index === 1 ? [
      { index: 0, from: 3, to: 3.8, text: "line" },
      { index: 1, from: 3.8, to: 4.6, text: "1" },
    ] : [],
    tokens: [
      { index: 0, text: repeatedEveryLine || repeated.has(index) ? "同じ" : "line" },
      { index: 1, text: repeatedEveryLine || repeated.has(index) ? "合図" : String(index) },
    ],
    hasRealWordTiming: index === 3,
  }));
  return {
    trackID: "BV-v4:1",
    title: "V4 benchmark",
    artist: "Artist",
    duration: lineCount * 3,
    lyricsHash: "a".repeat(64),
    audioScoreHash: "b".repeat(64),
    target: { device: "private-device-id", os: "private-os-id" },
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
      durationMilliseconds: lineCount * 3_000,
      scoreHash: "private-audio-score-hash",
      mapFingerprint: "private-map-fingerprint",
      audioFingerprint: "private-audio-fingerprint",
      secret: "never-send-this-secret",
      confidence: {
        beat: 204, downbeat: 191, onset: 204, energy: 230,
        pitch: 178, sections: 191, overall: 224,
      },
      tempoSegments: [[0, lineCount * 3_000, 1_200, 204]],
      sections: [
        [
          0, 0, Math.floor(lineCount / 2) * 3_000,
          0, Math.floor(lineCount / 2) - 1,
          210, 110, 190, 42, 120, 130, 100, 18, 170, 55, 180, 0, 240,
        ],
        [
          1, Math.floor(lineCount / 2) * 3_000, lineCount * 3_000,
          Math.floor(lineCount / 2), lineCount - 1,
          220, 180, 240, -24, 150, 190, 140, -12, 200, 72, 190, 100, 300,
        ],
      ],
      lineFacts: lines.map((line) => [
        line.index,
        line.index < lineCount / 2 ? 0 : 1,
        128,
        line.index % 2 ? -40 : 35,
        line.index % 4 ? -120 : 80,
        32,
        110,
        210,
        line.index % 3 === 0 ? 35 : -20,
        3,
        205,
        line.index === 3 ? 850 : 0,
        0,
      ]),
      lineDetails: lines.map((line) => [
        line.index,
        [30, 90, 160],
        [580, null, 720],
        190,
        170,
        [["onset", 120, 220], ["raw-accent-secret", 260, 180]],
      ]),
      moments: [
        ["section-0", "sectionStart", 0, 120, 220, 230, 0],
        ["silence-3", "silenceExit", 8_700, 9_000, 230, 230, 3],
        ["peak-4", "energyPeak", 12_200, 12_450, 255, 220, 4],
        ["cadence-last", "cadence", (lineCount - 1) * 3_000, lineCount * 3_000, 210, 205, lineCount - 1],
      ],
      beats: [0.1, 0.4],
      onsets: [{ time: 1, strength: 1 }],
      rawEvents: [{ secret: "raw-event-secret" }],
    },
  };
}

function typedBible() {
  return {
    concept: "a rail remembers each phrase",
    intensityArc: "quiet introduction, opening transform, stable resolve",
    primaryMotif: { signature: "rail", axis: "horizontal", cadence: "phrase" },
    secondaryMotif: { signature: "aperture", axis: "centered", cadence: "downbeat" },
  };
}

test("V4 sanitizer accepts the bounded score and prompt strips private and raw audio fields", () => {
  const input = sanitizeDirectorV4Input(payload());
  assert.equal(input.audioScore.availability, "ready");
  assert.equal(input.audioScore.lineFacts.length, 12);
  assert.equal(input.audioScore.lineDetails.length, 12);
  assert.equal(input.audioScore.durationMilliseconds, 36_000);
  assert.equal(input.audioScore.confidence.overall, 224);
  assert.deepEqual(input.audioScore.lineDetails[0].pitchContourTenths, [580, null, 720]);
  assert.equal(input.audioScore.lineDetails[0].pitchConfidenceQ, 190);
  assert.equal(input.audioScore.lineDetails[0].voicednessQ, 170);
  assert.equal(input.lines[0].tokens[1].text, "合図");
  assert.equal(input.lines[3].hasRealWordTiming, true, "explicit compact timing capability survives without words");

  const compact = compactStageV4PromptInput(input);
  assert.equal(compact.audioScore.lineFacts[0][0], 0);
  assert.equal(compact.audioScore.moments[1][0], "silence-3");
  assert.equal(compact.audioScore.tempoSegments[0][2], 1_200);
  assert.equal(compact.audioScore.lineDetails[0].length, 5, "accent event arrays stay local");
  assert.deepEqual(compact.repeatClusters[0].lineIndices, [0, 4, 8]);
  const encoded = JSON.stringify(compact);
  for (const forbidden of [
    "private-device-id", "private-os-id", "private-map-fingerprint",
    "private-audio-fingerprint", "never-send-this-secret", "raw-event-secret", "raw-accent-secret",
    "b".repeat(64),
    "mapFingerprint", "audioFingerprint", "rawEvents", "\"beats\":", "\"onsets\":",
  ]) {
    assert.equal(encoded.includes(forbidden), false, forbidden);
  }
});

test("V4 reconstructs compact token text from grapheme ranges without duplicating lyrics", () => {
  const compactTokens = payload(4);
  compactTokens.lines[0].text = "you&合図";
  compactTokens.lines[0].tokens = [[0, 0, 3], [1, 3, 4], [2, 4, 6]];
  compactTokens.lines[0].hasRealWordTiming = true;
  compactTokens.lines[0].words = [];

  const input = sanitizeDirectorV4Input(compactTokens);
  assert.deepEqual(
    input.lines[0].tokens.map((token) => [token.index, token.text]),
    [[0, "you"], [1, "&"], [2, "合図"]],
  );
  assert.equal(input.lines[0].hasRealWordTiming, true);
});

test("V4 preserves complete lyric lines beyond the legacy 500-code-unit limit", () => {
  const longLine = `  ${"長い歌詞".repeat(140)}  `;
  const completeLyrics = payload(4);
  completeLyrics.lines[0].text = longLine;
  completeLyrics.lines[0].tokens = [[0, 2, 6]];

  const input = sanitizeDirectorV4Input(completeLyrics);
  const compact = compactStageV4PromptInput(input);

  assert.ok(longLine.length > 500);
  assert.equal(input.lines[0].text, longLine);
  assert.equal(compact.outline[0][3], longLine);
  assert.equal(input.lines[0].tokens[0].text, "長い歌詞");
});

test("V4 accepts the audioStructureScore alias but requires complete ready line facts", () => {
  const aliased = payload(4);
  aliased.audioStructureScore = aliased.audioScore;
  delete aliased.audioScore;
  assert.equal(sanitizeDirectorV4Input(aliased).audioScore.lineFacts.length, 4);

  const incomplete = payload(4);
  incomplete.audioScore.lineFacts.pop();
  assert.throws(
    () => sanitizeDirectorV4Input(incomplete),
    /one fact per lyric line/u,
  );

  const noncontiguous = payload(4);
  noncontiguous.lines[2].index = 5;
  assert.throws(() => sanitizeDirectorV4Input(noncontiguous), /contiguous from zero/u);

  const missingIdentity = payload(4);
  delete missingIdentity.audioScoreHash;
  assert.throws(() => sanitizeDirectorV4Input(missingIdentity), /audio score identity/u);

  const wrongSemantics = payload(4);
  wrongSemantics.audioScore.semantics.energy = "prompt-injected-meaning";
  assert.throws(() => sanitizeDirectorV4Input(wrongSemantics), /feature semantics/u);
});

test("V4 canonicalizes each family independently and repairs continuous sections", () => {
  const input = sanitizeDirectorV4Input(payload());
  const ai = {
    stageBible: typedBible(),
    sections: [
      { id: "opening", lineFrom: 0, lineTo: 2, kind: "verse", intensity: -1, motifPhase: "introduce" },
      { id: "ending", lineFrom: 8, lineTo: 11, kind: "outro", intensity: 2, motifPhase: "resolve" },
    ],
    scenes: [
      {
        lineIndex: 1, family: "railHandoff", topology: "contour", entrance: "aperture",
        focus: "tokenRange", sustain: "echo", continuity: "accumulate",
        driver: "structuralMoment", landmarkIDs: ["missing"], companionLineIndices: [9],
        motifPhase: "bad", intensity: 3,
      },
      {
        lineIndex: 2, family: "semanticLens", topology: "split", entrance: "slide",
        focus: "tokenRange", tokenRange: { startTokenIndex: 0, endTokenIndex: 1 },
        sustain: "echo", continuity: "handoff", driver: "wordReveal", intensity: 0.7,
      },
      {
        lineIndex: 4, family: "chorusMemory", topology: "contour", entrance: "aperture",
        focus: "tokenRange", sustain: "none", continuity: "clear", driver: "lyricReveal",
        companionLineIndices: [0, 99], motifPhase: "transform", intensity: 0.9,
      },
      {
        lineIndex: 3, family: "silenceAperture", topology: "contour", entrance: "slide",
        focus: "tokenRange", sustain: "echo", continuity: "residue",
        driver: "lyricReveal", landmarkIDs: ["silence-3", "peak-4"], intensity: 0.8,
      },
      {
        lineIndex: 5, family: "semanticLens", focus: "tokenRange",
        tokenRange: { startTokenIndex: 0, endTokenIndex: 99 },
      },
      { lineIndex: 6, family: "inventedFamily" },
    ],
  };
  const score = finalizeStagePlanV4(input, ai, "director-v4-test", "b".repeat(64));
  assert.equal(score.version, STAGE_V4_CONTRACT_VERSION);
  assert.equal(score.grammarVersion, STAGE_V4_GRAMMAR_VERSION);
  assert.equal(score.audioScoreHash, "b".repeat(64));
  assert.deepEqual(score.stageBible.primaryMotif, typedBible().primaryMotif);
  assert.equal(score.sections[0].lineFrom, 0);
  assert.equal(score.sections.at(-1).lineTo, 11);
  for (let index = 1; index < score.sections.length; index += 1) {
    assert.equal(score.sections[index].lineFrom, score.sections[index - 1].lineTo + 1);
  }

  const rail = score.scenes.find((scene) => scene.lineIndex === 1);
  assert.deepEqual(rail, {
    lineIndex: 1, family: "railHandoff", topology: "relay", entrance: "slide",
    focus: "wholeLine", sustain: "railTravel", continuity: "handoff",
    driver: "lyricReveal", landmarkIDs: [], companionLineIndices: [],
    motifPhase: "introduce", intensity: 1,
  });
  const lens = score.scenes.find((scene) => scene.lineIndex === 2);
  assert.deepEqual(lens.tokenRange, { startTokenIndex: 0, endTokenIndex: 1 });
  assert.equal(lens.driver, "lyricReveal", "line-only timing cannot become word reveal");
  assert.equal(lens.sustain, "weightBloom");
  const memory = score.scenes.find((scene) => scene.lineIndex === 4);
  assert.equal(memory.topology, "stack");
  assert.equal(memory.sustain, "echo");
  assert.deepEqual(memory.companionLineIndices, [0]);
  const aperture = score.scenes.find((scene) => scene.lineIndex === 3);
  assert.equal(aperture.entrance, "aperture");
  assert.equal(aperture.driver, "structuralMoment");
  assert.deepEqual(aperture.landmarkIDs, ["silence-3"]);
  assert.equal(score.scenes.some((scene) => scene.lineIndex === 5), false);
  assert.equal(score.scenes.some((scene) => scene.lineIndex === 6), false);
  assert.equal(isUsableStageV4Output(ai, score, input), true);
});

test("V4 enforces sparse and high-motion whole-song budgets deterministically", () => {
  const input = sanitizeDirectorV4Input(payload(20, true));
  const ai = {
    stageBible: typedBible(),
    sections: [{
      id: "whole", lineFrom: 0, lineTo: 19, kind: "chorus",
      intensity: 0.9, motifPhase: "transform",
    }],
    scenes: Array.from({ length: 20 }, (_, lineIndex) => ({
      lineIndex,
      family: "chorusMemory",
      topology: "stack",
      entrance: "interleave",
      focus: "wholeLine",
      sustain: "echo",
      continuity: "accumulate",
      driver: "lyricReveal",
      motifPhase: "transform",
      intensity: 0.6 + lineIndex / 100,
    })),
  };
  const first = finalizeStagePlanV4(input, ai, "v4", "c".repeat(64));
  const second = finalizeStagePlanV4(input, ai, "v4", "c".repeat(64));
  assert.deepEqual(first, second);
  assert.equal(first.scenes.length, 9, "45 percent sparse-scene ceiling");
  let run = 0;
  let previous = -2;
  for (const scene of first.scenes) {
    const high = scene.family === "chorusMemory" || scene.family === "silenceAperture";
    run = high && scene.lineIndex === previous + 1 ? run + 1 : (high ? 1 : 0);
    assert.ok(run <= 2, `high-motion run at line ${scene.lineIndex}`);
    previous = scene.lineIndex;
  }
});

test("V4 does not report fallback-only or malformed model output as usable", () => {
  const input = sanitizeDirectorV4Input(payload());
  const empty = finalizeStagePlanV4(input, {}, "v4", "d".repeat(64));
  assert.equal(empty.scenes.length, 0);
  assert.equal(isUsableStageV4Output({}, empty, input), false);

  const badBible = {
    stageBible: {
      concept: "concept", intensityArc: "arc",
      primaryMotif: { signature: "sparkles", axis: "random", cadence: "everyBeat" },
    },
    scenes: [{ lineIndex: 1, family: "railHandoff" }, { lineIndex: 2, family: "railHandoff" }],
  };
  const repaired = finalizeStagePlanV4(input, badBible, "v4", "d".repeat(64));
  assert.equal(repaired.scenes.length, 2);
  assert.equal(isUsableStageV4Output(badBible, repaired, input), false);
});
