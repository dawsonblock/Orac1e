from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class SwebenchTask:
    repo: str
    repo_path: Path
    issue_number: int
    title: str
    body: str
    base_ref: str = 'main'
    labels: list[str] | None = None


def load_manifest(path: Path) -> list[SwebenchTask]:
    tasks: list[SwebenchTask] = []
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        if not line.strip():
            continue
        payload = json.loads(line)
        tasks.append(
            SwebenchTask(
                repo=payload['repo'],
                repo_path=Path(payload['repo_path']),
                issue_number=int(payload['issue_number']),
                title=payload['title'],
                body=payload['body'],
                base_ref=payload.get('base_ref', 'main'),
                labels=payload.get('labels', ['agent:fix']),
            )
        )
    return tasks
