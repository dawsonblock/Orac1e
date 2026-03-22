from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


@dataclass
class ProcessResult:
    argv: list[str]
    cwd: str
    exit_code: int
    stdout: str
    stderr: str

    @property
    def ok(self) -> bool:
        return self.exit_code == 0


def run(
    argv: Sequence[str],
    cwd: str | Path,
    env: dict[str, str] | None = None,
    timeout: int = 300,
) -> ProcessResult:
    proc = subprocess.run(
        list(argv),
        cwd=str(cwd),
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return ProcessResult(list(argv), str(cwd), proc.returncode, proc.stdout, proc.stderr)
