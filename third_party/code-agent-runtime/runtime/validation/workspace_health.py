from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path

from runtime.common.result import Result


@dataclass(frozen=True)
class WorkspaceStatus:
    is_git_repo: bool
    clean: bool
    changed_files: list[str]
    message: str


class WorkspaceHealth:
    def _run(self, repo_root: Path, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(list(args), cwd=repo_root, check=False, capture_output=True, text=True)

    def status(self, repo_root: Path) -> WorkspaceStatus:
        if not (repo_root / '.git').exists():
            return WorkspaceStatus(is_git_repo=False, clean=True, changed_files=[], message='not a git repository')
        proc = self._run(repo_root, 'git', 'status', '--porcelain')
        if proc.returncode != 0:
            return WorkspaceStatus(is_git_repo=True, clean=False, changed_files=[], message=proc.stderr.strip() or proc.stdout.strip())
        changed_files = []
        for line in proc.stdout.splitlines():
            if not line.strip():
                continue
            changed_files.append(line[3:].strip() if len(line) > 3 else line.strip())
        return WorkspaceStatus(is_git_repo=True, clean=not changed_files, changed_files=changed_files, message='clean' if not changed_files else 'workspace has modifications')

    def ensure_clean(self, repo_root: Path) -> Result:
        status = self.status(repo_root)
        if not status.is_git_repo:
            return Result(True, 'not_git', status.message, {'changed_files': []})
        if status.clean:
            return Result(True, 'workspace_clean', status.message, {'changed_files': []})
        return Result(False, 'workspace_dirty', status.message, {'changed_files': status.changed_files})

    def hard_reset(self, repo_root: Path) -> Result:
        if not (repo_root / '.git').exists():
            return Result(True, 'not_git', 'not a git repository')
        reset = self._run(repo_root, 'git', 'reset', '--hard', 'HEAD')
        if reset.returncode != 0:
            return Result(False, 'git_reset_failed', reset.stderr.strip() or reset.stdout.strip())
        clean = self._run(repo_root, 'git', 'clean', '-fd')
        if clean.returncode != 0:
            return Result(False, 'git_clean_failed', clean.stderr.strip() or clean.stdout.strip())
        status = self.status(repo_root)
        if not status.clean:
            return Result(False, 'workspace_still_dirty', status.message, {'changed_files': status.changed_files})
        return Result(True, 'workspace_reset', 'workspace reset to HEAD')
