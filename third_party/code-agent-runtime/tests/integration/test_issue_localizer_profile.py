from pathlib import Path

from runtime.intake.issue_parser import IssueParser
from runtime.planning.issue_localizer import IssueLocalizer


def test_issue_localizer_respects_profile_ignore_paths(tmp_path: Path):
    (tmp_path / 'pyproject.toml').write_text('[tool.code_agent_runtime]\nignore_paths = ["vendor/**"]\n', encoding='utf-8')
    vendor = tmp_path / 'vendor'
    vendor.mkdir()
    (vendor / 'bug.py').write_text('def crash():\n    return broken\n', encoding='utf-8')
    src = tmp_path / 'src'
    src.mkdir()
    (src / 'bug.py').write_text('def crash():\n    return broken\n', encoding='utf-8')
    tests = tmp_path / 'tests'
    tests.mkdir()
    (tests / 'test_bug.py').write_text('def test_bug():\n    assert True\n', encoding='utf-8')

    parsed = IssueParser().parse('fix bug', 'Search: crash')
    files, test_targets = IssueLocalizer().localize(tmp_path, parsed)
    assert 'src/bug.py' in files
    assert 'vendor/bug.py' not in files
    assert 'tests/test_bug.py' in test_targets
