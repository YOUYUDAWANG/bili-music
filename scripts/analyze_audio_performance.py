#!/usr/bin/env python3
"""Extract a compact beat/onset/energy map from mono float32 PCM."""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path

import numpy as np


def normalized(values: np.ndarray, low: float = 10, high: float = 95) -> np.ndarray:
    lo, hi = np.percentile(values, [low, high])
    if hi <= lo:
        return np.zeros_like(values)
    return np.clip((values - lo) / (hi - lo), 0, 1)


def local_peaks(values: np.ndarray, threshold: float, minimum_distance: int) -> list[int]:
    candidates = np.flatnonzero(
        (values >= np.roll(values, 1))
        & (values > np.roll(values, -1))
        & (values >= threshold)
    )
    selected: list[int] = []
    for index in candidates[np.argsort(values[candidates])[::-1]]:
        if all(abs(int(index) - prior) >= minimum_distance for prior in selected):
            selected.append(int(index))
    return sorted(selected)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pcm", type=Path)
    parser.add_argument("--sample-rate", type=int, default=22_050)
    parser.add_argument("--absolute-start", type=float, default=0)
    args = parser.parse_args()

    audio = np.fromfile(args.pcm, dtype="<f4")
    frame = 1024
    hop = 256
    if len(audio) < frame:
        raise SystemExit("PCM is too short")
    frame_count = 1 + (len(audio) - frame) // hop
    frames = np.lib.stride_tricks.sliding_window_view(audio, frame)[::hop][:frame_count]
    windowed = frames * np.hanning(frame)
    spectrum = np.abs(np.fft.rfft(windowed, axis=1))

    rms = np.sqrt(np.mean(frames * frames, axis=1))
    energy = normalized(np.log1p(rms * 120))
    positive = np.maximum(0, np.diff(spectrum, axis=0, prepend=spectrum[:1]))
    flux = normalized(np.sqrt(np.mean(positive * positive, axis=1)), 20, 97)
    frequencies = np.fft.rfftfreq(frame, 1 / args.sample_rate)
    centroid = (spectrum * frequencies).sum(axis=1) / np.maximum(spectrum.sum(axis=1), 1e-9)
    brightness = normalized(np.log1p(centroid), 5, 95)

    frame_rate = args.sample_rate / hop
    onset_indices = local_peaks(flux, float(np.percentile(flux, 82)), round(frame_rate * 0.085))

    onset_centered = flux - np.mean(flux)
    minimum_lag = round(frame_rate * 60 / 180)
    maximum_lag = round(frame_rate * 60 / 70)
    correlations = np.array([
        np.dot(onset_centered[:-lag], onset_centered[lag:]) for lag in range(minimum_lag, maximum_lag + 1)
    ])
    beat_lag = minimum_lag + int(np.argmax(correlations))
    bpm = 60 * frame_rate / beat_lag
    phase_scores = np.array([
        flux[phase::beat_lag].sum() for phase in range(beat_lag)
    ])
    beat_phase = int(np.argmax(phase_scores))
    beat_indices = list(range(beat_phase, frame_count, beat_lag))
    strongest_bar_phase = max(
        range(4),
        key=lambda phase: sum(flux[index] for offset, index in enumerate(beat_indices) if offset % 4 == phase),
    )

    sample_step = max(1, round(frame_rate / 20))
    sampled_energy = np.clip(np.round(energy[::sample_step] * 255), 0, 255).astype(np.uint8)
    sampled_brightness = np.clip(np.round(brightness[::sample_step] * 255), 0, 255).astype(np.uint8)
    to_time = lambda index: args.absolute_start + index / frame_rate
    payload = {
        "version": "audio-performance-map-v1",
        "absoluteStart": args.absolute_start,
        "duration": len(audio) / args.sample_rate,
        "sampleRateHz": frame_rate / sample_step,
        "bpm": round(float(bpm), 3),
        "beats": [round(to_time(index), 4) for index in beat_indices],
        "downbeats": [
            round(to_time(index), 4)
            for offset, index in enumerate(beat_indices)
            if offset % 4 == strongest_bar_phase
        ],
        "onsets": [
            {"time": round(to_time(index), 4), "strength": round(float(flux[index]), 3)}
            for index in onset_indices
            if flux[index] >= 0.42
        ],
        "energyBase64": base64.b64encode(sampled_energy.tobytes()).decode("ascii"),
        "brightnessBase64": base64.b64encode(sampled_brightness.tobytes()).decode("ascii"),
    }
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
