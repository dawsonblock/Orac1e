from pathlib import Path

from runtime.common.config import SandboxConfig
from runtime.sandbox.docker_runner import DockerCommandRunner


def test_docker_runner_builds_network_isolated_command(tmp_path: Path):
    runner = DockerCommandRunner(SandboxConfig(mode='docker', image='python:3.11-slim', network='none'))
    cmd = runner.build_command(['python', '-m', 'pytest', 'tests/test_calc.py'], cwd=tmp_path, env={'PYTHONDONTWRITEBYTECODE': '1'})
    joined = ' '.join(cmd)
    assert cmd[:3] == ['docker', 'run', '--rm']
    assert '--network' in cmd
    assert 'none' in cmd
    assert '/workspace' in joined
    assert 'PYTHONDONTWRITEBYTECODE=1' in joined
