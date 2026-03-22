from __future__ import annotations

import json
from pathlib import Path

from runtime.reflection.proposal_builder import ReflectionProposalRecord


class ReflectionIndex:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if not self.path.exists():
            self.path.write_text('[]', encoding='utf-8')

    def append(self, proposals: list[ReflectionProposalRecord]) -> None:
        existing = json.loads(self.path.read_text(encoding='utf-8'))
        existing.extend([p.__dict__ for p in proposals])
        self.path.write_text(json.dumps(existing, indent=2, sort_keys=True), encoding='utf-8')
