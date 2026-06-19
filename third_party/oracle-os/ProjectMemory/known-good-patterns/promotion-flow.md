# Promotion Flow Pattern

## Intent

Oracle Build v5 implements an **approval-gated promotion flow** where code changes progress from isolated worktrees to the canonical repository only after explicit operator approval. The flow is designed for **idempotency** - repeated calls produce the same result - and **atomic rollback** on failure.

## Motivation

Promoting code from a worktree to canonical requires careful coordination:

| Concern | Solution |
|---------|----------|
| Unauthorized changes | Approval gate before apply |
| Failed apply corrupts canonical | Atomic rollback on failure |
| Duplicate promotion attempts | Idempotent status checks |
| Audit trail | Persistent receipts for all decisions |
| Worktree lifecycle | Automatic cleanup after success |

## State Machine

```
                    ┌─────────────────────────────────────────────────────┐
                    │                  State Transitions                   │
                    └─────────────────────────────────────────────────────┘

    ┌──────────┐     ┌──────────────────┐     ┌───────────────────┐
    │          │     │                  │     │                   │
    │ created  │────▶│     running      │────▶│ awaiting_approval │
    │          │     │                  │     │                   │
    └──────────┘     └──────────────────┘     └─────────┬─────────┘
                                                        │
                                        ┌───────────────┴───────────────┐
                                        │                               │
                                        ▼                               ▼
                            ┌───────────────────┐           ┌───────────────────┐
                            │                   │           │                   │
                            │     applied       │           │     rejected      │
                            │                   │           │                   │
                            └───────────────────┘           └───────────────────┘

    Transitions:
    ────────────
    created → running: Oracle creates worktree, routes to worker
    running → awaiting_approval: Worker returns proposal, Oracle validates
    awaiting_approval → applied: Operator approves, patch applied, validated
    awaiting_approval → rejected: Operator rejects
    applied → failed: (rollback from promotion failure)
```

## Promotion Implementation ([`scripts/coding_run_promotion.py`](../../../../scripts/coding_run_promotion.py:208))

### Core Promotion Function

```python
@dataclass
class PromotionResult:
    run_id: str
    canonical_repo: str
    promotion_commit: str
    status: str
    validation_ok: bool
    receipt_path: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "canonical_repo": self.canonical_repo,
            "promotion_commit": self.promotion_commit,
            "status": self.status,
            "validation_ok": self.validation_ok,
            "receipt_path": self.receipt_path,
        }

def promote_run(
    run_id: str,
    actor: str = "operator",
    note: str = "",
    cleanup_worktree: bool = True
) -> PromotionResult:
    """Promote an approved run into the canonical repository."""
    
    # Load run state
    run = _load_run(run_id)
    metadata = _load_metadata(run_id)
    canonical_repo = Path(metadata.get("canonicalRepoPath"))
    worktree_repo = Path(metadata.get("worktreePath"))
    validation_commands = list(metadata.get("validationCommands") or [])

    # Idempotency: Already applied?
    current_status = run.get("status")
    if current_status == "applied":
        paths = _paths_for(run_id)
        if paths.promotion_receipt_path.exists():
            existing = _read_json(paths.promotion_receipt_path, {})
            return PromotionResult(
                run_id=run_id,
                canonical_repo=existing.get("canonical_repo", str(canonical_repo)),
                promotion_commit=existing.get("promotion_commit", ""),
                status="applied",
                validation_ok=existing.get("validation_ok", False),
                receipt_path=str(paths.promotion_receipt_path),
            )
        raise PromotionError(f"run {run_id} is already applied but receipt is missing")

    # Precondition check
    if current_status not in ("awaiting_approval", "running"):
        raise PromotionError(
            f"run {run_id} is not awaiting approval (current status: {current_status})"
        )

    # Safety: Canonical must be clean
    if not _repo_is_clean(canonical_repo):
        raise PromotionError("canonical repo is dirty; refusing promotion")

    # Validate lineage
    base_commit = _validate_worktree_lineage(canonical_repo, worktree_repo)
    
    # Record approval
    approval = _record_approval(run_id, "approved", actor, note)
    _record_event(run_id, "approval.recorded", approval)

    try:
        # Apply patch...
        # (see validation-pipeline.md for full flow)
        
        # On success
        run["status"] = "applied"
        _replace_run(run)
        
        receipt = {
            "run_id": run_id,
            "actor": actor,
            "note": note,
            "at": now_iso(),
            "base_commit": base_commit,
            "promotion_commit": promotion_commit,
            "canonical_repo": str(canonical_repo),
            "worktree_repo": str(worktree_repo),
            "status": "applied",
            "validation_ok": True,
            "patch_file": str(patch_file),
        }
        _record_promotion(run_id, receipt)
        _record_event(run_id, "promotion.completed", receipt)

        # Cleanup worktree
        if cleanup_worktree:
            _run(["git", "-C", str(canonical_repo), "worktree", "remove", 
                  "--force", str(worktree_repo)], check=False)
            shutil.rmtree(worktree_repo, ignore_errors=True)

        return PromotionResult(..., validation_ok=True, ...)
        
    except Exception as exc:
        # Atomic rollback
        _run(["git", "-C", str(canonical_repo), "reset", "--hard", "HEAD"], check=False)
        _run(["git", "-C", str(canonical_repo), "clean", "-fd"], check=False)
        
        run["status"] = "failed"
        _replace_run(run)
        
        receipt = {
            "run_id": run_id,
            "status": "failed",
            "validation_ok": False,
            "error": str(exc),
            ...
        }
        _record_promotion(run_id, receipt)
        _record_event(run_id, "promotion.failed", receipt)
        raise PromotionError(str(exc))
```

## Rejection Flow

```python
def reject_run(
    run_id: str,
    actor: str = "operator",
    note: str = ""
) -> dict[str, Any]:
    """Reject a run without applying the patch."""
    
    run = _load_run(run_id)
    current_status = run.get("status")
    
    # Idempotency: Already rejected?
    if current_status == "rejected":
        paths = _paths_for(run_id)
        if paths.approval_receipt_path.exists():
            return _read_json(paths.approval_receipt_path, {})
        raise PromotionError(f"run {run_id} is already rejected but receipt is missing")
    
    # Can't reject already applied
    if current_status == "applied":
        raise PromotionError(f"run {run_id} is already applied")
    
    # Record rejection
    approval = _record_approval(run_id, "rejected", actor, note)
    run["status"] = "rejected"
    _replace_run(run)
    _record_event(run_id, "approval.rejected", approval)
    
    return approval
```

## Receipt Persistence

Receipts provide audit trails and enable idempotent operations:

```python
def _record_approval(run_id: str, decision: str, actor: str, note: str) -> dict[str, Any]:
    """Record approval decision to both JSONL and individual file."""
    receipt = {
        "run_id": run_id,
        "decision": decision,  # "approved" or "rejected"
        "actor": actor,
        "note": note,
        "at": now_iso(),
    }
    _append_jsonl(APPROVALS_FILE, receipt)
    _write_json(_paths_for(run_id).approval_receipt_path, receipt)
    return receipt

def _record_promotion(run_id: str, receipt: dict[str, Any]) -> None:
    """Record promotion result to both JSONL and individual file."""
    _append_jsonl(PROMOTIONS_FILE, receipt)
    _write_json(_paths_for(run_id).promotion_receipt_path, receipt)

def _paths_for(run_id: str) -> RunPaths:
    """Compute all receipt paths for a run."""
    return RunPaths(
        metadata_path=RUN_METADATA_DIR / f"{run_id}.json",
        approval_receipt_path=RUNS_ROOT / "approvals" / f"{run_id}.json",
        promotion_receipt_path=RUNS_ROOT / "promotions" / f"{run_id}.json",
    )
```

## Approval Receipt Structure

```json
{
  "run_id": "run-abc123",
  "decision": "approved",
  "actor": "operator",
  "note": "Looks good, ship it",
  "at": "2024-01-15T10:30:00Z"
}
```

## Promotion Receipt Structure

```json
{
  "run_id": "run-abc123",
  "actor": "operator",
  "note": "Looks good, ship it",
  "at": "2024-01-15T10:30:00Z",
  "base_commit": "abc123def",
  "promotion_commit": "789xyz012",
  "canonical_repo": "/path/to/canonical",
  "worktree_repo": "/path/to/worktrees/run-abc123",
  "status": "applied",
  "validation_ok": true,
  "patch_file": "/path/to/artifacts/run-abc123.patch"
}
```

## Worktree Lineage Validation

Before promotion, ensure worktree is still based on canonical HEAD:

```python
def _validate_worktree_lineage(canonical_repo: Path, worktree_repo: Path) -> str:
    """Ensure worktree hasn't diverged from canonical HEAD."""
    canonical_head = _git(canonical_repo, "rev-parse", "HEAD")
    worktree_head = _git(worktree_repo, "rev-parse", "HEAD")
    if canonical_head != worktree_head:
        raise PromotionError(
            "worktree base no longer matches canonical repo HEAD; refusing promotion"
        )
    return canonical_head
```

## CLI Interface

```bash
# Promote a run
python scripts/coding_run_promotion.py run-abc123 \
    --actor operator \
    --note "Approved for shipping"

# Reject a run
python scripts/coding_run_promotion.py run-abc123 \
    --actor operator \
    --note "Needs more testing" \
    --reject

# Keep worktree after promotion (for debugging)
python scripts/coding_run_promotion.py run-abc123 \
    --actor operator \
    --keep-worktree
```

## Idempotency Guarantees

| Scenario | Behavior |
|----------|----------|
| Promote already-applied run | Returns existing receipt, no-op |
| Reject already-rejected run | Returns existing receipt, no-op |
| Promote with dirty canonical | Error before any changes |
| Promote divergent worktree | Error before any changes |
| Promote after rejection | Error |

## Testing Pattern

```python
# From tests/e2e/test_validation_flow.py
class TestValidationFlowApprovals:
    def test_validation_flow_persists_approval_receipt(self, promotion_env):
        """Approval receipt is persisted with correct decision."""
        crp.promote_run(promotion_env["run_id"], actor="tester", note="ok")

        approvals_path = (
            promotion_env["runs_root"] / "approvals" / f"{promotion_env['run_id']}.json"
        )
        receipt = json.loads(approvals_path.read_text())
        
        assert receipt["decision"] == "approved"
        assert receipt["actor"] == "tester"
        assert "at" in receipt

    def test_rejection_creates_approval_receipt(self, promotion_env):
        """Rejection creates receipt with rejected decision."""
        crp.reject_run(promotion_env["run_id"], actor="reviewer", note="needs work")

        approvals_path = (
            promotion_env["runs_root"] / "approvals" / f"{promotion_env['run_id']}.json"
        )
        receipt = json.loads(approvals_path.read_text())

        assert receipt["decision"] == "rejected"
        assert receipt["actor"] == "reviewer"
        assert receipt["note"] == "needs work"
```

## Key Invariants

1. **Canonical must be clean** before promotion
2. **Worktree must match canonical HEAD** before promotion
3. **Approval receipt is always persisted** before apply
4. **Failure triggers atomic rollback** via `git reset --hard HEAD`
5. **Promotion is idempotent** - repeated calls return same result
6. **Run status is source of truth** for current state

## Related Patterns

- [Validation Pipeline](validation-pipeline.md) - How patches are validated before/after apply
- [Worktree Isolation](worktree-isolation.md) - How worktrees enable safe experimentation