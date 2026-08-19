from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from . import SCHEMA


class ResolveRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    schema_: Literal[SCHEMA] = Field(default=SCHEMA, alias="schema")
    request_id: str = Field(alias="requestID", min_length=1, max_length=180)
    title: str = Field(min_length=1, max_length=240)
    artists: list[str] = Field(min_length=1, max_length=8)
    aliases: list[str] = Field(default_factory=list, max_length=12)
    duration_milliseconds: int | None = Field(
        default=None, alias="durationMilliseconds", ge=1_000, le=7_200_000
    )
    require_duration_match: bool = Field(default=True, alias="requireDurationMatch")
    max_candidates: int = Field(default=6, alias="maxCandidates", ge=1, le=12)

    @field_validator("title")
    @classmethod
    def clean_title(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("title is empty")
        return cleaned

    @field_validator("artists", "aliases")
    @classmethod
    def clean_names(cls, values: list[str]) -> list[str]:
        cleaned: list[str] = []
        seen: set[str] = set()
        for value in values:
            name = value.strip()
            key = name.casefold()
            if name and key not in seen:
                seen.add(key)
                cleaned.append(name)
        return cleaned


class WordPayload(BaseModel):
    start_milliseconds: int = Field(alias="startMilliseconds", ge=0)
    end_milliseconds: int = Field(alias="endMilliseconds", ge=1)
    text: str = Field(min_length=1, max_length=160)


class LinePayload(BaseModel):
    start_milliseconds: int = Field(alias="startMilliseconds", ge=0)
    end_milliseconds: int = Field(alias="endMilliseconds", ge=1)
    text: str = Field(min_length=1, max_length=600)
    words: list[WordPayload] = Field(default_factory=list, max_length=300)


class CandidatePayload(BaseModel):
    source: Literal["kugou", "tencent", "netease"]
    id: str
    title: str
    artist: str
    album: str | None = None
    duration_seconds: int | None = Field(default=None, alias="durationSeconds")
    timing_kind: Literal["word", "line", "none"] = Field(alias="timingKind")
    lyric_lines: list[LinePayload] = Field(alias="lyricLines")
    translation_lines: list[LinePayload] = Field(default_factory=list, alias="translationLines")
    romanization_lines: list[LinePayload] = Field(default_factory=list, alias="romanizationLines")
    title_score: float = Field(alias="titleScore")
    artist_score: float = Field(alias="artistScore")
    from_cache: bool = Field(default=False, alias="fromCache")


class ResolveResponse(BaseModel):
    schema_: Literal[SCHEMA] = Field(default=SCHEMA, alias="schema")
    request_id: str = Field(alias="requestID")
    candidates: list[CandidatePayload]


class HealthResponse(BaseModel):
    schema_: Literal[SCHEMA] = Field(default=SCHEMA, alias="schema")
    status: Literal["ok"] = "ok"
    lddc_commit: str = Field(alias="lddcCommit")
