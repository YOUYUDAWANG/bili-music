from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any

import torch
import whisperx


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vocals", type=Path, required=True)
    parser.add_argument("--qwen-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model-cache", type=Path, required=True)
    parser.add_argument("--language-code", default="ja")
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    args.model_cache.mkdir(parents=True, exist_ok=True)
    qwen = json.loads(args.qwen_report.read_text(encoding="utf-8"))
    lines = qwen["comparisons"]
    offset = float(qwen["global_alignment"]["offset_seconds"])
    duration = float(qwen["duration"])

    segments: list[dict[str, Any]] = []
    for index, line in enumerate(lines):
        current = float(line["source_start"]) + offset
        previous_source = float(lines[index - 1]["source_start"]) if index > 0 else float(line["source_start"]) - 5
        next_source = float(lines[index + 1]["source_start"]) if index + 1 < len(lines) else float(line["source_start"]) + 5
        previous = previous_source + offset
        following = next_source + offset
        segments.append({
            "start": max(0.0, (previous + current) / 2),
            "end": min(duration, max(current + 2.0, following + 0.75)),
            "text": line["text"],
        })

    if not torch.cuda.is_available():
        raise RuntimeError("WhisperX CUDA environment is not active")
    torch.cuda.reset_peak_memory_stats()
    started = time.perf_counter()
    model, metadata = whisperx.load_align_model(
        language_code=args.language_code,
        device="cuda",
        model_dir=str(args.model_cache),
    )
    loaded = time.perf_counter()
    audio = whisperx.load_audio(str(args.vocals))
    result = whisperx.align(
        segments,
        model,
        metadata,
        audio,
        "cuda",
        return_char_alignments=True,
    )
    torch.cuda.synchronize()
    finished = time.perf_counter()

    aligned_segments = result.get("segments", [])
    comparisons: list[dict[str, Any]] = []
    for index, source in enumerate(lines):
        aligned = aligned_segments[index] if index < len(aligned_segments) else {}
        characters = aligned.get("chars") or []
        timed = [item for item in characters if item.get("start") is not None]
        onset = min((float(item["start"]) for item in timed), default=None)
        scores = [float(item["score"]) for item in timed if item.get("score") is not None]
        comparisons.append({
            "line_index": index,
            "text": source["text"],
            "source_start": source["source_start"],
            "qwen_start": source["host_start"],
            "whisperx_start": onset,
            "whisperx_minus_qwen": onset - float(source["host_start"]) if onset is not None else None,
            "aligned_character_count": len(timed),
            "mean_character_score": sum(scores) / len(scores) if scores else None,
            "segment": aligned,
        })

    report = {
        "schema": "bilimusic-whisperx-verification-v1",
        "language_code": args.language_code,
        "vocals": str(args.vocals),
        "model": metadata.get("model_name") if isinstance(metadata, dict) else None,
        "global_offset_seconds": offset,
        "comparisons": comparisons,
        "metrics": {
            "load_seconds": loaded - started,
            "inference_seconds": finished - loaded,
            "peak_vram_bytes": torch.cuda.max_memory_allocated(),
        },
    }
    report_path = args.output / f"{qwen['bvid']}-whisperx.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({
        "report": str(report_path),
        "aligned_lines": sum(item["whisperx_start"] is not None for item in comparisons),
        "metrics": report["metrics"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
