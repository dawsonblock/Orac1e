from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import Mapping

from runtime.common.config import SandboxConfig
from runtime.sandbox.base import CommandResult


class DockerUnavailableError(RuntimeError):
    pass


class DockerCommandRunner:
    def __init__(self, config: SandboxConfig):
        self.config = config

    def docker_available(self) -> bool:
        return shutil.which('docker') is not None

    def maybe_pull(self) -> None:
        if self.config.pull_policy == 'never':
            return
        if not self.docker_available():
            raise DockerUnavailableError('docker executable not found')
        if self.config.pull_policy == 'always':
            subprocess.run(['docker', 'pull', self.config.image], check=True, capture_output=True, text=True)
        elif self.config.pull_policy == 'missing':
            inspect = subprocess.run(['docker', 'image', 'inspect', self.config.image], capture_output=True, text=True)
            if inspect.returncode != 0:
                subprocess.run(['docker', 'pull', self.config.image], check=True, capture_output=True, text=True)

    def build_command(self, command: list[str], *, cwd: Path, env: Mapping[str, str] | None = None) -> list[str]:
        mount_mode = 'rw' if self.config.mount_repo_readwrite else 'ro'
        docker_cmd = [
            'docker', 'run', '--rm',
            '--network', self.config.network,
            '-v', f'{cwd.resolve()}:/workspace:{mount_mode}',
            '-w', '/workspace',
            '--memory', self.config.memory_limit,
            '--cpus', self.config.cpu_limit,
        ]
        if env:
            for key, value in env.items():
                docker_cmd.extend(['-e', f'{key}={value}'])
        docker_cmd.append(self.config.image)
        docker_cmd.extend(command)
        return docker_cmd

    def run(
        self,
        command: list[str],
        *,
        cwd: Path,
        env: Mapping[str, str] | None = None,
        timeout_seconds: int | None = None,
    ) -> CommandResult:
        if not self.docker_available():
            raise DockerUnavailableError('docker executable not found')
        self.maybe_pull()
        docker_cmd = self.build_command(command, cwd=cwd, env=env)
        merged_env = os.environ.copy()
        proc = subprocess.run(
            docker_cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            env=merged_env,
            timeout=timeout_seconds,
        )
        return CommandResult(
            returncode=proc.returncode,
            stdout=proc.stdout,
            stderr=proc.stderr,
            command=docker_cmd,
        )
