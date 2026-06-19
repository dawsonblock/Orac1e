from pathlib import Path

from runtime.common.ids import stable_task_id
from runtime.events.schemas import IssueTask
from runtime.orchestration.attempt_runner import AttemptRunner
from tests.helpers import init_python_repo


def test_attempt_runner_returns_first_passing_attempt(tmp_path: Path):
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
    result = AttemptRunner().run(repo, task, max_attempts=2)
    assert result.best_patch is not None
    assert result.best_report is not None
    assert result.best_report.targeted_tests_passed
    assert result.records[0].attempt_index == 1
