from __future__ import annotations

from runtime.events.schemas import EditPlan, IssueTask, PatchArtifact, PublishDecision, ValidationReport


def render_attempt_summary(
    *,
    task: IssueTask,
    plan: EditPlan,
    patch: PatchArtifact | None,
    report: ValidationReport | None,
    decision: PublishDecision | None,
    attempt_index: int,
    attempted_files: list[str] | None = None,
    validation_commands: list[str] | None = None,
    dependency_snapshot: dict[str, str] | None = None,
) -> str:
    lines = [
        '# Code Agent Attempt Summary',
        '',
        f'- Repo: `{task.repo}`',
        f'- Issue: `#{task.issue_number}` {task.title}',
        f'- Attempt: `{attempt_index}`',
        f'- Base ref: `{task.base_ref}`',
        '',
        '## Plan',
        '',
        f'- Candidate files: {", ".join(plan.candidate_files) if plan.candidate_files else "none"}',
        f'- Hypotheses: {"; ".join(plan.hypotheses) if plan.hypotheses else "none"}',
        f'- Test targets: {", ".join(plan.test_targets) if plan.test_targets else "none"}',
    ]
    if attempted_files is not None:
        lines.extend(['', '## Search', '', f'- Attempted files: {", ".join(attempted_files) if attempted_files else "none"}'])
    if patch is not None:
        lines.extend([
            '',
            '## Patch',
            '',
            f'- Patch ID: `{patch.patch_id}`',
            f'- Summary: {patch.summary}',
            f'- Changed files: {", ".join(patch.changed_files) if patch.changed_files else "none"}',
            f'- Added tests: {", ".join(patch.added_tests) if patch.added_tests else "none"}',
            f'- Rationale: {patch.rationale}',
        ])
    if report is not None:
        lines.extend([
            '',
            '## Validation',
            '',
            f'- Preflight passed: `{report.preflight_passed}`',
            f'- Lint passed: `{report.lint_passed}`',
            f'- Targeted tests passed: `{report.targeted_tests_passed}`',
            f'- Full tests passed: `{report.full_tests_passed}`',
            f'- Risk score: `{report.risk_score:.3f}`',
            f'- Confidence: `{report.confidence:.3f}`',
        ])
        if report.notes:
            lines.extend(['', '### Notes', ''])
            lines.extend([f'- {note}' for note in report.notes])
    if validation_commands:
        lines.extend(['', '## Validation commands', ''])
        lines.extend([f'- `{cmd}`' for cmd in validation_commands])
    if dependency_snapshot:
        lines.extend(['', '## Dependency snapshot', ''])
        for key in sorted(dependency_snapshot):
            lines.append(f'- `{key}`: `{dependency_snapshot[key]}`')
    if decision is not None:
        lines.extend(['', '## Publish decision', '', f'- Mode: `{decision.mode}`', f'- Reason: {decision.reason}'])
    return '\n'.join(lines).rstrip() + '\n'
