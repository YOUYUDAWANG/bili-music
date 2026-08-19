from __future__ import annotations

import asyncio
import hmac
import logging
import os
import threading
import time
from dataclasses import dataclass

import uvicorn
from fastapi import FastAPI, Header, HTTPException

from . import SCHEMA
from .lddc_adapter import LDDCCatalogAdapter
from .models import HealthResponse, ResolveRequest, ResolveResponse
from .resolver import resolve

LDDC_COMMIT = "84631e8cd011fcc3f71ca0ae017e2c9758958ffc"
audit_log = logging.getLogger("uvicorn.error")


@dataclass(slots=True)
class CacheEntry:
    expires_at: float
    response: ResolveResponse


class ResponseCache:
    def __init__(self, ttl_seconds: int = 86_400, capacity: int = 512) -> None:
        self.ttl_seconds = ttl_seconds
        self.capacity = capacity
        self._entries: dict[str, CacheEntry] = {}
        self._lock = threading.Lock()

    def get(self, key: str) -> ResolveResponse | None:
        now = time.monotonic()
        with self._lock:
            entry = self._entries.get(key)
            if entry is None or entry.expires_at <= now:
                self._entries.pop(key, None)
                return None
            return entry.response

    def put(self, key: str, response: ResolveResponse) -> None:
        if not response.candidates:
            return
        with self._lock:
            if len(self._entries) >= self.capacity:
                oldest = min(self._entries, key=lambda item: self._entries[item].expires_at)
                self._entries.pop(oldest, None)
            self._entries[key] = CacheEntry(
                expires_at=time.monotonic() + self.ttl_seconds,
                response=response,
            )


def create_app(adapter: LDDCCatalogAdapter | None = None) -> FastAPI:
    app = FastAPI(title="BiliMusic LDDC Lyrics Backend", version="0.1.0")
    catalog = adapter
    cache = ResponseCache()
    semaphore = asyncio.Semaphore(2)

    def get_adapter() -> LDDCCatalogAdapter:
        nonlocal catalog
        if catalog is None:
            catalog = LDDCCatalogAdapter()
        return catalog

    def authorize(value: str | None) -> None:
        expected = os.environ.get("LDDC_BACKEND_TOKEN", "").strip()
        if not expected:
            raise HTTPException(status_code=503, detail="backend token is not configured")
        prefix = "Bearer "
        provided = value[len(prefix) :] if value and value.startswith(prefix) else ""
        if not provided or not hmac.compare_digest(provided, expected):
            raise HTTPException(status_code=401, detail="unauthorized")

    def audit(response: ResolveResponse, *, from_cache: bool) -> None:
        word_candidates = sum(candidate.timing_kind == "word" for candidate in response.candidates)
        audit_log.info(
            "LDDC resolve completed candidates=%d word=%d cache=%s",
            len(response.candidates),
            word_candidates,
            from_cache,
        )

    @app.get("/health", response_model=HealthResponse, response_model_by_alias=True)
    async def health() -> HealthResponse:
        return HealthResponse(schema=SCHEMA, status="ok", lddcCommit=LDDC_COMMIT)

    @app.post("/v1/lyrics/resolve", response_model=ResolveResponse, response_model_by_alias=True)
    async def resolve_lyrics(
        request: ResolveRequest,
        authorization: str | None = Header(default=None),
    ) -> ResolveResponse:
        authorize(authorization)
        cache_key = request.model_dump_json(by_alias=True, exclude={"request_id"})
        if cached := cache.get(cache_key):
            response = cached.model_copy(update={"request_id": request.request_id})
            audit(response, from_cache=True)
            return response
        timeout = float(os.environ.get("LDDC_BACKEND_TIMEOUT_SECONDS", "18"))
        async with semaphore:
            try:
                response = await asyncio.wait_for(
                    asyncio.to_thread(resolve, request, get_adapter()),
                    timeout=max(5.0, min(timeout, 30.0)),
                )
            except TimeoutError as error:
                raise HTTPException(status_code=504, detail="lyrics providers timed out") from error
        cache.put(cache_key, response)
        audit(response, from_cache=False)
        return response

    return app


app = create_app()


def run() -> None:
    host = os.environ.get("LDDC_BACKEND_HOST", "127.0.0.1")
    port = int(os.environ.get("LDDC_BACKEND_PORT", "8788"))
    uvicorn.run("lddc_backend.app:app", host=host, port=port, workers=1, access_log=True)
