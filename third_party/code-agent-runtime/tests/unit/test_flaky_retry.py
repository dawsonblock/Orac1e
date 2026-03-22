from pathlib import Path

from runtime.sandbox.base import CommandResult
from runtime.targeted_stub import SequenceRunner
from runtime.validation.targeted_tests import TargetedTestRunner


def test_targeted_runner_retries_on_flaky_signal(tmp_path: Path):
    (tmp_path / 'pyproject.toml').write_text('[tool.code_agent_runtime]\nflaky_retries = 1\n', encoding='utf-8')
    tests_dir = tmp_path / 'tests'
    tests_dir.mkdir()
    (tests_dir / 'test_sample.py').write_text('def test_ok():\n    assert True\n', encoding='utf-8')

    runner = SequenceRunner([
        CommandResult(returncode=1, stdout='flaky timeout in worker', stderr='', command=['python']),
        CommandResult(returncode=0, stdout='1 passed', stderr='', command=['python']),
    ])
    result = TargetedTestRunner(runner=runner).run_pytest(tmp_path, ['tests/test_sample.py'])
    assert result.ok is True
    assert 'retried after flaky signal' in result.message
