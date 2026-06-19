from __future__ import annotations

import itertools
import re
from hashlib import sha1

_counter = itertools.count(1)


def _slug(value: str) -> str:
    value = re.sub(r"[^a-zA-Z0-9]+", "-", value.strip().lower()).strip("-")
    return value[:40] or "x"


def next_id(prefix: str) -> str:
    return f"{prefix}_{next(_counter):06d}"


def stable_task_id(repo: str, issue_number: int) -> str:
    return f"task_{_slug(repo)}_{issue_number:06d}"


def stable_attempt_id(task_id: str, attempt_index: int) -> str:
    return f"attempt_{task_id}_{attempt_index:02d}"


def workspace_id(task_id: str, attempt_id: str) -> str:
    digest = sha1(f"{task_id}:{attempt_id}".encode()).hexdigest()[:10]
    return f"ws_{digest}"


def patch_id(attempt_id: str, changed_files: list[str]) -> str:
    digest = sha1((attempt_id + "|" + "|".join(sorted(changed_files))).encode()).hexdigest()[:10]
    return f"patch_{digest}"
