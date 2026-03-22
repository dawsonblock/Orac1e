# Dual-Worker Architecture Pattern

## Intent

Oracle Build v5 uses a dual-worker architecture that separates **interactive pair-programming** from **bounded autonomous issue resolution**. Both workers operate under Oracle's authority, returning proposals rather than direct edits.

## Motivation

Different coding tasks require different worker characteristics:

| Use Case | Worker | Characteristics |
|----------|--------|-----------------|
| Guided pair programming with operator in the loop | Aider | Interactive, streaming, conversational |
| Bounded autonomous fix for well-scoped issues | Hardened | Structured, constrained, self-validated |

The dual-worker model allows Oracle to route work based on task characteristics while maintaining consistent safety guarantees.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Oracle OS (Authority)                  │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐  ┌───────────┐  │
│  │  Tool   │  │  Worktree │  │ Validation│  │ Approval  │  │
│  │ Registry│  │Coordinator│  │Pipeline   │  │  Store    │  │
│  └────┬────┘  └─────┬────┘  └─────┬─────┘  └─────┬─────┘  │
└───────┼─────────────┼────────────┼──────────────┼────────┘
        │             │            │              │
        ▼             ▼            ▼              ▼
┌───────────────┐         ┌──────────────────────────────┐
│    Aider      │         │   Code-Agent-Runtime-Hardened │
│ (Interactive) │         │       (Bounded Autonomy)       │
│               │         │                               │
│ Capabilities: │         │  Capabilities:                  │
│ • chat        │         │  • worker.code.patch            │
│ • edit        │         │  • worker.code.issue_fix        │
│ • ask         │         │                               │
│ • commit      │         │  Path budget enforcement        │
└───────────────┘         │  Max line count limits          │
                         │  Multi-attempt with rollback    │
                         └───────────────────────────────-─┘
```

## Worker Interface Contract

Both workers implement the same envelope interface:

### ToolInvokeEnvelope (Request)

```python
from integration.tool_sdk.base_models import ToolInvokeEnvelope

envelope = ToolInvokeEnvelope(
    contract_version="1.0",
    run_id="run-123",
    tool_id="hardened",          # or "aider"
    capability="worker.code.patch",
    payload={
        "repo_path": "/path/to/repo",
        "task": "Fix the null pointer exception",
        "constraints": {
            "allowed_paths": ["src/", "lib/"],
            "max_changed_lines": 500,
        }
    },
    constraints={},
    context={},
    metadata={}
)
```

### ToolResponseEnvelope (Response)

```python
from integration.tool_sdk.base_models import ToolResponseEnvelope

response = ToolResponseEnvelope(
    status="ok",                 # or "error", "no_result"
    tool_id="hardened",
    capability="worker.code.patch",
    summary="Proposed patch for null pointer fix",
    payload={
        "diff": "--- a/src/handler.py\n+++ b/src/handler.py\n@@ ...",
        "touched_files": ["src/handler.py"],
        "warnings": [],
        "commands_requested": [],
    },
    warnings=["Consider adding null check"],
    artifacts=[],
    metrics={
        "touched_file_count": 1,
        "warning_count": 1,
        "command_request_count": 0,
    },
    error=None
)
```

## Hardened Worker Implementation

The hardened worker provides bounded autonomous behavior with strong safety guarantees.

### Bridge Pattern ([`integration/worker_hardened/bridge.py`](../../../../integration/worker_hardened/bridge.py:31))

```python
def run_hardened(req: ProposeRequest) -> dict:
    """Execute hardened worker with bounded constraints."""
    PlannerWorker, PatchWorker, ValidationWorker, IssueTask = _load_runtime()
    issue_task = IssueTask(**build_issue_task_kwargs(req))
    repo_root = Path(req.repo_path)

    # Three-phase execution: plan → patch → validate
    planner = PlannerWorker()
    patcher = PatchWorker(max_attempts=3)
    validator = ValidationWorker()

    plan, parsed = planner.run(repo_root=repo_root, task=issue_task, attempt_index=1)
    patch, patch_result, trace = patcher.run(repo_root=repo_root, plan=plan, parsed=parsed)

    if patch is not None:
        # Enforce path budget - critical security boundary
        violations = enforce_path_budget(patch.diff_text, req.constraints.allowed_paths)
        if violations:
            raise ValueError(f"patch touched blocked paths: {', '.join(violations)}")
        
        # Enforce line count budget
        lines = changed_line_count(patch.diff_text)
        if lines > req.constraints.max_changed_lines:
            raise ValueError(f'patch exceeded max_changed_lines: {lines} > {req.constraints.max_changed_lines}')
        
        # Run validation before returning
        report, _ = validator.run(repo_root=repo_root, plan=plan, patch=patch)
    else:
        report = None

    return to_response(patch, report, trace, getattr(patch_result, 'message', None))
```

### Path Budget Enforcement

```python
from integration.shared_py.diff_utils import enforce_path_budget

# Example: Enforce allowed paths
diff_text = """diff --git a/src/main.py b/src/main.py
+import os
"""

allowed_paths = ["src/", "lib/"]
violations = enforce_path_budget(diff_text, allowed_paths)

# Empty violations = all paths within budget
assert violations == [], "All paths are within budget"
```

### Service Interface ([`integration/worker_hardened/service.py`](../../../../integration/worker_hardened/service.py:15))

```python
from fastapi import FastAPI
from integration.shared_py.models import HealthResponse, ProposeRequest, ProposeResponse

app = FastAPI(title="worker-hardened", version="0.2.0")

SUPPORTED_CAPABILITIES = {"worker.code.patch", "worker.code.issue_fix"}

@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(
        name="worker-hardened",
        details={
            "code_agent_repo_path": os.environ.get("CODE_AGENT_REPO_PATH", ""),
            "capabilities": sorted(SUPPORTED_CAPABILITIES),
        },
    )

@app.post("/propose", response_model=ProposeResponse)
def propose(req: ProposeRequest) -> ProposeResponse:
    try:
        result = run_hardened(req)
        return ProposeResponse(status="ok", worker="code-agent-runtime-hardened", **result)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
```

## Aider Worker Pattern

The Aider worker provides interactive, conversational code editing.

### Diff Extraction Pattern

```python
from integration.shared_py.diff_utils import extract_touched_files, changed_line_count

diff_text = """diff --git a/src/main.py b/src/main.py
index 1234567..89abcdef 100644
--- a/src/main.py
+++ b/src/main.py
@@ -1,5 +1,6 @@
+import os
 def main():
     print("hello")
+    return 0
"""

# Extract touched files from diff
touched_files = extract_touched_files(diff_text)
assert touched_files == ["src/main.py"]

# Count changed lines (additions + deletions)
line_count = changed_line_count(diff_text)
assert line_count == 2
```

## Key Invariants

1. **Workers return diffs only** - Never commits, never pushes
2. **Path budget is enforced** - No path outside `allowed_paths` can be modified
3. **Line count is bounded** - `max_changed_lines` prevents runaway patches
4. **Oracle re-validates** - Worker validation is not a substitute for Oracle validation

## When to Use Each Worker

| Scenario | Worker | Rationale |
|----------|--------|-----------|
| Exploratory refactoring with operator guidance | Aider | Interactive sessions allow course correction |
| Well-scoped bug fix with known trigger | Hardened | Structured approach with automatic retry |
| Large architectural changes | Aider | Human judgment needed for trade-offs |
| Batch processing multiple similar issues | Hardened | Consistent, bounded execution |
| Learning codebase structure | Aider | Conversational context helps |
| Security-sensitive changes | Hardened | Path budget prevents collateral damage |

## Testing Pattern

```python
# From tests/integration/test_hardened_adapter.py
class TestPathBudgetEnforcement:
    def test_enforce_path_budget_allows_within_budget(self):
        diff_text = """diff --git a/src/main.py b/src/main.py
+import os
"""
        allowed_paths = ["src/", "lib/"]
        
        violations = enforce_path_budget(diff_text, allowed_paths)
        
        assert len(violations) == 0, \
            "Path within allowed_paths should not be a violation"

    def test_enforce_path_budget_blocks_outside_budget(self):
        diff_text = """diff --git a/config/prod.json b/config/prod.json
+{}
"""
        allowed_paths = ["src/", "lib/"]
        
        violations = enforce_path_budget(diff_text, allowed_paths)
        
        assert len(violations) == 1, \
            "Should detect exactly 1 violation"
        assert "config/prod.json" in violations, \
            "config/prod.json should be flagged as violation"
```

## Related Patterns

- [Manifest-Driven Tool Discovery](manifest-tool-discovery.md) - How workers declare capabilities
- [Worktree Isolation](worktree-isolation.md) - How workers get isolated execution context
- [Validation Pipeline](validation-pipeline.md) - How proposals get validated