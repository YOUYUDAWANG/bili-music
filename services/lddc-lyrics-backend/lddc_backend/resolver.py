from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed

from .catalog import CatalogAdapter, CatalogLyrics, CatalogSong, TimedLine, TimedWord
from .identity import overlap_score, title_score
from .models import CandidatePayload, LinePayload, ResolveRequest, ResolveResponse, WordPayload


SOURCE_ORDER = ("kugou", "tencent", "netease")


def _line_payload(line: TimedLine) -> LinePayload:
    return LinePayload(
        startMilliseconds=max(0, line.start_milliseconds),
        endMilliseconds=max(line.start_milliseconds + 1, line.end_milliseconds),
        text=line.text,
        words=[
            WordPayload(
                startMilliseconds=max(0, word.start_milliseconds),
                endMilliseconds=max(word.start_milliseconds + 1, word.end_milliseconds),
                text=word.text,
            )
            for word in line.words
            if word.text
        ],
    )


def _credible(song: CatalogSong, request: ResolveRequest) -> tuple[bool, float, float]:
    candidate_title_score = title_score(song.title, request.title, request.aliases)
    candidate_artist_score = overlap_score(song.artist, request.artists)
    if candidate_title_score < 65 or candidate_artist_score < 55:
        return False, candidate_title_score, candidate_artist_score
    if request.require_duration_match and request.duration_milliseconds:
        if song.duration_milliseconds is None:
            return False, candidate_title_score, candidate_artist_score
        if abs(song.duration_milliseconds - request.duration_milliseconds) > 4_000:
            return False, candidate_title_score, candidate_artist_score
    return True, candidate_title_score, candidate_artist_score


def _candidate(
    song: CatalogSong,
    lyrics: CatalogLyrics,
    title_match: float,
    artist_match: float,
) -> CandidatePayload | None:
    lines = [_line_payload(line) for line in lyrics.lyric_lines if line.text]
    if not lines:
        return None
    timing = lyrics.timing_kind if lyrics.timing_kind in {"word", "line", "none"} else "none"
    if timing == "word" and not any(line.words for line in lines):
        timing = "line"
    return CandidatePayload(
        source=song.source,
        id=song.id,
        title=song.title,
        artist=song.artist,
        album=song.album,
        durationSeconds=round(song.duration_milliseconds / 1000) if song.duration_milliseconds else None,
        timingKind=timing,
        lyricLines=lines,
        translationLines=[_line_payload(line) for line in lyrics.translation_lines if line.text],
        romanizationLines=[_line_payload(line) for line in lyrics.romanization_lines if line.text],
        titleScore=title_match,
        artistScore=artist_match,
        fromCache=lyrics.from_cache,
    )


def _resolve_source(source: str, request: ResolveRequest, adapter: CatalogAdapter) -> list[CandidatePayload]:
    queries = [f"{request.title} {artist}" for artist in request.artists]
    queries.append(request.title)
    songs: dict[tuple[str, str], CatalogSong] = {}
    for query in queries:
        for song in adapter.search(source, query):
            songs.setdefault((song.source, song.id), song)
        if songs:
            break

    ranked: list[tuple[float, float, CatalogSong]] = []
    for song in songs.values():
        credible, candidate_title_score, candidate_artist_score = _credible(song, request)
        if credible:
            ranked.append((candidate_title_score, candidate_artist_score, song))
    ranked.sort(key=lambda item: (item[0] + item[1], item[0], item[1]), reverse=True)

    fetched: list[CandidatePayload] = []
    for candidate_title_score, candidate_artist_score, song in ranked[:3]:
        try:
            lyrics = adapter.fetch(song)
        except Exception:
            continue
        payload = _candidate(song, lyrics, candidate_title_score, candidate_artist_score)
        if payload is not None:
            fetched.append(payload)
        if payload is not None and payload.timing_kind == "word":
            break
    return fetched


def resolve(request: ResolveRequest, adapter: CatalogAdapter) -> ResolveResponse:
    collected: list[CandidatePayload] = []
    with ThreadPoolExecutor(max_workers=3, thread_name_prefix="lddc-source") as executor:
        futures = {
            executor.submit(_resolve_source, source, request, adapter): source
            for source in SOURCE_ORDER
        }
        for future in as_completed(futures):
            try:
                collected.extend(future.result())
            except Exception:
                continue

    source_rank = {source: index for index, source in enumerate(SOURCE_ORDER)}
    timing_rank = {"word": 0, "line": 1, "none": 2}
    collected.sort(
        key=lambda item: (
            timing_rank[item.timing_kind],
            source_rank[item.source],
            -(item.title_score + item.artist_score),
        )
    )
    deduped: list[CandidatePayload] = []
    seen: set[tuple[str, str]] = set()
    for item in collected:
        key = (item.source, item.id)
        if key in seen:
            continue
        seen.add(key)
        deduped.append(item)
        if len(deduped) >= request.max_candidates:
            break
    return ResolveResponse(requestID=request.request_id, candidates=deduped)

