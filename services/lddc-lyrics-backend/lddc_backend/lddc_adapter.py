from __future__ import annotations

from .catalog import CatalogLyrics, CatalogSong, TimedLine, TimedWord


class LDDCCatalogAdapter:
    """Thin headless adapter around LDDC's provider and parser APIs."""

    def __init__(self) -> None:
        from LDDC.common.models import SearchType, Source

        self._search_type = SearchType.SONG
        self._sources = {
            "kugou": Source.KG,
            "tencent": Source.QM,
            "netease": Source.NE,
        }

    def search(self, source: str, keyword: str) -> list[CatalogSong]:
        from LDDC.core.api.lyrics import search

        native_source = self._sources[source]
        results = search(native_source, keyword, self._search_type)
        songs: list[CatalogSong] = []
        for item in results:
            song_id = str(item.id or item.mid or item.hash or "")
            if not song_id or not item.title:
                continue
            songs.append(
                CatalogSong(
                    source=source,
                    id=song_id,
                    title=item.title,
                    artist=str(item.artist or ""),
                    album=item.album,
                    duration_milliseconds=item.duration,
                    native=item,
                )
            )
        return songs

    def fetch(self, song: CatalogSong) -> CatalogLyrics:
        from LDDC.common.models import LyricsType
        from LDDC.core.api.lyrics import get_lyrics

        lyrics = get_lyrics(song.native)
        timing = lyrics.types.get("orig")
        if timing == LyricsType.VERBATIM:
            timing_kind = "word"
        elif timing == LyricsType.LINEBYLINE:
            timing_kind = "line"
        else:
            timing_kind = "none"
        duration = song.duration_milliseconds or lyrics.get_duration() or None
        full = lyrics.get_fslyrics(duration)
        return CatalogLyrics(
            timing_kind=timing_kind,
            lyric_lines=self._lines(full.get("orig", [])),
            translation_lines=self._lines(full.get("ts", [])),
            romanization_lines=self._lines(full.get("roma", [])),
            from_cache=bool(lyrics.cached),
        )

    @staticmethod
    def _lines(lines: list) -> list[TimedLine]:
        converted: list[TimedLine] = []
        for line in lines:
            if line.start is None or line.end is None:
                continue
            words = [
                TimedWord(
                    start_milliseconds=word.start,
                    end_milliseconds=word.end,
                    text=word.text,
                )
                for word in line.words
                if word.start is not None and word.end is not None and word.text
            ]
            text = "".join(word.text for word in words)
            if not text:
                continue
            converted.append(
                TimedLine(
                    start_milliseconds=line.start,
                    end_milliseconds=line.end,
                    text=text,
                    words=words,
                )
            )
        return converted

