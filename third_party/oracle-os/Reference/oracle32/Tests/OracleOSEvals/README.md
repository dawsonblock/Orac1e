# Oracle OS Benchmark Harness

This directory contains the merge-blocking fixture benchmark suites for Oracle OS.

Benchmark families:

- `OperatorBenchmarks.swift`
  - browser navigation
  - workflow-backed browser flow
  - file operation
  - ambiguous UI recovery
- `CodingBenchmarks.swift`
  - build-break repair
  - failing-test repair
  - experiment escalation and ranked patch selection
- `HybridBenchmarks.swift`
  - mixed OS handoff into code repair
  - inspect-project then apply change

Shared harness files:

- `EvalTask.swift`
  - benchmark family + per-run snapshot contract
- `EvalRunner.swift`
  - runs bounded repeated tasks and computes metrics
- `EvalMetrics.swift`
  - shared benchmark metrics and comparison formatting
- `EvalFixtures.swift`
  - deterministic fixtures, temporary workspaces, and loop test doubles

Primary metrics:

- `success_rate`
- `first_pass_success_rate`
- `average_steps`
- `recovery_success_rate`
- `graph_reuse_ratio`
- `workflow_reuse_ratio`
- `ambiguity_failure_count`
- `patch_selection_success_rate`

How to run:

```bash
swift test --filter "Operator Benchmarks"
swift test --filter "Coding Benchmarks"
swift test --filter "Hybrid Benchmarks"
swift test
```

How to interpret:

- Prefer higher success, first-pass success, graph reuse, workflow reuse, and patch-selection success.
- Prefer lower average steps and ambiguity failures.
- Recovery success should stay high without masking first-pass regressions.
- Any planner/runtime change should update the affected benchmark family or add a new benchmark before merge.
