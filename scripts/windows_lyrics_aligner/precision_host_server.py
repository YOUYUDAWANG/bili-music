from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import queue
import re
import subprocess
import threading
import time
import traceback
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


SCHEMA = "bilimusic-precision-host-v1"
PIPELINE_VERSION = 3
MAX_METADATA_BYTES = 512 * 1024
MAX_AUDIO_BYTES = 200 * 1024 * 1024
JOB_ID = re.compile(r"^[A-Za-z0-9_-]+$")
BVID = re.compile(r"^BV[A-Za-z0-9]+$")
LRC_LINE = re.compile(r"^\[\d{1,2}:\d{2}(?:\.\d+)?\].+", re.MULTILINE)


def atomic_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f"{path.name}.{threading.get_ident()}.tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    for attempt in range(10):
        try:
            os.replace(temporary, path)
            return
        except PermissionError:
            if attempt == 9:
                raise
            time.sleep(0.05)


def read_json(path: Path) -> dict[str, Any] | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return None


def concise_pipeline_error(output: str) -> str:
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    for line in reversed(lines):
        if re.match(r"^(ValueError|RuntimeError|OSError|FileNotFoundError|TimeoutError):", line):
            return line[:500]
    for line in reversed(lines):
        if "FullyQualifiedErrorId" not in line and "CategoryInfo" not in line:
            return line[:500]
    return "pipeline failed"


def normalized_language(value: str) -> str:
    aliases = {
        "ja": "Japanese",
        "japanese": "Japanese",
        "zh": "Chinese",
        "chinese": "Chinese",
        "mandarin": "Chinese",
        "ko": "Korean",
        "korean": "Korean",
        "en": "English",
        "english": "English",
    }
    result = aliases.get(value.strip().casefold())
    if result is None:
        raise ValueError("language must be Japanese, Chinese, Korean, or English")
    return result


def validate_request(payload: dict[str, Any]) -> dict[str, Any]:
    if payload.get("schema") != SCHEMA:
        raise ValueError("unsupported request schema")
    bvid = str(payload.get("bvid", "")).strip()
    if not BVID.fullmatch(bvid):
        raise ValueError("invalid bvid")
    lyric = str(payload.get("lyric", ""))
    if len(lyric) > 250_000 or len(LRC_LINE.findall(lyric)) < 2:
        raise ValueError("at least two timestamped lyric lines are required")
    cid = payload.get("cid")
    if cid is not None:
        cid = int(cid)
    return {
        "schema": SCHEMA,
        "bvid": bvid,
        "cid": cid,
        "title": str(payload.get("title", ""))[:500],
        "artist": str(payload.get("artist", ""))[:500],
        "language": normalized_language(str(payload.get("language", "Japanese"))),
        "duration": max(0, int(payload.get("duration", 0))),
        "lyric": lyric,
        "karaokeLyric": str(payload.get("karaokeLyric") or "")[:500_000],
    }


def job_identifier(payload: dict[str, Any]) -> str:
    stable = {
        key: payload.get(key)
        for key in ("bvid", "cid", "language", "lyric")
    }
    stable["pipelineVersion"] = PIPELINE_VERSION
    digest = hashlib.sha256(
        json.dumps(stable, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()[:20]
    return f"{payload['bvid']}-{digest}"


def result_quality(report: dict[str, Any], qrc: str, elapsed_seconds: float) -> dict[str, Any]:
    lines = report.get("lines") or []
    characters = [character for line in lines for character in line.get("characters", [])]
    durations = sorted(
        max(0.0, float(item.get("end_time", 0)) - float(item.get("start_time", 0)))
        for item in characters
    )
    global_alignment = report.get("global_alignment") or {}
    counts = report.get("decision_counts") or {}
    return {
        "lineCount": len(lines),
        "characterCount": len(characters),
        "modelConsensusLines": int(counts.get("model_consensus", 0)),
        "globalAnchorLines": int(counts.get("global_anchor_disagreement", 0)),
        "rhythmFallbackLines": int(counts.get("qwen_rhythm_fallback", 0)),
        "whisperXCharacterLines": int(counts.get("whisperx_character_timing", 0)),
        "globalSampleCount": int(global_alignment.get("sample_count", 0)),
        "globalCandidateCount": int(global_alignment.get("candidate_count", 0)),
        "globalMedianAbsoluteDeviation": float(global_alignment.get("median_absolute_deviation", 999)),
        "globalOffsetSeconds": float(global_alignment.get("offset_seconds", 0)),
        "minimumCharacterSeconds": durations[0] if durations else 0,
        "medianCharacterSeconds": durations[len(durations) // 2] if durations else 0,
        "elapsedSeconds": elapsed_seconds,
        "qrcBytes": len(qrc.encode("utf-8")),
    }


class PrecisionHost:
    def __init__(self, root: Path, token: str) -> None:
        self.root = root
        self.token = token
        self.jobs_root = root / "jobs"
        self.jobs_root.mkdir(parents=True, exist_ok=True)
        self.pending: queue.Queue[str] = queue.Queue()
        self.enqueued: set[str] = set()
        self.lock = threading.Lock()
        self.status_lock = threading.RLock()
        self.worker = threading.Thread(target=self._worker_loop, name="precision-host-worker", daemon=True)

    def start(self) -> None:
        self.worker.start()
        for directory in self.jobs_root.iterdir():
            if not directory.is_dir() or not JOB_ID.fullmatch(directory.name):
                continue
            status = read_json(directory / "status.json") or {}
            if status.get("state") in {"queued", "running"} and (directory / "source-audio").exists():
                self.enqueue(directory.name)

    def job_directory(self, job_id: str) -> Path:
        if not JOB_ID.fullmatch(job_id):
            raise ValueError("invalid job id")
        return self.jobs_root / job_id

    def status(self, job_id: str) -> dict[str, Any] | None:
        directory = self.job_directory(job_id)
        with self.status_lock:
            status = read_json(directory / "status.json")
            if status is None:
                return None
            if status.get("state") == "completed":
                result = read_json(directory / "result.json")
                if result is not None:
                    status["result"] = result
            return status

    def create_job(self, payload: dict[str, Any]) -> dict[str, Any]:
        request = validate_request(payload)
        job_id = job_identifier(request)
        directory = self.job_directory(job_id)
        directory.mkdir(parents=True, exist_ok=True)
        atomic_json(directory / "request.json", request)
        status = self.status(job_id)
        if status is None:
            status = self._write_status(job_id, "awaitingUpload", "等待上传音频")
        elif status.get("state") == "failed":
            if (directory / "source-audio").exists() and (directory / "lyrics-library.json").exists():
                status = self._write_status(job_id, "queued", "已重新排队")
                self.enqueue(job_id)
            else:
                status = self._write_status(job_id, "awaitingUpload", "等待上传音频")
        status["uploadRequired"] = status.get("state") == "awaitingUpload"
        return status

    def receive_audio(self, job_id: str, source) -> dict[str, Any]:
        directory = self.job_directory(job_id)
        request = read_json(directory / "request.json")
        if request is None:
            raise FileNotFoundError("job does not exist")
        temporary = directory / "source-audio.upload"
        target = directory / "source-audio"
        remaining = source["content_length"]
        if remaining <= 0 or remaining > MAX_AUDIO_BYTES:
            raise ValueError("audio body is empty or too large")
        with temporary.open("wb") as handle:
            while remaining:
                chunk = source["stream"].read(min(1024 * 1024, remaining))
                if not chunk:
                    raise ConnectionError("audio upload ended early")
                handle.write(chunk)
                remaining -= len(chunk)
        os.replace(temporary, target)
        library = [{
            "trackKey": {"bvid": request["bvid"], "cid": request.get("cid")},
            "document": {
                "lyric": request["lyric"],
                "karaokeLyric": request.get("karaokeLyric") or None,
            },
        }]
        (directory / "lyrics-library.json").write_text(
            json.dumps(library, ensure_ascii=False), encoding="utf-8"
        )
        self._write_status(job_id, "queued", "已排队")
        self.enqueue(job_id)
        status = self.status(job_id) or {}
        status["uploadRequired"] = False
        return status

    def enqueue(self, job_id: str) -> None:
        with self.lock:
            if job_id in self.enqueued:
                return
            self.enqueued.add(job_id)
        self.pending.put(job_id)

    def _write_status(
        self,
        job_id: str,
        state: str,
        message: str,
        error: str | None = None,
        started_at: float | None = None,
    ) -> dict[str, Any]:
        value: dict[str, Any] = {
            "schema": SCHEMA,
            "jobId": job_id,
            "state": state,
            "message": message,
            "updatedAt": time.time(),
        }
        if error:
            value["error"] = error
        if started_at:
            value["startedAt"] = started_at
        with self.status_lock:
            atomic_json(self.job_directory(job_id) / "status.json", value)
        return value

    def _worker_loop(self) -> None:
        while True:
            job_id = self.pending.get()
            try:
                try:
                    self._run_job(job_id)
                except Exception as error:
                    traceback.print_exc()
                    try:
                        self._write_status(job_id, "failed", "生成失败", str(error)[-4000:])
                    except Exception:
                        traceback.print_exc()
            finally:
                with self.lock:
                    self.enqueued.discard(job_id)
                self.pending.task_done()

    def _run_job(self, job_id: str) -> None:
        directory = self.job_directory(job_id)
        request = read_json(directory / "request.json")
        if request is None:
            self._write_status(job_id, "failed", "请求文件损坏", "request metadata is missing")
            return
        started = time.time()
        self._write_status(job_id, "running", "正在分离人声并生成双模型共识", started_at=started)
        output_directory = self.root / "outputs" / job_id / "consensus"
        command = [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(self.root / "scripts" / "run_offline.ps1"),
            "-Audio",
            str(directory / "source-audio"),
            "-Library",
            str(directory / "lyrics-library.json"),
            "-Bvid",
            request["bvid"],
            "-JobId",
            job_id,
            "-Language",
            request["language"],
            "-SkipDiagnostics",
            "-Root",
            str(self.root),
        ]
        try:
            completed = subprocess.run(
                command,
                cwd=self.root,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=30 * 60,
                check=False,
            )
            if completed.returncode != 0:
                detail = completed.stderr or completed.stdout or "pipeline failed"
                raise RuntimeError(concise_pipeline_error(detail))
            report_path = output_directory / f"{request['bvid']}-host-consensus.json"
            qrc_path = output_directory / f"{request['bvid']}-host-consensus.qrc"
            report = json.loads(report_path.read_text(encoding="utf-8"))
            qrc = qrc_path.read_text(encoding="utf-8")
            if report.get("schema") != "bilimusic-host-consensus-v1" or not qrc.strip():
                raise ValueError("pipeline returned an invalid result")
            elapsed = time.time() - started
            result = {
                "schema": SCHEMA,
                "jobId": job_id,
                "bvid": request["bvid"],
                "karaokeLyric": qrc,
                "quality": result_quality(report, qrc, elapsed),
            }
            atomic_json(directory / "result.json", result)
            self._write_status(job_id, "completed", "高精度逐字歌词已生成", started_at=started)
        except Exception as error:  # keep the worker alive after a model/process failure
            traceback.print_exc()
            self._write_status(job_id, "failed", "生成失败", str(error)[-4000:], started_at=started)


class Handler(BaseHTTPRequestHandler):
    server_version = "BiliMusicPrecisionHost/1"

    @property
    def app(self) -> PrecisionHost:
        return self.server.app  # type: ignore[attr-defined]

    def log_message(self, format: str, *args: Any) -> None:
        # A scheduled-task parent may be restarted while this process is still
        # unwinding. Request handling must never depend on a live stdout pipe.
        return

    def _json(self, status: int, value: dict[str, Any]) -> None:
        body = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self) -> bool:
        supplied = self.headers.get("Authorization", "")
        expected = f"Bearer {self.app.token}"
        if hmac.compare_digest(supplied, expected):
            return True
        self._json(HTTPStatus.UNAUTHORIZED, {"schema": SCHEMA, "error": "unauthorized"})
        return False

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/health":
            self._json(HTTPStatus.OK, {
                "schema": SCHEMA,
                "status": "ok",
                "queueDepth": self.app.pending.qsize(),
            })
            return
        if not self._authorized():
            return
        match = re.fullmatch(r"/v1/jobs/([A-Za-z0-9_-]+)", path)
        if match:
            status = self.app.status(match.group(1))
            if status is None:
                self._json(HTTPStatus.NOT_FOUND, {"schema": SCHEMA, "error": "job not found"})
            else:
                status["uploadRequired"] = status.get("state") == "awaitingUpload"
                self._json(HTTPStatus.OK, status)
            return
        self._json(HTTPStatus.NOT_FOUND, {"schema": SCHEMA, "error": "not found"})

    def do_POST(self) -> None:
        if not self._authorized():
            return
        if urlparse(self.path).path != "/v1/jobs":
            self._json(HTTPStatus.NOT_FOUND, {"schema": SCHEMA, "error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > MAX_METADATA_BYTES:
                raise ValueError("metadata body is empty or too large")
            payload = json.loads(self.rfile.read(length))
            self._json(HTTPStatus.OK, self.app.create_job(payload))
        except (ValueError, TypeError, json.JSONDecodeError) as error:
            self._json(HTTPStatus.BAD_REQUEST, {"schema": SCHEMA, "error": str(error)})

    def do_PUT(self) -> None:
        if not self._authorized():
            return
        match = re.fullmatch(r"/v1/jobs/([A-Za-z0-9_-]+)/audio", urlparse(self.path).path)
        if not match:
            self._json(HTTPStatus.NOT_FOUND, {"schema": SCHEMA, "error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            status = self.app.receive_audio(match.group(1), {
                "content_length": length,
                "stream": self.rfile,
            })
            self._json(HTTPStatus.ACCEPTED, status)
        except FileNotFoundError as error:
            self._json(HTTPStatus.NOT_FOUND, {"schema": SCHEMA, "error": str(error)})
        except (ValueError, ConnectionError, OSError) as error:
            self._json(HTTPStatus.BAD_REQUEST, {"schema": SCHEMA, "error": str(error)})


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(r"D:\BiliMusicAligner"))
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--token-file", type=Path, required=True)
    args = parser.parse_args()
    token = args.token_file.read_text(encoding="utf-8").strip()
    if len(token) < 32:
        raise RuntimeError("token file must contain at least 32 characters")
    app = PrecisionHost(args.root, token)
    app.start()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.app = app  # type: ignore[attr-defined]
    print(f"BiliMusic precision host listening on {args.host}:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
