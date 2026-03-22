from __future__ import annotations

from pathlib import Path

from runtime.common.result import Result
from .worktree_manager import WorktreeManager


class CleanupService:
    def __init__(self, manager: WorktreeManager):
        self.manager = manager

    def cleanup_workspace(self, workspace_path: Path) -> Result:
        return self.manager.remove_worktree(workspace_path)
