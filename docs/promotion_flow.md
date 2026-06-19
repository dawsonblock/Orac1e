# Promotion flow

Approved runs now promote through the Python run server bridge.

Flow:

1. Oracle writes `workspace/runs/runs.json`, `events.jsonl`, and `metadata/<run_id>.json`.
2. `IntegratedCodingRunService` stops at `awaiting_approval` after validation succeeds.
3. `POST /runs/{id}/approve` records approval, validates the worktree again, applies the patch into the canonical repo, reruns validation there, commits the result, writes a promotion receipt, and removes the disposable worktree.
4. `POST /runs/{id}/reject` records the rejection and marks the run rejected.

Receipts live under:

- `workspace/runs/approvals/<run_id>.json`
- `workspace/runs/promotions/<run_id>.json`
- `workspace/runs/validation/<run_id>.worktree.json`
- `workspace/runs/validation/<run_id>.canonical.json`
