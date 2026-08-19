const EFFECTS = new Set([
  "rise", "impact", "drift", "breathe", "echo", "focus", "drop", "stretch", "cascade",
]);
const WORD_EFFECTS = new Set(["sweep", "impact", "stretch", "echoTrail"]);
const ALIGNMENTS = new Set(["leading", "center", "trailing"]);
const VOICE_ROLES = new Set(["lead", "backing", "duetA", "duetB", "together"]);
const STAGE_BEHAVIORS = new Set([
  "assemble", "gravityDrop", "ripple", "stretch", "echo", "drift", "focus", "converge",
]);
const STAGE_PALETTE_ROLES = new Set(["primary", "accent", "warm", "secondary"]);

export function sanitizeDirectorInput(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("body must be an object");
  const trackID = cleanText(raw.trackID, 160);
  const title = cleanText(raw.title, 300);
  const artist = cleanText(raw.artist, 200);
  const lyricsHash = cleanText(raw.lyricsHash, 128);
  if (!trackID || !title || !/^[a-f0-9]{64}$/u.test(lyricsHash)) throw new Error("invalid track identity");
  if (!Array.isArray(raw.lines) || raw.lines.length === 0 || raw.lines.length > 180) {
    throw new Error("lines must contain 1 to 180 entries");
  }

  const seen = new Set();
  const lines = raw.lines.map((line) => {
    if (!line || typeof line !== "object") throw new Error("invalid lyric line");
    const index = integer(line.index, -1);
    const from = finiteNumber(line.from, -1);
    const to = finiteNumber(line.to, -1);
    const text = cleanText(line.text, 500);
    if (index < 0 || seen.has(index) || from < 0 || to <= from || !text) throw new Error("invalid lyric line");
    seen.add(index);
    const words = Array.isArray(line.words) ? line.words.map((word) => {
      if (!word || typeof word !== "object") throw new Error("invalid lyric word");
      const wordIndex = integer(word.index, -1);
      const wordFrom = finiteNumber(word.from, -1);
      const wordTo = finiteNumber(word.to, -1);
      const wordText = cleanText(word.text, 120);
      if (wordIndex < 0 || wordFrom < 0 || wordTo < wordFrom || !wordText) throw new Error("invalid lyric word");
      return { index: wordIndex, from: wordFrom, to: wordTo, text: wordText };
    }).slice(0, 120) : [];
    if (words.some((word, wordIndex) => word.index !== wordIndex)) throw new Error("invalid lyric word order");
    const voiceRoleValue = cleanText(line.voiceRole, 20);
    const voiceRole = VOICE_ROLES.has(voiceRoleValue) ? voiceRoleValue : "lead";
    const layerID = cleanText(line.layerID, 120) || `line-${index}-${voiceRole}`;
    const overlapGroup = cleanText(line.overlapGroup, 120) || null;
    return { index, from, to, text, words, voiceRole, layerID, overlapGroup };
  });

  return {
    trackID,
    title,
    artist,
    duration: clamp(integer(raw.duration, 0), 0, 86_400),
    lyricsHash,
    target: {
      device: cleanText(raw.target?.device, 80) || "iPhone 17 Pro",
      os: cleanText(raw.target?.os, 80) || "iOS 27",
    },
    lines,
  };
}

// Keep the public request explicit and independently verifiable, but send Luna a
// compact representation. Long word-timed songs otherwise spend most of the
// context repeating JSON field names and can exceed the upstream time budget.
// Tuple schemas:
//   track = [title, artist, durationSeconds]
//   line  = [lineIndex, fromSeconds, toSeconds, text, words]
//   word  = [wordIndex, fromSeconds, toSeconds, text]
export function compactDirectorPromptInputs(input, targetLinesPerSegment = 12) {
  const desiredSize = clamp(integer(targetLinesPerSegment, 12), 6, 30);
  const segmentSize = Math.max(desiredSize, Math.ceil(input.lines.length / 8));
  const outline = input.lines.map((line) => [
    line.index, roundedTime(line.from), line.text, line.voiceRole, line.overlapGroup,
  ]);
  const segments = [];
  for (let offset = 0; offset < input.lines.length; offset += segmentSize) {
    const lines = input.lines.slice(offset, offset + segmentSize);
    segments.push({
      track: [input.title, input.artist, input.duration],
      segment: [lines[0].index, lines.at(-1).index, input.lines.length],
      outline,
      lines: lines.map((line) => [
        line.index,
        roundedTime(line.from),
        roundedTime(line.to),
        line.text,
        line.words.map((word) => [
          word.index,
          roundedTime(word.from),
          roundedTime(word.to),
          word.text,
        ]),
        line.voiceRole,
        line.layerID,
        line.overlapGroup,
      ]),
    });
  }
  return segments;
}

export function mergeDirectorOutputs(values) {
  const usable = values.filter((value) => value && typeof value === "object" && !Array.isArray(value));
  return {
    mood: usable.map((value) => value.mood).find((value) => typeof value === "string") || "adaptive",
    compositions: usable.flatMap((value) => Array.isArray(value.compositions) ? value.compositions : []),
    scenes: usable.flatMap((value) => Array.isArray(value.scenes) ? value.scenes : []),
    wordCues: usable.flatMap((value) => Array.isArray(value.wordCues) ? value.wordCues : []),
    stageDirectives: usable.flatMap((value) => Array.isArray(value.stageDirectives) ? value.stageDirectives : []),
  };
}

export function compactStageBiblePromptInput(input) {
  return {
    track: [input.title, input.artist, input.duration],
    outline: input.lines.map((line) => [
      line.index,
      roundedTime(line.from),
      roundedTime(line.to),
      line.text,
      line.voiceRole,
      line.overlapGroup,
    ]),
  };
}

export function sanitizeStageBible(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const concept = cleanText(value.concept, 160);
  const motif = cleanText(value.motif, 160);
  const intensityArc = cleanText(value.intensityArc, 200);
  if (!concept || !motif) return null;
  return { concept, motif, intensityArc };
}

export function finalizePerformanceScore(input, ai, directorVersion) {
  const lineIndices = new Set(input.lines.map((line) => line.index));
  const compositionsByLine = new Map();
  for (const composition of Array.isArray(ai?.compositions) ? ai.compositions : []) {
    const safe = sanitizeComposition(composition, lineIndices);
    if (safe && !compositionsByLine.has(safe.lineIndex)) compositionsByLine.set(safe.lineIndex, safe);
  }
  const compositions = input.lines.map((line) => compositionsByLine.get(line.index) || {
    lineIndex: line.index,
    textLineIndices: [line.index],
  });
  const compositionSizes = new Map(compositions.map((composition) => [
    composition.lineIndex,
    composition.textLineIndices.length,
  ]));
  const seen = new Set();
  const scenes = (Array.isArray(ai?.scenes) ? ai.scenes : [])
    .map((scene) => sanitizeScene(scene, lineIndices, compositionSizes))
    .filter((scene) => scene && !seen.has(scene.lineIndex) && seen.add(scene.lineIndex))
    .sort((left, right) => left.lineIndex - right.lineIndex);
  const wordCounts = new Map(input.lines.map((line) => [line.index, line.words.length]));
  const seenWordCueLines = new Set();
  const wordCues = (Array.isArray(ai?.wordCues) ? ai.wordCues : [])
    .map((cue) => sanitizeWordCue(cue, wordCounts))
    .filter((cue) => cue && !seenWordCueLines.has(cue.lineIndex) && seenWordCueLines.add(cue.lineIndex))
    .sort((left, right) => left.lineIndex - right.lineIndex);
  const stageBible = sanitizeStageBible(ai?.stageBible);
  const seenStageLines = new Set();
  const stageDirectives = (Array.isArray(ai?.stageDirectives) ? ai.stageDirectives : [])
    .map((directive) => sanitizeStageDirective(directive, lineIndices))
    .filter((directive) => directive && !seenStageLines.has(directive.lineIndex) && seenStageLines.add(directive.lineIndex))
    .sort((left, right) => left.lineIndex - right.lineIndex);

  return {
    version: "lyric-performance-v4",
    directorVersion: cleanText(directorVersion, 120) || "luna-lyric-director-v4-word-choreography",
    trackID: input.trackID,
    lyricsHash: input.lyricsHash,
    lineCount: input.lines.length,
    mood: cleanText(ai?.mood, 80) || "adaptive",
    compositions,
    scenes,
    wordCues,
    ...(stageBible ? { stageBible } : {}),
    stageDirectives,
  };
}

function sanitizeStageDirective(directive, lineIndices) {
  if (!directive || typeof directive !== "object") return null;
  const lineIndex = integer(directive.lineIndex, -1);
  const behavior = cleanText(directive.behavior, 30);
  if (!lineIndices.has(lineIndex) || !STAGE_BEHAVIORS.has(behavior)) return null;
  const alignmentValue = cleanText(directive.alignment, 20).toLowerCase();
  const paletteValue = cleanText(directive.paletteRole, 20);
  return {
    lineIndex,
    behavior,
    ...(ALIGNMENTS.has(alignmentValue) ? { alignment: alignmentValue } : {}),
    direction: finiteNumber(directive.direction, 1) < 0 ? -1 : 1,
    intensity: clamp(finiteNumber(directive.intensity, 0.8), 0.35, 1.25),
    fontScale: clamp(finiteNumber(directive.fontScale, 1), 0.78, 1.22),
    glyphStagger: clamp(finiteNumber(directive.glyphStagger, 0.05), 0, 0.14),
    ...(STAGE_PALETTE_ROLES.has(paletteValue) ? { paletteRole: paletteValue } : {}),
  };
}

function sanitizeComposition(composition, lineIndices) {
  if (!composition || typeof composition !== "object") return null;
  const lineIndex = integer(composition.lineIndex, -1);
  if (!lineIndices.has(lineIndex) || !Array.isArray(composition.textLineIndices)) return null;
  const seen = new Set();
  const textLineIndices = composition.textLineIndices
    .map((index) => integer(index, -1))
    .filter((index) => lineIndices.has(index) && Math.abs(index - lineIndex) <= 2 && !seen.has(index) && seen.add(index))
    .slice(0, 3);
  if (!textLineIndices.includes(lineIndex)) return null;
  return { lineIndex, textLineIndices };
}

function sanitizeScene(scene, lineIndices, compositionSizes) {
  if (!scene || typeof scene !== "object") return null;
  const lineIndex = integer(scene.lineIndex, -1);
  const effect = cleanText(scene.effect, 20).toLowerCase();
  if (!lineIndices.has(lineIndex) || !EFFECTS.has(effect)) return null;
  if (effect === "cascade" && (compositionSizes.get(lineIndex) || 0) < 2) return null;
  const alignmentValue = cleanText(scene.alignment, 20).toLowerCase();
  const alignment = ALIGNMENTS.has(alignmentValue) ? alignmentValue : null;
  return {
    lineIndex,
    effect,
    ...(alignment ? { alignment } : {}),
    direction: finiteNumber(scene.direction, 1) < 0 ? -1 : 1,
    intensity: clamp(finiteNumber(scene.intensity, 0.8), 0.35, 1.25),
    fontScale: clamp(finiteNumber(scene.fontScale, 1), 0.9, 1.18),
    trackingScale: clamp(finiteNumber(scene.trackingScale, 1), 0.5, 1.8),
  };
}

function sanitizeWordCue(cue, wordCounts) {
  if (!cue || typeof cue !== "object") return null;
  const lineIndex = integer(cue.lineIndex, -1);
  const wordCount = wordCounts.get(lineIndex) || 0;
  const startWordIndex = integer(cue.startWordIndex, -1);
  const endWordIndex = integer(cue.endWordIndex, -1);
  const effect = cleanText(cue.effect, 20);
  if (wordCount <= 0 || !WORD_EFFECTS.has(effect)) return null;
  if (startWordIndex < 0 || endWordIndex < startWordIndex || endWordIndex >= wordCount) return null;
  if (endWordIndex - startWordIndex >= 12) return null;
  return {
    lineIndex,
    startWordIndex,
    endWordIndex,
    effect,
    intensity: clamp(finiteNumber(cue.intensity, 0.8), 0.35, 1.25),
    direction: finiteNumber(cue.direction, 1) < 0 ? -1 : 1,
  };
}

function cleanText(value, limit) {
  return typeof value === "string" ? value.trim().slice(0, limit) : "";
}

function finiteNumber(value, fallback) {
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

function roundedTime(value) {
  return Math.round(value * 1000) / 1000;
}
