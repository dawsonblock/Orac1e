from pathlib import Path

from runtime.common.ids import stable_attempt_id, stable_task_id
from runtime.editing.patch_builder import PatchBuilder
from runtime.events.schemas import EditPlan
from runtime.intake.issue_parser import IssueParser


def _plan(task_id: str, files: list[str]) -> EditPlan:
    return EditPlan(task_id=task_id, attempt_id=stable_attempt_id(task_id, 1), candidate_files=files, hypotheses=['x'], test_targets=[])


def test_patch_builder_supports_insert_before(tmp_path: Path):
    src = tmp_path / 'src'
    src.mkdir()
    target = src / 'calc.py'
    target.write_text('def f(x):\n    return x + 2\n', encoding='utf-8')
    task_id = stable_task_id('acme/repo', 1)
    parsed = IssueParser().parse('fix', 'File: src/calc.py\nInsert-Before: return x + 2\nWith: if x is None:\n        return 0\n')
    patch = PatchBuilder().build(tmp_path, _plan(task_id, ['src/calc.py']), parsed)
    assert patch.changed_files == ['src/calc.py']
    text = target.read_text(encoding='utf-8')
    assert 'if x is None:' in text
    assert text.index('if x is None:') < text.index('return x + 2')


def test_patch_builder_supports_function_scoped_return_rewrite(tmp_path: Path):
    src = tmp_path / 'src'
    src.mkdir()
    target = src / 'calc.py'
    target.write_text('def inc(x):\n    return x + 2\n\ndef dec(x):\n    return x - 1\n', encoding='utf-8')
    task_id = stable_task_id('acme/repo', 1)
    parsed = IssueParser().parse('fix', 'File: src/calc.py\nFunction: inc\nWith: return x + 1\n')
    patch = PatchBuilder().build(tmp_path, _plan(task_id, ['src/calc.py']), parsed)
    assert patch.changed_files == ['src/calc.py']
    text = target.read_text(encoding='utf-8')
    assert 'def inc(x):\n    return x + 1' in text
    assert 'def dec(x):\n    return x - 1' in text
