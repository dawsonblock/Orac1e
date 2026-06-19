from __future__ import annotations

import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel

from integration.security.approval_auth import require_approval_token
from integration.shared_json import append_jsonl, read_json, read_jsonl, write_json
from scripts.coding_run_promotion import (
    APPROVALS_FILE,
    EVENTS_FILE,
    PROMOTIONS_FILE,
    RUNS_FILE,
    PromotionError,
    promote_run,
    reject_run,
)

ROOT = Path(__file__).resolve().parents[1]
RUNS_ROOT = ROOT / "workspace" / "runs"

app = FastAPI(title="coding-runs")

_RUN_ID_RE = re.compile(r"^[a-zA-Z0-9_-]+$")


class ApprovalBody(BaseModel):
    actor: str = "operator"
    note: str = ""


class CreateRunBody(BaseModel):
    repo_path: str
    task: str
    validation_commands: list[str] = ["pytest -q"]
    mode: str = "commit"
    allowed_paths: list[str] | None = None


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/ready")
def ready() -> dict[str, str]:
    """Readiness check - verifies data stores are accessible."""
    try:
        read_json(RUNS_FILE, [])
        return {"status": "ready"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"not ready: {e}")


@app.post("/runs")
def create_run(body: CreateRunBody) -> dict[str, Any]:
    """Create a new coding run and record run.created event."""
    if not body.repo_path or not body.task:
        raise HTTPException(status_code=400, detail="repo_path and task are required")
    if not body.validation_commands:
        raise HTTPException(status_code=400, detail="validation_commands cannot be empty")
    if body.mode not in ("commit", "sandbox"):
        raise HTTPException(status_code=400, detail=f"mode must be 'commit' or 'sandbox', got '{body.mode}'")

    now = datetime.now(timezone.utc).isoformat()
    run_id = f"run-{int(datetime.now(timezone.utc).timestamp())}"

    if not _RUN_ID_RE.match(run_id):
        raise HTTPException(status_code=400, detail="invalid run_id generated")

    run_dir = RUNS_ROOT / "runs" / run_id
    if run_dir.exists():
        raise HTTPException(status_code=409, detail="run already exists")

    # Create run entry
    run: dict[str, Any] = {
        "id": run_id,
        "repoPath": body.repo_path,
        "task": body.task,
        "validationCommands": body.validation_commands,
        "status": "created",
        "mode": body.mode,
        "createdAt": now,
        "updatedAt": now,
    }
    if body.allowed_paths is not None:
        run["allowedPaths"] = body.allowed_paths

    # Persist runs.json
    runs_list = read_json(RUNS_FILE, [])
    runs_list.append(run)
    write_json(RUNS_FILE, runs_list)

    # Create metadata file
    run_dir.mkdir(parents=True, exist_ok=True)
    metadata_dir = RUNS_ROOT / "metadata"
    metadata_dir.mkdir(parents=True, exist_ok=True)
    write_json(metadata_dir / f"{run_id}.json", run)

    # Create worktree directory
    (run_dir / "worktree").mkdir(parents=True, exist_ok=True)

    # Record event
    event = {"run_id": run_id, "event": "run.created", "timestamp": now, "task": body.task}
    append_jsonl(EVENTS_FILE, event)

    # Initialize git repo if repo_path exists
    repo_path = ROOT / body.repo_path
    if repo_path.is_dir():
        if not (repo_path / ".git").exists():
            subprocess.run(["git", "init", str(repo_path)], check=False, capture_output=True)
            subprocess.run(["git", "-C", str(repo_path), "add", "."], check=False, capture_output=True)
            subprocess.run(["git", "-C", str(repo_path), "commit", "-m", "initial fixture state"], check=False, capture_output=True)

    return {"ok": True, "run_id": run_id, "status": "created"}


def _enrich_run_with_detail(run: dict[str, Any]) -> dict[str, Any]:
    """Enrich a run with associated events, approvals, and promotions."""
    run_id = run.get("id")
    if not run_id:
        return run
    
    events = [item for item in read_jsonl(EVENTS_FILE) if item.get("runID") == run_id or item.get("run_id") == run_id]
    approvals = [item for item in read_jsonl(APPROVALS_FILE) if item.get("runID") == run_id or item.get("run_id") == run_id]
    promotions = [item for item in read_jsonl(PROMOTIONS_FILE) if item.get("runID") == run_id or item.get("run_id") == run_id]
    
    enriched = dict(run)
    enriched["_events"] = events
    enriched["_approvals"] = approvals
    enriched["_promotions"] = promotions
    return enriched


@app.get("/runs")
def list_runs() -> list[dict[str, Any]]:
    """List all runs with enriched detail including events, approvals, and promotions."""
    runs = read_json(RUNS_FILE, [])
    if not runs:
        return []

    # Build per-run-id indexes once instead of re-scanning JSONL files for every run.
    def _index_by_run(path: Path) -> dict[str, list[dict[str, Any]]]:
        idx: dict[str, list[dict[str, Any]]] = {}
        for item in read_jsonl(path):
            key = item.get("runID") or item.get("run_id") or ""
            if key:
                idx.setdefault(key, []).append(item)
        return idx

    events_idx = _index_by_run(EVENTS_FILE)
    approvals_idx = _index_by_run(APPROVALS_FILE)
    promotions_idx = _index_by_run(PROMOTIONS_FILE)

    def _enrich_fast(run: dict[str, Any]) -> dict[str, Any]:
        rid = run.get("id") or ""
        enriched = dict(run)
        enriched["_events"] = events_idx.get(rid, [])
        enriched["_approvals"] = approvals_idx.get(rid, [])
        enriched["_promotions"] = promotions_idx.get(rid, [])
        return enriched

    return [_enrich_fast(run) for run in runs]


@app.get("/runs/{run_id}")
def get_run(run_id: str) -> dict[str, Any]:
    """Get a specific run with enriched detail including events, approvals, and promotions."""
    for item in read_json(RUNS_FILE, []):
        if item.get("id") == run_id:
            return _enrich_run_with_detail(item)
    raise HTTPException(status_code=404, detail="run not found")


@app.get("/runs/{run_id}/events")
def get_events(run_id: str) -> list[dict[str, Any]]:
    return [item for item in read_jsonl(EVENTS_FILE) if item.get("runID") == run_id or item.get("run_id") == run_id]


@app.get("/runs/{run_id}/approvals")
def get_approvals(run_id: str) -> list[dict[str, Any]]:
    return [item for item in read_jsonl(APPROVALS_FILE) if item.get("runID") == run_id or item.get("run_id") == run_id]


@app.get("/runs/{run_id}/promotions")
def get_promotions(run_id: str) -> list[dict[str, Any]]:
    return [item for item in read_jsonl(PROMOTIONS_FILE) if item.get("runID") == run_id or item.get("run_id") == run_id]


@app.post("/runs/{run_id}/approve")
def approve(run_id: str, body: ApprovalBody, _auth: None = Depends(require_approval_token)) -> dict[str, Any]:
    """
    Approve a coding run with idempotency guard.
    Returns enriched run detail with events, approvals, and promotions.
    """
    run = get_run(run_id)

    current_status = run.get("status")
    if current_status == "applied":
        return {
            "ok": True,
            "idempotent": True,
            "run": _enrich_run_with_detail(run)
        }

    if current_status == "rejected":
        raise HTTPException(status_code=409, detail="run already rejected")

    if current_status != "awaiting_approval":
        raise HTTPException(status_code=409, detail=f"run not in approvable state (current status: {current_status})")

    try:
        result = promote_run(run_id, actor=body.actor, note=body.note)
    except PromotionError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    updated_run = get_run(run_id)
    return {
        "ok": True,
        "idempotent": False,
        "promotion": result.to_dict(),
        "run": updated_run
    }


@app.post("/runs/{run_id}/reject")
def reject_endpoint(run_id: str, body: ApprovalBody, _auth: None = Depends(require_approval_token)) -> dict[str, Any]:
    """
    Reject a coding run with idempotency guard.
    Returns enriched run detail with events, approvals, and promotions.
    """
    run = get_run(run_id)

    current_status = run.get("status")
    if current_status == "rejected":
        updated_run = get_run(run_id)
        return {
            "ok": True,
            "idempotent": True,
            "run": updated_run
        }

    if current_status == "applied":
        raise HTTPException(status_code=409, detail="run already applied")

    if current_status != "awaiting_approval":
        raise HTTPException(status_code=409, detail=f"run not in rejectable state (current status: {current_status})")

    try:
        result = reject_run(run_id, actor=body.actor, note=body.note)
    except PromotionError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    updated_run = get_run(run_id)
    return {
        "ok": True,
        "idempotent": False,
        "rejection": result,
        "run": updated_run
    }
