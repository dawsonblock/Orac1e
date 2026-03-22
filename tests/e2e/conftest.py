from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from scripts import coding_run_promotion as crp


@pytest.fixture()
def promotion_env(tmp_path, monkeypatch):
    root = tmp_path / "repo"
    workspace_runs = root / "workspace" / "runs"
    metadata_dir = workspace_runs / "metadata"
    metadata_dir.mkdir(parents=True, exist_ok=True)

    canonical = root / "canonical"
    canonical.mkdir()
    (canonical / "app.py").write_text("print('hello')\n", encoding="utf-8")
    subprocess.run(["git", "init", str(canonical)], check=True, capture_output=True, text=True)
    subprocess.run(["git", "-C", str(canonical), "config", "user.name", "Test User"], check=True)
    subprocess.run(["git", "-C", str(canonical), "config", "user.email", "test@example.com"], check=True)
    subprocess.run(["git", "-C", str(canonical), "add", "app.py"], check=True)
    subprocess.run(["git", "-C", str(canonical), "commit", "-m", "baseline"], check=True, capture_output=True, text=True)

    run_id = "run-123"
    worktree = root / "workspace" / "worktrees" / run_id
    worktree.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "-C", str(canonical), "worktree", "add", "--detach", str(worktree), "HEAD"], check=True, capture_output=True, text=True)

    runs = [{
        "id": run_id,
        "repoName": "demo",
        "repoPath": str(canonical),
        "mode": "interactive",
        "status": "awaiting_approval",
        "task": "update app",
        "createdAt": "2026-03-21T00:00:00Z",
    }]
    (workspace_runs / "runs.json").write_text(json.dumps(runs, indent=2), encoding="utf-8")
    metadata = {
        "runID": run_id,
        "canonicalRepoPath": str(canonical),
        "worktreePath": str(worktree),
        "validationCommands": ["python -m py_compile app.py"],
        "allowedPaths": ["app.py"],
        "retrievalQuery": "app",
        "workerMode": "interactive",
        "createdAt": "2026-03-21T00:00:00Z",
    }
    (metadata_dir / f"{run_id}.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    monkeypatch.setattr(crp, "ROOT", root)
    monkeypatch.setattr(crp, "RUNS_ROOT", workspace_runs)
    monkeypatch.setattr(crp, "RUNS_FILE", workspace_runs / "runs.json")
    monkeypatch.setattr(crp, "EVENTS_FILE", workspace_runs / "events.jsonl")
    monkeypatch.setattr(crp, "APPROVALS_FILE", workspace_runs / "approvals.jsonl")
    monkeypatch.setattr(crp, "PROMOTIONS_FILE", workspace_runs / "promotions.jsonl")
    monkeypatch.setattr(crp, "RUN_METADATA_DIR", metadata_dir)

    return {
        "root": root,
        "runs_root": workspace_runs,
        "run_id": run_id,
        "canonical": canonical,
        "worktree": worktree,
        "metadata_dir": metadata_dir,
    }
