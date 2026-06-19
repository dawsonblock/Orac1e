from __future__ import annotations

import subprocess
from pathlib import Path

from runtime.common.result import Result
from runtime.events.schemas import PatchArtifact


class PatchPreflight:
    def run(self, repo_root: Path, artifact: PatchArtifact) -> Result:
        # The patch is already applied in the worktree. Validate git state and changed files.
        for path in artifact.changed_files:
            if not (repo_root / path).exists():
                return Result(False, "missing_file", f"changed file missing: {path}")
        try:
            subprocess.run(["git", "-C", str(repo_root), "diff", "--check"], check=True, capture_output=True, text=True)
            return Result(True, "ok", "preflight passed")
        except subprocess.CalledProcessError as exc:
            return Result(False, "git_diff_check_failed", exc.stderr or exc.stdout or str(exc))
