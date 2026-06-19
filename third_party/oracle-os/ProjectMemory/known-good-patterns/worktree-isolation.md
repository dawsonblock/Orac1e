# Worktree Isolation Pattern

## Intent

Oracle Build v5 uses **disposable worktrees** to isolate each coding run from the canonical repository. Workers edit only in worktrees, never touching canonical. This enables safe experimentation with zero risk to production code.

## Motivation

Traditional coding agents edit files directly, risking corruption of canonical state. The worktree model provides:

| Concern | Solution |
|---------|----------|
| Worker errors corrupt canonical | Workers never write to canonical |
| Need to revert failed attempts | Delete worktree, canonical untouched |
| Multiple concurrent runs | Separate worktrees per run |
| Parallel experimentation | Each run gets isolated branch |
| Audit trail | Canonical commits only after approval |

## Directory Structure

```
workspace/
├── repos/                    # Canonical repositories
│   └── myproject/
│       ├── .git/
│       └── (source files)
├── worktrees/               # Disposable worktrees per run
│   ├── run-abc123/
│   │   └── (copy of myproject)
│   └── run-def456/
│       └── (copy of myproject)
└── runs/                    # Run state and artifacts
    ├── runs.json
    ├── events.jsonl
    ├── metadata/
    │   └── run-abc123.json
    ├── approvals/
    │   └── run-abc123.json
    ├── promotions/
    │   └── run-abc123.json
    ├── validation/
    │   ├── run-abc123.worktree.json
    │   └── run-abc123.canonical.json
    └── artifacts/
        └── run-abc123.patch
```

## Worktree Lifecycle

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Worktree Lifecycle                                 │
│                                                                     │
│  1. Oracle creates run + worktree                                   │
│              │                                                       │
│              ▼                                                       │
│  ┌──────────────────────┐                                          │
│  │   Oracle owns both   │                                          │
│  │   canonical + worktree│                                          │
│  └──────────┬───────────┘                                          │
│             │                                                        │
│             ▼                                                        │
│  2. Worker edits ONLY worktree                                      │
│              │                                                       │
│              ▼                                                       │
│  3. Oracle validates in worktree                                    │
│              │                                                       │
│              ├──────────────────────────────────────┐                │
│              │                                      │                │
│              ▼                                      ▼                │
│  ┌──────────────────────┐              ┌──────────────────────┐   │
│  │  Validation passes   │              │  Validation fails    │   │
│  └──────────┬───────────┘              └──────────────────────┘   │
│             │                                      │                 │
│             ▼                                      ▼                 │
│  4a. Operator approves                          4b. Discard         │
│             │                                      │                 │
│             ▼                                      ▼                 │
│  ┌──────────────────────┐              ┌──────────────────────┐   │
│  │  Apply to canonical  │              │  Delete worktree    │   │
│  │  Validate canonical  │              │  (nothing to clean) │   │
│  │  Commit to canonical  │              └──────────────────────┘   │
│  │  Delete worktree      │                                          │
│  └──────────────────────┘                                          │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Invariants

From [`docs/worktree_model.md`](../../../docs/worktree_model.md):

> 1. **Workers never edit the canonical repo**
> 2. **A proposal is always generated against a worktree**
> 3. **Apply happens only after Oracle approval**
> 4. **Failed runs keep artifacts; the worktree can then be deleted**

## Worktree Creation

Worktrees are created using `git worktree add`:

```bash
# Oracle creates worktree for run
cd canonical-repo
git worktree add \
    --checkout \
    workspace/worktrees/run-abc123 \
    HEAD

# Worktree now has identical content to canonical at HEAD
# But it's a separate working directory with its own .git file
```

## Worktree Cleanup

After successful promotion, worktrees are removed:

```python
# From scripts/coding_run_promotion.py:289
if cleanup_worktree:
    try:
        _run([
            "git", "-C", str(canonical_repo),
            "worktree", "remove", "--force",
            str(worktree_repo)
        ], check=False)
    finally:
        shutil.rmtree(worktree_repo, ignore_errors=True)
```

### Cleanup Scenarios

| Scenario | Cleanup Action |
|----------|----------------|
| Promotion succeeds | Remove worktree, preserve artifacts |
| Promotion fails | Remove worktree after rollback |
| Run rejected | Remove worktree (optional) |
| Operator debugging | `--keep-worktree` flag preserves |

## Lineage Validation

Before promotion, verify worktree is still based on canonical HEAD:

```python
def _validate_worktree_lineage(canonical_repo: Path, worktree_repo: Path) -> str:
    """Ensure worktree hasn't diverged from canonical HEAD."""
    canonical_head = _git(canonical_repo, "rev-parse", "HEAD")
    worktree_head = _git(worktree_repo, "rev-parse", "HEAD")
    
    if canonical_head != worktree_head:
        raise PromotionError(
            "worktree base no longer matches canonical repo HEAD; "
            "refusing promotion"
        )
    return canonical_head
```

This prevents promotion when:
- Worktree was manually modified
- Other promotions occurred since worktree creation
- Branch protection rules changed canonical HEAD

## Diff Extraction

Patches are extracted from worktree diffs:

```python
# From scripts/coding_run_promotion.py:253
patch_text = _git(worktree_repo, "diff", "--binary", strip=False)
if not patch_text.strip():
    raise PromotionError("no diff found in worktree; refusing empty promotion")
```

The diff is then:
1. Saved as artifact for audit
2. Applied to canonical via `git apply`
3. Validated in canonical context

## Isolation Guarantees

| Guarantee | Mechanism |
|-----------|------------|
| Canonical never directly modified | Workers only access worktree |
| No lost work on failure | Artifacts persist before cleanup |
| Parallel runs don't interfere | Separate worktrees |
| Audit trail maintained | Patch artifacts + commits |
| Reversion always possible | Git history + artifacts |

## Safety Benefits

```
┌────────────────────────────────────────────────────────────────────┐
│                    Without Worktree Isolation                       │
│                                                                     │
│  Worker ──────▶ Direct Edit ──────▶ Canonical                     │
│                      │                                              │
│                      ▼                                              │
│               If mistake:                                           │
│                      │                                              │
│                      ▼                                              │
│               Canonical corrupted                                    │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│                    With Worktree Isolation                          │
│                                                                     │
│  Worker ──────▶ Edit ──────▶ Worktree ──────▶ Canonical            │
│                      │                        (after approval)     │
│                      ▼                                              │
│               If mistake:                                           │
│                      │                                              │
│                      ▼                                              │
│               Delete worktree, try again                            │
│               Canonical untouched                                   │
└────────────────────────────────────────────────────────────────────┘
```

## Testing Worktree Isolation

```python
# Verify canonical unchanged after failed promotion
def test_validation_failure_rolls_back(self, promotion_env):
    """Canonical remains unchanged after failed validation."""
    worktree = promotion_env["worktree"]
    worktree.joinpath("app.py").write_text("print('broken'\n", encoding="utf-8")

    try:
        crp.promote_run(promotion_env["run_id"], ...)
    except crp.PromotionError:
        pass  # Expected

    # Canonical should have ORIGINAL content
    canonical_content = (
        promotion_env["canonical"] / "app.py"
    ).read_text(encoding="utf-8")
    
    assert "hello" in canonical_content, \
        "Canonical preserved after failed promotion"
```

## Run Metadata

Each run stores its worktree path in metadata:

```json
{
  "run_id": "run-abc123",
  "canonicalRepoPath": "/path/to/canonical",
  "worktreePath": "/path/to/worktrees/run-abc123",
  "validationCommands": ["python3 -m py_compile app.py"],
  "createdAt": "2024-01-15T10:00:00Z",
  "status": "awaiting_approval"
}
```

This allows:
- Locating worktree for debugging
- Verifying worktree still exists
- Cleanup of orphaned worktrees

## Multi-Repository Support

Oracle can manage multiple canonical repositories:

```
workspace/repos/
├── frontend/
│   └── (React project)
├── backend/
│   └── (Python API)
└── shared-lib/
    └── (common code)

workspace/worktrees/
├── frontend-run-abc123/
├── backend-run-def456/
└── shared-lib-run-ghi789/
```

Each worktree is tied to its specific canonical repo.

## Related Patterns

- [Dual-Worker Architecture](dual-worker-architecture.md) - Workers operate in worktrees
- [Validation Pipeline](validation-pipeline.md) - Validation occurs in worktree before promotion
- [Promotion Flow](promotion-flow.md) - Worktrees are cleaned up after promotion