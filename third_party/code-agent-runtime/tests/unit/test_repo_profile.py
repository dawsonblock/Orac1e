from pathlib import Path

from runtime.profile.repo_profile import RepoProfileLoader


def test_repo_profile_loader_reads_pyproject_and_yaml(tmp_path: Path):
    (tmp_path / 'pyproject.toml').write_text(
        '\n'.join([
            '[tool.code_agent_runtime]',
            'ignore_paths = ["vendor/**"]',
            'max_files = 7',
            '[tool.code_agent_runtime.python]',
            'targeted_test_prefix = ["python", "-m", "pytest", "-q"]',
        ]),
        encoding='utf-8',
    )
    agent_dir = tmp_path / '.agent'
    agent_dir.mkdir()
    (agent_dir / 'runtime.yaml').write_text(
        'flaky_retries: 1\n'
        'test_paths:\n'
        '  - qa/tests\n'
        'sensitive_paths:\n'
        '  - security/**\n',
        encoding='utf-8',
    )

    profile = RepoProfileLoader().load(tmp_path)
    assert profile.max_files == 7
    assert profile.flaky_retries == 1
    assert profile.test_paths == ['qa/tests']
    assert profile.python.targeted_test_prefix == ['python', '-m', 'pytest', '-q']
    assert profile.is_ignored('vendor/lib.py') is True
    assert profile.is_sensitive('security/auth.py') is True
