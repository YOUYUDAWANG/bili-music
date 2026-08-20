export const EMBELLISHER_PROMPT = `You are the lyric embellisher for an iPhone music player.
Your task is to analyze the emotional tone and imagery of the lyrics and assign subtle micro-embellishment styles to keywords and significant lines.

Allowed styles (use only these):
- shimmer: starlight, sparkle, radiant, shine, celestial, dawn
- whisper: whisper, quiet, soft, secret, gentle breath, delicate
- impact: shout, blast, energetic burst, punch, exclamation, crash
- floating: dream, wander, illusion, sky, question, drifting
- digital: 8-bit, cyber, pixel, code, retro tech, data
- ripple: echo, repeat syllables, trailing chorus
- neon: night city, electric, disco, synthwave, vibrant lights
- blaze: fire, burning, passion, heat, flame, warm energy
- crystallize: ice, snow, crystal, diamond, cold, pure clarity
- heartbeat: heartbeat, throbbing, love, pulse, deep emotion
- vintage: nostalgia, memory, past, retro tape, old film
- sway: breeze, wind, swaying, flowing, leaves dancing

Rules:
1. Select about 20% to 45% of notable lines or words. Do not over-style every single word; keep the majority clean and natural.
2. For lines with a list of words, you may specify wordIndex to embellish a single word. If wordIndex is omitted/null, the style applies to the whole line.
3. Return only valid JSON:
{
  "mood": "a short phrase describing the song's overall emotion",
  "cues": [
    { "lineIndex": 0, "wordIndex": 1, "style": "shimmer", "note": "shining keyword" },
    { "lineIndex": 2, "style": "impact", "note": "explosive hook" }
  ]
}`;

export const ALLOWED_STYLES = new Set([
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
]);

export function sanitizeEmbellisherInput(raw) {
  if (!raw || typeof raw !== "object") {
    throw new Error("Invalid payload: expected an object");
  }
  const trackID = String(raw.trackID || "unknown");
  const title = String(raw.title || "untitled").trim();
  const artist = String(raw.artist || "unknown").trim();
  const duration = Number(raw.duration || 0);
  const lyricsHash = String(raw.lyricsHash || "").trim();
  const lines = Array.isArray(raw.lines)
    ? raw.lines.slice(0, 150).map((l, i) => ({
        index: Number(l.index ?? i),
        text: String(l.text || "").trim(),
        words: Array.isArray(l.words)
          ? l.words.slice(0, 40).map((w, wi) => ({
              index: Number(w.index ?? wi),
              text: String(w.text || "").trim(),
            }))
          : [],
      }))
    : [];

  return { trackID, title, artist, duration, lyricsHash, lines };
}

export function finalizeEmbellisherOutput(aiOutput, input) {
  const lineCount = input.lines.length;
  const mood = typeof aiOutput?.mood === "string" ? aiOutput.mood.slice(0, 80) : "Expressive";
  const rawCues = Array.isArray(aiOutput?.cues) ? aiOutput.cues : [];

  const cues = [];
  const seenKeys = new Set();

  for (const cue of rawCues) {
    if (!cue || typeof cue !== "object") continue;
    const lineIndex = Number(cue.lineIndex);
    if (!Number.isInteger(lineIndex) || lineIndex < 0 || lineIndex >= lineCount) continue;

    const style = String(cue.style || "").toLowerCase().trim();
    if (!ALLOWED_STYLES.has(style)) continue;

    let wordIndex = null;
    if (cue.wordIndex !== undefined && cue.wordIndex !== null) {
      const wIdx = Number(cue.wordIndex);
      const lineWords = input.lines[lineIndex]?.words || [];
      if (Number.isInteger(wIdx) && wIdx >= 0 && wIdx < lineWords.length) {
        wordIndex = wIdx;
      } else {
        continue;
      }
    }

    const key = `${lineIndex}:${wordIndex ?? "line"}`;
    if (seenKeys.has(key)) continue;
    seenKeys.add(key);

    cues.push({
      lineIndex,
      wordIndex,
      style,
      note: typeof cue.note === "string" ? cue.note.slice(0, 50) : undefined,
    });
  }

  return {
    version: "lyric-embellish-v1",
    trackID: input.trackID,
    lyricsHash: input.lyricsHash,
    mood,
    cues,
    degraded: false,
  };
}

export function deterministicFallbackEmbellishment(input) {
  const cues = [];
  input.lines.forEach((line, lineIndex) => {
    if (line.text.includes("!") || line.text.includes("！")) {
      cues.push({ lineIndex, wordIndex: null, style: "impact", note: "exclamation" });
    } else if (line.text.includes("?") || line.text.includes("？")) {
      cues.push({ lineIndex, wordIndex: null, style: "floating", note: "question" });
    } else if (line.text.includes("…") || line.text.includes("...")) {
      cues.push({ lineIndex, wordIndex: null, style: "whisper", note: "ellipsis" });
    }
  });

  return {
    version: "lyric-embellish-v1",
    trackID: input.trackID,
    lyricsHash: input.lyricsHash,
    mood: "Natural",
    cues,
    degraded: false,
  };
}
