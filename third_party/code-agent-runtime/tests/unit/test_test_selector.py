from pathlib import Path

from runtime.validation.test_selector import TestSelector


def test_test_selector_combines_explicit_and_inferred_tests(tmp_path: Path):
    (tmp_path / 'src').mkdir()
    (tmp_path / 'tests').mkdir()
    (tmp_path / 'src' / 'calc.py').write_text('def inc(x):\n    return x + 1\n', encoding='utf-8')
    (tmp_path / 'tests' / 'test_calc.py').write_text('def test_inc():\n    assert True\n', encoding='utf-8')
    (tmp_path / 'tests' / 'test_other.py').write_text('def test_other():\n    assert True\n', encoding='utf-8')
    selected = TestSelector().select(tmp_path, ['src/calc.py'], ['tests/test_other.py'])
    assert selected == ['tests/test_other.py', 'tests/test_calc.py']


def test_test_selector_falls_back_to_repo_tests(tmp_path: Path):
    (tmp_path / 'pkg').mkdir()
    (tmp_path / 'tests').mkdir()
    (tmp_path / 'pkg' / 'mod.py').write_text('x = 1\n', encoding='utf-8')
    (tmp_path / 'tests' / 'test_a.py').write_text('def test_a():\n    assert True\n', encoding='utf-8')
    (tmp_path / 'tests' / 'test_b.py').write_text('def test_b():\n    assert True\n', encoding='utf-8')
    selected = TestSelector().select(tmp_path, ['pkg/mod.py'], [])
    assert selected == ['tests/test_a.py', 'tests/test_b.py']
