from pathlib import Path

from runtime.validation.command_discovery import CommandDiscovery


def test_command_discovery_honors_profile_override(tmp_path: Path):
    (tmp_path / 'pyproject.toml').write_text(
        '\n'.join([
            '[tool.code_agent_runtime.python]',
            'targeted_test_prefix = ["python", "-m", "pytest", "-q", "-x"]',
            'full_test = ["python", "-m", "pytest", "-q"]',
        ]),
        encoding='utf-8',
    )

    cmds = CommandDiscovery().discover(tmp_path, 'python')
    assert cmds.targeted_test_prefix == ['python', '-m', 'pytest', '-q', '-x']
    assert cmds.full_test == ['python', '-m', 'pytest', '-q']
