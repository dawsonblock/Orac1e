from runtime.events.schemas import EditPlan, IssueTask, PatchArtifact, PublishDecision, ValidationReport
from runtime.reporting.markdown_summary import render_attempt_summary


def test_markdown_summary_includes_validation_commands_and_dependency_snapshot():
    task = IssueTask(task_id='task_1', repo='org/repo', repo_url='https://example.com/repo.git', issue_number=12, base_ref='main', title='Fix bug', body='Body', labels=[])
    plan = EditPlan(task_id='task_1', attempt_id='attempt_1', candidate_files=['src/app.py'], hypotheses=['bug'], test_targets=['tests/test_app.py'])
    patch = PatchArtifact(task_id='task_1', attempt_id='attempt_1', patch_id='patch_1', diff_text='diff', changed_files=['src/app.py'], added_tests=['tests/test_app.py'], rationale='fix', summary='summary')
    report = ValidationReport(task_id='task_1', attempt_id='attempt_1', preflight_passed=True, lint_passed=True, targeted_tests_passed=True, full_tests_passed=True, risk_score=0.12, confidence=0.88, changed_files=['src/app.py'])
    decision = PublishDecision(task_id='task_1', attempt_id='attempt_1', mode='draft_pr', reason='ok')

    text = render_attempt_summary(task=task, plan=plan, patch=patch, report=report, decision=decision, attempt_index=1, validation_commands=['python -m pytest tests/test_app.py'], dependency_snapshot={'requirements.txt': 'abc123'})
    assert '## Validation commands' in text
    assert 'requirements.txt' in text
