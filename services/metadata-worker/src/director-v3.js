import { sanitizeDirectorInput, sanitizeStageBible } from "./director.js";

export const STAGE_V3_CONTRACT_VERSION = "lyric-stage-v3-choreography";
export const STAGE_V3_GRAMMAR_VERSION = "v53-composition-grammar-v1";

const COMPOSITIONS = new Set([
  "stillness",
  "leadingAnchor",
  "trailingAnchor",
  "dialogue",
  "stack",
  "arc",
  "hero",
  "hookCall",
  "hookEcho",
  "hookConverge",
  "hookLock",
]);
const SECTION_KINDS = new Set([
  "intro", "verse", "preChorus", "chorus", "bridge", "breakdown", "outro", "unknown",
]);
const MOTIF_PHASES = new Set(["introduce", "develop", "transform", "resolve"]);
const HOOK_COMPOSITIONS = new Set(["hookCall", "hookEcho", "hookConverge", "hookLock"]);

export const STAGE_V3_PROMPT = `You direct one coherent whole-song kinetic-typography plan for an iPhone 17 Pro lyric stage.
The app owns lyric text, line timing, word reveal timing, layout measurement, coordinates, and rendering. Never rewrite lyrics and never output lyric text, absolute seconds, coordinates, glyph indices, or animation curves.
Input track is [title, artist, durationSeconds]. outline entries are [lineIndex, fromSeconds, toSeconds, exactText, voiceRole, overlapGroup]. repeatClusters contain real repeated-line indices. audioSummary is an optional compact feature map created locally; it is evidence for intensity and accents, never permission to move lyric reveal timing.
audioSummary.sections tuples are [sectionIndex, from, to, lineFrom, lineTo, meanEnergy, energyTrend, onsetDensity, pitchTrendSemitones, confidence].
audioSummary.lines tuples are [lineIndex, from, to, sectionIndex, meanEnergy, peakEnergy, energyDelta, onsetCount, beatStrength, pitchStartMIDI, pitchEndMIDI, pitchTrendSemitones, pitchConfidence, silenceBefore, silenceAfter, onsetStrength, longToneRatio].

Return exactly one JSON object with:
{
  "stageBible": { "concept": "short", "motif": "short", "intensityArc": "short" },
  "sections": [{
    "id": "short-unique-id", "lineFrom": 0, "lineTo": 7,
    "kind": "intro|verse|preChorus|chorus|bridge|breakdown|outro|unknown",
    "intensity": 0.3, "motifPhase": "introduce|develop|transform|resolve"
  }],
  "scenes": [{
    "lineIndex": 3,
    "composition": "stillness|leadingAnchor|trailingAnchor|dialogue|stack|arc|hero|hookCall|hookEcho|hookConverge|hookLock",
    "companionLineIndices": [2],
    "intensity": 0.65,
    "motifRef": "optional-stage-bible-motif"
  }]
}

Rules:
1. Establish one whole-song motif and evolve it across sections. Repeated hooks should progress rather than receive random effects.
2. Direct only exceptional structural moments, roughly 20% to 55% of lines. The app fills every omitted line with a deterministic local plan.
3. Keep 60% to 70% of the song visually clear and stable. Hero composition is rare, no more than about 10% of lines.
4. companionLineIndices may contain at most two real lines. Use nearby lines for dialogue/stack, or lines in the same real overlapGroup for simultaneous voices.
5. Hook compositions are only for repeatClusters. The server will deterministically correct their call/echo/converge/lock order.
6. Audio evidence may shape intensity, but it never delays or retimes text.
7. Do not specialize for a title, track ID, absolute timestamp, or fixed lyric line number. Base decisions only on the supplied general structure.
Return JSON only.`;

export function sanitizeDirectorV3Input(raw) {
  const base = sanitizeDirectorInput(raw);
  if (base.lines.some((line, index) => line.index !== index)) {
    throw new Error("V3 line indices must be contiguous from zero");
  }
  const suppliedAudioHash = clean(raw?.audioSummaryHash ?? raw?.audioSummary?.summaryHash, 64).toLowerCase();
  return {
    ...base,
    audioSummary: sanitizeAudioSummary(raw?.audioSummary, base.lines),
    audioSummaryHash: /^[a-f0-9]{64}$/u.test(suppliedAudioHash) ? suppliedAudioHash : null,
  };
}

export function compactStageV3PromptInput(input) {
  return {
    track: [input.title, input.artist, input.duration],
    outline: input.lines.map((line) => [
      line.index,
      round(line.from),
      round(line.to),
      line.text,
      line.voiceRole,
      line.overlapGroup,
    ]),
    repeatClusters: repeatClusters(input.lines),
    audioSummary: {
      version: input.audioSummary.version,
      mapFingerprint: input.audioSummary.mapFingerprint,
      duration: input.audioSummary.duration,
      bpm: input.audioSummary.bpm,
      confidence: input.audioSummary.confidence,
      sections: input.audioSummary.sections.map((section) => [
        section.index,
        round(section.from),
        round(section.to),
        section.lineFrom,
        section.lineTo,
        section.meanEnergy,
        section.energyTrend,
        section.onsetDensity,
        section.pitchTrend,
        section.confidence,
      ]),
      lines: input.audioSummary.lineFeatures.map((line) => [
        line.lineIndex,
        round(line.from),
        round(line.to),
        line.sectionIndex,
        line.meanEnergy,
        line.peakEnergy,
        line.energyDelta,
        line.onsetCount,
        line.beatStrength,
        line.pitchStart,
        line.pitchEnd,
        line.pitchTrend,
        line.pitchConfidence,
        line.silenceBefore,
        line.silenceAfter,
        line.onsetStrength,
        line.longToneRatio,
      ]),
    },
  };
}

export function finalizeStagePlanV3(
  input,
  ai,
  directorVersion,
  audioSummaryHash,
) {
  const stageBible = sanitizeStageBibleV3(ai?.stageBible) || {
    concept: "adaptive whole-song typography",
    motif: "structured repetition",
    intensityArc: "quiet development, bounded climax, clear resolution",
  };
  const sections = sanitizeSections(ai?.sections, input);
  const scenes = sanitizeScenes(ai?.scenes, input);
  return {
    version: STAGE_V3_CONTRACT_VERSION,
    directorVersion: clean(directorVersion, 120) || "luna-lyric-director-v3-whole-song",
    trackID: input.trackID,
    lyricsHash: input.lyricsHash,
    lineCount: input.lines.length,
    audioSummaryHash: clean(audioSummaryHash, 64).toLowerCase(),
    stageBible,
    sections,
    scenes,
  };
}

export function isUsableStageV3Output(ai, score) {
  const minimumScenes = Math.max(1, Math.ceil(score.lineCount * 0.10));
  return sanitizeStageBibleV3(ai?.stageBible) !== null && score.scenes.length >= minimumScenes;
}

function sanitizeStageBibleV3(value) {
  const bible = sanitizeStageBible(value);
  return bible?.intensityArc ? { ...bible, motif: bible.motif.slice(0, 120) } : null;
}

function sanitizeAudioSummary(value, lines) {
  const linesByIndex = new Map(lines.map((line) => [line.index, line]));
  const lineIndices = new Set(linesByIndex.keys());
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {
      version: "none", mapFingerprint: null, duration: 0, bpm: null,
      confidence: 0, sections: [], lineFeatures: [],
    };
  }
  const version = clean(value.version ?? value.analysisVersion, 80) || "unknown";
  const rawBPM = finite(value.bpm, NaN);
  const bpm = Number.isFinite(rawBPM) ? clamp(rawBPM, 30, 300) : null;
  const sections = (Array.isArray(value.sections) ? value.sections : [])
    .map((section, index) => sanitizeAudioSection(section, index, linesByIndex))
    .filter(Boolean)
    .slice(0, 32);
  const seenLines = new Set();
  const rawLineFeatures = Array.isArray(value.lines)
    ? value.lines
    : (Array.isArray(value.lineFeatures) ? value.lineFeatures : []);
  const lineFeatures = rawLineFeatures
    .map((feature) => sanitizeLineFeature(feature, linesByIndex))
    .filter((feature) => feature && !seenLines.has(feature.lineIndex) && seenLines.add(feature.lineIndex))
    .slice(0, 180)
    .sort((left, right) => left.lineIndex - right.lineIndex);
  return {
    version,
    mapFingerprint: clean(value.mapFingerprint, 128) || null,
    duration: clamp(finite(value.duration, 0), 0, 86_400),
    bpm,
    confidence: clamp(finite(value.confidence?.overall ?? value.confidence, 0), 0, 1),
    sections,
    lineFeatures,
  };
}

function sanitizeAudioSection(section, fallbackIndex, linesByIndex) {
  if (!section || typeof section !== "object" || Array.isArray(section)) return null;
  const index = clamp(integer(section.index, fallbackIndex), 0, 10_000);
  const id = clean(section.id, 40) || `audio-${index}`;
  const requestedLineFrom = integer(section.lineFrom, -1);
  const requestedLineTo = integer(section.lineTo, -1);
  const hasLineRange = requestedLineFrom >= 0
    && requestedLineTo >= requestedLineFrom
    && rangeExists(requestedLineFrom, requestedLineTo, new Set(linesByIndex.keys()));
  const lineFrom = hasLineRange ? requestedLineFrom : null;
  const lineTo = hasLineRange ? requestedLineTo : null;
  const firstLine = lineFrom === null ? null : linesByIndex.get(lineFrom);
  const lastLine = lineTo === null ? null : linesByIndex.get(lineTo);
  const from = clamp(finite(section.from, firstLine?.from ?? 0), 0, 86_400);
  const to = clamp(finite(section.to, lastLine?.to ?? from), from, 86_400);
  return {
    index,
    id,
    from,
    to,
    lineFrom,
    lineTo,
    meanEnergy: clamp(finite(section.meanEnergy ?? section.energy, 0), 0, 1),
    energyTrend: sanitizeEnergyTrend(section.energyTrend),
    onsetDensity: clamp(finite(section.onsetDensity, 0), 0, 1),
    pitchTrend: sanitizePitchTrend(section.pitchTrend),
    confidence: clamp(finite(section.confidence?.overall ?? section.confidence, 0), 0, 1),
  };
}

function sanitizeLineFeature(feature, linesByIndex) {
  if (!feature || typeof feature !== "object" || Array.isArray(feature)) return null;
  const lineIndex = integer(feature.lineIndex, -1);
  const line = linesByIndex.get(lineIndex);
  if (!line) return null;
  const nearestBeatDistance = finite(feature.nearestBeatDistance, NaN);
  const derivedBeatStrength = Number.isFinite(nearestBeatDistance)
    ? 1 - clamp(Math.abs(nearestBeatDistance) / 0.5, 0, 1)
    : finite(feature.beatStrength, 0);
  const from = clamp(finite(feature.from, line.from), 0, 86_400);
  const to = clamp(finite(feature.to, line.to), from, 86_400);
  return {
    lineIndex,
    from,
    to,
    sectionIndex: integer(feature.sectionIndex, -1) >= 0 ? integer(feature.sectionIndex, -1) : null,
    meanEnergy: clamp(finite(feature.meanEnergy ?? feature.energy, 0), 0, 1),
    peakEnergy: clamp(finite(feature.peakEnergy, feature.meanEnergy ?? feature.energy ?? 0), 0, 1),
    energyDelta: clamp(finite(feature.energyDelta, 0), -1, 1),
    onsetCount: clamp(integer(feature.onsetCount, 0), 0, 10_000),
    onsetStrength: clamp(finite(feature.onsetStrength, 0), 0, 1),
    beatStrength: clamp(derivedBeatStrength, 0, 1),
    pitchStart: nullableFinite(feature.pitchStart ?? feature.pitch?.start, 0, 20_000),
    pitchEnd: nullableFinite(feature.pitchEnd ?? feature.pitch?.end, 0, 20_000),
    pitchTrend: sanitizePitchTrend(feature.pitchTrend ?? feature.pitch?.trend),
    pitchConfidence: clamp(finite(
      feature.pitchConfidence ?? feature.pitch?.confidence ?? feature.confidence,
      0,
    ), 0, 1),
    longToneRatio: clamp(finite(feature.longToneRatio, 0), 0, 1),
    silenceBefore: clamp(finite(feature.silenceBefore, 0), 0, 30),
    silenceAfter: clamp(finite(feature.silenceAfter, 0), 0, 30),
  };
}

function sanitizeSections(values, input) {
  const lineIndices = new Set(input.lines.map((line) => line.index));
  const seenIDs = new Set();
  const accepted = (Array.isArray(values) ? values : [])
    .map((section) => sanitizeSection(section, lineIndices))
    .filter((section) => section && !seenIDs.has(section.id) && seenIDs.add(section.id))
    .sort((left, right) => left.lineFrom - right.lineFrom || left.lineTo - right.lineTo);
  const nonOverlapping = [];
  for (const section of accepted) {
    if (nonOverlapping.some((prior) => section.lineFrom <= prior.lineTo)) continue;
    nonOverlapping.push(section);
  }
  const candidates = nonOverlapping.length ? nonOverlapping.slice(0, 32) : fallbackSections(input);
  return fillSectionCoverage(candidates, input.lines.length);
}

function sanitizeSection(section, lineIndices) {
  if (!section || typeof section !== "object" || Array.isArray(section)) return null;
  const id = clean(section.id, 40);
  const lineFrom = integer(section.lineFrom, -1);
  const lineTo = integer(section.lineTo, -1);
  if (!id || lineTo < lineFrom || !rangeExists(lineFrom, lineTo, lineIndices)) return null;
  return {
    id,
    lineFrom,
    lineTo,
    kind: SECTION_KINDS.has(section.kind) ? section.kind : "unknown",
    intensity: clamp(finite(section.intensity, 0.3), 0, 1),
    motifPhase: MOTIF_PHASES.has(section.motifPhase) ? section.motifPhase : "develop",
  };
}

function sanitizeScenes(values, input) {
  const linesByIndex = new Map(input.lines.map((line) => [line.index, line]));
  const repeatsByLine = repeatMap(input.lines);
  const seenLines = new Set();
  const maximumScenes = Math.max(1, Math.floor(input.lines.length * 0.6));
  const maximumHeroes = Math.max(1, Math.ceil(input.lines.length * 0.12));
  let heroCount = 0;
  const accepted = [];
  for (const value of Array.isArray(values) ? values : []) {
    if (accepted.length >= maximumScenes) break;
    const scene = sanitizeScene(value, linesByIndex, repeatsByLine);
    if (!scene || seenLines.has(scene.lineIndex)) continue;
    if (scene.composition === "hero" || scene.composition === "hookLock") {
      if (heroCount >= maximumHeroes) continue;
      heroCount += 1;
    }
    seenLines.add(scene.lineIndex);
    accepted.push(scene);
  }
  return accepted.sort((left, right) => left.lineIndex - right.lineIndex);
}

function sanitizeScene(value, linesByIndex, repeatsByLine) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const lineIndex = integer(value.lineIndex, -1);
  const line = linesByIndex.get(lineIndex);
  let composition = clean(value.composition, 32);
  if (!line || !COMPOSITIONS.has(composition)) return null;
  if (composition === "hero" && [...line.text.replace(/\s/gu, "")].length > 12) return null;
  const repeatedIndices = repeatsByLine.get(lineIndex) || [];
  if (HOOK_COMPOSITIONS.has(composition)) {
    if (repeatedIndices.length < 2) return null;
    composition = expectedHookComposition(lineIndex, repeatedIndices);
  }
  const seenCompanions = new Set();
  let companionLineIndices = (Array.isArray(value.companionLineIndices) ? value.companionLineIndices : [])
    .map((candidate) => integer(candidate, -1))
    .filter((candidate) => {
      if (candidate === lineIndex || seenCompanions.has(candidate)) return false;
      const companion = linesByIndex.get(candidate);
      if (!companion) return false;
      const nearby = Math.abs(candidate - lineIndex) <= 2;
      const sameOverlap = Boolean(line.overlapGroup && line.overlapGroup === companion.overlapGroup);
      if (!nearby && !sameOverlap) return false;
      seenCompanions.add(candidate);
      return true;
    })
    .slice(0, 2);
  const motifRef = clean(value.motifRef, 40);
  if ((composition === "dialogue" || composition === "stack") && companionLineIndices.length === 0) {
    return null;
  }
  if (composition !== "dialogue" && composition !== "stack") companionLineIndices = [];
  return {
    lineIndex,
    composition,
    companionLineIndices,
    intensity: clamp(finite(value.intensity, 0.6), 0.25, 1),
    ...(motifRef ? { motifRef } : {}),
  };
}

function fallbackSections(input) {
  const mappedAudioSections = input.audioSummary.sections.filter((section) => section.lineFrom !== null);
  if (mappedAudioSections.length) {
    return mappedAudioSections.map((section) => ({
      id: section.id,
      lineFrom: section.lineFrom,
      lineTo: section.lineTo,
      kind: "unknown",
      intensity: section.meanEnergy,
      motifPhase: "develop",
    }));
  }
  const indices = input.lines.map((line) => line.index);
  return [{
    id: "whole-song",
    lineFrom: Math.min(...indices),
    lineTo: Math.max(...indices),
    kind: "unknown",
    intensity: 0.3,
    motifPhase: "develop",
  }];
}

function fillSectionCoverage(sections, lineCount) {
  if (lineCount <= 0) return [];
  const result = [];
  let cursor = 0;
  const sorted = sections
    .filter((section) => section.lineFrom >= 0 && section.lineTo >= section.lineFrom)
    .sort((left, right) => left.lineFrom - right.lineFrom || left.lineTo - right.lineTo);
  for (const section of sorted) {
    if (section.lineFrom < cursor || section.lineFrom >= lineCount) continue;
    if (section.lineFrom > cursor) result.push(gapSection(cursor, section.lineFrom - 1, lineCount));
    const lineTo = Math.min(section.lineTo, lineCount - 1);
    result.push({ ...section, lineTo });
    cursor = lineTo + 1;
    if (cursor >= lineCount) break;
  }
  if (cursor < lineCount) result.push(gapSection(cursor, lineCount - 1, lineCount));
  return result.length ? result : [gapSection(0, lineCount - 1, lineCount)];
}

function gapSection(lineFrom, lineTo, lineCount) {
  const motifPhase = lineFrom === 0
    ? "introduce"
    : (lineTo === lineCount - 1 ? "resolve" : "develop");
  return {
    id: `fallback-${lineFrom}-${lineTo}`,
    lineFrom,
    lineTo,
    kind: lineFrom === 0 ? "intro" : (lineTo === lineCount - 1 ? "outro" : "unknown"),
    intensity: 0.3,
    motifPhase,
  };
}

function repeatClusters(lines) {
  const groups = new Map();
  for (const line of lines) {
    const key = normalize(line.text);
    if (key.length < 2) continue;
    const values = groups.get(key) || [];
    values.push(line.index);
    groups.set(key, values);
  }
  return [...groups.values()]
    .filter((indices) => indices.length >= 2)
    .map((lineIndices, index) => ({ id: `repeat-${index + 1}`, lineIndices }));
}

function repeatMap(lines) {
  const byLine = new Map();
  for (const cluster of repeatClusters(lines)) {
    for (const lineIndex of cluster.lineIndices) {
      const local = contiguousRepeatCluster(lines, lineIndex);
      byLine.set(lineIndex, local.length >= 2 ? local : cluster.lineIndices);
    }
  }
  return byLine;
}

function contiguousRepeatCluster(lines, lineIndex) {
  const key = normalize(lines[lineIndex]?.text);
  if (!key) return [];
  let lower = lineIndex;
  while (
    lower > 0
    && normalize(lines[lower - 1].text) === key
    && lines[lower].from - lines[lower - 1].to <= 1.35
  ) lower -= 1;
  let upper = lineIndex;
  while (
    upper + 1 < lines.length
    && normalize(lines[upper + 1].text) === key
    && lines[upper + 1].from - lines[upper].to <= 1.35
  ) upper += 1;
  return Array.from({ length: upper - lower + 1 }, (_, offset) => lower + offset);
}

function expectedHookComposition(lineIndex, repeatedIndices) {
  const occurrence = repeatedIndices.indexOf(lineIndex);
  if (occurrence <= 0) return "hookCall";
  if (occurrence === repeatedIndices.length - 1) return "hookLock";
  if (occurrence === 1) return "hookEcho";
  return "hookConverge";
}

function rangeExists(from, to, indices) {
  if (from < 0 || to < from) return false;
  for (let index = from; index <= to; index += 1) {
    if (!indices.has(index)) return false;
  }
  return true;
}

function normalize(text) {
  return String(text || "").toLowerCase().replace(/[\s\p{P}]+/gu, "");
}

function clean(value, limit) {
  return typeof value === "string" ? value.trim().slice(0, limit) : "";
}

function finite(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function nullableFinite(value, minimum, maximum) {
  const number = Number(value);
  return Number.isFinite(number) ? clamp(number, minimum, maximum) : null;
}

function sanitizeEnergyTrend(value) {
  const number = Number(value);
  if (Number.isFinite(number)) return clamp(number, -1, 1);
  const text = clean(value, 20).toLowerCase();
  return new Set(["rising", "falling", "steady", "mixed", "unknown"]).has(text) ? text : "unknown";
}

function sanitizePitchTrend(value) {
  const number = Number(value);
  if (Number.isFinite(number)) return clamp(number, -48, 48);
  const text = clean(value, 20).toLowerCase();
  return new Set(["rising", "falling", "steady", "mixed", "unknown"]).has(text) ? text : "unknown";
}

function integer(value, fallback) {
  const number = Number(value);
  return Number.isInteger(number) ? number : fallback;
}

function clamp(value, minimum, maximum) {
  return Math.min(Math.max(value, minimum), maximum);
}

function round(value) {
  return Math.round(value * 1000) / 1000;
}
