from pathlib import Path

from runtime.sandbox.base import CommandResult
from runtime.validation.lint_runner import LintRunner
from runtime.validation.targeted_tests import TargetedTestRunner


class FakeRunner:
    def __init__(self):
        self.commands = []

    def run(self, command, *, cwd, env=None, timeout_seconds=None):
        self.commands.append(command)
        return CommandResult(returncode=0, stdout='ok', stderr='', command=list(command))


def test_js_validation_commands(tmp_path: Path):
    (tmp_path / 'package.json').write_text('{"name":"x"}', encoding='utf-8')
    (tmp_path / 'tsconfig.json').write_text('{"compilerOptions":{}}', encoding='utf-8')
    runner = FakeRunner()
    lint = LintRunner(runner=runner)
    tests = TargetedTestRunner(runner=runner)
    lint_result = lint.run_for_language(tmp_path, ['src/app.js', 'src/lib.ts'], 'js_ts')
    test_result = tests.run_for_language(tmp_path, ['src/app.test.ts'], 'js_ts')
    assert lint_result.ok and test_result.ok
    assert runner.commands[0][:2] == ['node', '--check']
    assert runner.commands[1][:2] == ['npx', 'tsc']
    assert runner.commands[2][0] == 'npm'


def test_rust_validation_commands(tmp_path: Path):
    (tmp_path / 'Cargo.toml').write_text('[package]\nname = "x"\nversion = "0.1.0"\n', encoding='utf-8')
    runner = FakeRunner()
    lint = LintRunner(runner=runner)
    tests = TargetedTestRunner(runner=runner)
    lint_result = lint.run_for_language(tmp_path, ['src/lib.rs'], 'rust')
    test_result = tests.run_for_language(tmp_path, ['core'], 'rust')
    assert lint_result.ok and test_result.ok
    assert runner.commands[0][:2] == ['cargo', 'check']
    assert runner.commands[1][:2] == ['cargo', 'test']
