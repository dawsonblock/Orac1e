# Validation Pipeline Pattern

## Intent

Oracle Build v5 implements a **dual-phase validation pipeline** that verifies code changes both in the isolated worktree before patch application and again in the canonical repository after application. All validation steps produce artifacts that persist for debugging, audit, and rollback decisions.

## Motivation

Validation must occur in two contexts:

| Context | Purpose | Constraints |
|---------|---------|-------------|
| **Worktree validation** | Verify patch is sound before applying | Read-only on canonical |
| **Canonical validation** | Confirm patch works in production context | After patch application |

This ensures:
1. Wasted work on invalid patches is caught early
2. Canonical repository is never left in a broken state
3. Validation evidence is preserved for debugging

## Validation Execution ([`scripts/coding_run_promotion.py`](../../../../scripts/coding_run_promotion.py:180))

```python
def _run_validation(repo: Path, commands: list[str]) -> dict[str, Any]:
    """Execute validation commands in sequence, aborting on first failure."""
    steps: list[dict[str, Any]] = []
    for command in commands:
        proc = subprocess.run(
            ["/bin/bash", "-lc", command],
            cwd=repo,
            text=True,
            capture_output=True,
        )
        step = {
            "name": command,
            "ok": proc.returncode == 0,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "exitCode": proc.returncode,
        }
        steps.append(step)
        if proc.returncode != 0:
            return {"ok": False, "steps": steps}
    return {"ok": True, "steps": steps}
```

## Dual-Phase Validation Flow

```
┌────────────────────────────────────────────────────────────────────┐
│                    Validation Pipeline                               │
│                                                                     │
│  1. Worker proposes patch (in worktree)                            │
│              │                                                      │
│              ▼                                                      │
│  ┌──────────────────────┐                                           │
│  │   Phase 1: Worktree  │                                           │
│  │      Validation      │                                           │
│  └──────────┬───────────┘                                           │
│             │                                                        │
│     ┌───────┴───────┐                                               │
│     │               │                                                │
│  Pass?           Fail?                                               │
│     │               │                                                │
│     ▼               ▼                                                │
│  Extract         Stop Pipeline,                                      │
│  patch diff     preserve artifacts                                   │
│  and persist                                                           │
│                                                                     │
│             ┌──────────────────────┐                                │
│             │   Phase 2: Canonical  │                                │
│             │      Validation       │                                │
│             └──────────┬───────────┘                                │
│                        │                                             │
│              ┌────────┴────────┐                                    │
│              │                 │                                     │
│           Pass?            Fail?                                     │
│              │                 │                                     │
│              ▼                 ▼                                     │
│     Record success,      Rollback,                                  │
│     commit, cleanup      record failure                             │
└────────────────────────────────────────────────────────────────────┘
```

## Artifact Persistence

Validation artifacts are stored with structured naming:

```python
def _write_validation_artifact(run_id: str, validation: dict[str, Any], kind: str) -> str:
    """Persist validation result as JSON artifact."""
    path = RUNS_ROOT / "validation" / f"{run_id}.{kind}.json"
    _write_json(path, validation)
    return str(path)
```

### Artifact Structure

```json
{
  "ok": true,
  "steps": [
    {
      "name": "python3 -m py_compile app.py",
      "ok": true,
      "stdout": "",
      "stderr": "",
      "exitCode": 0
    },
    {
      "name": "python3 -m pytest tests/",
      "ok": true,
      "stdout": "collected 5 items",
      "stderr": "",
      "exitCode": 0
    }
  ]
}
```

### Artifact Locations

| Artifact | Path Pattern |
|----------|--------------|
| Worktree validation | `workspace/runs/validation/<run_id>.worktree.json` |
| Canonical validation | `workspace/runs/validation/<run_id>.canonical.json` |
| Patch file | `workspace/runs/artifacts/<run_id>.patch` |
| Approval receipt | `workspace/runs/approvals/<run_id>.json` |
| Promotion receipt | `workspace/runs/promotions/<run_id>.json` |

## Multi-Step Validation

Validation commands run sequentially, aborting on first failure:

```python
# From tests/e2e/test_validation_flow.py
class TestMultiStepValidation:
    def test_multi_command_validation_allows_if_all_pass(self, promotion_env):
        """Multi-command validation passes only if ALL commands pass."""
        metadata = json.loads(...)
        metadata["validationCommands"] = [
            "python3 -m py_compile app.py",
            "python3 -c 'import ast; ast.parse(open(\"app.py\").read())'",
        ]
        
        result = crp.promote_run(run_id, actor="tester", note="multi-step ok")
        
        assert result.status == "applied", \
            "Should apply when all validation commands pass"

    def test_multi_command_validation_fails_if_any_fails(self, promotion_env):
        """Multi-command validation fails on FIRST command failure."""
        metadata["validationCommands"] = [
            "python3 -m py_compile app.py",
            "false",  # This will fail
        ]
        
        with pytest.raises(crp.PromotionError, match="validation failed"):
            crp.promote_run(run_id, actor="tester", note="should fail")
```

## Rollback on Failure

If canonical validation fails, the patch is automatically rolled back:

```python
# From scripts/coding_run_promotion.py:303
except Exception as exc:
    # Rollback to pre-patch state
    _run(["git", "-C", str(canonical_repo), "reset", "--hard", "HEAD"], check=False)
    _run(["git", "-C", str(canonical_repo), "clean", "-fd"], check=False)
    
    # Update status to failed
    run["status"] = "failed"
    _replace_run(run)
    
    # Record failure receipt
    receipt = {
        "run_id": run_id,
        "status": "failed",
        "validation_ok": False,
        "error": str(exc),
    }
    _record_promotion(run_id, receipt)
    _record_event(run_id, "promotion.failed", receipt)
    raise PromotionError(str(exc))
```

## Validation in Promotion Flow

The complete promotion flow integrates validation:

```python
def promote_run(run_id: str, actor: str = "operator", note: str = "", 
                cleanup_worktree: bool = True) -> PromotionResult:
    # Load run and metadata
    run = _load_run(run_id)
    metadata = _load_metadata(run_id)
    canonical_repo = Path(metadata.get("canonicalRepoPath"))
    worktree_repo = Path(metadata.get("worktreePath"))
    validation_commands = list(metadata.get("validationCommands") or [])

    # Validate canonical is clean
    if not _repo_is_clean(canonical_repo):
        raise PromotionError("canonical repo is dirty; refusing promotion")

    # Validate worktree lineage
    base_commit = _validate_worktree_lineage(canonical_repo, worktree_repo)
    
    # Record approval
    approval = _record_approval(run_id, "approved", actor, note)

    try:
        # Phase 1: Validate in worktree
        pre_validation = _run_validation(worktree_repo, validation_commands)
        _write_validation_artifact(run_id, pre_validation, "worktree")
        if not pre_validation["ok"]:
            raise PromotionError("worktree validation failed before promotion")

        # Extract patch
        patch_text = _git(worktree_repo, "diff", "--binary", strip=False)
        if not patch_text.strip():
            raise PromotionError("no diff found in worktree; refusing empty promotion")

        # Apply to canonical
        _run(["git", "-C", str(canonical_repo), "apply", "--index", 
              "--whitespace=nowarn", str(patch_file)])

        # Phase 2: Validate in canonical
        post_validation = _run_validation(canonical_repo, validation_commands)
        _write_validation_artifact(run_id, post_validation, "canonical")
        if not post_validation["ok"]:
            raise PromotionError("canonical validation failed after patch apply")

        # Commit and record success
        _run(["git", "-C", str(canonical_repo), "commit", "-m", 
              f"Promote approved coding run {run_id}"])
        promotion_commit = _git(canonical_repo, "rev-parse", "HEAD")

        run["status"] = "applied"
        _replace_run(run)
        
        # Record promotion receipt
        receipt = {
            "run_id": run_id,
            "base_commit": base_commit,
            "promotion_commit": promotion_commit,
            "validation_ok": True,
            ...
        }
        _record_promotion(run_id, receipt)
        
        # Cleanup worktree
        if cleanup_worktree:
            _run(["git", "-C", str(canonical_repo), "worktree", "remove", 
                  "--force", str(worktree_repo)], check=False)
            shutil.rmtree(worktree_repo, ignore_errors=True)

        return PromotionResult(..., validation_ok=True, ...)

    except Exception as exc:
        # Rollback handled in except block
        ...
```

## Testing Validation

```python
# From tests/e2e/test_validation_flow.py
class TestValidationFlowWithValidation:
    def test_validation_flow_with_syntax_check(self, promotion_env):
        """Validation flow with Python syntax check."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('valid syntax')\n", encoding="utf-8")

        # Update validation commands
        metadata = json.loads(...)
        metadata["validationCommands"] = ["python3 -m py_compile app.py"]
        
        result = crp.promote_run(run_id, actor="tester", note="syntax ok")

        assert result.status == "applied"
        assert result.validation_ok is True

    def test_validation_flow_fails_on_invalid_syntax(self, promotion_env):
        """Validation flow fails on invalid syntax."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('broken'\n", encoding="utf-8")  # Missing )

        metadata["validationCommands"] = ["python3 -m py_compile app.py"]

        with pytest.raises(crp.PromotionError, match="validation failed"):
            crp.promote_run(run_id, actor="tester", note="syntax error")

    def test_validation_failure_rolls_back(self, promotion_env):
        """Validation failure rolls back changes."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('broken'\n", encoding="utf-8")

        try:
            crp.promote_run(run_id, actor="tester", note="test")
        except crp.PromotionError:
            pass  # Expected

        # Canonical should have ORIGINAL content
        canonical_content = (promotion_env["canonical"] / "app.py").read_text()
        assert "hello" in canonical_content, \
            "Canonical should have original content after rollback"
```

## Key Invariants

1. **Worktree validation always precedes application**
2. **Canonical validation always follows application**
3. **Validation failure triggers automatic rollback**
4. **All validation steps produce artifacts**
5. **Validation commands are run sequentially, aborting on first failure**
6. **Canonical repo must be clean before promotion**

## Related Patterns

- [Promotion Flow](promotion-flow.md) - How validation integrates with approval
- [Worktree Isolation](worktree-isolation.md) - How worktrees enable safe experimentation