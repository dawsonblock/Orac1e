from runtime.common.ids import stable_task_id
from runtime.events.schemas import IssueTask
from runtime.intake.issue_parser import IssueParser
from runtime.planning.edit_plan import EditPlanner


def test_edit_planner_uses_max_attempts_and_hypotheses():
    task = IssueTask(
        task_id=stable_task_id('acme/repo', 1),
        repo='acme/repo',
        repo_url='https://example.invalid/repo.git',
        issue_number=1,
        base_ref='main',
        title='Fix',
        body='Function: inc\nWith: return x + 1\nMax-Attempts: 4\n',
        labels=['agent:fix'],
    )
    parsed = IssueParser().parse(task.title, task.body)
    plan = EditPlanner().build(task, parsed, 'attempt_1', ['src/calc.py'], ['tests/test_calc.py'])
    assert plan.stop_after_n_failed_attempts == 4
    assert any('function-scoped return rewrite' in h for h in plan.hypotheses)
