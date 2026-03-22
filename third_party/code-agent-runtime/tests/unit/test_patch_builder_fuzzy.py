from runtime.events.schemas import EditPlan
from runtime.intake.issue_parser import IssueParser
from runtime.editing.patch_builder import PatchBuilder


def test_patch_builder_fuzzy_line_replace(tmp_path):
    src = tmp_path / 'calc.py'
    src.write_text('def f():\n    return x+2\n', encoding='utf-8')
    body = 'File: calc.py\nReplace: return x + 2\nWith:     return x + 1\n'
    parsed = IssueParser().parse('fix', body)
    plan = EditPlan(task_id='t', attempt_id='a', candidate_files=['calc.py'], hypotheses=['h'], test_targets=[])
    candidates = PatchBuilder().preview_candidates(tmp_path, plan, parsed)
    assert any(c.strategy == 'fuzzy_line_replace' for c in candidates)
