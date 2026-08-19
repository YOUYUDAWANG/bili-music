const VERSION = "lyric-stage-v2-events";
const PALETTE = new Set([
  "coverAnalogous", "coverComplementary", "coverMonochrome", "warmClimax", "coolClimax",
]);
const SECTION_KINDS = new Set([
  "intro", "verse", "preChorus", "chorus", "bridge", "breakdown", "outro", "unknown",
]);
const COMPOSITIONS = new Set(["singleAnchor", "stacked", "splitVoices", "heroBackdrop"]);
const ACTOR_ROLES = new Set(["base", "supporting", "protagonist", "backdrop", "vocalA", "vocalB"]);
const ANCHORS = new Set([
  "center", "leading", "trailing", "upperLeading", "upperTrailing",
  "lowerLeading", "lowerTrailing", "offstageLeft", "offstageRight", "aboveStage", "belowStage",
]);
const TYPE_ROLES = new Set(["whisper", "supporting", "normal", "emphasis", "hero"]);
const PALETTE_ROLES = new Set(["primary", "secondary", "accent", "warm", "backgroundContrast"]);
const PHASES = new Set(["entrance", "performance", "hold", "exit"]);
const VERBS = new Set([
  "appear", "assemble", "drift", "drop", "pulse", "stretch", "echo", "scatter", "dissolve",
]);
const PHASE_VERBS = {
  entrance: new Set(["appear", "assemble", "drift", "drop"]),
  performance: new Set(["pulse", "stretch", "echo", "drift"]),
  hold: new Set(["pulse", "echo", "appear"]),
  exit: new Set(["dissolve", "scatter", "drift"]),
};
const REASONS = new Set([
  "actionWord", "emotionalPeak", "hookRepeat", "sustainedPhrase",
  "callAndResponse", "structuralTransition", "vocalOverlap",
]);
const DIRECTIONS = new Set(["leading", "trailing", "up", "down"]);
const TOKEN_KINDS = new Set(["word", "particle", "punctuation", "whitespace", "emoji", "unknown"]);

export const STAGE_V2_BIBLE_PROMPT = `You are creating a machine-readable style bible for an iPhone 17 Pro lyric stage.
Do not rewrite lyrics. Choose a concept, a paletteStrategy from coverAnalogous/coverComplementary/coverMonochrome/warmClimax/coolClimax, a typeSystem with whisper/supporting/normal/emphasis/hero point sizes in the allowed ranges, named motifs, and sections with density and budgets.
Sections should follow the song, not a fixed 12-line machine split. Keep verses quiet and spend attention in chorus/climax.
Return only JSON: concept, paletteStrategy, typeSystem, motifs, sections.`;

export const STAGE_V2_SCENE_PROMPT = `You are directing a limited lyric choreography section for iPhone.
Use the provided token indices. Prefer token targets; use glyph targets only for a single hero character. Do not output absolute seconds or coordinates.
A scene may contain 1-3 real lineIndices. First-version compositions: singleAnchor, stacked, splitVoices, heroBackdrop.
Actors have named anchors. Events use relative 0-1 scene time, phases entrance/performance/hold/exit, and verbs appear/assemble/drift/drop/pulse/stretch/echo/scatter/dissolve.
Select only a few moments that deserve performance. Ordinary lines can be omitted so the app injects a quiet appear/dissolve baseline.
Relations: pushNeighbors, attractTo, mirrorWith. Handoffs: cut, dissolve, push.
Respect overlapGroup: backing vocals must not automatically converge; splitVoices only for real overlap.
Return at least one valid scene when the section contains lyrics. Every scene must have a unique id, lineIndices, composition, at least one actor, events, and handoffOut.
Use this exact JSON contract:
{
  "scenes": [{
    "id": "short-unique-id",
    "lineIndices": [0],
    "composition": "singleAnchor|stacked|splitVoices|heroBackdrop",
    "actors": [{
      "id": "actor-id-unique-within-scene",
      "target": { "kind": "line", "lineIndex": 0 },
      "role": "base|supporting|protagonist|backdrop|vocalA|vocalB",
      "anchor": "center|leading|trailing|upperLeading|upperTrailing|lowerLeading|lowerTrailing|offstageLeft|offstageRight|aboveStage|belowStage",
      "typeRole": "whisper|supporting|normal|emphasis|hero",
      "paletteRole": "primary|secondary|accent|warm|backgroundContrast"
    }],
    "events": [{
      "actorID": "actor-id",
      "phase": "entrance|performance|hold|exit",
      "verb": "appear|assemble|drift|drop|pulse|stretch|echo|scatter|dissolve",
      "start": 0.0,
      "duration": 0.3,
      "intensity": 0.7,
      "reason": "actionWord|emotionalPeak|hookRepeat|sustainedPhrase|callAndResponse|structuralTransition|vocalOverlap",
      "priority": 0
    }],
    "handoffOut": { "kind": "cut|dissolve|push", "direction": "leading|trailing|up|down" }
  }]
}
For token targets use { "kind": "tokens", "lineIndex": 0, "tokenIndices": [0] }. The token index is the second value in each supplied token tuple. For a single glyph use { "kind": "glyphs", "lineIndex": 0, "glyphFrom": 0, "glyphTo": 0 }.
Phase and verb must agree: entrance uses appear/assemble/drift/drop; performance uses pulse/stretch/echo/drift; hold uses pulse/echo/appear; exit uses dissolve/scatter/drift.
Return only that JSON object.`;

export function compactStageV2BibleInput(input) {
  return {
    track: [input.title, input.artist, input.duration],
    outline: input.lines.map((line) => [
      line.index, round(line.from), round(line.to), line.text, line.voiceRole, line.overlapGroup,
    ]),
    repeats: repeatedTexts(input.lines),
    tokens: summarizeTokens(input),
  };
}

export function compactStageV2SceneInput(input, section, bible) {
  const lines = input.lines.filter((line) => line.index >= section.lineFrom && line.index <= section.lineTo);
  return {
    track: [input.title, input.artist, input.duration],
    section,
    bible: {
      concept: bible.concept,
      paletteStrategy: bible.paletteStrategy,
      motifs: bible.motifs,
    },
    lines: lines.map((line) => [
      line.index, round(line.from), round(line.to), line.text, line.voiceRole, line.overlapGroup,
      line.words.map((word) => [word.index, word.text]),
    ]),
    tokens: summarizeTokens({ ...input, lines }),
  };
}

export function heuristicBible(input) {
  const last = Math.max(0, input.lines.length - 1);
  const introEnd = Math.max(0, Math.floor(input.lines.length * 0.12));
  const outroStart = Math.min(last, Math.max(introEnd + 1, Math.floor(input.lines.length * 0.88)));
  const repeats = new Set(repeatedTexts(input.lines));
  const chorusHits = input.lines.filter((line) => repeats.has(normalize(line.text))).map((line) => line.index);
  const chorusFrom = chorusHits.length ? Math.min(...chorusHits) : Math.min(last, introEnd + 1);
  const chorusTo = chorusHits.length ? Math.max(...chorusHits) : chorusFrom;
  return {
    concept: "quiet local stage",
    paletteStrategy: "coverAnalogous",
    typeSystem: { whisper: 19, supporting: 22, normal: 29, emphasis: 38, hero: 56 },
    motifs: [{ id: "echo-repeat", verb: "echo", note: "reprise" }],
    sections: [
      section("intro", 0, introEnd, "intro", 0.1, 0),
      section("verse", Math.min(last, introEnd + 1), Math.max(introEnd + 1, chorusFrom - 1), "verse", 0.2, 0),
      section("chorus", chorusFrom, Math.max(chorusFrom, Math.min(outroStart, chorusTo)), chorusHits.length ? "chorus" : "verse", chorusHits.length ? 0.85 : 0.2, chorusHits.length ? 1 : 0),
      section("outro", outroStart, last, "outro", 0.15, 0),
    ].filter((item) => item.lineTo >= item.lineFrom),
  };
}

export function sanitizeStyleBible(value, input) {
  const fallback = heuristicBible(input);
  if (!value || typeof value !== "object" || Array.isArray(value)) return fallback;
  const concept = clean(value.concept, 160) || fallback.concept;
  const paletteStrategy = PALETTE.has(value.paletteStrategy) ? value.paletteStrategy : fallback.paletteStrategy;
  const typeSystem = {
    whisper: clamp(finite(value.typeSystem?.whisper, 19), 18, 20),
    supporting: clamp(finite(value.typeSystem?.supporting, 22), 20, 24),
    normal: clamp(finite(value.typeSystem?.normal, 29), 26, 32),
    emphasis: clamp(finite(value.typeSystem?.emphasis, 38), 34, 42),
    hero: clamp(finite(value.typeSystem?.hero, 56), 48, 72),
  };
  const motifs = (Array.isArray(value.motifs) ? value.motifs : fallback.motifs)
    .map((motif) => ({
      id: clean(motif?.id, 40),
      verb: VERBS.has(motif?.verb) ? motif.verb : "echo",
      note: clean(motif?.note, 120),
    }))
    .filter((motif) => motif.id)
    .slice(0, 12);
  const lineCount = input.lines.length;
  const sections = (Array.isArray(value.sections) ? value.sections : fallback.sections)
    .map((item) => sanitizeSection(item, lineCount))
    .filter(Boolean);
  return {
    concept,
    paletteStrategy,
    typeSystem,
    motifs: motifs.length ? motifs : fallback.motifs,
    sections: sections.length ? sections : fallback.sections,
  };
}

export function finalizeStageScoreV2(input, bible, sceneBatches, directorVersion) {
  const lineIndices = new Set(input.lines.map((line) => line.index));
  const tokenCounts = tokenCountMap(input);
  const glyphCounts = Object.fromEntries(input.lines.map((line) => [line.index, Array.from(line.text).length]));
  const seen = new Set();
  const scenes = sceneBatches
    .flat()
    .map((scene) => sanitizeScene(scene, lineIndices, tokenCounts, glyphCounts, input.lines))
    .filter((scene) => scene && !seen.has(scene.id) && seen.add(scene.id));
  return {
    version: VERSION,
    directorVersion: clean(directorVersion, 120) || "luna-lyric-director-v2-events",
    trackID: input.trackID,
    lyricsHash: input.lyricsHash,
    styleSheet: {
      concept: bible.concept,
      paletteStrategy: bible.paletteStrategy,
      typeSystem: bible.typeSystem,
      motifs: bible.motifs,
    },
    sections: bible.sections,
    scenes,
    droppedEvents: [],
  };
}

export function sliceSections(bible, maxLines = 16, maxSlices = 4) {
  if (!Array.isArray(bible?.sections) || bible.sections.length === 0) return [];
  const split = (width) => {
    const slices = [];
    for (const section of bible.sections) {
      for (let from = section.lineFrom; from <= section.lineTo; from += width) {
        slices.push({
          ...section,
          id: `${section.id}-${from}`,
          lineFrom: from,
          lineTo: Math.min(section.lineTo, from + width - 1),
        });
      }
    }
    return slices;
  };

  let width = Math.max(1, maxLines);
  let slices = split(width);
  while (slices.length > maxSlices && width < 120) {
    width += 8;
    slices = split(width);
  }
  if (slices.length <= maxSlices) return slices;

  const lineFrom = bible.sections[0].lineFrom;
  const lineTo = bible.sections.at(-1).lineTo;
  const size = Math.ceil((lineTo - lineFrom + 1) / maxSlices);
  const rebinned = [];
  for (let from = lineFrom, index = 0; from <= lineTo && index < maxSlices; from += size, index += 1) {
    const to = Math.min(lineTo, from + size - 1);
    const source = bible.sections.find((section) => section.lineTo >= from) || bible.sections[0];
    rebinned.push({
      ...source,
      id: `${source.id}-${from}`,
      lineFrom: from,
      lineTo: to,
    });
  }
  return rebinned;
}

function sanitizeSection(section, lineCount) {
  if (!section || typeof section !== "object") return null;
  const id = clean(section.id, 40);
  const lineFrom = integer(section.lineFrom ?? section.lineRange?.from, -1);
  const lineTo = integer(section.lineTo ?? section.lineRange?.to, -1);
  if (!id || lineFrom < 0 || lineTo < lineFrom || lineTo >= lineCount) return null;
  return {
    id,
    lineFrom,
    lineTo,
    kind: SECTION_KINDS.has(section.kind) ? section.kind : "unknown",
    density: clamp(finite(section.density, 0.2), 0, 1),
    heroBudget: clamp(integer(section.heroBudget, 0), 0, 4),
    accentBudget: clamp(finite(section.accentBudget, 0.12), 0, 0.4),
    preferredMotifs: Array.isArray(section.preferredMotifs)
      ? section.preferredMotifs.map((item) => clean(item, 40)).filter(Boolean).slice(0, 6)
      : [],
  };
}

function sanitizeScene(scene, lineIndices, tokenCounts, glyphCounts, lines) {
  if (!scene || typeof scene !== "object") return null;
  const id = clean(scene.id, 48);
  if (!id || !Array.isArray(scene.lineIndices)) return null;
  const unique = [];
  for (const value of scene.lineIndices) {
    const index = integer(value, -1);
    if (lineIndices.has(index) && !unique.includes(index) && unique.length < 3) unique.push(index);
  }
  if (!unique.length) return null;
  const overlapGroups = new Set(unique.map((index) => lines.find((line) => line.index === index)?.overlapGroup).filter(Boolean));
  let composition = COMPOSITIONS.has(scene.composition) ? scene.composition : "singleAnchor";
  if (composition === "splitVoices" && overlapGroups.size === 0) composition = "stacked";
  const actors = (Array.isArray(scene.actors) ? scene.actors : [])
    .map((actor) => sanitizeActor(actor, unique, tokenCounts, glyphCounts))
    .filter(Boolean);
  const seenActors = new Set();
  const uniqueActors = actors.filter((actor) => !seenActors.has(actor.id) && seenActors.add(actor.id));
  if (!uniqueActors.length) return null;
  const actorIDs = new Set(uniqueActors.map((actor) => actor.id));
  const events = (Array.isArray(scene.events) ? scene.events : [])
    .map((event) => sanitizeEvent(event, actorIDs))
    .filter(Boolean);
  return {
    id,
    lineIndices: unique,
    composition,
    actors: uniqueActors,
    events,
    handoffOut: sanitizeHandoff(scene.handoffOut),
  };
}

function sanitizeActor(actor, lineIndices, tokenCounts, glyphCounts) {
  if (!actor || typeof actor !== "object") return null;
  const id = clean(actor.id, 40);
  const target = sanitizeTarget(actor.target, lineIndices, tokenCounts, glyphCounts);
  if (!id || !target) return null;
  return {
    id,
    target,
    role: ACTOR_ROLES.has(actor.role) ? actor.role : "base",
    anchor: ANCHORS.has(actor.anchor) ? actor.anchor : "center",
    typeRole: TYPE_ROLES.has(actor.typeRole) ? actor.typeRole : "normal",
    paletteRole: PALETTE_ROLES.has(actor.paletteRole) ? actor.paletteRole : "primary",
  };
}

function sanitizeTarget(target, lineIndices, tokenCounts, glyphCounts) {
  if (!target || typeof target !== "object") return null;
  const lineIndex = integer(target.lineIndex, -1);
  if (!lineIndices.includes(lineIndex)) return null;
  const kind = target.kind;
  if (kind === "tokens") {
    const count = tokenCounts[lineIndex] || 0;
    const tokenIndices = (Array.isArray(target.tokenIndices) ? target.tokenIndices : [])
      .map((value) => integer(value, -1))
      .filter((value, index, array) => value >= 0 && value < count && array.indexOf(value) === index);
    return tokenIndices.length ? { kind: "tokens", lineIndex, tokenIndices } : null;
  }
  if (kind === "glyphs") {
    const count = glyphCounts[lineIndex] || 0;
    const glyphFrom = integer(target.glyphFrom, -1);
    const glyphTo = integer(target.glyphTo, -1);
    if (glyphFrom < 0 || glyphTo < glyphFrom || glyphTo >= count) return null;
    return { kind: "glyphs", lineIndex, glyphFrom, glyphTo };
  }
  return { kind: "line", lineIndex };
}

function sanitizeEvent(event, actorIDs) {
  if (!event || typeof event !== "object") return null;
  const actorID = clean(event.actorID, 40);
  if (!actorIDs.has(actorID) || !PHASES.has(event.phase) || !VERBS.has(event.verb) || !REASONS.has(event.reason)) {
    return null;
  }
  if (!PHASE_VERBS[event.phase]?.has(event.verb)) return null;
  const start = clamp(finite(event.start, 0), 0, 1);
  const duration = clamp(finite(event.duration, 0.3), 0.04, 1 - start);
  if (duration <= 0) return null;
  return {
    actorID,
    phase: event.phase,
    verb: event.verb,
    start,
    duration,
    intensity: clamp(finite(event.intensity, 0.7), 0.2, 1.25),
    motifRef: clean(event.motifRef, 40) || undefined,
    reason: event.reason,
    relation: sanitizeRelation(event.relation, actorIDs),
    priority: integer(event.priority, 0),
  };
}

function sanitizeRelation(relation, actorIDs) {
  if (!relation || typeof relation !== "object") return undefined;
  if (relation.kind === "pushNeighbors") return { kind: "pushNeighbors" };
  if ((relation.kind === "attractTo" || relation.kind === "mirrorWith") && actorIDs.has(relation.actorID)) {
    return { kind: relation.kind, actorID: relation.actorID };
  }
  return undefined;
}

function sanitizeHandoff(value) {
  if (!value || typeof value !== "object") return { kind: "dissolve" };
  if (value.kind === "cut") return { kind: "cut" };
  if (value.kind === "push") {
    return { kind: "push", direction: DIRECTIONS.has(value.direction) ? value.direction : "trailing" };
  }
  if (value.kind === "residue") return { kind: "dissolve" };
  return { kind: "dissolve" };
}

function summarizeTokens(input) {
  if (Array.isArray(input.tokens) && input.tokens.length) {
    return input.tokens.slice(0, 1_200).map((token) => [
      integer(token.lineIndex, -1),
      integer(token.id, -1),
      clean(token.text, 80),
      TOKEN_KINDS.has(token.kind) ? token.kind : "unknown",
      integer(token.glyphFrom, 0),
      integer(token.glyphTo, 0),
    ]).filter((token) => token[0] >= 0 && token[1] >= 0);
  }
  return input.lines.flatMap((line) => line.words.map((word) => [
    line.index, word.index, word.text, "word", 0, 0,
  ]));
}

function tokenCountMap(input) {
  const counts = {};
  for (const line of input.lines) counts[line.index] = 0;
  if (Array.isArray(input.tokens)) {
    for (const token of input.tokens) {
      const lineIndex = integer(token.lineIndex, -1);
      if (lineIndex >= 0) counts[lineIndex] = (counts[lineIndex] || 0) + 1;
    }
    return counts;
  }
  for (const line of input.lines) counts[line.index] = line.words.length;
  return counts;
}

function repeatedTexts(lines) {
  const seen = new Map();
  for (const line of lines) {
    const key = normalize(line.text);
    if (key.length < 2) continue;
    seen.set(key, (seen.get(key) || 0) + 1);
  }
  return [...seen.entries()].filter(([, count]) => count > 1).map(([key]) => key);
}

function section(id, lineFrom, lineTo, kind, density, heroBudget) {
  return {
    id,
    lineFrom,
    lineTo,
    kind,
    density,
    heroBudget,
    accentBudget: kind === "chorus" ? 0.2 : 0.12,
    preferredMotifs: kind === "chorus" ? ["echo-repeat"] : [],
  };
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
