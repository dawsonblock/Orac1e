from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from runtime.common.result import Result


class WorktreeManager:
    def __init__(self, workspaces_root: Path):
        self.workspaces_root = Path(workspaces_root)
        self.workspaces_root.mkdir(parents=True, exist_ok=True)

    def create_worktree(self, repo_dir: Path, base_ref: str, branch_name: str) -> Path:
        sanitized_branch_name = branch_name.replace("/", "_")
        target = self.workspaces_root / sanitized_branch_name
        # Ensure the target path is within the workspaces_root to prevent path traversal
        try:
            target.resolve().relative_to(self.workspaces_root.resolve())
        except ValueError:
            raise ValueError(f"Invalid branch name {branch_name!r} leads to path outside of workspaces root")
        if target.exists():
            shutil.rmtree(target)
        subprocess.run(["git", "-C", str(repo_dir), "worktree", "add", "-b", branch_name, str(target), base_ref], check=True, capture_output=True, text=True)
        (target / ".agent_workspace").write_text("managed\n", encoding="utf-8")
        return target

    def remove_worktree(self, workspace_path: Path) -> Result:
        workspace_path = Path(workspace_path)
        try:
            workspace_path.relative_to(self.workspaces_root)
        except ValueError:
            return Result(False, "unsafe_path", "workspace path escapes managed root")
        if not (workspace_path / ".agent_workspace").exists():
            return Result(False, "missing_marker", "workspace marker missing")
        try:
            subprocess.run(["git", "worktree", "remove", "--force", str(workspace_path)], check=True, capture_output=True, text=True)
            return Result(True, "ok", "removed worktree")
        except subprocess.CalledProcessError:
            shutil.rmtree(workspace_path, ignore_errors=True)
            return Result(True, "ok", "removed worktree by fallback")
