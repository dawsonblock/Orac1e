"""
Approval store for Oracle Build v5.

Thin re-export facade. All implementation lives in scripts.coding_run_promotion.
This module exists so that ``from oracle_runtime.approval_store import ...`` works
as a single canonical import path for the runtime layer.
"""

from __future__ import annotations

from scripts.coding_run_promotion import (
    ApprovalRecord,
    ApprovalStore,
    RunState,
    promote_run,
    reject_run,
    get_store,
    get_run_state,
    is_approved,
    is_rejected,
    list_awaiting_approval,
)

__all__ = [
    "ApprovalStore",
    "ApprovalRecord",
    "RunState",
    "promote_run",
    "reject_run",
    "get_store",
    "get_run_state",
    "is_approved",
    "is_rejected",
    "list_awaiting_approval",
]
