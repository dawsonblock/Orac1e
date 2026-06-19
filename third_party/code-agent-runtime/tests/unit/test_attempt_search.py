from pathlib import Path

from runtime.common.ids import stable_attempt_id, stable_task_id
from runtime.editing.attempt_search import MultiAttemptPatchSearcher
from runtime.events.schemas import EditPlan
from runtime.intake.issue_parser import IssueParser


def test_multi_attempt_search_tries_second_candidate(tmp_path: Path):
    (tmp_path / 'src').mkdir()
    (tmp_path / 'src' / 'wrong.py').write_text('def inc(x):\n    return x + 5\n', encoding='utf-8')
    (tmp_path / 'src' / 'calc.py').write_text('def inc(x):\n    return x + 2\n', encoding='utf-8')
    task_id = stable_task_id('acme/repo', 1)
    plan = EditPlan(
        task_id=task_id,
        attempt_id=stable_attempt_id(task_id, 1),
        candidate_files=['src/wrong.py', 'src/calc.py'],
        hypotheses=['literal replacement'],
        test_targets=['tests/test_calc.py'],
    )
    parsed = IssueParser().parse('Fix calc', 'Replace: return x + 2\nWith: return x + 1\n')
    patch, guard, trace = MultiAttemptPatchSearcher(max_attempts=3).search(tmp_path, plan, parsed)
    assert patch is not None
    assert guard.ok is True
    assert trace.attempted_files == ['src/calc.py']
    assert (tmp_path / 'src' / 'calc.py').read_text(encoding='utf-8').strip().endswith('return x + 1')
