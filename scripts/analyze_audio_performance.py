#!/usr/bin/env python3
"""Extract the versioned BiliMusic audio-performance fact map from mono float32 PCM."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path

import numpy as np


MAP_VERSION = "audio-performance-map-v2"
ANALYZER_VERSION = "bilimusic-local-audio-analysis-v2"


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def normalized(values: np.ndarray, low: float = 0.10, high: float = 0.95) -> np.ndarray:
    if values.size == 0:
        return np.zeros_like(values)
    lo, hi = np.quantile(values, [low, high])
    if hi <= lo + 1e-12:
        return np.zeros_like(values)
    return np.clip((values - lo) / (hi - lo), 0, 1)


def local_peaks(values: np.ndarray, threshold: float, minimum_distance: int) -> list[int]:
    if len(values) < 3:
        return []
    candidates = np.flatnonzero(
        (values >= np.roll(values, 1))
        & (values > np.roll(values, -1))
        & (values >= threshold)
    )
    candidates = candidates[(candidates > 0) & (candidates < len(values) - 1)]
    selected: list[int] = []
    for index in candidates[np.argsort(values[candidates])[::-1]]:
        if all(abs(int(index) - prior) >= minimum_distance for prior in selected):
            selected.append(int(index))
    return sorted(selected)


def quantized(values: np.ndarray, minimum: float = 0, maximum: float = 1) -> str:
    span = max(1e-12, maximum - minimum)
    samples = np.clip(np.round((values - minimum) / span * 255), 0, 255).astype(np.uint8)
    return base64.b64encode(samples.tobytes()).decode("ascii")


def envelope(kind: str, values: np.ndarray, sample_rate_hz: float, minimum: float = 0, maximum: float = 1) -> dict:
    return {
        "kind": kind,
        "startTime": 0,
        "sampleRateHz": sample_rate_hz,
        "minimum": minimum,
        "maximum": maximum,
        "samples": quantized(values, minimum, maximum),
    }


def pitch_envelopes(frames: np.ndarray, sample_rate: int, raw_energy: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    pitch = np.full(len(frames), 36.0, dtype=np.float64)
    confidence = np.zeros(len(frames), dtype=np.float64)
    audible_floor = max(0.0005, float(np.quantile(raw_energy, 0.20)) * 0.75)
    stride = 4
    decimation = 4
    reduced_rate = sample_rate / decimation
    minimum_lag = max(2, int(reduced_rate / 1000))
    for frame_index in range(0, len(frames), stride):
        if raw_energy[frame_index] < audible_floor:
            continue
        values = frames[frame_index, ::decimation].astype(np.float64)
        values -= values.mean()
        maximum_lag = min(len(values) // 2, max(minimum_lag, int(np.ceil(reduced_rate / 65))))
        correlation = np.correlate(values, values, mode="full")[len(values) - 1 :]
        normalizer = max(float(correlation[0]), 1e-9)
        scores = correlation[minimum_lag : maximum_lag + 1] / normalizer
        if scores.size == 0:
            continue
        offset = int(np.argmax(scores))
        best_lag = minimum_lag + offset
        best_score = float(scores[offset])
        if best_score < 0.18:
            continue
        frequency = reduced_rate / best_lag
        midi = float(np.clip(69 + 12 * np.log2(max(1, frequency) / 440), 36, 96))
        value_confidence = float(np.clip((best_score - 0.18) / 0.72, 0, 1))
        pitch[frame_index : frame_index + stride] = midi
        confidence[frame_index : frame_index + stride] = value_confidence
    return pitch, confidence


def beat_grid(onset: np.ndarray, energy: np.ndarray, frame_rate: float, duration: float) -> dict:
    minimum_lag = max(1, round(frame_rate * 60 / 210))
    maximum_lag = min(len(onset) // 2, max(minimum_lag, round(frame_rate * 60 / 55)))
    if maximum_lag < minimum_lag:
        return {"bpm": None, "confidence": 0.0, "downbeatConfidence": 0.0, "beats": [], "downbeats": []}
    scores = np.array([
        np.dot(onset[lag:], onset[:-lag]) for lag in range(minimum_lag, maximum_lag + 1)
    ])
    best_offset = int(np.argmax(scores))
    beat_lag = minimum_lag + best_offset
    confidence = float(np.clip(scores[best_offset] / max(float(np.dot(onset, onset)), 1e-9) * 1.8, 0, 1))
    if confidence < 0.05:
        return {"bpm": None, "confidence": confidence, "downbeatConfidence": 0.0, "beats": [], "downbeats": []}
    phase_scores = np.array([onset[phase::beat_lag].sum() for phase in range(beat_lag)])
    beat_phase = int(np.argmax(phase_scores))
    beat_indices = list(range(beat_phase, len(onset), beat_lag))
    bar_scores = np.array([
        sum(onset[index] * 0.65 + energy[index] * 0.35 for offset, index in enumerate(beat_indices) if offset % 4 == phase)
        for phase in range(4)
    ])
    downbeat_phase = int(np.argmax(bar_scores))
    ordered = np.sort(bar_scores)[::-1]
    downbeat_confidence = float(np.clip((ordered[0] - ordered[1]) / max(ordered[0], 1e-9), 0, 1))
    to_time = lambda index: min(duration, index / frame_rate)
    return {
        "bpm": 60 * frame_rate / beat_lag,
        "confidence": confidence,
        "downbeatConfidence": downbeat_confidence,
        "beats": [round(to_time(index), 4) for index in beat_indices if to_time(index) < duration],
        "downbeats": [
            round(to_time(index), 4)
            for offset, index in enumerate(beat_indices)
            if offset % 4 == downbeat_phase and to_time(index) < duration
        ],
    }


def contiguous_regions(
    kind: str,
    values: np.ndarray,
    predicate,
    minimum_duration: float,
    frame_rate: float,
    duration: float,
) -> list[dict]:
    mask = predicate(values)
    padded = np.concatenate(([False], mask, [False])).astype(np.int8)
    changes = np.diff(padded)
    starts = np.flatnonzero(changes == 1)
    ends = np.flatnonzero(changes == -1)
    result = []
    for start, end in zip(starts, ends):
        region_from = start / frame_rate
        region_to = min(duration, end / frame_rate)
        if region_to - region_from < minimum_duration:
            continue
        result.append({
            "id": f"{kind}-{len(result)}",
            "kind": kind,
            "from": region_from,
            "to": region_to,
            "confidence": min(1, 0.55 + (region_to - region_from) / 8),
        })
    return result


def acoustic_sections(energy: np.ndarray, brightness: np.ndarray, frame_rate: float, duration: float) -> list[dict]:
    radius = max(1, round(frame_rate * 1.8))
    kernel = np.ones(radius) / radius
    smooth_energy = np.convolve(energy, kernel, mode="same")
    smooth_brightness = np.convolve(brightness, kernel, mode="same")
    novelty = np.zeros_like(energy)
    if len(energy) > radius * 2:
        novelty[radius:-radius] = (
            np.abs(smooth_energy[radius * 2 :] - smooth_energy[: -radius * 2]) * 0.72
            + np.abs(smooth_brightness[radius * 2 :] - smooth_brightness[: -radius * 2]) * 0.28
        )
    novelty = normalized(novelty, 0.45, 0.98)
    candidates = local_peaks(
        novelty,
        max(0.52, float(np.quantile(novelty, 0.86))),
        max(1, round(frame_rate * 8)),
    )
    candidates = [index for index in candidates if 6 <= index / frame_rate <= duration - 6]
    strongest = sorted(sorted(candidates, key=lambda index: novelty[index], reverse=True)[:11])
    boundaries = [0.0, *[index / frame_rate for index in strongest], duration]
    result = []
    for index, (region_from, region_to) in enumerate(zip(boundaries, boundaries[1:])):
        boundary_index = strongest[max(0, index - 1)] if strongest else None
        result.append({
            "id": f"section-{index}",
            "kind": "acousticSection",
            "from": region_from,
            "to": region_to,
            "confidence": float(novelty[boundary_index]) if boundary_index is not None else 0.55,
        })
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pcm", type=Path)
    parser.add_argument("--sample-rate", type=int, default=22_050)
    parser.add_argument("--audio-fingerprint")
    parser.add_argument("--absolute-start", type=float, default=0)
    parser.add_argument("--schema", choices=("v1", "v2"), default="v1")
    args = parser.parse_args()

    audio = np.fromfile(args.pcm, dtype="<f4")
    frame = 2048
    hop = 1024
    if len(audio) < max(frame, int(args.sample_rate * 0.75)):
        raise SystemExit("PCM is too short")
    frame_count = 1 + (len(audio) - frame) // hop
    frames = np.lib.stride_tricks.sliding_window_view(audio, frame)[::hop][:frame_count]
    duration = len(audio) / args.sample_rate
    frame_rate = args.sample_rate / hop

    raw_energy = np.sqrt(np.mean(frames * frames, axis=1))
    energy = normalized(np.log1p(raw_energy * 120))
    signs = np.signbit(frames)
    zero_crossings = np.mean(signs[:, 1:] != signs[:, :-1], axis=1)
    brightness = normalized(zero_crossings, 0.05, 0.95)
    onset = normalized(
        np.maximum(0, np.diff(energy, prepend=energy[:1])) * 0.78
        + np.maximum(0, np.diff(brightness, prepend=brightness[:1])) * 0.22,
        0.20,
        0.97,
    )
    onset_indices = local_peaks(onset, max(0.36, float(np.quantile(onset, 0.82))), max(1, round(frame_rate * 0.08)))
    pitch, pitch_confidence = pitch_envelopes(frames, args.sample_rate, raw_energy)
    vocal_activity = np.clip(energy * 0.38 + pitch_confidence * 0.62, 0, 1)
    beat = beat_grid(onset, energy, frame_rate, duration)

    sections = acoustic_sections(energy, brightness, frame_rate, duration)
    silence = contiguous_regions("silence", np.maximum(energy, vocal_activity), lambda values: values <= 0.10, 0.65, frame_rate, duration)
    low_energy = contiguous_regions("lowEnergy", energy, lambda values: values <= 0.20, 1.0, frame_rate, duration)
    high_energy = contiguous_regions("highEnergy", energy, lambda values: values >= 0.76, 0.8, frame_rate, duration)
    transitions = [
        {
            "id": f"transition-{round(region['from'] * 1000)}",
            "kind": "transition",
            "from": max(0, region["from"] - 0.35),
            "to": min(duration, region["from"] + 0.35),
            "confidence": region["confidence"],
        }
        for region in sections[1:]
    ]

    energy_confidence = float(np.clip((np.quantile(raw_energy, 0.95) - np.quantile(raw_energy, 0.10)) * 14, 0, 1))
    onset_confidence = float(np.mean(onset[onset_indices])) if onset_indices else 0.0
    voiced = pitch_confidence[pitch_confidence >= 0.35]
    pitch_confidence_value = float(np.mean(pitch_confidence[pitch_confidence > 0])) if np.any(pitch_confidence > 0) else 0.0
    pitch_confidence_value *= min(1, len(voiced) / max(1, len(pitch_confidence)) * 2.5)
    region_confidence = float(np.mean([region["confidence"] for region in sections]))
    confidence = {
        "beat": beat["confidence"],
        "downbeat": beat["downbeatConfidence"],
        "onset": onset_confidence,
        "energy": energy_confidence,
        "pitch": float(np.clip(pitch_confidence_value, 0, 1)),
        "regions": region_confidence,
        "overall": float(np.clip(np.mean([
            beat["confidence"], onset_confidence, energy_confidence, pitch_confidence_value, region_confidence
        ]), 0, 1)),
    }

    if args.schema == "v1":
        offset_time = lambda value: round(args.absolute_start + value, 4)
        legacy = {
            "version": "audio-performance-map-v1",
            "absoluteStart": args.absolute_start,
            "duration": duration,
            "sampleRateHz": frame_rate,
            "bpm": None if beat["bpm"] is None else round(beat["bpm"], 3),
            "beats": [offset_time(value) for value in beat["beats"]],
            "downbeats": [offset_time(value) for value in beat["downbeats"]],
            "onsets": [
                {"time": offset_time(index / frame_rate), "strength": round(float(onset[index]), 3)}
                for index in onset_indices
            ],
            "energyBase64": quantized(energy),
            "brightnessBase64": quantized(brightness),
        }
        print(json.dumps(legacy, ensure_ascii=False, separators=(",", ":")))
        return

    fingerprint = args.audio_fingerprint or file_sha256(args.pcm)
    payload = {
        "version": MAP_VERSION,
        "analysisVersion": ANALYZER_VERSION,
        "audioFingerprint": fingerprint,
        "duration": duration,
        "tempoSegments": [] if beat["bpm"] is None else [{
            "from": 0,
            "to": duration,
            "bpm": beat["bpm"],
            "confidence": beat["confidence"],
        }],
        "beats": beat["beats"],
        "downbeats": beat["downbeats"],
        "onsets": [
            {"time": round(index / frame_rate, 4), "strength": round(float(onset[index]), 4)}
            for index in onset_indices
        ],
        "envelopes": [
            envelope("energy", energy, frame_rate),
            envelope("brightness", brightness, frame_rate),
            envelope("pitch", pitch, frame_rate, 36, 96),
            envelope("pitchConfidence", pitch_confidence, frame_rate),
            envelope("vocalActivity", vocal_activity, frame_rate),
        ],
        "regions": [*sections, *silence, *low_energy, *high_energy, *transitions],
        "confidence": confidence,
    }
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
