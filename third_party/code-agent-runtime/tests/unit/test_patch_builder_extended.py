from pathlib import Path

from runtime.common.ids import stable_attempt_id, stable_task_id
from runtime.editing.patch_builder import PatchBuilder
from runtime.events.schemas import EditPlan
from runtime.intake.issue_parser import IssueParser


def test_patch_builder_supports_regex_replace(tmp_path: Path):
    (tmp_path / 'src').mkdir()
    (tmp_path / 'src' / 'calc.py').write_text('def inc(x):\n    return x + 2\n', encoding='utf-8')
    task_id = stable_task_id('acme/repo', 1)
    plan = EditPlan(task_id=task_id, attempt_id=stable_attempt_id(task_id, 1), candidate_files=['src/calc.py'], hypotheses=['regex'], test_targets=[])
    parsed = IssueParser().parse('Fix', 'Regex: return x \\+ 2\nWith: return x + 1\n')
    patch = PatchBuilder().build(tmp_path, plan, parsed)
    assert patch.changed_files == ['src/calc.py']
    assert 'return x + 1' in (tmp_path / 'src' / 'calc.py').read_text(encoding='utf-8')


def test_patch_builder_supports_append_test_content(tmp_path: Path):
    (tmp_path / 'tests').mkdir()
    task_id = stable_task_id('acme/repo', 1)
    plan = EditPlan(task_id=task_id, attempt_id=stable_attempt_id(task_id, 1), candidate_files=['tests/test_calc.py'], hypotheses=['test'], test_targets=[])
    body = 'Add-Test-File: tests/test_calc.py\nAdd-Test-Content: ```python\ndef test_added():\n    assert True\n```\n'
    parsed = IssueParser().parse('Add test', body)
    patch = PatchBuilder().build(tmp_path, plan, parsed)
    assert patch.added_tests == ['tests/test_calc.py']
    assert 'test_added' in (tmp_path / 'tests' / 'test_calc.py').read_text(encoding='utf-8')
