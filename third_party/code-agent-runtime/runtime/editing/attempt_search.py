from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from runtime.common.result import Result
from runtime.editing.patch_builder import PatchBuilder
from runtime.editing.patch_guard import PatchGuard
from runtime.events.schemas import EditPlan, PatchArtifact


@dataclass(frozen=True)
class SearchTrace:
    attempted_files: list[str] = field(default_factory=list)
    rejected_files: list[str] = field(default_factory=list)
    reasons: list[str] = field(default_factory=list)
    strategies: list[str] = field(default_factory=list)


class MultiAttemptPatchSearcher:
    def __init__(self, builder: PatchBuilder | None = None, guard: PatchGuard | None = None, max_attempts: int = 3):
        self.builder = builder or PatchBuilder()
        self.guard = guard or PatchGuard()
        self.max_attempts = max_attempts

    def search(self, repo_root: Path, plan: EditPlan, parsed) -> tuple[PatchArtifact | None, Result, SearchTrace]:
        trace = SearchTrace()
        candidates = self.builder.preview_candidates(repo_root, plan, parsed)
        if not candidates:
            return None, Result(False, 'patch_build_failed', 'replacement target not found in candidate files'), trace
        for candidate in candidates[: self.max_attempts]:
            trace.attempted_files.append(candidate.relpath)
            trace.strategies.append(candidate.strategy)
            guard = self.guard.evaluate(candidate.artifact)
            if not guard.ok:
                trace.rejected_files.append(candidate.relpath)
                trace.reasons.append(f'{candidate.strategy}: {guard.message}')
                continue
            self.builder.apply_candidate(repo_root, candidate)
            return candidate.artifact, guard, trace
        message = '; '.join(trace.reasons) if trace.reasons else 'no patch candidate passed guard evaluation'
        return None, Result(False, 'guard_rejected', message), trace
