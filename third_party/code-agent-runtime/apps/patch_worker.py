from __future__ import annotations

from pathlib import Path

from runtime.common.result import Result
from runtime.editing.attempt_search import MultiAttemptPatchSearcher, SearchTrace
from runtime.events.schemas import EditPlan, PatchArtifact


class PatchWorker:
    def __init__(self, max_attempts: int = 3):
        self.searcher = MultiAttemptPatchSearcher(max_attempts=max_attempts)

    def run(self, repo_root: Path, plan: EditPlan, parsed) -> tuple[PatchArtifact | None, Result, SearchTrace]:
        return self.searcher.search(repo_root, plan, parsed)
