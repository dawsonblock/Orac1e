from pathlib import Path

from apps.validation_worker import ValidationWorker
from runtime.common.ids import stable_attempt_id, stable_task_id
from runtime.events.schemas import EditPlan, PatchArtifact
from runtime.sandbox.base import CommandResult


class FakeRunner:
    def __init__(self):
        self.commands = []

    def run(self, command, *, cwd, env=None, timeout_seconds=None):
        self.commands.append(command)
        return CommandResult(returncode=0, stdout='ok', stderr='', command=list(command))


class FakeWorker(ValidationWorker):
    def __init__(self):
        super().__init__()
        self.fake_runner = FakeRunner()

    def _make_runner(self, repo_root: Path):
        return self.fake_runner


def test_validation_worker_uses_js_pipeline(tmp_path: Path):
    (tmp_path / 'package.json').write_text('{"name":"x"}', encoding='utf-8')
    (tmp_path / 'src').mkdir()
    (tmp_path / 'tests').mkdir()
    (tmp_path / 'src' / 'calc.js').write_text('function inc(x) { return x + 1; }\nmodule.exports = { inc };\n', encoding='utf-8')
    (tmp_path / 'tests' / 'calc.test.js').write_text('test("inc", () => {});\n', encoding='utf-8')
    task_id = stable_task_id('acme/repo', 1)
    plan = EditPlan(task_id=task_id, attempt_id=stable_attempt_id(task_id, 1), candidate_files=['src/calc.js'], hypotheses=['literal'], test_targets=[])
    patch = PatchArtifact(task_id=task_id, attempt_id=plan.attempt_id, patch_id='patch_1', diff_text='diff', changed_files=['src/calc.js'], added_tests=[], rationale='x', summary='y')
    worker = FakeWorker()
    report, details = worker.run(tmp_path, plan, patch)
    assert report.lint_passed is True
    assert report.targeted_tests_passed is True
    assert any('language=js_ts' == note for note in report.notes)
    assert details['full_tests'].ok is True
