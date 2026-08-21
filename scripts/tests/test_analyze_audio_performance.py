from __future__ import annotations

import base64
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import numpy as np


SCRIPT = Path(__file__).resolve().parents[1] / "analyze_audio_performance.py"


class AnalyzeAudioPerformanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.pcm = Path(self.temporary.name) / "fixture.pcm"
        sample_rate = 8_000
        duration = 4
        times = np.arange(sample_rate * duration, dtype=np.float64) / sample_rate
        audio = np.sin(times * 2 * np.pi * 220) * 0.2
        for beat in np.arange(0.25, duration, 0.5):
            start = round(beat * sample_rate)
            length = min(80, len(audio) - start)
            audio[start : start + length] += 0.8 * np.exp(-np.arange(length) / 16)
        audio.astype("<f4").tofile(self.pcm)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_script(self, *arguments: str) -> dict:
        completed = subprocess.run(
            [sys.executable, str(SCRIPT), str(self.pcm), "--sample-rate", "8000", *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(completed.stdout)

    def test_v2_contract_contains_compact_facts(self) -> None:
        payload = self.run_script("--schema", "v2", "--audio-fingerprint", "fixture-hash")
        self.assertEqual(payload["version"], "audio-performance-map-v2")
        self.assertEqual(payload["analysisVersion"], "bilimusic-local-audio-analysis-v2")
        self.assertEqual(payload["audioFingerprint"], "fixture-hash")
        self.assertEqual(
            {item["kind"] for item in payload["envelopes"]},
            {"energy", "brightness", "pitch", "pitchConfidence", "vocalActivity"},
        )
        self.assertTrue(payload["regions"])
        self.assertEqual(payload["regions"][0]["kind"], "acousticSection")
        self.assertIn("overall", payload["confidence"])
        self.assertTrue(base64.b64decode(payload["envelopes"][0]["samples"]))

    def test_default_v1_keeps_absolute_start_compatible(self) -> None:
        payload = self.run_script("--absolute-start", "12.5")
        self.assertEqual(payload["version"], "audio-performance-map-v1")
        self.assertEqual(payload["absoluteStart"], 12.5)
        self.assertIn("energyBase64", payload)
        if payload["beats"]:
            self.assertGreaterEqual(payload["beats"][0], 12.5)


if __name__ == "__main__":
    unittest.main()
