from __future__ import annotations

import argparse
import gc
import json
import os
import re
import subprocess
import time
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Any

import torch
from qwen_asr import Qwen3ASRModel, Qwen3ForcedAligner


LRC_PATTERN = re.compile(r"^\[(\d+):(\d+(?:\.\d+)?)\](.*)$")


def json_value(value: Any) -> Any:
    if is_dataclass(value):
        return {key: json_value(item) for key, item in asdict(value).items()}
    if isinstance(value, dict):
        return {str(key): json_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_value(item) for item in value]
    if hasattr(value, "item"):
        try:
            return value.item()
        except (TypeError, ValueError):
            pass
    return value


def load_track(library_path: Path, bvid: str) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    library = json.loads(library_path.read_text(encoding="utf-8"))
    entry = next((item for item in library if item.get("trackKey", {}).get("bvid") == bvid), None)
    if entry is None:
        raise ValueError(f"track not found in library: {bvid}")
    document = entry["document"]
    lines: list[dict[str, Any]] = []
    for raw_line in document.get("lyric", "").splitlines():
        match = LRC_PATTERN.match(raw_line.strip())
        if not match:
            continue
        text = match.group(3).strip()
        if not text:
            continue
        lines.append({
            "source_start": int(match.group(1)) * 60 + float(match.group(2)),
            "text": text,
        })
    if not lines:
        raise ValueError("no timed lyric lines found")
    return entry, lines


def release_cuda(model: Any) -> None:
    del model
    gc.collect()
    torch.cuda.empty_cache()
    torch.cuda.synchronize()


def normalized_audio(source: Path, output_directory: Path) -> Path:
    target = output_directory / f"{source.stem}-16k-mono.wav"
    if target.exists() and target.stat().st_mtime >= source.stat().st_mtime:
        return target
    subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(source),
            "-ac",
            "1",
            "-ar",
            "16000",
            "-c:a",
            "pcm_s16le",
            str(target),
        ],
        check=True,
    )
    return target


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio", type=Path, required=True)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--bvid", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--language", default="Japanese")
    args = parser.parse_args()

    if not torch.cuda.is_available():
        raise RuntimeError("CUDA is required for the precision host pipeline")
    args.output.mkdir(parents=True, exist_ok=True)
    entry, lines = load_track(args.library, args.bvid)
    exact_text = "\n".join(line["text"] for line in lines)
    audio_path = normalized_audio(args.audio, args.output)

    report: dict[str, Any] = {
        "schema": "bilimusic-host-alignment-v1",
        "bvid": args.bvid,
        "audio": str(args.audio),
        "normalized_audio": str(audio_path),
        "language": args.language,
        "source_lines": lines,
        "iphone_karaoke_lyric": entry.get("document", {}).get("karaokeLyric"),
        "environment": {
            "torch": torch.__version__,
            "cuda_runtime": torch.version.cuda,
            "device": torch.cuda.get_device_name(0),
            "bf16": torch.cuda.is_bf16_supported(),
        },
    }

    torch.cuda.reset_peak_memory_stats()
    started = time.perf_counter()
    aligner = Qwen3ForcedAligner.from_pretrained(
        "Qwen/Qwen3-ForcedAligner-0.6B",
        dtype=torch.bfloat16,
        device_map="cuda:0",
        attn_implementation="sdpa",
    )
    loaded = time.perf_counter()
    exact_results = aligner.align(
        audio=str(audio_path),
        text=exact_text,
        language=args.language,
    )
    torch.cuda.synchronize()
    aligned = time.perf_counter()
    report["exact_alignment"] = json_value(exact_results[0])
    report["exact_alignment_metrics"] = {
        "load_seconds": loaded - started,
        "inference_seconds": aligned - loaded,
        "peak_vram_bytes": torch.cuda.max_memory_allocated(),
    }
    release_cuda(aligner)

    torch.cuda.reset_peak_memory_stats()
    started = time.perf_counter()
    asr = Qwen3ASRModel.from_pretrained(
        "Qwen/Qwen3-ASR-1.7B",
        forced_aligner="Qwen/Qwen3-ForcedAligner-0.6B",
        forced_aligner_kwargs={
            "dtype": torch.bfloat16,
            "device_map": "cuda:0",
            "attn_implementation": "sdpa",
        },
        dtype=torch.bfloat16,
        device_map="cuda:0",
        attn_implementation="sdpa",
        max_inference_batch_size=1,
        max_new_tokens=2048,
    )
    loaded = time.perf_counter()
    asr_results = asr.transcribe(
        audio=str(audio_path),
        language=args.language,
        return_time_stamps=True,
    )
    torch.cuda.synchronize()
    transcribed = time.perf_counter()
    report["asr_alignment"] = json_value(asr_results[0])
    report["asr_alignment_metrics"] = {
        "load_seconds": loaded - started,
        "inference_seconds": transcribed - loaded,
        "peak_vram_bytes": torch.cuda.max_memory_allocated(),
    }
    release_cuda(asr)

    report_path = args.output / f"{args.bvid}-raw-alignment.json"
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, default=str),
        encoding="utf-8",
    )
    print(json.dumps({
        "report": str(report_path),
        "exact_items": len(report["exact_alignment"].get("items", [])),
        "asr_text_length": len(report["asr_alignment"].get("text", "")),
        "exact_inference_seconds": report["exact_alignment_metrics"]["inference_seconds"],
        "asr_inference_seconds": report["asr_alignment_metrics"]["inference_seconds"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
    main()
