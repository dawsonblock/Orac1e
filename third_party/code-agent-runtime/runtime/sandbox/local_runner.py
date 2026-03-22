from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Mapping

from runtime.sandbox.base import CommandResult


class LocalCommandRunner:
    def run(
        self,
        command: list[str],
        *,
        cwd: Path,
        env: Mapping[str, str] | None = None,
        timeout_seconds: int | None = None,
    ) -> CommandResult:
        merged_env = os.environ.copy()
        if env:
            merged_env.update(env)
        proc = subprocess.run(
            command,
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
            command=list(command),
        )
