# Python-Swift Bridge Documentation

## Overview

The `integration/worker_hardened/bridge.py` module acts as a crucial bridge between Python and Swift components in the Orac1e system. It loads Swift runtime components and maps Python request objects to Swift task objects.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Python Integration Layer                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   workers_   │    │   bridge.py  │    │   diff_utils │  │
│  │   planner.py │───▶│              │───▶│   .py        │  │
│  └──────────────┘    └──────┬───────┘    └──────────────┘  │
│                             │                               │
│                             ▼                               │
│                    ┌────────────────┐                       │
│                    │  Swift Runtime │                       │
│                    │  (PlannerWorker,│                       │
│                    │   PatchWorker,  │                       │
│                    │   ValidationWorker)                     │
│                    └────────────────┘                       │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow

### 1. Request Input (Python → Bridge)

The Python layer creates a `ProposeRequest` object:

```python
from integration.shared_py.models import ProposeRequest, ProposeContext, Constraints

req = ProposeRequest(
    run_id="run-123",
    repo_name="my-repo",
    repo_path="/path/to/repo",
    task="Fix first_token function to handle empty list",
    mode="autonomous",
    context=ProposeContext(),
    constraints=Constraints(allowed_paths=["src/"])
)
```

### 2. Task Normalization (Bridge Internal)

The `_task_normalize()` function extracts structured hints from plain language:

```python
# Input: "Fix first_token function to handle empty list"
# Output: [("return tokens[0]", "if not tokens:\n        return None\n    return tokens[0]")]
```

### 3. Swift Runtime Loading (Bridge → Swift)

The bridge loads Swift workers dynamically:

```python
PlannerWorker, PatchWorker, ValidationWorker, IssueTask = _load_runtime()
```

### 4. Task Mapping (Python → Swift)

Python `ProposeRequest` is mapped to Swift `IssueTask`:

```python
from integration.worker_hardened.task_mapper import build_issue_task_kwargs

# Converts Python request to Swift-compatible kwargs
issue_task_kwargs = build_issue_task_kwargs(req)
```

### 5. Execution (Swift Runtime)

Swift workers execute the task:

```python
planner = PlannerWorker()
plan = planner.execute(issue_task_kwargs)

patcher = PatchWorker()
patch = patcher.execute(plan)

validator = ValidationWorker()
validation = validator.execute(patch)
```

### 6. Response Mapping (Swift → Python)

Swift results are mapped back to Python:

```python
from integration.worker_hardened.result_mapper import to_response

result = to_response(plan, patch, validation, trace, failure_reason=None)
```

## Key Functions

### `_task_normalize(req: ProposeRequest) -> list[tuple[str, str]]`

Extracts `(target_fragment, replacement_hint)` pairs from plain-language tasks.

**Supported Patterns:**
- "fix `first_token`" → extracts function name
- "so it returns None" → extracts replacement hint
- "fix `get_first_token`" → extracts function name

**Returns:**
List of (target, replacement) tuples for heuristic fallback.

### `_heuristic_fallback(repo_root, trace, plan, normalized_hints) -> _FallbackPatch | None`

Last-resort line-level heuristic patcher when structured search fails.

**Parameters:**
- `repo_root`: Path to repository root
- `trace`: Execution trace (for debugging)
- `plan`: Structured plan from PlannerWorker
- `normalized_hints`: Hints from `_task_normalize()`

**Returns:**
`_FallbackPatch` if changes were made, else `None`.

### `run_hardened(req: ProposeRequest) -> dict`

Main entry point for hardened worker execution.

**Execution Flow:**
1. Load Swift runtime
2. Execute PlannerWorker
3. If no hypotheses, use `_task_normalize()` hints
4. Execute PatchWorker
5. Validate with ValidationWorker
6. Apply path budget enforcement
7. Return structured response

**Returns:**
```python
{
    "success": True,
    "file": "src/parser.py",
    "search": "def first_token(tokens):",
    "replace": "def first_token(tokens):\n    if not tokens:\n        return None",
    "confidence": 0.95,
    "patch": "--- a/src/parser.py\n+++ b/src/parser.py\n..."
}
```

## Error Handling

### Bridge Errors

- **RuntimeLoadError**: Swift runtime components not found
- **TaskMappingError**: Failed to map Python request to Swift task
- **ExecutionError**: Swift worker execution failed

### Validation Errors

- **PathBudgetViolation**: Patch touches files outside allowed paths
- **BlockedPathError**: Patch touches blocked paths (.git/, secrets/, etc.)

## Integration Points

### Vision Sidecar

The bridge integrates with `vision-sidecar` for visual grounding:

```python
# vision-sidecar provides VLM capabilities
# Used for UI element detection and text recognition
```

### Circuit Breaker

The `workers_planner.py` uses a circuit breaker pattern:

```python
from integration.shared_py.production_utils import CircuitBreaker

planner_breaker = CircuitBreaker(failure_threshold=3)

if not planner_breaker.can_execute():
    return {"success": False, "error": "CIRCUIT_BREAKER_OPEN"}
```

## Testing

### Unit Tests

- `tests/e2e/test_circuit_breaker.py` - Circuit breaker behavior
- `tests/e2e/test_validation_flow_e2e.py` - Diff parsing and validation

### E2E Tests

- `tests/e2e/test_full_planner_pipeline.py` - Full pipeline with real model
- `tests/e2e/test_parallel_orchestrator.py` - Batch execution

## Configuration

### Environment Variables

- `CODE_AGENT_REPO_PATH`: Path to code-agent-runtime directory
- `DEEPSEEK_API_KEY`: API key for DeepSeek model (for E2E tests)

### Path Budget

Configured in `integration/shared_py/diff_utils.py`:

```python
BLOCKED_PATH_PREFIXES = [
    ".git/",
    ".github/",
    "secrets/",
    "infra/",
    "deploy/",
]
```

## Troubleshooting

### Common Issues

1. **"CODE_AGENT_REPO_PATH is not set"**
   - Set environment variable or ensure `third_party/code-agent-runtime` exists

2. **"CIRCUIT_BREAKER_OPEN"**
   - Too many failures; reset circuit breaker or wait for timeout

3. **"Path budget violation"**
   - Check `allowed_paths` in Constraints
   - Review `BLOCKED_PATH_PREFIXES` in diff_utils.py

### Debug Mode

Enable debug logging:

```python
import logging
logging.basicConfig(level=logging.DEBUG)
```
