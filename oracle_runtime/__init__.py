"""
Oracle Runtime package for Orac1e Control Plane.

Single canonical runtime module. All implementation lives in
scripts.coding_run_promotion; this package re-exports the public API.
"""

__version__ = "0.2.0"

from oracle_runtime.approval_store import (
    ApprovalRecord,
    ApprovalStore,
    RunState,
    get_run_state,
    get_store,
    is_approved,
    is_rejected,
    list_awaiting_approval,
    promote_run,
    reject_run,
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
