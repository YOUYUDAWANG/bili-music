const JAPANESE_KANA = /[\p{Script=Hiragana}\p{Script=Katakana}]/u;
const HANGUL = /\p{Script=Hangul}/u;
const CJK = /\p{Script=Han}/u;
const COVER_MARKER = /(翻唱|日文翻唱|日语翻唱|中文填词|歌ってみた|歌いました|acoustic\s*cover|vtuber\s*cover|(?:^|[^\p{L}])cover(?:ed)?(?:\s*ver(?:sion)?)?(?:$|[^\p{L}]))/iu;
const NOISE_BLOCK = /(4k|8k|1080|2160|60fps|hi[ -]?res|flac|dolby|杜比|修复|重制|高清|超清|official|官方|mv|music\s*video|字幕|中字|lyrics?|完整版|纯享|remastered|歌ってみた|歌いました|日文翻唱|日语翻唱|和訳)/iu;

export function sanitizeInput(payload) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new TypeError("请求体必须是 JSON 对象");
  }
  const title = cleanText(payload.title, 500);
  if (!title) throw new TypeError("title 不能为空");
  const duration = Number(payload.duration);
  return {
    title,
    uploader: cleanText(payload.uploader, 160),
    pageTitle: cleanText(payload.pageTitle, 500),
    bvid: cleanText(payload.bvid, 32),
    cid: Number.isFinite(Number(payload.cid)) ? Math.round(Number(payload.cid)) : null,
    duration: Number.isFinite(duration) && duration > 0 ? Math.round(duration) : null,
  };
}

export function detectLanguageHint(value) {
  if (JAPANESE_KANA.test(value)) return "ja";
  if (HANGUL.test(value)) return "ko";
  if (CJK.test(value)) return "zh";
  return "und";
}

export function quotedAlternatives(value) {
  const pairs = [["《", "》"], ["「", "」"], ["『", "』"], ["“", "”"]];
  const values = [];
  for (const [open, close] of pairs) {
    let cursor = 0;
    while (cursor < value.length) {
      const start = value.indexOf(open, cursor);
      if (start < 0) break;
      const end = value.indexOf(close, start + open.length);
      if (end < 0) break;
      const inner = value.slice(start + open.length, end);
      for (const part of inner.split(/[/／|｜]/u)) {
        const candidate = cleanTitle(part);
        if (candidate) values.push(candidate);
      }
      cursor = end + close.length;
    }
  }
  return unique(values).sort((left, right) => Number(JAPANESE_KANA.test(right)) - Number(JAPANESE_KANA.test(left)));
}

export function deterministicFallback(input) {
  const quoteCandidates = quotedAlternatives(`${input.title} ${input.pageTitle}`);
  const parsed = parseExplicitStructure(input.title);
  const canonicalTitle = quoteCandidates[0] || parsed.title || stripPackaging(input.title) || input.title;
  const artists = parsed.artists;
  const performers = parsed.performers;
  if (COVER_MARKER.test(input.title) && input.uploader && !isGenericUploader(input.uploader)) {
    performers.push(input.uploader);
  }
  return {
    canonicalTitle,
    artists: deduplicateNames(artists),
    performers: deduplicateNames(performers),
    aliases: unique(quoteCandidates.slice(1)),
    language: detectLanguageHint(canonicalTitle || input.title),
    confidence: quoteCandidates.length ? 0.9 : parsed.title !== input.title ? 0.78 : 0.45,
    evidence: quoteCandidates.length ? ["quoted-title"] : parsed.evidence,
    needsReview: !canonicalTitle || (!artists.length && !performers.length),
  };
}

export function finalizeNormalization(input, aiValue) {
  const fallback = deterministicFallback(input);
  const ai = aiValue && typeof aiValue === "object" ? aiValue : {};
  const quoteCandidates = quotedAlternatives(`${input.title} ${input.pageTitle}`);
  const japaneseQuoted = quoteCandidates.find((value) => JAPANESE_KANA.test(value));
  let canonicalTitle = cleanTitle(ai.canonicalTitle) || fallback.canonicalTitle;
  let japaneseGuardApplied = false;

  if (japaneseQuoted && !comparable(canonicalTitle).includes(comparable(japaneseQuoted))) {
    canonicalTitle = japaneseQuoted;
    japaneseGuardApplied = true;
  }

  const coverDetected = COVER_MARKER.test(`${input.title} ${input.pageTitle}`);
  const explicitOriginals = fallback.artists;
  let artists = mergeNames(fallback.artists, ai.artists);
  const performers = mergeNames(fallback.performers, ai.performers);
  if (coverDetected && performers.length) {
    artists = artists.filter((artist) => !performers.some((performer) => namesOverlap(artist, performer)));
  }
  const hasExplicitOriginal = evidenceHas(fallback.evidence, "explicit-original-artist")
    || explicitOriginals.length > 0;
  const catalogOK = cleanArray(ai.evidence).includes("catalog-original-artist")
    && clampNumber(ai.confidence, fallback.confidence) >= 0.85;
  if (!hasExplicitOriginal && !catalogOK) {
    artists = artists.filter((artist) => explicitOriginals.some((explicit) => namesOverlap(artist, explicit)));
  }
  if (coverDetected) {
    artists = artists.filter((artist) => !namesOverlap(artist, input.uploader || "") || explicitOriginals.some((explicit) => namesOverlap(artist, explicit)));
  }
  const aliases = unique([
    ...fallback.aliases,
    ...cleanArray(ai.aliases),
  ]).filter((value) => comparable(value) !== comparable(canonicalTitle));
  const detectedLanguage = detectLanguageHint(canonicalTitle);
  const language = detectedLanguage !== "und"
    ? detectedLanguage
    : (normalizeLanguage(ai.language) || "und");
  const confidence = clampNumber(ai.confidence, fallback.confidence);
  const evidence = unique([
    ...fallback.evidence,
    ...cleanArray(ai.evidence),
    ...(japaneseGuardApplied ? ["japanese-original-guard"] : []),
  ]).slice(0, 8);
  const lyricSearchQueries = buildSearchQueries(canonicalTitle, artists, performers);

  const hasStrongExplicitEvidence = evidence.includes("quoted-title")
    && (artists.length > 0 || performers.length > 0);
  return {
    canonicalTitle,
    originalArtists: artists,
    coverPerformers: performers,
    artists,
    performers,
    uploader: input.uploader || null,
    language,
    aliases,
    lyricSearchQueries,
    searchQueries: lyricSearchQueries,
    isCover: coverDetected,
    confidence: Math.round((japaneseGuardApplied ? Math.min(confidence, 0.9) : confidence) * 100) / 100,
    needsReview: confidence < 0.68
      || (!artists.length && !performers.length)
      || (coverDetected && !artists.length)
      || (Boolean(ai.needsReview) && !hasStrongExplicitEvidence),
    evidence,
  };
}

function parseExplicitStructure(rawTitle) {
  const result = { title: rawTitle, artists: [], performers: [], evidence: [] };
  const quoted = quotedAlternatives(rawTitle);
  const firstQuoteIndex = Math.min(...["《", "「", "『", "“"].map((mark) => {
    const index = rawTitle.indexOf(mark);
    return index < 0 ? Number.MAX_SAFE_INTEGER : index;
  }));
  if (quoted.length) {
    result.title = quoted[0];
    result.evidence.push("quoted-title");
    const prefix = firstQuoteIndex < Number.MAX_SAFE_INTEGER ? rawTitle.slice(0, firstQuoteIndex) : "";
    const names = explicitNamesFromPrefix(prefix);
    if (COVER_MARKER.test(rawTitle)) result.performers.push(...names);
    else result.artists.push(...names);
    return result;
  }

  const parts = rawTitle.split(/\s[-–—｜|]\s/u).map(cleanTextValue).filter(Boolean);
  if (parts.length >= 2 && parts[0].length <= 60) {
    if (COVER_MARKER.test(rawTitle)) result.performers.push(parts[0]);
    else result.artists.push(parts[0]);
    result.title = cleanTitle(stripPackaging(parts.slice(1).join(" ")));
    result.evidence.push("artist-title-separator");
  } else {
    result.title = cleanTitle(stripPackaging(rawTitle));
  }
  return result;
}

function explicitNamesFromPrefix(prefix) {
  const bracketNames = [...prefix.matchAll(/[【\[(（]([^】\])）]{1,60})[】\])）]/gu)]
    .map((match) => cleanTextValue(match[1]))
    .filter((value) => value && !NOISE_BLOCK.test(value));
  if (bracketNames.length) return unique(bracketNames);
  const cleaned = stripPackaging(prefix).replace(COVER_MARKER, " ").trim();
  return cleaned && cleaned.length <= 60 ? [cleaned] : [];
}

function stripPackaging(value) {
  return value
    .replace(/[【\[(（]([^】\])）]*)[】\])）]/gu, (full, content) => NOISE_BLOCK.test(content) ? " " : full)
    .replace(/\b(?:official|music\s*video|lyrics?|remastered|hd|4k|8k)\b/giu, " ")
    .replace(/\s+/gu, " ")
    .trim();
}

function buildSearchQueries(title, originalArtists, coverPerformers) {
  const queries = [];
  for (const artist of originalArtists) queries.push(`${title} ${artist}`);
  queries.push(title);
  for (const performer of coverPerformers) queries.push(`${title} ${performer}`);
  return unique(queries).slice(0, 8);
}

function evidenceHas(evidence, key) {
  return Array.isArray(evidence) && evidence.includes(key);
}

function namesOverlap(left, right) {
  const leftKey = comparable(left);
  const rightKey = comparable(right);
  return leftKey && rightKey && (leftKey.includes(rightKey) || rightKey.includes(leftKey));
}

function mergeNames(fallback, value) {
  return deduplicateNames([...fallback, ...cleanArray(value)])
    .filter((name) => !isGenericUploader(name))
    .slice(0, 8);
}

function deduplicateNames(values) {
  const output = [];
  for (const value of unique(values)) {
    const key = comparable(value);
    const overlappingIndex = output.findIndex((existing) => {
      const existingKey = comparable(existing);
      return existingKey.includes(key) || key.includes(existingKey);
    });
    if (overlappingIndex < 0) {
      output.push(value);
    } else if (key.length < comparable(output[overlappingIndex]).length) {
      output[overlappingIndex] = value;
    }
  }
  return output;
}

function cleanArray(value) {
  if (!Array.isArray(value)) return [];
  return value.map((item) => cleanText(item, 120)).filter(Boolean);
}

function cleanTitle(value) {
  return cleanText(value, 300)
    .replace(/^[《「『“"']+|[》」』”"']+$/gu, "")
    .replace(/\s+/gu, " ")
    .trim();
}

function cleanText(value, maxLength) {
  return typeof value === "string" ? value.replace(/\s+/gu, " ").trim().slice(0, maxLength) : "";
}

function cleanTextValue(value) {
  return cleanText(value, 300);
}

function isGenericUploader(value) {
  return /(搬运|转载|音乐分享|中字|字幕组|频道|channel|official\s*account|合集|剪辑)/iu.test(value);
}

function normalizeLanguage(value) {
  const language = cleanText(value, 12).toLowerCase();
  return ["ja", "zh", "ko", "en", "und", "mixed"].includes(language) ? language : "";
}

function clampNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.min(1, Math.max(0, number)) : fallback;
}

function comparable(value) {
  return cleanText(value, 500).normalize("NFKC").toLocaleLowerCase().replace(/[\s\-_/／·・.,，。:：'"“”‘’()\[\]【】（）《》「」『』!！?？]/gu, "");
}

function unique(values) {
  const seen = new Set();
  return values.filter((value) => {
    const cleaned = cleanText(value, 500);
    const key = comparable(cleaned);
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
