from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path
from typing import Any

from refine_segments import consensus, qrc_line, semantic_characters


def shifted_characters(characters: list[dict[str, Any]], target_start: float) -> list[dict[str, Any]]:
    delta = target_start - float(characters[0]["start_time"])
    return [
        {
            "text": item["text"],
            "start_time": float(item["start_time"]) + delta,
            "end_time": float(item["end_time"]) + delta,
        }
        for item in characters
    ]


def whisperx_characters(verifier: dict[str, Any]) -> list[dict[str, Any]] | None:
    expected = semantic_characters(verifier["text"])
    characters = []
    for item in verifier.get("segment", {}).get("chars") or []:
        text = str(item.get("char", ""))
        start = item.get("start")
        end = item.get("end")
        if not text.isalnum() or start is None or end is None:
            continue
        characters.append({
            "text": text,
            "start_time": float(start),
            "end_time": max(float(start) + 0.02, float(end)),
        })
    if [item["text"] for item in characters] != expected:
        return None
    return characters


def stabilize_character_timing(
    characters: list[dict[str, Any]],
    next_line_start: float,
) -> list[dict[str, Any]]:
    if not characters:
        return characters
    first = float(characters[0]["start_time"])
    last_start = float(characters[-1]["start_time"])
    raw_end = max(float(item["end_time"]) for item in characters)
    line_end = min(float(next_line_start) - 0.001, max(raw_end, last_start + 0.18))
    available = max(0.02, line_end - first)
    minimum = min(0.05, available / max(len(characters), 1))
    raw_starts = [float(item["start_time"]) for item in characters]
    starts = raw_starts[:]
    for index in range(len(starts) - 1, -1, -1):
        latest = line_end - (len(starts) - index) * minimum
        starts[index] = min(starts[index], latest)
    starts[0] = first
    for index in range(1, len(starts)):
        starts[index] = max(starts[index], starts[index - 1] + minimum)
    result: list[dict[str, Any]] = []
    for index, item in enumerate(characters):
        end = starts[index + 1] if index + 1 < len(starts) else line_end
        result.append({
            "text": item["text"],
            "start_time": starts[index],
            "end_time": max(starts[index] + minimum, end),
        })
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--qwen-report", type=Path, required=True)
    parser.add_argument("--whisperx-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--agreement-seconds", type=float, default=0.8)
    parser.add_argument("--maximum-global-deviation", type=float, default=1.25)
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    qwen = json.loads(args.qwen_report.read_text(encoding="utf-8"))
    whisperx = json.loads(args.whisperx_report.read_text(encoding="utf-8"))
    initial_global_alignment = qwen["global_alignment"]
    refined_offsets = [
        float(item["offset_seconds"])
        for item in qwen.get("first_pass", [])
        if item.get("usable")
        and item.get("quality", {}).get("onset") is not None
        and float(item["quality"]["onset"]) > float(item["window_start"]) + 0.25
        and float(item["quality"]["onset"]) < float(item["window_end"]) - 0.25
    ]
    try:
        global_alignment = consensus(refined_offsets)
        global_alignment["source"] = "first-pass-interior-consensus"
    except ValueError:
        global_alignment = dict(initial_global_alignment)
        global_alignment["source"] = "first-pass-fallback"
    offset = float(global_alignment["offset_seconds"])
    decisions: list[dict[str, Any]] = []

    for qwen_line, verifier in zip(qwen["second_pass"], whisperx["comparisons"]):
        source_start = float(qwen_line["source_start"])
        global_start = source_start + offset
        qwen_start = float(qwen_line["characters"][0]["start_time"])
        whisperx_start = verifier.get("whisperx_start")
        difference = abs(float(whisperx_start) - qwen_start) if whisperx_start is not None else None
        model_start = (
            statistics.median([qwen_start, float(whisperx_start)])
            if difference is not None and difference <= args.agreement_seconds
            else None
        )
        global_difference = (
            abs(model_start - global_start) if model_start is not None else None
        )
        maximum_deviation = 3.0 if int(qwen_line["line_index"]) == 0 else args.maximum_global_deviation
        if model_start is not None and global_difference is not None and global_difference <= maximum_deviation:
            final_start = model_start
            decision = "model-consensus"
        else:
            final_start = global_start
            decision = "global-anchor-disagreement"
        verifier_characters = whisperx_characters(verifier)
        timing_source = "whisperx-ctc" if verifier_characters else "qwen-forced-aligner"
        source_characters = verifier_characters or qwen_line["characters"]
        decisions.append({
            "line_index": qwen_line["line_index"],
            "text": qwen_line["text"],
            "source_start": source_start,
            "global_start": global_start,
            "qwen_start": qwen_start,
            "qwen_fallback": qwen_line.get("fallback"),
            "whisperx_start": whisperx_start,
            "whisperx_score": verifier.get("mean_character_score"),
            "model_difference": difference,
            "model_global_difference": global_difference,
            "decision": decision,
            "final_start": final_start,
            "timing_source": timing_source,
            "characters": shifted_characters(source_characters, final_start),
        })

    qrc_lines: list[str] = []
    for index, item in enumerate(decisions):
        next_start = decisions[index + 1]["final_start"] if index + 1 < len(decisions) else qwen["duration"]
        if index + 1 < len(decisions) and next_start <= item["final_start"] + 0.04:
            raise ValueError(f"consensus line starts are not monotonic at {index}")
        characters = stabilize_character_timing(item["characters"], float(next_start))
        item["characters"] = characters
        source_start = float(characters[0]["start_time"])
        source_end = max(float(character["end_time"]) for character in characters)
        available_end = max(source_start + 0.02, float(next_start) - 0.001)
        if source_end > available_end and source_end > source_start:
            scale = (available_end - source_start) / (source_end - source_start)
            for character in characters:
                old_start = float(character["start_time"])
                old_end = float(character["end_time"])
                character["start_time"] = source_start + (old_start - source_start) * scale
                character["end_time"] = source_start + (old_end - source_start) * scale
        qrc_lines.append(qrc_line(item["text"], characters))

    iphone = qwen["comparisons"]
    final_minus_iphone = [
        item["final_start"] - float(iphone[index]["iphone_start"])
        for index, item in enumerate(decisions)
        if iphone[index].get("iphone_start") is not None
    ]
    sorted_difference = sorted(final_minus_iphone)
    iphone_comparison = {
        "minimum": min(sorted_difference),
        "median": statistics.median(sorted_difference),
        "maximum": max(sorted_difference),
    } if sorted_difference else {
        "minimum": None,
        "median": None,
        "maximum": None,
    }
    report = {
        "schema": "bilimusic-host-consensus-v1",
        "bvid": qwen["bvid"],
        "agreement_threshold_seconds": args.agreement_seconds,
        "global_alignment": global_alignment,
        "initial_global_alignment": initial_global_alignment,
        "decision_counts": {
            "model_consensus": sum(item["decision"] == "model-consensus" for item in decisions),
            "global_anchor_disagreement": sum(item["decision"] != "model-consensus" for item in decisions),
            "qwen_rhythm_fallback": sum(item["qwen_fallback"] is not None for item in decisions),
            "whisperx_character_timing": sum(item["timing_source"] == "whisperx-ctc" for item in decisions),
        },
        "final_minus_iphone": iphone_comparison,
        "lines": decisions,
    }
    report_path = args.output / f"{qwen['bvid']}-host-consensus.json"
    qrc_path = args.output / f"{qwen['bvid']}-host-consensus.qrc"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    qrc_path.write_text("\n".join(qrc_lines) + "\n", encoding="utf-8")
    print(json.dumps({
        "report": str(report_path),
        "qrc": str(qrc_path),
        "decision_counts": report["decision_counts"],
        "final_minus_iphone": report["final_minus_iphone"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
