# Lyric Stage V4 · Audio Structure Score + Scene Recipe

Status: implemented and production-canary verified (2026-08-21)

## Objective

V4 makes the original product idea explicit: Gemini directs from lyrics plus a bounded audio-structure score, while the App remains the deterministic compiler and timing authority. It is additive to V3 and must fail back to the complete local V5.3 plan without affecting playback or lyric timing.

## Ownership

`LyricsFacts + AudioPerformanceMapV2 -> AudioStructureScoreV4`

`LyricsFacts + AudioStructureScoreV4 + GeminiDirectionV4 -> LocalSceneRecipeCompilerV4`

`Resolved V5.3 plan + SceneRecipeV4 -> Prepared V5.3 renderer`

- Lyrics own text, line/word reveal, voices, overlap, and user offset.
- The full audio map stays local and owns exact beat/onset/downbeat lookup.
- Gemini sees quantized structure and chooses allow-listed intent only.
- Gemini never returns text, coordinates, absolute reveal times, glyph indices, or curves.
- Audio accents never reveal text early and never delay revealed text.

## Request contract

Endpoint: `POST /v4/lyrics/direct`

Protocol: `lyric-stage-v4-scene-recipe`

The request contains complete lyric lines plus `AudioStructureScoreV4`:

- `availability`: `ready | missingCache | analysisFailed | stale`
- explicit feature semantics and domain confidence
- at most 8 quantized tempo segments
- at most 24 structural sections
- a compact fact tuple for every lyric line
- at most 64 detailed line contours
- at most 32 stable structural moments

Structural moment kinds are `sectionStart`, `silenceExit`, `energyPeak`, `strongDownbeat`, and `cadence`. Gemini references stable moment IDs; the App resolves them against the local full map. Raw audio, full beat/onset arrays, file fingerprints, secrets, and device identifiers are never placed in the model prompt.

The App applies an 88 KiB soft request budget. It degrades `lineDetails`, then structural moments, then contours. It never truncates lyrics or changes timing. If the complete lyric outline still cannot fit below the Worker hard limit, V4 uses the local fallback instead of sending a partial song.

## Response contract

The response carries a typed stage bible and sparse scene recipes:

```text
StageBibleV4
  concept
  intensityArc
  primaryMotif { signature, axis, cadence }
  secondaryMotif?

SceneRecipeV4
  lineIndex
  family
  topology
  entrance
  focus
  sustain
  continuity
  driver
  landmarkIDs[]
  companionLineIndices[]
  motifPhase
  intensity
```

Allow-listed dimensions:

- family: `railHandoff | semanticLens | chorusMemory | silenceAperture`
- topology: `anchor | relay | split | stack | contour | lockup`
- entrance: `settle | slide | gather | aperture | interleave`
- focus: `wholeLine | tokenRange`
- sustain: `none | sweep | weightBloom | trackingBreath | echo | railTravel`
- continuity: `clear | residue | handoff | accumulate`
- driver: `lyricReveal | wordReveal | structuralMoment | sectionEdge`
- motif signature: `rail | echo | aperture | counterline`
- motif axis: `horizontal | diagonal | centered`
- motif cadence: `phrase | downbeat | free`
- motif phase: `introduce | develop | transform | resolve`

The Worker canonicalizes every scene against a family-specific compatibility table. Invalid fields are repaired scene-by-scene; an invalid sparse scene cannot invalidate the complete local plan.

## Initial visual grammar

1. **Rail Handoff** — the previous line's rail becomes the next line's entry path. It establishes continuity without requiring word timing.
2. **Semantic Lens** — Gemini selects a contiguous token range; the full line remains visible while weight, scale, color, and a short rail create focus.
3. **Chorus Memory** — repeated hooks keep a controlled one- or two-layer residue and evolve across motif phases.
4. **Silence Aperture** — silence clears residue and opens a restrained aperture before the line; the lyric still appears strictly on its own timeline.

## Budgets and degradation

- One motion family and one material behavior per scene.
- At most two echo layers, eight decorative particles, 48 independently transformed glyphs, and 96 text draws.
- Stable scenes should occupy 55–70% of a song; high-motion scenes cannot run for more than two consecutive lines.
- Long or complex text degrades to a fully wrapped anchor/relay. No ellipsis and no clipped lines.
- No real word timing: token/glyph animation degrades to line or row animation.
- Low audio confidence: remove the affected binding instead of guessing.
- Reduce Motion: retain typography, color, rail, and readable phase changes; remove travel, scale pulses, and residues.
- Runtime overload degradation order: echoes -> glyph transforms -> row transforms -> wrapped anchor.

## Cache, rollout, and rollback

- Independent endpoint, Worker KV prefix, App store, grammar version, director version, and feature flag.
- V3 remains untouched and callable.
- V4 appears only behind an explicit Debug generation action during canary validation.
- Invalid, timed-out, disabled, or degraded V4 output resolves to the complete local V5.3 plan.
- Disable `LYRIC_DIRECTOR_V4_ENABLED` to stop new online V4 work without affecting V1–V3.

## Acceptance gates

- Complete text and unchanged line/word timing for every valid or invalid V4 response.
- 180-line rich request remains below the Worker hard limit; client soft-budget degradation is deterministic.
- Local compiler output is deterministic for the same score/direction/compiler versions.
- Prepared runtime keeps scene lookup O(log n) and performs no per-frame text measurement, wrapping, hashing, or sorting.
- iPhone 17 Pro / iOS 27 simulator: focused contract, validator, store, route, fallback, and renderer tests pass.
- Canvas draw CPU target: p95 <= 6 ms, p99 <= 10 ms, max < 16.67 ms in the existing signpost fixture.
- Production canary: authenticated cold request succeeds with non-degraded Gemini output, then the identical request hits cache; V1–V3 remain healthy.

## Implemented verification

- App: iPhone 17 Pro / iOS 27 simulator V4 score/client/validator/store/renderer tests 24/24; default inline lyrics and V4 fixture UI regressions 1/1 each; full App target and Prepared renderer compile succeeded.
- Motion policy: ordinary lyrics settle after a short landing envelope and remain still. Continuous beat/onset scaling and perpetual tracking-breath/cosmic drift are forbidden for body text; explicit Impact/Heartbeat and structural transitions remain available.
- Renderer performance: a dedicated UI fixture asserted `v4:chorusMemory` before sampling a double-residue short-Hook baseline (about 14 text draws, not the theoretical 96-draw limit). Across the latest 240 Canvas draws, p50 was 0.93 ms, p95 3.30 ms, p99 5.56 ms and max 12.01 ms, with zero draws over 16.67 ms. These are simulator Canvas CPU timings, not whole-frame/GPU measurements.
- Worker: complete suite 54/54 after compact grapheme token, pitch-contour and >500-code-unit complete-line cross-language fixes. V4 preserves complete line text inside the route's 98,304-byte hard limit; V1–V3 retain their compatible sanitizer behavior.
- Production: Worker version `79c3d38c-363f-4c5d-b76b-625c16b3bdf1`, V3/V4 switches enabled. The first 12-line word-timed Hook/duet request with tempo, two sections, per-line facts/contours and four structural moments returned four valid recipes in 9.10s, `degraded=false`, `chat-json-object`, `gemini-3.7-flash-high`; identical replay hit KV in 83ms. A fresh four-line request against the final complete-text deployment also returned a valid non-degraded `chorusMemory` recipe and then a V4 KV hit.
- Old routes: normalize, V1, V2, V3 and embellish continue to exist and preserve the unauthenticated 401 boundary. V4 can be disabled independently; pre-V4 rollback is `52cc64da-2efd-4ce6-84ad-df1472b9e692`.
- Runtime safety confirmed by tests: raw audio and offset lyric clocks remain separate; unrevealed glyph opacity is zero; 49/97-glyph cases use bounded wrapped fallback; duplicate recipes and malformed scalar/null scenes cannot trap; invalid individual recipes do not invalidate the local full-song plan.
