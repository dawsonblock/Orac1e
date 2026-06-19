# Runtime Hardening Rollout

Branch: `codex/runtime-hardening`

This document is the single-branch rollout board for the next Oracle OS hardening cycle.

## Branch Rules

- Keep all milestone work on `codex/runtime-hardening`.
- Do not merge partial milestones to `main`.
- Keep history linear and milestone-oriented.
- After each milestone:
  - add tests or benchmarks
  - run `swift test`
  - inspect trace / graph / memory effects
  - only then continue

## Milestone Order

1. governance freeze
2. runtime spine cleanup
3. execution-truth audit
4. graph hardening
5. graph-first planner rewrite
6. semantic targeting enforcement
7. recovery first-class integration
8. workflow synthesis rewrite
9. memory activation
10. experiment normalization
11. architecture-aware ranking
12. eval hardening
13. controller diagnostics
14. only then higher-order upgrades

## Commit Groups

### M0 Governance Freeze

Targets:
- `GOVERNANCE.md`
- `ARCHITECTURE.md`
- `ARCHITECTURE_GOVERNANCE.md`
- `Tests/OracleOSTests/Core/GovernanceEnforcementTests.swift`

Commit group:
- docs and governance rules
- tests for workflow / graph / project-memory promotion loopholes

Gate:
- governance rules explicit
- governance suite blocks loop/planner/workflow/memory drift

### M1 Runtime Spine Cleanup

Targets:
- `Sources/OracleOS/Agent/Loop/AgentLoop.swift`
- `Sources/OracleOS/Runtime/LoopBudget.swift`
- `Sources/OracleOS/Runtime/LoopTerminationReason.swift`
- `Sources/OracleOS/Agent/Loop/LoopDiagnostics.swift`

Gate:
- loop is orchestration-only
- termination is explicit
- every step is diagnosable

### M2 Execution Truth Audit

Targets:
- `Sources/OracleOS/Core/Execution/VerifiedActionExecutor.swift`
- `Sources/OracleOS/Runtime/OracleRuntime.swift`
- mutating skills / recovery / experiment replay paths

Gate:
- no meaningful action bypasses verified execution

### M3 Graph Hardening

Targets:
- `Sources/OracleOS/Graph/*`

Gate:
- stable graph contains only repeated trusted evidence

### M4 Graph-First Planner Rewrite

Targets:
- `Sources/OracleOS/Agent/Planning/*`
- `Sources/OracleOS/Agent/Planning/GraphSearch/*`

Gate:
- planner order is workflow -> stable graph -> candidate edge -> exploration

### M5 Semantic Targeting Enforcement

Targets:
- `Sources/OracleOS/Agent/Skills/OS/*`
- `Sources/OracleOS/Core/World/WorldQuery.swift`
- `Sources/OracleOS/Core/Ranking/*`

Gate:
- all target-bearing UI actions use ranked semantic targeting

### M6 Recovery As First-Class Mode

Targets:
- `Sources/OracleOS/Agent/Recovery/*`
- `Sources/OracleOS/Agent/Loop/AgentLoop.swift`

Gate:
- recovery actions are verified, traced, graphed, and separately tiered

### M7 Workflow Synthesis Rewrite

Targets:
- `Sources/OracleOS/Learning/Recipes/*`
- `Sources/OracleOS/Workflows/*`

Gate:
- workflows are multi-episode, parameterized, replayable, and decay correctly

### M8 Memory Activation

Targets:
- new `Sources/OracleOS/Memory/*`
- existing `Sources/OracleOS/Learning/Memory/*`
- planners, workflow retriever, recovery selector, ranking, project memory

Gate:
- planner behavior changes based on relevant memory

### M9 Experiment Normalization

Targets:
- `Sources/OracleOS/Agent/Planning/CodePlanner.swift`
- `Sources/OracleOS/Experiments/*`
- `Sources/OracleOS/CodeExecution/*`
- `Sources/OracleOS/CodeIntelligence/*`

Gate:
- uncertain code repair branches into experiments routinely

### M10 Architecture-Aware Ranking

Targets:
- `Sources/OracleOS/Architecture/*`
- experiment ranking path
- `Sources/OracleOS/Agent/Planning/CodePlanner.swift`

Gate:
- safer passing patches beat riskier passing patches

### M11 Eval Hardening

Targets:
- `Tests/OracleOSEvals/*`

Gate:
- repeated-run benchmark deltas can reject regressions

### M12 Controller Diagnostics

Targets:
- controller UI/host/shared diagnostics surfaces

Gate:
- most failures can be investigated from the controller

## Final Merge Gate

Before merging `codex/runtime-hardening` to `main`:
- governance suite passes
- operator, coding, and hybrid benchmark suites pass
- full `swift test` passes
- no dirty worktree
- no unresolved execution-path or promotion-policy regressions
