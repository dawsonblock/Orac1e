from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class Result:
    ok: bool
    code: str
    message: str
    data: dict[str, Any] | None = None
