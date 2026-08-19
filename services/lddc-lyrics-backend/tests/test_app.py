from __future__ import annotations

from fastapi.testclient import TestClient

from lddc_backend.app import create_app
from lddc_backend.catalog import CatalogLyrics, CatalogSong, TimedLine, TimedWord


class SingleSongCatalog:
    def search(self, source: str, keyword: str) -> list[CatalogSong]:
        if source != "kugou":
            return []
        return [CatalogSong("kugou", "kg-1", "心拍数#0822", "鹿乃", None, 321_000)]

    def fetch(self, song: CatalogSong) -> CatalogLyrics:
        return CatalogLyrics(
            timing_kind="word",
            lyric_lines=[
                TimedLine(
                    1_000,
                    2_000,
                    "心拍",
                    [TimedWord(1_000, 1_500, "心"), TimedWord(1_500, 2_000, "拍")],
                )
            ],
            translation_lines=[],
            romanization_lines=[],
        )


def payload(request_id: str) -> dict:
    return {
        "schema": "bilimusic-lddc-lyrics-v1",
        "requestID": request_id,
        "title": "心拍数#0822",
        "artists": ["鹿乃"],
        "aliases": ["心拍数♯0822"],
        "durationMilliseconds": 322_000,
        "requireDurationMatch": True,
        "maxCandidates": 6,
    }


def test_resolve_requires_bearer(monkeypatch) -> None:
    monkeypatch.setenv("LDDC_BACKEND_TOKEN", "secret")
    client = TestClient(create_app(SingleSongCatalog()))

    response = client.post("/v1/lyrics/resolve", json=payload("one"))

    assert response.status_code == 401


def test_cached_response_echoes_current_request_id(monkeypatch) -> None:
    monkeypatch.setenv("LDDC_BACKEND_TOKEN", "secret")
    client = TestClient(create_app(SingleSongCatalog()))
    headers = {"Authorization": "Bearer secret"}

    first = client.post("/v1/lyrics/resolve", headers=headers, json=payload("one"))
    second = client.post("/v1/lyrics/resolve", headers=headers, json=payload("two"))

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["requestID"] == "one"
    assert second.json()["requestID"] == "two"
    assert second.json()["candidates"][0]["timingKind"] == "word"

