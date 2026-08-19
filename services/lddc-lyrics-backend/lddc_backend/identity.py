from __future__ import annotations

import re
import unicodedata
from difflib import SequenceMatcher


_IGNORED = re.compile(r"[\W_]+", re.UNICODE)


def comparable(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold()
    return _IGNORED.sub("", normalized)


def overlap_score(value: str, expected: list[str]) -> float:
    left = comparable(value)
    if not left:
        return 0.0
    best = 0.0
    for item in expected:
        right = comparable(item)
        if not right:
            continue
        if left in right or right in left:
            return 100.0
        best = max(best, SequenceMatcher(None, left, right).ratio() * 100)
    return round(best, 1)


def title_score(value: str, title: str, aliases: list[str]) -> float:
    return overlap_score(value, [title, *aliases])

