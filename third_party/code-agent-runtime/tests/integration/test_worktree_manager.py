import subprocess
from pathlib import Path

from runtime.workspace.worktree_manager import WorktreeManager


def init_repo(path: Path):
    subprocess.run(["git", "init", "-b", "main"], cwd=path, check=True, capture_output=True, text=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=path, check=True, capture_output=True, text=True)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=path, check=True, capture_output=True, text=True)
    (path / "README.md").write_text("hello\n", encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=path, check=True, capture_output=True, text=True)
    subprocess.run(["git", "commit", "-m", "init"], cwd=path, check=True, capture_output=True, text=True)


def test_create_and_remove_worktree(tmp_path: Path):
    repo = tmp_path / "repo"
    repo.mkdir()
    init_repo(repo)
    manager = WorktreeManager(tmp_path / "workspaces")
    ws = manager.create_worktree(repo, "main", "agent/test-01")
    assert ws.exists()
    assert (ws / ".agent_workspace").exists()
    res = manager.remove_worktree(ws)
    assert res.ok
