from __future__ import annotations

import argparse
import json
import re
import statistics
import time
from pathlib import Path
from typing import Any

import numpy as np
import soundfile as sf
import torch
from qwen_asr import Qwen3ForcedAligner

from run_alignment import json_value, load_track


QRC_HEADER = re.compile(r"^\[(\d+),(\d+)\]")


def semantic_characters(text: str) -> list[str]:
    return [character for character in text if character.isalnum()]


def display_units(text: str) -> list[str]:
    units: list[str] = []
    prefix = ""
    for character in text:
        if character.isalnum():
            units.append(prefix + character)
            prefix = ""
        elif units:
            units[-1] += character
        else:
            prefix += character
    if prefix and units:
        units[-1] += prefix
    return units


def audio_slice(audio: np.ndarray, sample_rate: int, start: float, end: float) -> tuple[np.ndarray, int]:
    lower = max(0, min(len(audio), int(start * sample_rate)))
    upper = max(lower + 1, min(len(audio), int(end * sample_rate)))
    return np.ascontiguousarray(audio[lower:upper], dtype=np.float32), sample_rate


def align_line(
    aligner: Qwen3ForcedAligner,
    audio: np.ndarray,
    sample_rate: int,
    text: str,
    start: float,
    end: float,
    language: str,
) -> dict[str, Any]:
    result = aligner.align(
        audio=audio_slice(audio, sample_rate, start, end),
        text=text,
        language=language,
    )[0]
    items = json_value(result).get("items", [])
    for item in items:
        item["start_time"] = float(item["start_time"]) + start
        item["end_time"] = float(item["end_time"]) + start
    return {"window_start": start, "window_end": end, "items": items}


def alignment_quality(text: str, items: list[dict[str, Any]]) -> dict[str, Any]:
    expected = semantic_characters(text)
    actual = [character for item in items for character in semantic_characters(item["text"])]
    spans = [max(0.0, item["end_time"] - item["start_time"]) for item in items]
    nonzero = [span for span in spans if span >= 0.04]
    coverage = sum(left == right for left, right in zip(expected, actual)) / max(len(expected), len(actual), 1)
    onset = min((item["start_time"] for item in items), default=None)
    ending = max((item["end_time"] for item in items), default=None)
    duration = (ending - onset) if onset is not None and ending is not None else 0.0
    valid = (
        bool(items)
        and coverage >= 0.9
        and duration >= min(0.20, max(0.08, len(expected) * 0.02))
        and len(nonzero) >= max(1, len(items) // 4)
    )
    return {
        "coverage": coverage,
        "nonzero_item_ratio": len(nonzero) / max(len(items), 1),
        "onset": onset,
        "ending": ending,
        "duration": duration,
        "valid": valid,
    }


def consensus(values: list[float], radius: float = 1.75) -> dict[str, Any]:
    if not values:
        raise ValueError("no usable first-pass offsets")
    best = max(
        ([value for value in values if abs(value - center) <= radius] for center in values),
        key=len,
    )
    if len(best) < max(6, int(np.ceil(len(values) * 0.35))):
        raise ValueError(f"offsets do not form a majority cluster: {values}")
    center = statistics.median(best)
    deviations = [abs(value - center) for value in best]
    return {
        "offset_seconds": center,
        "sample_count": len(best),
        "candidate_count": len(values),
        "median_absolute_deviation": statistics.median(deviations),
        "minimum": min(best),
        "maximum": max(best),
    }


def token_character_timings(text: str, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    expected = semantic_characters(text)
    actual = [character for item in items for character in semantic_characters(item["text"])]
    if expected != actual:
        raise ValueError(f"token coverage mismatch for line: {text}")
    timings: list[dict[str, Any]] = []
    cursor = 0
    for item in items:
        token_characters = semantic_characters(item["text"])
        if not token_characters:
            continue
        start = float(item["start_time"])
        end = max(start + 0.02, float(item["end_time"]))
        duration = end - start
        for index, character in enumerate(token_characters):
            character_start = start + duration * index / len(token_characters)
            character_end = start + duration * (index + 1) / len(token_characters)
            timings.append({
                "text": expected[cursor],
                "start_time": character_start,
                "end_time": max(character_start + 0.02, character_end),
            })
            cursor += 1
    return timings


def qrc_line(text: str, character_timings: list[dict[str, Any]]) -> str:
    surfaces = display_units(text)
    if len(surfaces) != len(character_timings):
        raise ValueError(f"display text coverage mismatch for line: {text}")
    line_start = int(round(character_timings[0]["start_time"] * 1000))
    line_end = max(line_start + 80, int(round(character_timings[-1]["end_time"] * 1000)))
    body = "".join(
        f"<{max(0, int(round(item['start_time'] * 1000)) - line_start)},"
        f"{max(20, int(round((item['end_time'] - item['start_time']) * 1000)))},0>{surface}"
        for item, surface in zip(character_timings, surfaces)
    )
    return f"[{line_start},{line_end - line_start}]{body}"


def iphone_line_starts(karaoke_lyric: str | None) -> list[float]:
    if not karaoke_lyric:
        return []
    starts: list[float] = []
    for line in karaoke_lyric.splitlines():
        match = QRC_HEADER.match(line)
        if match:
            starts.append(int(match.group(1)) / 1000)
    return starts


def split_group_items(
    group_lines: list[dict[str, Any]],
    items: list[dict[str, Any]],
) -> list[list[dict[str, Any]]]:
    expected = [len(semantic_characters(line["text"])) for line in group_lines]
    result: list[list[dict[str, Any]]] = []
    cursor = 0
    for count in expected:
        current: list[dict[str, Any]] = []
        consumed = 0
        while cursor < len(items) and consumed < count:
            item = items[cursor]
            size = len(semantic_characters(item["text"]))
            if consumed + size > count:
                raise ValueError("forced-aligner token crossed a repeated-line boundary")
            current.append(item)
            consumed += size
            cursor += 1
        if consumed != count:
            raise ValueError("forced-aligner did not cover a repeated-line group")
        result.append(current)
    if cursor != len(items):
        raise ValueError("forced-aligner returned extra tokens for a repeated-line group")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vocals", type=Path, required=True)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--bvid", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--language", default="Japanese")
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    entry, lines = load_track(args.library, args.bvid)
    audio, sample_rate = sf.read(args.vocals, dtype="float32", always_2d=True)
    audio = np.mean(audio, axis=1, dtype=np.float32)
    duration = len(audio) / sample_rate
    counts: dict[str, int] = {}
    for line in lines:
        key = "".join(semantic_characters(line["text"])).casefold()
        counts[key] = counts.get(key, 0) + 1

    torch.cuda.reset_peak_memory_stats()
    load_started = time.perf_counter()
    aligner = Qwen3ForcedAligner.from_pretrained(
        "Qwen/Qwen3-ForcedAligner-0.6B",
        dtype=torch.bfloat16,
        device_map="cuda:0",
        attn_implementation="sdpa",
    )
    loaded_at = time.perf_counter()

    first_pass: list[dict[str, Any]] = []
    offsets: list[float] = []
    for index, line in enumerate(lines):
        normalized = "".join(semantic_characters(line["text"])).casefold()
        if len(normalized) < 5 or counts[normalized] != 1 or line["text"].startswith("("):
            continue
        window_start = max(0.0, line["source_start"] - 3.0)
        window_end = min(duration, line["source_start"] + 18.0)
        result = align_line(
            aligner,
            audio,
            sample_rate,
            line["text"],
            window_start,
            window_end,
            args.language,
        )
        quality = alignment_quality(line["text"], result["items"])
        delta = quality["onset"] - line["source_start"] if quality["onset"] is not None else None
        interior_onset = bool(
            quality["onset"] is not None
            and quality["onset"] > window_start + 0.25
            and quality["onset"] < window_end - 0.25
        )
        usable = bool(
            quality["valid"]
            and interior_onset
            and delta is not None
            and -10 <= delta <= 15
        )
        if usable:
            offsets.append(delta)
        first_pass.append({
            "line_index": index,
            "text": line["text"],
            "source_start": line["source_start"],
            "offset_seconds": delta,
            "interior_onset": interior_onset,
            "usable": usable,
            "quality": quality,
            **result,
        })

    global_alignment = consensus(offsets)
    offset = global_alignment["offset_seconds"]
    grouped_results: dict[int, dict[str, Any]] = {}
    group_index = 0
    while group_index < len(lines):
        normalized = "".join(semantic_characters(lines[group_index]["text"])).casefold()
        group_end = group_index + 1
        while group_end < len(lines):
            candidate = "".join(semantic_characters(lines[group_end]["text"])).casefold()
            if candidate != normalized:
                break
            group_end += 1
        if group_end - group_index >= 2:
            previous_source = lines[group_index - 1]["source_start"] if group_index > 0 else lines[group_index]["source_start"] - 5
            next_source = lines[group_end]["source_start"] if group_end < len(lines) else lines[group_end - 1]["source_start"] + 5
            window_start = max(0.0, (previous_source + lines[group_index]["source_start"]) / 2 + offset)
            window_end = min(duration, next_source + offset + 0.75)
            group_lines = lines[group_index:group_end]
            grouped = align_line(
                aligner,
                audio,
                sample_rate,
                "\n".join(line["text"] for line in group_lines),
                window_start,
                window_end,
                args.language,
            )
            try:
                split = split_group_items(group_lines, grouped["items"])
            except ValueError:
                # Some model tokens span two repeated lyric lines and cannot
                # be split without inventing a boundary. Leave this group out
                # so the second pass aligns each line inside its own window.
                split = []
            if split:
                for relative_index, group_items in enumerate(split):
                    grouped_results[group_index + relative_index] = {
                        "window_start": window_start,
                        "window_end": window_end,
                        "items": group_items,
                    }
        group_index = group_end

    second_pass: list[dict[str, Any]] = []
    qrc_lines: list[str] = []
    host_line_starts: list[float] = []
    for index, line in enumerate(lines):
        corrected_start = line["source_start"] + offset
        previous_source = lines[index - 1]["source_start"] if index > 0 else line["source_start"] - 5.0
        next_source = lines[index + 1]["source_start"] if index + 1 < len(lines) else line["source_start"] + 5.0
        previous_corrected = previous_source + offset
        corrected_end = next_source + offset
        normalized = "".join(semantic_characters(line["text"])).casefold()
        is_repeated = counts[normalized] > 1
        window_start = max(0.0, (previous_corrected + corrected_start) / 2)
        window_end = min(duration, max(corrected_start + 2.0, corrected_end + 0.75))
        result = grouped_results.get(index) or align_line(
            aligner,
            audio,
            sample_rate,
            line["text"],
            window_start,
            window_end,
            args.language,
        )
        quality = alignment_quality(line["text"], result["items"])
        ownership_end = (corrected_start + corrected_end) / 2 + 0.5
        accepted = bool(
            quality["valid"]
            and quality["onset"] is not None
            and quality["onset"] >= window_start
            and quality["onset"] <= ownership_end
        )
        fallback = None
        if not accepted:
            fallback = "global-offset-rhythm"
            result = {
                "window_start": window_start,
                "window_end": window_end,
                "items": [{
                    "text": "".join(semantic_characters(line["text"])),
                    "start_time": corrected_start,
                    "end_time": max(corrected_start + 0.20, corrected_end - 0.04),
                }],
            }
            quality = alignment_quality(line["text"], result["items"])
            accepted = quality["valid"]
        if not accepted:
            raise ValueError(f"second-pass alignment failed at line {index}: {line['text']} / {quality}")
        character_timings = token_character_timings(line["text"], result["items"])
        if host_line_starts and character_timings[0]["start_time"] <= host_line_starts[-1] + 0.04:
            # A locally plausible model onset can still cross the previous
            # line. Keep the global LRC consensus as the ordering authority
            # and degrade only this line to deterministic rhythm instead of
            # rejecting the entire song.
            fallback = "global-offset-rhythm-monotonic"
            fallback_start = max(corrected_start, host_line_starts[-1] + 0.05)
            fallback_start = min(fallback_start, max(0.0, duration - 0.10))
            fallback_end = min(
                duration,
                max(fallback_start + 0.20, corrected_end - 0.04),
            )
            result = {
                "window_start": window_start,
                "window_end": window_end,
                "items": [{
                    "text": "".join(semantic_characters(line["text"])),
                    "start_time": fallback_start,
                    "end_time": fallback_end,
                }],
            }
            quality = alignment_quality(line["text"], result["items"])
            character_timings = token_character_timings(line["text"], result["items"])
        host_line_starts.append(character_timings[0]["start_time"])
        second_pass.append({
            "line_index": index,
            "text": line["text"],
            "source_start": line["source_start"],
            "corrected_start": corrected_start,
            "accepted": accepted,
            "fallback": fallback,
            "quality": quality,
            "characters": character_timings,
            **result,
        })

    for index, item in enumerate(second_pass):
        characters = item["characters"]
        next_start = host_line_starts[index + 1] if index + 1 < len(host_line_starts) else duration
        if index + 1 < len(host_line_starts) and next_start <= host_line_starts[index] + 0.04:
            raise ValueError(f"non-monotonic refined line starts at {index}")
        for character in characters:
            character["end_time"] = min(character["end_time"], next_start)
            if character["end_time"] <= character["start_time"]:
                character["end_time"] = min(next_start, character["start_time"] + 0.02)
        qrc_lines.append(qrc_line(item["text"], characters))

    iphone_starts = iphone_line_starts(entry.get("document", {}).get("karaokeLyric"))
    comparisons = []
    for index, host_start in enumerate(host_line_starts):
        source_start = lines[index]["source_start"]
        iphone_start = iphone_starts[index] if index < len(iphone_starts) else None
        comparisons.append({
            "line_index": index,
            "text": lines[index]["text"],
            "source_start": source_start,
            "host_start": host_start,
            "host_minus_source": host_start - source_start,
            "iphone_start": iphone_start,
            "host_minus_iphone": host_start - iphone_start if iphone_start is not None else None,
        })

    report = {
        "schema": "bilimusic-host-segment-refinement-v1",
        "bvid": args.bvid,
        "vocals": str(args.vocals),
        "duration": duration,
        "global_alignment": global_alignment,
        "first_pass": first_pass,
        "second_pass": second_pass,
        "comparisons": comparisons,
        "metrics": {
            "model_load_seconds": loaded_at - load_started,
            "total_seconds": time.perf_counter() - load_started,
            "peak_vram_bytes": torch.cuda.max_memory_allocated(),
        },
    }
    report_path = args.output / f"{args.bvid}-segment-refinement.json"
    qrc_path = args.output / f"{args.bvid}-host.qrc"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    qrc_path.write_text("\n".join(qrc_lines) + "\n", encoding="utf-8")
    print(json.dumps({
        "report": str(report_path),
        "qrc": str(qrc_path),
        "global_alignment": global_alignment,
        "line_count": len(qrc_lines),
        "total_seconds": report["metrics"]["total_seconds"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
