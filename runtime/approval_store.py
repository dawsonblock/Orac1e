"""
Approval store for Oracle Build v5.

This module provides the core approval and promotion functionality
for code change management. It wraps the underlying persistence layer
and provides a clean API for the approval flow.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# Re-export key functions from coding_run_promotion for backward compatibility
# This ensures imports like `from runtime.approval_store import promote_run` work
#
# NOTE: There is no separate approve_run() - approval and promotion happen together.
# Use promote_run() to approve AND promote, or reject_run() to reject.
from scripts.coding_run_promotion import (
    APPROVALS_FILE,
    EVENTS_FILE,
    PROMOTIONS_FILE,
    RUNS_FILE,
    PromotionError,
    PromotionResult,
    RunPaths,
    promote_run,
    reject_run,
)

logger = logging.getLogger(__name__)

# Root paths
ROOT = Path(__file__).resolve().parents[1]
RUNS_ROOT = ROOT / "workspace" / "runs"
RUN_METADATA_DIR = RUNS_ROOT / "metadata"


def now_iso() -> str:
    """Return current UTC time in ISO format."""
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _read_json(path: Path, default: Any) -> Any:
    """Read JSON file or return default if not exists."""
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    """Read JSONL file or return empty list if not exists."""
    if not path.exists():
        return []
    items: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        items.append(json.loads(line))
    return items


@dataclass
class ApprovalRecord:
    """An approval record for a run."""
    run_id: str
    decision: str  # "approved" or "rejected"
    actor: str
    note: str
    timestamp: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "decision": self.decision,
            "actor": self.actor,
            "note": self.note,
            "at": self.timestamp,
        }


@dataclass
class RunState:
    """Current state of a run including approvals."""
    run_id: str
    status: str
    approvals: list[ApprovalRecord]
    promotions: list[dict[str, Any]]
    events: list[dict[str, Any]]


class ApprovalStore:
    """
    Store for managing run approvals and promotions.
    
    This is the primary interface for the approval flow:
    - Query run state
    - Record approvals
    - Record rejections
    - Execute promotions
    """
    
    def __init__(self, runs_root: Path | None = None) -> None:
        self.runs_root = runs_root or RUNS_ROOT
        self.runs_file = self.runs_root / "runs.json"
        self.events_file = self.runs_root / "events.jsonl"
        self.approvals_file = self.runs_root / "approvals.jsonl"
        self.promotions_file = self.runs_root / "promotions.jsonl"
    
    def get_run(self, run_id: str) -> dict[str, Any] | None:
        """Get a run by ID."""
        for item in _read_json(self.runs_file, []):
            if item.get("id") == run_id:
                return item
        return None
    
    def get_run_state(self, run_id: str) -> RunState | None:
        """Get full state of a run including approvals and events."""
        run = self.get_run(run_id)
        if not run:
            return None
        
        approvals = [
            ApprovalRecord(
                run_id=item.get("run_id", run_id),
                decision=item.get("decision", ""),
                actor=item.get("actor", ""),
                note=item.get("note", ""),
                timestamp=item.get("at", ""),
            )
            for item in _read_jsonl(self.approvals_file)
            if item.get("run_id") == run_id or item.get("runID") == run_id
        ]
        
        promotions = [
            item for item in _read_jsonl(self.promotions_file)
            if item.get("run_id") == run_id or item.get("runID") == run_id
        ]
        
        events = [
            item for item in _read_jsonl(self.events_file)
            if item.get("run_id") == run_id or item.get("runID") == run_id
        ]
        
        return RunState(
            run_id=run_id,
            status=run.get("status", "unknown"),
            approvals=approvals,
            promotions=promotions,
            events=events,
        )
    
    def is_approved(self, run_id: str) -> bool:
        """Check if a run has been approved."""
        state = self.get_run_state(run_id)
        if not state:
            return False
        return any(a.decision == "approved" for a in state.approvals)
    
    def is_rejected(self, run_id: str) -> bool:
        """Check if a run has been rejected."""
        state = self.get_run_state(run_id)
        if not state:
            return False
        return any(a.decision == "rejected" for a in state.approvals)
    
    def list_runs(self) -> list[dict[str, Any]]:
        """List all runs."""
        return _read_json(self.runs_file, [])
    
    def list_awaiting_approval(self) -> list[dict[str, Any]]:
        """List runs waiting for approval."""
        runs = self.list_runs()
        result = []
        for run in runs:
            run_id = run.get("id")
            if not run_id:
                continue
            state = self.get_run_state(run_id)
            if state and state.status == "awaiting_approval":
                result.append(run)
        return result


# Global instance for convenience
_default_store: ApprovalStore | None = None


def get_store() -> ApprovalStore:
    """Get the default approval store instance."""
    global _default_store
    if _default_store is None:
        _default_store = ApprovalStore()
    return _default_store


# Convenience functions that use the default store
def get_run_state(run_id: str) -> RunState | None:
    """Get state of a run."""
    return get_store().get_run_state(run_id)


def is_approved(run_id: str) -> bool:
    """Check if run is approved."""
    return get_store().is_approved(run_id)


def is_rejected(run_id: str) -> bool:
    """Check if run is rejected."""
    return get_store().is_rejected(run_id)


def list_awaiting_approval() -> list[dict[str, Any]]:
    """List runs waiting for approval."""
    return get_store().list_awaiting_approval()


# Approval workflow functions
# NOTE: promote_run() handles BOTH approval AND promotion together.
# There is no separate "approve only" step in this workflow.


def record_rejection(run_id: str, actor: str = "operator", note: str = "") -> dict[str, Any]:
    """Record a rejection for a run."""
    return reject_run(run_id, actor, note)


def execute_promotion(run_id: str) -> PromotionResult:
    """Execute promotion for an approved run."""
    return promote_run(run_id)


__all__ = [
    # Core classes
    "ApprovalStore",
    "ApprovalRecord",
    "RunState",
    "PromotionResult",
    "PromotionError",
    # Functions
    "get_store",
    "get_run_state",
    "is_approved",
    "is_rejected",
    "list_awaiting_approval",
    # Workflow functions (promote_run handles approval+promotion together)
    "promote_run",
    "reject_run",
    # Constants
    "APPROVALS_FILE",
    "EVENTS_FILE",
    "PROMOTIONS_FILE",
    "RUNS_FILE",
]
