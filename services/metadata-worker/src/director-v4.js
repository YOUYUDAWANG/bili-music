import { sanitizeDirectorInput } from "./director.js";

export const STAGE_V4_CONTRACT_VERSION = "lyric-stage-v4-scene-recipe";
export const STAGE_V4_GRAMMAR_VERSION = "scene-recipe-grammar-v1";
export const STAGE_V4_AUDIO_SCORE_VERSION = "lyric-stage-audio-structure-score-v4";

const AVAILABILITY = new Set(["ready", "missingCache", "analysisFailed", "stale"]);
const FAMILY = new Set(["railHandoff", "semanticLens", "chorusMemory", "silenceAperture"]);
const DRIVER = new Set(["lyricReveal", "wordReveal", "structuralMoment", "sectionEdge"]);
const MOTIF_SIGNATURE = new Set(["rail", "echo", "aperture", "counterline"]);
const MOTIF_AXIS = new Set(["horizontal", "diagonal", "centered"]);
const MOTIF_CADENCE = new Set(["phrase", "downbeat", "free"]);
const MOTIF_PHASE = new Set(["introduce", "develop", "transform", "resolve"]);
const SECTION_KIND = new Set([
  "intro", "verse", "preChorus", "chorus", "bridge", "breakdown", "outro", "unknown",
]);
const MOMENT_KIND = new Set([
  "sectionStart", "silenceExit", "energyPeak", "strongDownbeat", "cadence",
]);
const CONFIDENCE_DOMAINS = ["beat", "downbeat", "onset", "energy", "pitch", "sections", "overall"];
const SCORE_SEMANTICS = Object.freeze({
  energy: "trackRelativePercentile",
  brightness: "zeroCrossingRateProxy",
  pitch: "dominantMixMIDIAutocorrelation",
  vocalActivity: "energyPitchConfidenceProxy",
  downbeat: "heuristicFourBeatBar",
  quantization: "q8Milliseconds",
});

const FAMILY_RULES = {
  railHandoff: {
    topology: new Set(["relay", "anchor"]), defaultTopology: "relay",
    entrance: new Set(["slide", "gather", "settle"]), defaultEntrance: "slide",
    focus: "wholeLine",
    sustain: new Set(["railTravel", "trackingBreath", "none"]), defaultSustain: "railTravel",
    continuity: new Set(["handoff", "residue"]), defaultContinuity: "handoff",
    driver: new Set(["lyricReveal", "sectionEdge", "structuralMoment"]), defaultDriver: "lyricReveal",
  },
  semanticLens: {
    topology: new Set(["anchor", "lockup"]), defaultTopology: "anchor",
    entrance: new Set(["settle", "gather"]), defaultEntrance: "settle",
    focus: "tokenRange",
    sustain: new Set(["weightBloom", "sweep", "trackingBreath"]), defaultSustain: "weightBloom",
    continuity: new Set(["clear", "residue"]), defaultContinuity: "clear",
    driver: new Set(["lyricReveal", "wordReveal"]), defaultDriver: "lyricReveal",
  },
  chorusMemory: {
    topology: new Set(["stack", "relay", "lockup"]), defaultTopology: "stack",
    entrance: new Set(["gather", "interleave", "settle"]), defaultEntrance: "gather",
    focus: "wholeLine",
    sustain: new Set(["echo"]), defaultSustain: "echo",
    continuity: new Set(["residue", "accumulate"]), defaultContinuity: "residue",
    driver: new Set(["lyricReveal", "structuralMoment", "sectionEdge"]), defaultDriver: "lyricReveal",
  },
  silenceAperture: {
    topology: new Set(["anchor", "split"]), defaultTopology: "anchor",
    entrance: new Set(["aperture"]), defaultEntrance: "aperture",
    focus: "wholeLine",
    sustain: new Set(["none", "weightBloom"]), defaultSustain: "none",
    continuity: new Set(["clear"]), defaultContinuity: "clear",
    driver: new Set(["structuralMoment", "sectionEdge"]), defaultDriver: "structuralMoment",
  },
};

const PROMPT_SEMANTICS = Object.freeze({
  ...SCORE_SEMANTICS,
  confidenceDomains: CONFIDENCE_DOMAINS,
  confidenceDomain: "unsigned Q8, 0 to 255",
  tempoSegment: ["fromMs", "toMs", "bpmTenths", "confidenceQ"],
  section: [
    "sectionIndex", "fromMs", "toMs", "lineFrom", "lineTo", "boundaryQ",
    "meanEnergyQ", "peakEnergyQ", "energySlopeQ", "dynamicRangeQ", "onsetDensityQ",
    "brightnessMeanQ", "brightnessSlopeQ", "voicednessMeanQ", "pitchRangeTenths",
    "pitchConfidenceQ", "silenceHeadMs", "silenceTailMs",
  ],
  lineFact: [
    "lineIndex", "sectionIndex", "entryBeatPhaseQ", "signedBeatMs", "signedDownbeatMs",
    "beatsSpannedTenths", "meanEnergyQ", "peakEnergyQ", "energySlopeQ", "onsetCount",
    "onsetPeakQ", "silenceBeforeMs", "silenceAfterMs",
  ],
  lineDetail: [
    "lineIndex", "energyContourQ", "pitchContourTenths",
    "pitchConfidenceQ", "voicednessQ",
  ],
  moment: ["id", "kind", "fromMs", "toMs", "strengthQ", "confidenceQ", "lineIndex"],
});

export const STAGE_V4_PROMPT = `You direct a coherent whole-song kinetic-typography score for an iPhone 17 Pro lyric stage.
The App owns exact lyric text, line and word reveal timing, voice truth, coordinates, wrapping, curves, and rendering. Never rewrite lyrics. Never output lyric text, coordinates, absolute seconds, glyph indices, animation curves, audio fingerprints, or device identifiers.

Compact input:
- track = [title, artist, durationSeconds]
- outline line = [lineIndex, fromSeconds, toSeconds, exactText, voiceRole, overlapGroup, hasRealWordTiming, tokens]
- token = [tokenIndex, exactTokenText]
- repeatClusters contain only real normalized repetitions
- audioScore contains bounded Q8/millisecond semantics, confidence, tempo segments, structural sections, one line fact for every lyric line, optional detailed contours, and stable structural moments. Moment IDs are allow-listed references; output their IDs instead of copying or inventing times.

Return exactly one JSON object:
{
  "stageBible": {
    "concept": "short",
    "intensityArc": "short",
    "primaryMotif": { "signature": "rail|echo|aperture|counterline", "axis": "horizontal|diagonal|centered", "cadence": "phrase|downbeat|free" },
    "secondaryMotif": { "signature": "rail|echo|aperture|counterline", "axis": "horizontal|diagonal|centered", "cadence": "phrase|downbeat|free" }
  },
  "sections": [{
    "id": "short-unique-id", "lineFrom": 0, "lineTo": 7,
    "kind": "intro|verse|preChorus|chorus|bridge|breakdown|outro|unknown",
    "intensity": 0.4, "motifPhase": "introduce|develop|transform|resolve"
  }],
  "scenes": [{
    "lineIndex": 3,
    "family": "railHandoff|semanticLens|chorusMemory|silenceAperture",
    "topology": "anchor|relay|split|stack|contour|lockup",
    "entrance": "settle|slide|gather|aperture|interleave",
    "focus": "wholeLine|tokenRange",
    "tokenRange": { "startTokenIndex": 0, "endTokenIndex": 2 },
    "sustain": "none|sweep|weightBloom|trackingBreath|echo|railTravel",
    "continuity": "clear|residue|handoff|accumulate",
    "driver": "lyricReveal|wordReveal|structuralMoment|sectionEdge",
    "landmarkIDs": ["existing-moment-id"],
    "companionLineIndices": [2],
    "motifPhase": "introduce|develop|transform|resolve",
    "intensity": 0.7
  }]
}

Rules:
1. Establish one executable primary motif and at most one secondary motif. Evolve the same signature through introduce, develop, transform, and resolve rather than assigning random effects.
2. Direct only exceptional lines. Keep at least 55% of the song for the stable local compiler; high-motion recipes must never run for more than two consecutive lines.
3. railHandoff uses relay/anchor, slide/gather/settle, wholeLine, railTravel/trackingBreath/none, and handoff/residue.
4. semanticLens uses anchor/lockup, settle/gather, one contiguous real tokenRange, weightBloom/sweep/trackingBreath, and clear/residue. Never omit the rest of the line.
5. chorusMemory is only for a real repeatCluster. Use stack/relay/lockup, gather/interleave/settle, echo, and residue/accumulate. Repeated hooks should progress rather than reset randomly.
6. silenceAperture uses anchor/split, aperture, wholeLine, none/weightBloom, clear, and a real sectionStart or silenceExit moment.
7. wordReveal is allowed only when hasRealWordTiming is true. structuralMoment must reference supplied moment IDs. Audio intent may accent already revealed text but never retime it.
8. companionLineIndices may contain at most two real nearby, overlapping, or repeated lines. Do not invent a duet.
9. Output roughly 10% to 45% of lyric lines as sparse scenes. Long text still renders completely; prefer stable recipes instead of trying to shorten it.
Return JSON only.`;

export function sanitizeDirectorV4Input(raw) {
  // The router has already enforced the 98,304-byte body ceiling. Within that
  // bounded request, V4 must preserve every lyric line exactly instead of
  // inheriting the legacy director's 500-code-unit prompt compaction.
  const base = sanitizeDirectorInput(raw, { preserveCompleteLineText: true });
  if (base.lines.some((line, index) => line.index !== index)) {
    throw new Error("V4 line indices must be contiguous from zero");
  }
  const audioScoreHash = clean(raw?.audioScoreHash, 64).toLowerCase();
  if (!/^[a-f0-9]{64}$/u.test(audioScoreHash)) throw new Error("invalid V4 audio score identity");
  const rawLines = Array.isArray(raw?.lines) ? raw.lines : [];
  const lines = base.lines.map((line, index) => {
    const tokens = sanitizeTokens(rawLines[index], line);
    return {
      ...line,
      tokens,
      hasRealWordTiming: line.words.length > 0
        || (rawLines[index]?.hasRealWordTiming === true && tokens.length > 0),
    };
  });
  const audioScore = sanitizeAudioScore(raw?.audioScore ?? raw?.audioStructureScore, lines);
  return { ...base, lines, audioScoreHash, audioScore };
}

export function compactStageV4PromptInput(input) {
  return {
    track: [input.title, input.artist, input.duration],
    outline: input.lines.map((line) => [
      line.index,
      round(line.from),
      round(line.to),
      line.text,
      line.voiceRole,
      line.overlapGroup,
      line.hasRealWordTiming,
      line.tokens.map((token) => [token.index, token.text]),
    ]),
    repeatClusters: repeatClusters(input.lines),
    audioScore: {
      version: input.audioScore.version,
      availability: input.audioScore.availability,
      semantics: PROMPT_SEMANTICS,
      durationMilliseconds: input.audioScore.durationMilliseconds,
      confidence: CONFIDENCE_DOMAINS.map((domain) => input.audioScore.confidence[domain]),
      tempoSegments: input.audioScore.tempoSegments.map((segment) => [
        segment.fromMs, segment.toMs, segment.bpmTenths, segment.confidenceQ,
      ]),
      sections: input.audioScore.sections.map((section) => [
        section.index, section.fromMs, section.toMs, section.lineFrom, section.lineTo,
        section.boundaryQ, section.meanEnergyQ, section.peakEnergyQ, section.energySlopeQ,
        section.dynamicRangeQ, section.onsetDensityQ, section.brightnessMeanQ,
        section.brightnessSlopeQ, section.voicednessMeanQ, section.pitchRangeTenths,
        section.pitchConfidenceQ, section.silenceHeadMs, section.silenceTailMs,
      ]),
      lineFacts: input.audioScore.lineFacts.map((fact) => [
        fact.lineIndex, fact.sectionIndex, fact.entryBeatPhaseQ, fact.signedBeatMs,
        fact.signedDownbeatMs, fact.beatsSpannedTenths, fact.meanEnergyQ,
        fact.peakEnergyQ, fact.energySlopeQ, fact.onsetCount, fact.onsetPeakQ,
        fact.silenceBeforeMs, fact.silenceAfterMs,
      ]),
      lineDetails: input.audioScore.lineDetails.map((detail) => [
        detail.lineIndex, detail.energyContourQ, detail.pitchContourTenths,
        detail.pitchConfidenceQ, detail.voicednessQ,
      ]),
      moments: input.audioScore.moments.map((moment) => [
        moment.id, moment.kind, moment.fromMs, moment.toMs,
        moment.strengthQ, moment.confidenceQ, moment.lineIndex,
      ]),
    },
  };
}

export function finalizeStagePlanV4(input, ai, directorVersion, audioScoreHash) {
  const rawBible = sanitizeStageBibleV4(ai?.stageBible);
  const stageBible = rawBible || defaultStageBible();
  const sections = sanitizeSections(ai?.sections, input);
  const context = sceneContext(input, sections);
  const seenLines = new Set();
  const canonicalScenes = [];
  for (const value of Array.isArray(ai?.scenes) ? ai.scenes : []) {
    const scene = canonicalizeScene(value, context);
    if (!scene || seenLines.has(scene.lineIndex)) continue;
    seenLines.add(scene.lineIndex);
    canonicalScenes.push(scene);
  }
  canonicalScenes.sort((left, right) => left.lineIndex - right.lineIndex);
  const scenes = enforceMotionBudget(canonicalScenes, input.lines.length, sections);
  return {
    version: STAGE_V4_CONTRACT_VERSION,
    grammarVersion: STAGE_V4_GRAMMAR_VERSION,
    directorVersion: clean(directorVersion, 120) || "luna-lyric-director-v4-scene-recipe",
    trackID: input.trackID,
    lyricsHash: input.lyricsHash,
    lineCount: input.lines.length,
    audioScoreHash: clean(audioScoreHash, 64).toLowerCase(),
    stageBible,
    sections,
    scenes,
  };
}

export function isUsableStageV4Output(ai, score, input) {
  if (!sanitizeStageBibleV4(ai?.stageBible)) return false;
  if (input.audioScore.availability !== "ready") return false;
  const minimumScenes = Math.max(1, Math.ceil(input.lines.length * 0.10));
  const maximumScenes = Math.max(1, Math.floor(input.lines.length * 0.45));
  return score.scenes.length >= minimumScenes && score.scenes.length <= maximumScenes;
}

function sanitizeTokens(rawLine, line) {
  const rawTokens = Array.isArray(rawLine?.tokens)
    ? rawLine.tokens
    : line.words.map((word) => ({ index: word.index, text: word.text }));
  const lineGraphemes = splitGraphemes(line.text);
  const seen = new Set();
  return rawTokens.map((value, fallbackIndex) => {
    if (typeof value === "string") return { index: fallbackIndex, text: clean(value, 120) };
    if (Array.isArray(value)) {
      // The compact App contract sends [tokenIndex, glyphFrom, glyphTo] so the
      // exact lyric text is not duplicated in the request. glyphTo is exclusive.
      if (value.length >= 3 && Number.isFinite(Number(value[1])) && Number.isFinite(Number(value[2]))) {
        const from = integer(value[1], -1);
        const to = integer(value[2], -1);
        return {
          index: integer(value[0], fallbackIndex),
          text: from >= 0 && to > from && to <= lineGraphemes.length
            ? clean(lineGraphemes.slice(from, to).join(""), 120)
            : "",
        };
      }
      return { index: integer(value[0], fallbackIndex), text: clean(value[1], 120) };
    }
    return {
      index: integer(value?.index ?? value?.tokenIndex ?? value?.id, fallbackIndex),
      text: clean(value?.text, 120),
    };
  }).filter((token) => (
    token.index >= 0 && token.text && !seen.has(token.index) && seen.add(token.index)
  )).sort((left, right) => left.index - right.index).slice(0, 120);
}

function splitGraphemes(value) {
  const text = String(value ?? "");
  if (typeof Intl?.Segmenter === "function") {
    const segmenter = new Intl.Segmenter("und", { granularity: "grapheme" });
    return Array.from(segmenter.segment(text), (entry) => entry.segment);
  }
  return Array.from(text);
}

function sanitizeAudioScore(raw, lines) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return emptyAudioScore("missingCache");
  }
  const version = clean(raw.version, 80) || "unknown";
  const availability = clean(raw.availability, 24);
  if (!AVAILABILITY.has(availability)) throw new Error("invalid V4 audio availability");
  if (availability === "ready" && version !== STAGE_V4_AUDIO_SCORE_VERSION) {
    throw new Error("invalid V4 audio score version");
  }
  const semantics = sanitizeScoreSemantics(raw.semantics);
  if (availability === "ready" && !semantics) throw new Error("invalid V4 feature semantics");
  const durationMilliseconds = clamp(integer(raw.durationMilliseconds, 0), 0, 86_400_000);
  if (availability === "ready" && durationMilliseconds <= 0) throw new Error("invalid V4 audio duration");
  const confidenceSource = raw.confidence ?? raw.domainConfidence;
  const confidence = Object.fromEntries(CONFIDENCE_DOMAINS.map((domain) => [
    domain,
    q8(confidenceSource?.[domain] ?? (domain === "overall" ? confidenceSource : 0)),
  ]));
  const rawTempoSegments = raw.tempoSegments ?? raw.tempo;
  const tempoSegments = (Array.isArray(rawTempoSegments) ? rawTempoSegments : [])
    .map((value) => sanitizeTempoSegment(value, durationMilliseconds))
    .filter(Boolean).sort((left, right) => left.fromMs - right.fromMs).slice(0, 8);
  const rawSections = raw.sections ?? raw.structuralSections;
  const sections = (Array.isArray(rawSections) ? rawSections : [])
    .map((value, index) => sanitizeAudioSection(value, index, lines.length, durationMilliseconds))
    .filter(Boolean).sort((left, right) => left.fromMs - right.fromMs).slice(0, 24);
  const rawFacts = Array.isArray(raw.lineFacts) ? raw.lineFacts : [];
  const seenFacts = new Set();
  const lineFacts = rawFacts.map(sanitizeLineFact).filter((fact) => (
    fact && fact.lineIndex < lines.length && !seenFacts.has(fact.lineIndex) && seenFacts.add(fact.lineIndex)
  )).sort((left, right) => left.lineIndex - right.lineIndex);
  if (availability === "ready" && (
    lineFacts.length !== lines.length || lineFacts.some((fact, index) => fact.lineIndex !== index)
  )) {
    throw new Error("ready V4 audio score requires one fact per lyric line");
  }
  const seenDetails = new Set();
  const rawLineDetails = raw.lineDetails ?? raw.contours;
  const lineDetails = (Array.isArray(rawLineDetails) ? rawLineDetails : [])
    .map(sanitizeLineDetail).filter((detail) => (
      detail && detail.lineIndex < lines.length
      && !seenDetails.has(detail.lineIndex) && seenDetails.add(detail.lineIndex)
  )).sort((left, right) => left.lineIndex - right.lineIndex).slice(0, 64);
  const seenMoments = new Set();
  const rawMoments = raw.moments ?? raw.structuralMoments;
  const moments = (Array.isArray(rawMoments) ? rawMoments : [])
    .map((value) => sanitizeMoment(value, lines, durationMilliseconds)).filter((moment) => (
      moment && moment.lineIndex < lines.length
      && !seenMoments.has(moment.id) && seenMoments.add(moment.id)
    )).sort((left, right) => left.fromMs - right.fromMs).slice(0, 32);
  return {
    version,
    availability,
    semantics: semantics || SCORE_SEMANTICS,
    confidence,
    durationMilliseconds,
    tempoSegments,
    sections,
    lineFacts,
    lineDetails,
    moments,
  };
}

function emptyAudioScore(availability) {
  return {
    version: "unknown",
    availability,
    semantics: SCORE_SEMANTICS,
    confidence: Object.fromEntries(CONFIDENCE_DOMAINS.map((domain) => [domain, 0])),
    durationMilliseconds: 0,
    tempoSegments: [], sections: [], lineFacts: [], lineDetails: [], moments: [],
  };
}

function sanitizeScoreSemantics(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return Object.entries(SCORE_SEMANTICS).every(([key, expected]) => value[key] === expected)
    ? SCORE_SEMANTICS
    : null;
}

function sanitizeTempoSegment(value, durationMilliseconds) {
  const tuple = Array.isArray(value);
  const fromMs = integer(tuple ? value[0] : value?.fromMs, -1);
  const toMs = integer(tuple ? value[1] : value?.toMs, -1);
  if (fromMs < 0 || toMs <= fromMs || toMs > durationMilliseconds) return null;
  return {
    fromMs,
    toMs,
    bpmTenths: clamp(integer(tuple ? value[2] : value?.bpmTenths, 0), 200, 3_200),
    confidenceQ: q8(tuple ? value[3] : (value?.confidenceQ ?? value?.confidence)),
  };
}

function sanitizeAudioSection(value, fallbackIndex, lineCount, durationMilliseconds) {
  const tuple = Array.isArray(value);
  const index = integer(tuple ? value[0] : value?.index, fallbackIndex);
  const fromMs = integer(tuple ? value[1] : value?.fromMs, -1);
  const toMs = integer(tuple ? value[2] : value?.toMs, -1);
  const lineFrom = nullableBoundedInteger(tuple ? value[3] : value?.lineFrom, lineCount);
  const lineTo = nullableBoundedInteger(tuple ? value[4] : value?.lineTo, lineCount);
  if (index < 0 || fromMs < 0 || toMs <= fromMs || toMs > durationMilliseconds) return null;
  if ((lineFrom === null) !== (lineTo === null) || (lineFrom !== null && lineTo < lineFrom)) return null;
  return {
    index,
    fromMs,
    toMs,
    lineFrom,
    lineTo,
    boundaryQ: q8(tuple ? value[5] : value?.boundaryQ),
    meanEnergyQ: q8(tuple ? value[6] : value?.meanEnergyQ),
    peakEnergyQ: q8(tuple ? value[7] : value?.peakEnergyQ),
    energySlopeQ: signedQ8(tuple ? value[8] : value?.energySlopeQ),
    dynamicRangeQ: q8(tuple ? value[9] : value?.dynamicRangeQ),
    onsetDensityQ: q8(tuple ? value[10] : value?.onsetDensityQ),
    brightnessMeanQ: q8(tuple ? value[11] : value?.brightnessMeanQ),
    brightnessSlopeQ: signedQ8(tuple ? value[12] : value?.brightnessSlopeQ),
    voicednessMeanQ: q8(tuple ? value[13] : value?.voicednessMeanQ),
    pitchRangeTenths: clamp(integer(tuple ? value[14] : value?.pitchRangeTenths, 0), 0, 2_000),
    pitchConfidenceQ: q8(tuple ? value[15] : value?.pitchConfidenceQ),
    silenceHeadMs: milliseconds(tuple ? value[16] : value?.silenceHeadMs),
    silenceTailMs: milliseconds(tuple ? value[17] : value?.silenceTailMs),
  };
}

function sanitizeLineFact(value) {
  const tuple = Array.isArray(value);
  const lineIndex = integer(tuple ? value[0] : value?.lineIndex, -1);
  if (lineIndex < 0) return null;
  return {
    lineIndex,
    sectionIndex: nullableInteger(tuple ? value[1] : value?.sectionIndex),
    entryBeatPhaseQ: nullableQ8(tuple ? value[2] : value?.entryBeatPhaseQ),
    signedBeatMs: nullableSignedMilliseconds(tuple ? value[3] : value?.signedBeatMs),
    signedDownbeatMs: nullableSignedMilliseconds(tuple ? value[4] : value?.signedDownbeatMs),
    beatsSpannedTenths: nullableClampedInteger(tuple ? value[5] : value?.beatsSpannedTenths, 0, 20_000),
    meanEnergyQ: nullableQ8(tuple ? value[6] : value?.meanEnergyQ),
    peakEnergyQ: nullableQ8(tuple ? value[7] : value?.peakEnergyQ),
    energySlopeQ: nullableSignedQ8(tuple ? value[8] : value?.energySlopeQ),
    onsetCount: clamp(integer(tuple ? value[9] : value?.onsetCount, 0), 0, 10_000),
    onsetPeakQ: nullableQ8(tuple ? value[10] : value?.onsetPeakQ),
    silenceBeforeMs: milliseconds(tuple ? value[11] : value?.silenceBeforeMs),
    silenceAfterMs: milliseconds(tuple ? value[12] : value?.silenceAfterMs),
  };
}

function sanitizeLineDetail(value) {
  const tuple = Array.isArray(value);
  const lineIndex = integer(tuple ? value[0] : value?.lineIndex, -1);
  if (lineIndex < 0) return null;
  return {
    lineIndex,
    energyContourQ: q8Contour(tuple ? value[1] : value?.energyContourQ),
    pitchContourTenths: pitchContour(tuple ? value[2] : (value?.pitchContourTenths ?? value?.pitchContourQ)),
    pitchConfidenceQ: q8(tuple ? value[3] : value?.pitchConfidenceQ),
    voicednessQ: q8(tuple ? value[4] : value?.voicednessQ),
  };
}

function sanitizeMoment(value, lines, durationMilliseconds) {
  const tuple = Array.isArray(value);
  const id = clean(tuple ? value[0] : value?.id, 48);
  const kind = clean(tuple ? value[1] : value?.kind, 24);
  const fromMs = integer(tuple ? value[2] : value?.fromMs, -1);
  const toMs = integer(tuple ? value[3] : value?.toMs, -1);
  if (!id || !MOMENT_KIND.has(kind) || fromMs < 0 || toMs < fromMs || toMs > durationMilliseconds) return null;
  const suppliedLineIndex = nullableBoundedInteger(tuple ? value[6] : value?.lineIndex, lines.length);
  const lineIndex = suppliedLineIndex ?? nearestLineIndex(lines, fromMs, toMs);
  if (lineIndex === null) return null;
  return {
    id,
    kind,
    fromMs,
    toMs,
    strengthQ: q8(tuple ? value[4] : value?.strengthQ),
    confidenceQ: q8(tuple ? value[5] : value?.confidenceQ),
    lineIndex,
  };
}

function nearestLineIndex(lines, fromMs, toMs) {
  const midpoint = fromMs + (toMs - fromMs) / 2;
  let best = null;
  let bestDistance = Infinity;
  for (const line of lines) {
    const lineFrom = line.from * 1_000;
    const lineTo = line.to * 1_000;
    const distance = midpoint < lineFrom ? lineFrom - midpoint : (midpoint > lineTo ? midpoint - lineTo : 0);
    if (distance < bestDistance) {
      best = line.index;
      bestDistance = distance;
    }
  }
  return best;
}

function sanitizeStageBibleV4(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const concept = clean(value.concept, 160);
  const intensityArc = clean(value.intensityArc, 200);
  const primaryMotif = sanitizeMotif(value.primaryMotif);
  if (!concept || !intensityArc || !primaryMotif) return null;
  const secondaryMotif = sanitizeMotif(value.secondaryMotif);
  return { concept, intensityArc, primaryMotif, ...(secondaryMotif ? { secondaryMotif } : {}) };
}

function sanitizeMotif(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const signature = clean(value.signature, 20);
  const axis = clean(value.axis, 20);
  const cadence = clean(value.cadence, 20);
  if (!MOTIF_SIGNATURE.has(signature) || !MOTIF_AXIS.has(axis) || !MOTIF_CADENCE.has(cadence)) return null;
  return { signature, axis, cadence };
}

function defaultStageBible() {
  return {
    concept: "bounded structural typography",
    intensityArc: "clear introduction, restrained development, one transformation, readable resolution",
    primaryMotif: { signature: "rail", axis: "horizontal", cadence: "phrase" },
  };
}

function sanitizeSections(values, input) {
  const accepted = [];
  const seenIDs = new Set();
  for (const value of Array.isArray(values) ? values : []) {
    if (!value || typeof value !== "object" || Array.isArray(value)) continue;
    const id = clean(value.id, 40);
    const lineFrom = integer(value.lineFrom, -1);
    const lineTo = integer(value.lineTo, -1);
    if (!id || seenIDs.has(id) || lineFrom < 0 || lineTo < lineFrom || lineTo >= input.lines.length) continue;
    seenIDs.add(id);
    accepted.push({
      id,
      lineFrom,
      lineTo,
      kind: SECTION_KIND.has(value.kind) ? value.kind : "unknown",
      intensity: clamp(finite(value.intensity, 0.4), 0, 1),
      motifPhase: MOTIF_PHASE.has(value.motifPhase) ? value.motifPhase : phaseForProgress(lineFrom, input.lines.length),
    });
  }
  accepted.sort((left, right) => left.lineFrom - right.lineFrom || left.lineTo - right.lineTo);
  const nonOverlapping = [];
  for (const section of accepted) {
    if (nonOverlapping.some((prior) => section.lineFrom <= prior.lineTo)) continue;
    nonOverlapping.push(section);
  }
  return fillSectionCoverage(nonOverlapping.length ? nonOverlapping : fallbackSections(input), input.lines.length);
}

function fallbackSections(input) {
  const scoreSections = input.audioScore.sections
    .filter((section) => Number.isInteger(section.lineFrom) && section.lineTo >= section.lineFrom)
    .map((section, index) => ({
      id: `audio-section-${section.index}`,
      lineFrom: section.lineFrom,
      lineTo: section.lineTo,
      kind: index === 0 ? "intro" : "unknown",
      intensity: section.meanEnergyQ / 255,
      motifPhase: phaseForProgress(section.lineFrom, input.lines.length),
    }));
  return scoreSections.length ? scoreSections : [{
    id: "whole-song", lineFrom: 0, lineTo: input.lines.length - 1,
    kind: "unknown", intensity: 0.35, motifPhase: "develop",
  }];
}

function fillSectionCoverage(sections, lineCount) {
  const result = [];
  let cursor = 0;
  for (const section of sections) {
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
  return {
    id: `fallback-${lineFrom}-${lineTo}`,
    lineFrom,
    lineTo,
    kind: lineFrom === 0 ? "intro" : (lineTo === lineCount - 1 ? "outro" : "unknown"),
    intensity: 0.35,
    motifPhase: phaseForProgress(lineFrom, lineCount),
  };
}

function sceneContext(input, sections) {
  const linesByIndex = new Map(input.lines.map((line) => [line.index, line]));
  const momentsByID = new Map(input.audioScore.moments.map((moment) => [moment.id, moment]));
  const sectionByLine = new Map();
  for (const section of sections) {
    for (let line = section.lineFrom; line <= section.lineTo; line += 1) sectionByLine.set(line, section);
  }
  return {
    input,
    linesByIndex,
    momentsByID,
    sectionByLine,
    repeatsByLine: repeatMap(input.lines),
  };
}

function canonicalizeScene(value, context) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const lineIndex = integer(value.lineIndex, -1);
  const line = context.linesByIndex.get(lineIndex);
  const family = clean(value.family, 24);
  if (!line || !FAMILY.has(family)) return null;
  const rules = FAMILY_RULES[family];
  if (family === "chorusMemory" && !(context.repeatsByLine.get(lineIndex)?.length >= 2)) return null;

  const rawLandmarks = Array.isArray(value.landmarkIDs) ? value.landmarkIDs : [];
  const landmarkIDs = [];
  for (const candidate of rawLandmarks) {
    const id = clean(candidate, 48);
    const moment = context.momentsByID.get(id);
    if (!moment || landmarkIDs.includes(id)) continue;
    const sameSection = context.sectionByLine.get(moment.lineIndex)?.id === context.sectionByLine.get(lineIndex)?.id;
    if (moment.lineIndex === lineIndex || sameSection) landmarkIDs.push(id);
    if (landmarkIDs.length >= 2) break;
  }
  if (family === "silenceAperture") {
    const usable = landmarkIDs.filter((id) => {
      const moment = context.momentsByID.get(id);
      return moment?.lineIndex === lineIndex && (moment.kind === "sectionStart" || moment.kind === "silenceExit");
    });
    if (usable.length === 0) return null;
    landmarkIDs.splice(0, landmarkIDs.length, ...usable.slice(0, 2));
  }

  let driver = DRIVER.has(value.driver) && rules.driver.has(value.driver)
    ? value.driver
    : rules.defaultDriver;
  if (driver === "wordReveal" && !line.hasRealWordTiming) driver = "lyricReveal";
  if (driver === "structuralMoment" && landmarkIDs.length === 0) {
    if (family === "silenceAperture") return null;
    driver = rules.driver.has("lyricReveal") ? "lyricReveal" : "sectionEdge";
  }

  let tokenRange;
  if (family === "semanticLens") {
    tokenRange = sanitizeTokenRange(value.tokenRange, line.tokens);
    if (!tokenRange) return null;
  }

  const companionLineIndices = sanitizeCompanions(
    value.companionLineIndices ?? value.companions,
    lineIndex,
    family,
    context,
  );
  const section = context.sectionByLine.get(lineIndex);
  return {
    lineIndex,
    family,
    topology: rules.topology.has(value.topology) ? value.topology : rules.defaultTopology,
    entrance: rules.entrance.has(value.entrance) ? value.entrance : rules.defaultEntrance,
    focus: rules.focus,
    ...(tokenRange ? { tokenRange } : {}),
    sustain: rules.sustain.has(value.sustain) ? value.sustain : rules.defaultSustain,
    continuity: rules.continuity.has(value.continuity) ? value.continuity : rules.defaultContinuity,
    driver,
    landmarkIDs,
    companionLineIndices,
    motifPhase: MOTIF_PHASE.has(value.motifPhase) ? value.motifPhase : (section?.motifPhase || "develop"),
    intensity: clamp(finite(value.intensity, 0.65), 0.25, 1),
  };
}

function sanitizeTokenRange(value, tokens) {
  if (!value || typeof value !== "object" || Array.isArray(value) || tokens.length === 0) return null;
  const startTokenIndex = integer(value.startTokenIndex, -1);
  const endTokenIndex = integer(value.endTokenIndex, -1);
  const positions = new Map(tokens.map((token, index) => [token.index, index]));
  const start = positions.get(startTokenIndex);
  const end = positions.get(endTokenIndex);
  if (start === undefined || end === undefined || end < start || end - start >= 12) return null;
  const selected = tokens.slice(start, end + 1);
  if (selected.some((token, index) => token.index !== startTokenIndex + index)) return null;
  return { startTokenIndex, endTokenIndex };
}

function sanitizeCompanions(values, lineIndex, family, context) {
  if (family === "semanticLens" || family === "silenceAperture") return [];
  const line = context.linesByIndex.get(lineIndex);
  const repeated = new Set(context.repeatsByLine.get(lineIndex) || []);
  const result = [];
  for (const candidate of Array.isArray(values) ? values : []) {
    const index = integer(candidate, -1);
    const companion = context.linesByIndex.get(index);
    if (!companion || index === lineIndex || result.includes(index)) continue;
    const nearby = Math.abs(index - lineIndex) <= 2;
    const overlap = Boolean(line.overlapGroup && line.overlapGroup === companion.overlapGroup);
    const repeat = repeated.has(index);
    if (!nearby && !overlap && !repeat) continue;
    if (family === "chorusMemory" && !repeat && !overlap) continue;
    result.push(index);
    if (result.length >= 2) break;
  }
  if (family === "chorusMemory" && result.length === 0) {
    const previous = [...repeated].filter((index) => index < lineIndex).sort((a, b) => b - a).slice(0, 2);
    result.push(...previous);
  }
  return result;
}

function enforceMotionBudget(scenes, lineCount, sections) {
  const maximumScenes = Math.max(1, Math.floor(lineCount * 0.45));
  const sectionByLine = new Map();
  for (const section of sections) {
    for (let index = section.lineFrom; index <= section.lineTo; index += 1) sectionByLine.set(index, section.id);
  }
  const chosen = [];
  const chosenLines = new Set();
  const bySection = new Map();
  for (const scene of scenes) {
    const section = sectionByLine.get(scene.lineIndex) || "unknown";
    const existing = bySection.get(section);
    if (!existing || scenePriority(scene) > scenePriority(existing)) bySection.set(section, scene);
  }
  for (const scene of bySection.values()) {
    if (chosen.length >= maximumScenes) break;
    chosen.push(scene);
    chosenLines.add(scene.lineIndex);
  }
  const remaining = scenes
    .filter((scene) => !chosenLines.has(scene.lineIndex))
    .sort((left, right) => scenePriority(right) - scenePriority(left) || left.lineIndex - right.lineIndex);
  for (const scene of remaining) {
    if (chosen.length >= maximumScenes) break;
    chosen.push(scene);
  }
  chosen.sort((left, right) => left.lineIndex - right.lineIndex);

  let consecutiveHighMotion = 0;
  let previousLine = -2;
  let totalHighMotion = 0;
  const maximumHighMotion = Math.max(1, Math.floor(lineCount * 0.30));
  return chosen.map((scene) => {
    const high = isHighMotion(scene);
    consecutiveHighMotion = high && scene.lineIndex === previousLine + 1 ? consecutiveHighMotion + 1 : (high ? 1 : 0);
    previousLine = scene.lineIndex;
    if (high && (consecutiveHighMotion > 2 || totalHighMotion >= maximumHighMotion)) {
      consecutiveHighMotion = 0;
      return stableRepair(scene);
    }
    if (high) totalHighMotion += 1;
    return scene;
  });
}

function isHighMotion(scene) {
  return scene.family === "chorusMemory"
    || scene.family === "silenceAperture"
    || scene.entrance === "gather"
    || scene.entrance === "interleave"
    || scene.entrance === "aperture";
}

function stableRepair(scene) {
  return {
    lineIndex: scene.lineIndex,
    family: "railHandoff",
    topology: "relay",
    entrance: "settle",
    focus: "wholeLine",
    sustain: "none",
    continuity: "handoff",
    driver: "lyricReveal",
    landmarkIDs: [],
    companionLineIndices: [],
    motifPhase: scene.motifPhase,
    intensity: Math.min(0.58, scene.intensity),
  };
}

function scenePriority(scene) {
  const phase = { introduce: 0.05, develop: 0.1, transform: 0.35, resolve: 0.3 }[scene.motifPhase] || 0;
  const structural = scene.landmarkIDs.length > 0 ? 0.25 : 0;
  const family = scene.family === "chorusMemory" ? 0.22 : (scene.family === "semanticLens" ? 0.16 : 0.08);
  return scene.intensity + phase + structural + family;
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
  return [...groups.values()].filter((indices) => indices.length >= 2).map((lineIndices, index) => ({
    id: `repeat-${index}`,
    lineIndices,
  }));
}

function repeatMap(lines) {
  const result = new Map();
  for (const cluster of repeatClusters(lines)) {
    for (const lineIndex of cluster.lineIndices) result.set(lineIndex, cluster.lineIndices);
  }
  return result;
}

function normalize(value) {
  return String(value || "").normalize("NFKC").toLocaleLowerCase("en-US")
    .replace(/[^\p{L}\p{N}]+/gu, "");
}

function phaseForProgress(lineIndex, lineCount) {
  const progress = lineIndex / Math.max(1, lineCount - 1);
  if (progress < 0.25) return "introduce";
  if (progress < 0.55) return "develop";
  if (progress < 0.82) return "transform";
  return "resolve";
}

function q8Contour(value) {
  return (Array.isArray(value) ? value : []).slice(0, 32).map(q8);
}

function pitchContour(value) {
  return (Array.isArray(value) ? value : []).slice(0, 16).map((sample) => (
    sample === null || sample === undefined
      ? null
      : clamp(integer(sample, 0), -2_000, 2_000)
  ));
}

function q8(value) {
  return clamp(integer(value, 0), 0, 255);
}

function signedQ8(value) {
  return clamp(integer(value, 0), -255, 255);
}

function nullableQ8(value) {
  return value === null || value === undefined ? null : q8(value);
}

function nullableSignedQ8(value) {
  return value === null || value === undefined ? null : signedQ8(value);
}

function nullableSignedMilliseconds(value) {
  return value === null || value === undefined
    ? null
    : clamp(integer(value, 0), -60_000, 60_000);
}

function milliseconds(value) {
  return clamp(integer(value, 0), 0, 60_000);
}

function nullableClampedInteger(value, lower, upper) {
  return value === null || value === undefined
    ? null
    : clamp(integer(value, lower), lower, upper);
}

function nullableBoundedInteger(value, upperExclusive) {
  const number = Number(value);
  return Number.isInteger(number) && number >= 0 && number < upperExclusive ? number : null;
}

function nullableInteger(value) {
  const number = Number(value);
  return Number.isInteger(number) && number >= 0 ? number : null;
}

function integer(value, fallback) {
  const number = Number(value);
  return Number.isInteger(number) ? number : fallback;
}

function finite(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function clamp(value, lower, upper) {
  return Math.min(upper, Math.max(lower, value));
}

function clean(value, limit) {
  return typeof value === "string" ? value.trim().slice(0, limit) : "";
}

function round(value) {
  return Math.round(finite(value, 0) * 100) / 100;
}
