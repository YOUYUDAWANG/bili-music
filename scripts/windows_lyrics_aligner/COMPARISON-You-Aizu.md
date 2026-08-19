# `You＆合図` offline alignment comparison

Track: `BV1XWdrBVEn3` / `40610956838`, audio duration 176.52 seconds.

## Windows precision host

- Hardware: RTX 5070 Ti 16GB, Ryzen 7 7700X, 32GB RAM.
- Vocal separation: BS-RoFormer `model_bs_roformer_ep_317_sdr_12.9755`.
- Song diagnostics: Qwen3-ASR-1.7B BF16.
- Primary line alignment: Qwen3-ForcedAligner-0.6B BF16, two-pass local windows.
- Independent verification and character timing: WhisperX 3.8.6 Japanese wav2vec2 CTC.
- Stable offset cluster: +6.320s, 8 inliers from 20 candidates, median absolute deviation 0.040s.
- 26/40 line starts used model consensus; 14/40 disagreements used the stable global anchor.
- 8 Qwen line-rhythm failures were marked; WhisperX supplied character timing for all 40 lines.
- Final QRC: 40 lines, complete display text, monotonic, non-overlapping.
- 364 timed characters: minimum 50ms, median 180ms, no character at or below 40ms.
- Five durations exceed 1.5s; the 6.232s maximum is the explicitly sustained `Aa~` passage.

## Compared with the iPhone result

- iPhone global correction: approximately +6.241s.
- Windows stable offset: +6.320s.
- Median Windows-minus-iPhone line-start difference: +0.059s.
- First line: iPhone 16.401s; Windows model consensus approximately 16.464s.
- The host result is not accepted merely because it used larger models: raw mixture alignment hallucinated and full-song exact alignment collapsed. Vocal separation, local ownership windows, two-model agreement and explicit fallback gates are required.

## Deployed outputs

- `D:\BiliMusicAligner\outputs\BV1XWdrBVEn3\consensus\BV1XWdrBVEn3-host-consensus.qrc`
- `D:\BiliMusicAligner\outputs\BV1XWdrBVEn3\consensus\BV1XWdrBVEn3-host-consensus.json`

The result remains an offline comparison artifact and has not replaced the iPhone lyric cache.
