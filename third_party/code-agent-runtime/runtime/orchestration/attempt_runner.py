from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from apps.patch_worker import PatchWorker
from apps.planner_worker import PlannerWorker
from apps.validation_worker import ValidationWorker
from runtime.common.result import Result
from runtime.events.schemas import EditPlan, IssueTask, PatchArtifact, ValidationReport
from runtime.validation.workspace_health import WorkspaceHealth


@dataclass(frozen=True)
class AttemptRecord:
    attempt_index: int
    plan: EditPlan
    patch: PatchArtifact | None
    guard: Result
    report: ValidationReport | None
    attempted_files: list[str] = field(default_factory=list)
    reset_result: Result | None = None


@dataclass(frozen=True)
class AttemptRunResult:
    records: list[AttemptRecord]
    best_patch: PatchArtifact | None
    best_report: ValidationReport | None


class AttemptRunner:
    def __init__(
        self,
        planner: PlannerWorker | None = None,
        patcher: PatchWorker | None = None,
        validator: ValidationWorker | None = None,
        workspace_health: WorkspaceHealth | None = None,
    ):
        self.planner = planner or PlannerWorker()
        self.patcher = patcher or PatchWorker()
        self.validator = validator or ValidationWorker()
        self.workspace_health = workspace_health or WorkspaceHealth()

    def run(self, repo_root: Path, task: IssueTask, *, max_attempts: int = 2) -> AttemptRunResult:
        records: list[AttemptRecord] = []
        best_patch: PatchArtifact | None = None
        best_report: ValidationReport | None = None

        for attempt_index in range(1, max_attempts + 1):
            reset_result = self.workspace_health.hard_reset(repo_root) if attempt_index > 1 else self.workspace_health.ensure_clean(repo_root)
            plan, parsed = self.planner.run(repo_root, task, attempt_index=attempt_index)
            patch, guard, trace = self.patcher.run(repo_root, plan, parsed)
            report: ValidationReport | None = None
            if patch is not None and guard.ok:
                report, _ = self.validator.run(repo_root, plan, patch)
                if best_report is None or report.confidence > best_report.confidence:
                    best_patch = patch
                    best_report = report
                if report.preflight_passed and report.targeted_tests_passed:
                    records.append(AttemptRecord(attempt_index, plan, patch, guard, report, trace.attempted_files, reset_result))
                    return AttemptRunResult(records, patch, report)
            records.append(AttemptRecord(attempt_index, plan, patch, guard, report, trace.attempted_files, reset_result))
            if attempt_index >= plan.stop_after_n_failed_attempts:
                break

        return AttemptRunResult(records, best_patch, best_report)
