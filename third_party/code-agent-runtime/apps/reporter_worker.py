from __future__ import annotations

from pathlib import Path

from runtime.arbiter.contract_eval import ContractEvaluator
from runtime.arbiter.decision_gate import DecisionGate
from runtime.events.schemas import EditPlan, IssueTask, PatchArtifact, PublishDecision, ValidationReport
from runtime.github.comments_api import CommentReporter
from runtime.github.pr_api import PullRequestReporter
from runtime.reporting.markdown_summary import render_attempt_summary
from runtime.validation.artifact_collector import ArtifactCollector
from runtime.validation.dependency_snapshot import DependencySnapshotter


class ReporterWorker:
    def __init__(self, outbox_root: Path, contract_file: Path):
        collector = ArtifactCollector(outbox_root)
        self.collector = collector
        self.commenter = CommentReporter(collector)
        self.pr = PullRequestReporter(collector)
        self.contracts = ContractEvaluator(contract_file)
        self.gate = DecisionGate()
        self.snapshotter = DependencySnapshotter()

    def run(
        self,
        *,
        target_branch: str,
        task: IssueTask,
        plan: EditPlan,
        patch: PatchArtifact,
        report: ValidationReport,
        attempt_index: int,
        attempted_files: list[str] | None = None,
        repo_root: Path | None = None,
    ) -> tuple[PublishDecision, Path]:
        context = {
            'target_branch': target_branch,
            'action_type': 'pr.open',
            'changed_paths': patch.changed_files,
            'changed_code_files_count': len(patch.changed_files),
            'targeted_tests_passed': report.targeted_tests_passed,
            'test_runtime_network': False,
            'path_outside_workspace': False,
        }
        markdown_summary = render_attempt_summary(
            task=task,
            plan=plan,
            patch=patch,
            report=report,
            decision=None,
            attempt_index=attempt_index,
            attempted_files=attempted_files,
        )
        if repo_root is not None:
            dep_json = self.snapshotter.to_json(repo_root)
            self.collector.write_text(f'dependency_snapshot_{report.task_id}_{report.attempt_id}.json', dep_json)
        contract = self.contracts.evaluate(context)
        if not contract.ok:
            decision = PublishDecision(report.task_id, report.attempt_id, 'reject', contract.message)
            markdown_summary = render_attempt_summary(
                task=task,
                plan=plan,
                patch=patch,
                report=report,
                decision=decision,
                attempt_index=attempt_index,
                attempted_files=attempted_files,
            )
            path = self.commenter.post_failure_comment(task_id=report.task_id, attempt_id=report.attempt_id, reason=decision.reason, notes=report.notes, markdown_summary=markdown_summary)
            return decision, path
        decision = self.gate.decide(report, patch_has_tests=bool(patch.added_tests))
        markdown_summary = render_attempt_summary(
            task=task,
            plan=plan,
            patch=patch,
            report=report,
            decision=decision,
            attempt_index=attempt_index,
            attempted_files=attempted_files,
        )
        if decision.mode in {'reject', 'comment_only'}:
            path = self.commenter.post_failure_comment(task_id=report.task_id, attempt_id=report.attempt_id, reason=decision.reason, notes=report.notes, markdown_summary=markdown_summary)
            return decision, path
        path = self.pr.open_draft_pr(task_id=report.task_id, attempt_id=report.attempt_id, patch=patch, report=report, markdown_summary=markdown_summary)
        return decision, path
