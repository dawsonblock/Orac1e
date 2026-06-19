from __future__ import annotations

from runtime.events.schemas import EditPlan, IssueTask, PatchArtifact, ValidationReport


def build_attempt_provenance(*, task: IssueTask, plan: EditPlan, patch: PatchArtifact | None, report: ValidationReport | None, validation_commands: list[str] | None = None) -> dict[str, object]:
    return {
        'repo': task.repo,
        'issue_number': task.issue_number,
        'base_ref': task.base_ref,
        'task_id': task.task_id,
        'attempt_id': plan.attempt_id,
        'candidate_files': plan.candidate_files,
        'test_targets': plan.test_targets,
        'changed_files': (patch.changed_files if patch else []),
        'added_tests': (patch.added_tests if patch else []),
        'validation_commands': validation_commands or [],
        'validation': {
            'preflight_passed': (report.preflight_passed if report else None),
            'lint_passed': (report.lint_passed if report else None),
            'targeted_tests_passed': (report.targeted_tests_passed if report else None),
            'full_tests_passed': (report.full_tests_passed if report else None),
            'risk_score': (report.risk_score if report else None),
            'confidence': (report.confidence if report else None),
            'notes': (report.notes if report else []),
        },
    }
