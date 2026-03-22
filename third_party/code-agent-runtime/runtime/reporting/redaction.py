from __future__ import annotations

import re
from typing import Iterable

_DEFAULT_PATTERNS = [
    re.compile(r"gh[pousr]_[A-Za-z0-9_]{20,}"),
    re.compile(r"github_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"sk-[A-Za-z0-9]{16,}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", re.DOTALL),
    re.compile(r"(?i)(api[_-]?key|token|secret|password)\s*[:=]\s*['\"]?[^\s'\"]+['\"]?"),
]


def redact_text(text: str, extra_patterns: Iterable[re.Pattern[str]] | None = None) -> str:
    redacted = text
    for pattern in [*_DEFAULT_PATTERNS, *(list(extra_patterns or []))]:
        redacted = pattern.sub("[REDACTED]", redacted)
    return redacted
