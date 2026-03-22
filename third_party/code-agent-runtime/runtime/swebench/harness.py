from __future__ import annotations

import csv
import json
from dataclasses import asdict, dataclass
from pathlib import Path

from apps.patch_worker import PatchWorker
from apps.planner_worker import PlannerWorker
from apps.reporter_worker import ReporterWorker
from apps.validation_worker import ValidationWorker
from runtime.common.ids import stable_task_id
from runtime.events.schemas import IssueTask
from runtime.swebench.manifest import SwebenchTask


@dataclass(frozen=True)
class TaskRunResult:
    repo: str
    issue_number: int
    task_id: str
    decision_mode: str
    decision_reason: str
    changed_files: list[str]
    confidence: float
    risk_score: float


class SwebenchHarness:
    def __init__(self):
        self.planner = PlannerWorker()
        self.patcher = PatchWorker()
        self.validator = ValidationWorker()

    def run_task(self, task: SwebenchTask) -> TaskRunResult:
        issue_task = IssueTask(
            task_id=stable_task_id(task.repo, task.issue_number),
            repo=task.repo,
            repo_url=str(task.repo_path),
            issue_number=task.issue_number,
            base_ref=task.base_ref,
            title=task.title,
            body=task.body,
            labels=task.labels or ['agent:fix'],
        )
        plan, parsed = self.planner.run(task.repo_path, issue_task)
        patch, guard, _trace = self.patcher.run(task.repo_path, plan, parsed)
        if patch is None:
            return TaskRunResult(task.repo, task.issue_number, issue_task.task_id, 'reject', guard.message, [], 0.0, 1.0)
        report, _ = self.validator.run(task.repo_path, plan, patch)
        reporter = ReporterWorker(task.repo_path / '.agent_outbox', task.repo_path / 'domains' / 'code' / 'contracts.yaml')
        decision, _artifact = reporter.run(target_branch=f'agent/issue-{task.issue_number}-attempt-01', task=issue_task, plan=plan, patch=patch, report=report, attempt_index=1)
        return TaskRunResult(
            repo=task.repo,
            issue_number=task.issue_number,
            task_id=issue_task.task_id,
            decision_mode=decision.mode,
            decision_reason=decision.reason,
            changed_files=list(report.changed_files),
            confidence=report.confidence,
            risk_score=report.risk_score,
        )

    def run_manifest(self, tasks: list[SwebenchTask], output_dir: Path) -> list[TaskRunResult]:
        output_dir.mkdir(parents=True, exist_ok=True)
        results: list[TaskRunResult] = [self.run_task(task) for task in tasks]
        jsonl_path = output_dir / 'results.jsonl'
        csv_path = output_dir / 'results.csv'
        with jsonl_path.open('w', encoding='utf-8') as fh:
            for result in results:
                fh.write(json.dumps(asdict(result)) + '\n')
        with csv_path.open('w', encoding='utf-8', newline='') as fh:
            writer = csv.DictWriter(
                fh,
                fieldnames=list(asdict(results[0]).keys()) if results else ['repo', 'issue_number', 'task_id', 'decision_mode', 'decision_reason', 'changed_files', 'confidence', 'risk_score'],
            )
            writer.writeheader()
            for result in results:
                row = asdict(result)
                row['changed_files'] = ';'.join(result.changed_files)
                writer.writerow(row)
        return results
