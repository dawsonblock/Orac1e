import zipfile
from pathlib import Path

from apps.reporter_worker import ReporterWorker
from runtime.common.ids import patch_id, stable_attempt_id, stable_task_id
from runtime.events.schemas import EditPlan, IssueTask, PatchArtifact, ValidationReport
from tests.helpers import init_python_repo


def test_reporter_writes_bundle_with_markdown_and_patch(tmp_path: Path):
    repo = tmp_path / 'repo'
    repo.mkdir()
    init_python_repo(repo)
    task = IssueTask(
        task_id=stable_task_id('acme/repo', 1),
        repo='acme/repo',
        repo_url='https://example.invalid/acme/repo.git',
        issue_number=1,
        base_ref='main',
        title='Fix inc',
        body='File: src/calc.py\nReplace: return x + 2\nWith: return x + 1\nTests: tests/test_calc.py\n',
        labels=['agent:fix'],
    )
    aid = stable_attempt_id(task.task_id, 1)
    plan = EditPlan(task_id=task.task_id, attempt_id=aid, candidate_files=['src/calc.py'], hypotheses=['fix literal'], test_targets=['tests/test_calc.py'])
    patch = PatchArtifact(
        task_id=task.task_id,
        attempt_id=aid,
        patch_id=patch_id(aid, ['src/calc.py']),
        diff_text='--- a/src/calc.py\n+++ b/src/calc.py\n',
        changed_files=['src/calc.py'],
        added_tests=['tests/test_calc.py'],
        rationale='test patch',
        summary='Changed src/calc.py',
    )
    report = ValidationReport(
        task_id=task.task_id,
        attempt_id=aid,
        preflight_passed=True,
        lint_passed=True,
        targeted_tests_passed=True,
        full_tests_passed=True,
        risk_score=0.2,
        confidence=0.9,
        changed_files=['src/calc.py'],
        notes=['ok'],
    )
    reporter = ReporterWorker(repo / '.agent_outbox', repo / 'domains' / 'code' / 'contracts.yaml')
    decision, bundle_path = reporter.run(target_branch='agent/issue-1-attempt-01', task=task, plan=plan, patch=patch, report=report, attempt_index=1, attempted_files=['src/calc.py'])
    assert decision.mode in {'draft_pr', 'pr'}
    with zipfile.ZipFile(bundle_path) as zf:
        assert 'summary.md' in zf.namelist()
        assert 'patch.diff' in zf.namelist()
        assert 'draft_pr.json' in zf.namelist()
