from __future__ import annotations

import json
from pathlib import Path

from runtime.reflection.proposal_builder import ReflectionProposalRecord


class ProposalStage:
    def __init__(self, root: Path):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)

    def stage(self, proposal: ReflectionProposalRecord) -> Path:
        path = self.root / f'{proposal.proposal_id}.json'
        path.write_text(json.dumps(proposal.__dict__, indent=2, sort_keys=True), encoding='utf-8')
        return path
