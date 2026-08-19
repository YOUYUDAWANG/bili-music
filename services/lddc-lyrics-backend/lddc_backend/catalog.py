from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Protocol


@dataclass(slots=True)
class CatalogSong:
    source: str
    id: str
    title: str
    artist: str
    album: str | None
    duration_milliseconds: int | None
    native: Any = field(repr=False, compare=False, default=None)


@dataclass(slots=True)
class TimedWord:
    start_milliseconds: int
    end_milliseconds: int
    text: str


@dataclass(slots=True)
class TimedLine:
    start_milliseconds: int
    end_milliseconds: int
    text: str
    words: list[TimedWord]


@dataclass(slots=True)
class CatalogLyrics:
    timing_kind: str
    lyric_lines: list[TimedLine]
    translation_lines: list[TimedLine]
    romanization_lines: list[TimedLine]
    from_cache: bool = False


class CatalogAdapter(Protocol):
    def search(self, source: str, keyword: str) -> list[CatalogSong]: ...

    def fetch(self, song: CatalogSong) -> CatalogLyrics: ...

