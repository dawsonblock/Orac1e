from __future__ import annotations

import subprocess
from pathlib import Path

from runtime.common.result import Result


class GitPublisher:
    def push_branch(self, workspace_root: Path, branch_name: str, remote: str = 'origin') -> Result:
        proc = subprocess.run(
            ['git', '-C', str(workspace_root), 'push', remote, f'HEAD:refs/heads/{branch_name}'],
            capture_output=True,
            text=True,
        )
        if proc.returncode == 0:
            return Result(True, 'ok', proc.stdout.strip())
        return Result(False, 'push_failed', (proc.stdout + '\n' + proc.stderr).strip())

    def current_head_sha(self, workspace_root: Path) -> str:
        proc = subprocess.run(
            ['git', '-C', str(workspace_root), 'rev-parse', 'HEAD'],
            check=True,
            capture_output=True,
            text=True,
        )
        return proc.stdout.strip()
