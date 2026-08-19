from __future__ import annotations

from lddc_backend.catalog import CatalogLyrics, CatalogSong, TimedLine, TimedWord
from lddc_backend.models import ResolveRequest
from lddc_backend.resolver import resolve


class FakeCatalog:
    def __init__(self, songs: dict[str, list[CatalogSong]], lyrics: dict[str, CatalogLyrics]) -> None:
        self.songs = songs
        self.lyrics = lyrics

    def search(self, source: str, keyword: str) -> list[CatalogSong]:
        return self.songs.get(source, [])

    def fetch(self, song: CatalogSong) -> CatalogLyrics:
        return self.lyrics[song.id]


def word_lyrics(text: str = "目覚") -> CatalogLyrics:
    return CatalogLyrics(
        timing_kind="word",
        lyric_lines=[
            TimedLine(
                start_milliseconds=1_000,
                end_milliseconds=2_000,
                text=text,
                words=[
                    TimedWord(1_000, 1_500, text[0]),
                    TimedWord(1_500, 2_000, text[1:]),
                ],
            )
        ],
        translation_lines=[],
        romanization_lines=[],
    )


def request(*, require_duration_match: bool = True) -> ResolveRequest:
    return ResolveRequest(
        requestID="BV1:test:cover",
        title="心拍数#0822",
        artists=["鹿乃"],
        aliases=["心拍数♯0822"],
        durationMilliseconds=322_000,
        requireDurationMatch=require_duration_match,
    )


def test_returns_word_candidate_from_matching_cover() -> None:
    song = CatalogSong("kugou", "kg-1", "心拍数♯0822", "鹿乃", None, 321_000)
    response = resolve(request(), FakeCatalog({"kugou": [song]}, {"kg-1": word_lyrics()}))

    assert len(response.candidates) == 1
    assert response.candidates[0].source == "kugou"
    assert response.candidates[0].timing_kind == "word"
    assert response.candidates[0].lyric_lines[0].words[1].text == "覚"


def test_rejects_original_artist_during_cover_pass() -> None:
    original = CatalogSong("kugou", "kg-original", "心拍数#0822", "蝶々P", None, 322_000)
    response = resolve(request(), FakeCatalog({"kugou": [original]}, {"kg-original": word_lyrics()}))

    assert response.candidates == []


def test_rejects_same_artist_wrong_song() -> None:
    wrong = CatalogSong("kugou", "kg-wrong", "Overdose", "鹿乃", None, 322_000)
    response = resolve(request(), FakeCatalog({"kugou": [wrong]}, {"kg-wrong": word_lyrics()}))

    assert response.candidates == []


def test_duration_gate_can_be_relaxed_only_for_original_reference_pass() -> None:
    original = CatalogSong("kugou", "kg-original", "パレード", "ヨルシカ", None, 300_000)
    original_request = ResolveRequest(
        requestID="BV1:original",
        title="パレード",
        artists=["ヨルシカ"],
        durationMilliseconds=240_000,
        requireDurationMatch=False,
    )
    response = resolve(
        original_request,
        FakeCatalog({"kugou": [original]}, {"kg-original": word_lyrics("身体")}),
    )

    assert len(response.candidates) == 1
    assert response.candidates[0].duration_seconds == 300

