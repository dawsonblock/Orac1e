from __future__ import annotations

from pathlib import Path

from runtime.events.store import EventStore
from runtime.reflection.failure_miner import FailureMiner
from runtime.reflection.model_index import ReflectionIndex
from runtime.reflection.proposal_builder import ReflectionProposalBuilder
from runtime.staging.proposal_stage import ProposalStage


class ReflectionWorker:
    def __init__(self, db_path: Path, index_path: Path, stage_root: Path):
        self.store = EventStore(db_path)
        self.miner = FailureMiner()
        self.builder = ReflectionProposalBuilder()
        self.index = ReflectionIndex(index_path)
        self.stage = ProposalStage(stage_root)

    def run(self, task_id: str, attempt_id: str) -> list[Path]:
        events = self.store.list_by_attempt(attempt_id)
        patterns = self.miner.mine(events)
        proposals = self.builder.build(task_id, attempt_id, patterns)
        if proposals:
            self.index.append(proposals)
        return [self.stage.stage(p) for p in proposals]
