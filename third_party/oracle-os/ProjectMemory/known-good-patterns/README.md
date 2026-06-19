# Known Good Patterns

Reusable engineering patterns with repeated verified success belong here.

These records should be promoted from repeated evidence, not one-off wins.

## Patterns Index

| Pattern | Description | Key Files |
|---------|-------------|-----------|
| [Dual-Worker Architecture](dual-worker-architecture.md) | Aider (interactive) + Hardened (autonomous) worker pattern | [`integration/worker_hardened/bridge.py`](../../../../integration/worker_hardened/bridge.py), [`integration/worker_hardened/service.py`](../../../../integration/worker_hardened/service.py) |
| [Manifest-Driven Tool Discovery](manifest-tool-discovery.md) | Self-describing tools via `tool.json` manifests | [`integration/tool_sdk/registry.py`](../../../../integration/tool_sdk/registry.py), [`integration/tool_sdk/validators.py`](../../../../integration/tool_sdk/validators.py) |
| [Validation Pipeline](validation-pipeline.md) | Multi-stage validation with artifact persistence | [`scripts/coding_run_promotion.py`](../../../../scripts/coding_run_promotion.py), [`tests/e2e/test_validation_flow.py`](../../../../tests/e2e/test_validation_flow.py) |
| [Promotion Flow](promotion-flow.md) | Approval-gated promotion with rollback safety | [`scripts/coding_run_promotion.py`](../../../../scripts/coding_run_promotion.py), [`docs/promotion_flow.md`](../../../docs/promotion_flow.md) |
| [Worktree Isolation](worktree-isolation.md) | Disposable worktrees per run with canonical protection | [`docs/worktree_model.md`](../../../docs/worktree_model.md) |

## Pattern Summary

### Dual-Worker Architecture
Oracle Build v5 uses a dual-worker model where:
- **Aider** handles interactive pair-programming sessions
- **Hardened** handles bounded autonomous issue resolution

Both workers return **proposals** (diffs) rather than direct edits. Oracle retains authority over validation and approval.

### Manifest-Driven Tool Discovery
Tools declare capabilities via `tool.json` manifests. Oracle discovers tools through `ToolRegistry`, selects by capability, and invokes through a generic `/invoke` envelope. This decouples tool implementation from tool selection.

### Validation Pipeline
Validation runs in two phases: worktree validation before patch application, then canonical validation after. All validation steps produce artifacts that persist for debugging and audit.

### Promotion Flow
Promotion is approval-gated with idempotent behavior. Runs transition through states (`running` → `awaiting_approval` → `applied`/`rejected`). Failed promotions rollback atomically.

### Worktree Isolation
Each run gets a disposable worktree. Workers never touch the canonical repo. Apply happens only after Oracle approval. This ensures safe experimentation with zero risk to canonical state.
