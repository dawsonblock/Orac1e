from pathlib import Path

from runtime.intake.issue_parser import IssueParser
from runtime.planning.issue_localizer import IssueLocalizer


def test_localizer_boosts_symbol_and_ignored_files(tmp_path: Path):
    (tmp_path / 'src').mkdir()
    (tmp_path / 'tests').mkdir()
    (tmp_path / 'src' / 'maths.py').write_text('def clamp_value(x):\n    return max(0, x)\n', encoding='utf-8')
    (tmp_path / 'src' / 'other.py').write_text('def noop():\n    return 1\n', encoding='utf-8')
    (tmp_path / 'tests' / 'test_maths.py').write_text('def test_clamp_value():\n    assert True\n', encoding='utf-8')
    body = 'Symbol: clamp_value\nIgnore-Files: src/other.py\n'
    parsed = IssueParser().parse('Fix clamp_value', body)
    files, tests = IssueLocalizer().localize(tmp_path, parsed)
    assert files[0] == 'src/maths.py'
    assert 'src/other.py' not in files
    assert 'tests/test_maths.py' in tests
