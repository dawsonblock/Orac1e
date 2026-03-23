from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

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


def _read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    items = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        items.append(json.loads(line))
    return items


class ApprovalBody(BaseModel):
    actor: str = "operator"
    note: str = ""


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


def _enrich_run_with_detail(run: dict[str, Any]) -> dict[str, Any]:
    """Enrich a run with associated events, approvals, and promotions."""
    run_id = run.get("id")
    if not run_id:
        return run
    
    events = [item for item in _read_jsonl(EVENTS_FILE) if item.get("runID") == run_id or item.get("run_id") == run_id]
    approvals = [item for item in _read_jsonl(APPROVALS_FILE) if item.get("runID") == run_id or item.get("run_id") == run_id]
    promotions = [item for item in _read_jsonl(PROMOTIONS_FILE) if item.get("runID") == run_id or item.get("run_id") == run_id]
    
    enriched = dict(run)
    enriched["_events"] = events
    enriched["_approvals"] = approvals
    enriched["_promotions"] = promotions
    return enriched


@app.get("/runs")
def list_runs() -> list[dict[str, Any]]:
    """List all runs with enriched detail including events, approvals, and promotions."""
    runs = _read_json(RUNS_FILE, [])
    if not runs:
        return []

    # Build per-run-id indexes once instead of re-scanning JSONL files for every run.
    def _index_by_run(path: Path) -> dict[str, list[dict[str, Any]]]:
        idx: dict[str, list[dict[str, Any]]] = {}
        for item in _read_jsonl(path):
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
    for item in _read_json(RUNS_FILE, []):
        if item.get("id") == run_id:
            return _enrich_run_with_detail(item)
    raise HTTPException(status_code=404, detail="run not found")


@app.get("/runs/{run_id}/events")
def get_events(run_id: str) -> list[dict[str, Any]]:
    return [item for item in _read_jsonl(EVENTS_FILE) if item.get("runID") == run_id or item.get("run_id") == run_id]


@app.get("/runs/{run_id}/approvals")
def get_approvals(run_id: str) -> list[dict[str, Any]]:
    return [item for item in _read_jsonl(APPROVALS_FILE) if item.get("runID") == run_id or item.get("run_id") == run_id]


@app.get("/runs/{run_id}/promotions")
def get_promotions(run_id: str) -> list[dict[str, Any]]:
    return [item for item in _read_jsonl(PROMOTIONS_FILE) if item.get("runID") == run_id or item.get("run_id") == run_id]


@app.post("/runs/{run_id}/approve")
def approve(run_id: str, body: ApprovalBody) -> dict[str, Any]:
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
def reject_endpoint(run_id: str, body: ApprovalBody) -> dict[str, Any]:
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
