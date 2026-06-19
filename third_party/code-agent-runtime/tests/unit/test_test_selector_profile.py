from pathlib import Path

from runtime.validation.test_selector import TestSelector


def test_selector_uses_profile_test_paths(tmp_path: Path):
    (tmp_path / 'pyproject.toml').write_text('[tool.code_agent_runtime]\ntest_paths = ["qa/tests"]\n', encoding='utf-8')
    src = tmp_path / 'src'
    src.mkdir()
    (src / 'maths.py').write_text('def add(a,b):\n    return a+b\n', encoding='utf-8')
    qa = tmp_path / 'qa' / 'tests'
    qa.mkdir(parents=True)
    (qa / 'test_maths.py').write_text('def test_add():\n    assert 1+1 == 2\n', encoding='utf-8')

    selected = TestSelector().select(tmp_path, ['src/maths.py'], [])
    assert selected == ['qa/tests/test_maths.py']
