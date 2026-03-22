# Architecture Rules

This document is the single source of truth for Oracle-OS architectural invariants.
All contributors must follow these rules. No exceptions without explicit amendment here.

---

## Protected Backbone Modules

These modules form the execution and reasoning spine. They may be strengthened
but not bypassed, duplicated, or replaced without updating this document:

| Module | Role |
|--------|------|
| `VerifiedExecutor` | Only path for environment-changing actions (`execute(_:)` trust boundary) |
| `CriticLoop` | Post-action evaluation and failure classification |
| `PlanSimulator` | Simulates plans before commitment |
| `ProgramKnowledgeGraph` | Canonical code model (all code graphs are views over it) |
| `WorldStateModel` | Authoritative committed world state |
| `ObservationChangeDetector` | Element-level change detection with volatile filtering |
| `TaskGraph` | Runtime task tracking and graph navigation |
| `TraceStore` | Persistent execution evidence (verified deltas, not snapshots) |
| `RepairPipeline` | Canonical repair stages (localize → patch → validate → apply) |
| `BenchmarkBaseline` | Metric thresholds for evidence-driven upgrades |

---

## Required Runtime Sequence

Every environment mutation follows this exact sequence:

```
planner proposes
↓
policy authorizes
↓
executor acts
↓
verifier judges
↓
runtime commits
↓
trace records
↓
recovery reacts
```

No authoritative state mutation may exist without executor evidence.

---

## Required Rules

### R1 — One planner entry point

The runtime calls exactly one planner API (`Planner` through `DecisionCoordinator`).
All other plan generators (reasoning, LLM, graph search) are internal helpers
consumed by `PlanGenerator` or `Planner`, never called directly from the runtime.
`PlanGenerator` is the canonical runtime-facing planner API.
`PlanEvaluator` is the sole ranking authority.

### R2 — Three runtime memory categories only

Runtime memory is organized into exactly three categories:

| Category | Purpose |
|----------|---------|
| **Trace** | What happened (execution evidence) |
| **Workflow** | Reusable successful patterns |
| **Knowledge Graph** | Structured facts and symbol relations |

`ProjectMemory` is **static support material** — it stores documentation-like
knowledge (patterns, decisions, risks) that inform but do not drive runtime
decisions. It is not live runtime memory.

Do not create additional long-lived memory stores. Route new data into one of
the three runtime categories.

### R3 — No runtime imports from controller or UI targets

`OracleRuntime` and all files under `Sources/OracleOS/Runtime/` must import
only `Foundation`. They must never import `AppKit`, `SwiftUI`,
`OracleController`, or any controller/UI module. The controller is a surface,
not a dependency.

### R4 — No environment mutation outside the executor

Every environment-changing action (UI interaction, shell command, file write,
browser navigation, git operation) must flow through `VerifiedExecutor`.
The executor returns `ExecutionOutcome` with events and artifacts;
`CommitCoordinator` is the only entity that writes committed state.

> **Note:** `VerifiedActionExecutor` is removed from the runtime execution path.
> All side-effect execution must flow through `VerifiedExecutor` via
> `RuntimeOrchestrator.submitIntent(_:)`.

Forbidden outside the executor and its commit flow:
- Direct writes to `worldState`, `taskGraph`, or runtime memory stores
  that bypass the verified execution pipeline
- Spawning processes, writing files, or mutating UI state without
  executor evidence

### R5 — Planners choose structure, never execute

Planners must not resolve exact UI targets, mutate files, execute commands,
or inline recovery mechanics. Planning produces intent; execution resolves
and acts.

### R6 — Authoritative world model

The planner reads **only** from committed world state
(`WorldStateModel.snapshot`). Three state layers exist:

| Layer | Description |
|-------|-------------|
| **Observed** | Raw perception data from `ObservationBuilder` |
| **Predicted** | Simulated by `PlanSimulator` before commitment |
| **Committed** | `WorldStateModel.snapshot` — the only layer planners read |

State advances only through delta-based updates via `apply(diff:)`.
Raw AX/DOM/filesystem artifacts must not reach the planner directly.

### R7 — Experimental vision boundary

Vision tools (`oracle_parse_screen`, `oracle_ground`) are experimental.
Normal runtime operation must succeed without them. Planners must not
depend on vision output. Vision is allowed only for debugging, offline
evaluation, and optional enrichment.

Vision sidecar output must conform to `VisionPerceptionContract`:
structured `VisionDetection` frames validated by `VisionContractValidator`
before the world model accepts them. Raw untyped dictionaries are never
consumed directly.

### R8 — Canonical program graph

`ProgramKnowledgeGraph` is the canonical code model. All structural
code-intelligence graphs (`SymbolGraph`, `CallGraph`, `TestGraph`,
`BuildGraph`, `DependencyGraph`) are views over this single model.
Consumers should query code structure through `ProgramKnowledgeGraph`.

### R9 — Explicit repair pipeline

Code repair follows ordered stages: failure → localization → candidate
symbols → patch candidates → sandbox validation → regression check →
rank → apply. Localization is mandatory before patch generation.
Sandbox validation is mandatory before apply.

### R10 — Conservative learning

Workflow promotion requires **repeated critic-confirmed success** across
distinct episodes. One-off traces, sparse evidence, and unvalidated
patterns must not mutate planner policy or rewrite workflows.

### R11 — Lean traces

Traces store verified deltas — action proposals, executor results,
verification outcomes, and committed state changes. Full AX trees,
DOM snapshots, and large filesystem dumps are excluded from normal
traces and stored only in debug mode.

### R12 — Benchmark gating

Future upgrades must be evidence-driven. Core metrics (task success rate,
average steps, recovery count, wrong-target rate, patch success rate,
regression rate) are tracked by `MetricsRecorder`. Merges that degrade
core metrics are blocked until the regression is understood.

---

## Coordinator Ownership

| Coordinator | Owns | Does NOT own |
|-------------|------|-------------|
| `ExecutionCoordinator` | Action preparation, policy evaluation, budget tracking | Planning, memory writes |
| `RecoveryCoordinator` | Failure recovery workflows, recovery execution | Planning decisions, state building |
| `DecisionCoordinator` | Planner façade, strategy selection | Execution, memory recording |
| `LearningCoordinator` | Outcome recording to trace/memory subsystem | Planning, state building |
| `StateCoordinator` | Observation, state abstraction, task graph position | Execution, memory recording |

---

## Enforcement

These rules are enforced by governance tests under
`Tests/OracleOSTests/Governance/`. CI must pass all governance tests before
merge.

Governance test suites:
- `ArchitectureFreezeTests` — R1, R3, R4, R5, protected modules
- `ExecutionBoundaryTests` — R4, R5, R7
- `MemoryBoundaryTests` — R2
- `CoordinatorBoundaryTests` — Coordinator ownership
- `CodeIntelligenceBoundaryTests` — R8, R9
- `KnowledgePromotionTests` — R10
- `NoBypassExecutionTests` — R4
- `PlannerBoundaryTests` — R5
- `AgentLoopBoundaryTests` — Agent loop delegation

---

## Freeze Policy

During active refactoring phases:
- No new subsystem directories under `Sources/OracleOS/`
- All new work routes into existing modules
- Architecture expansion requires matching eval coverage
