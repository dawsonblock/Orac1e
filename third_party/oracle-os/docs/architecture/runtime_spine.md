# Oracle-OS Runtime Spine

## Enforced execution path

All side effects are expected to flow through this spine:

```
Intent
  → RuntimeOrchestrator.submitIntent(_:)
  → Planner.plan(...) -> Command
  → VerifiedExecutor.execute(_:)
  → CommandRouter
  → DomainRouter (SystemRouter / UIRouter / CodeRouter)
  → Execution
  → ExecutionOutcome(events)
  → CommitCoordinator.commit(_:)
  → Reducers apply events to WorldStateModel
  → snapshot / evaluation
```

`RuntimeExecutionDriver` is an adapter that translates `ActionIntent` inputs into
typed `Intent` values and forwards them to `IntentAPI.submitIntent(_:)`.

## Runtime invariants

1. `VerifiedExecutor.execute(_:)` is the only execution boundary for side effects.
2. `CommitCoordinator.commit(_:)` is the only committed-state write path.
3. Reducers are pure event-to-state derivation functions.
4. `ExecutionOutcome` must include events on success and failure paths.
5. `RuntimeOrchestrator` coordinates planning, execution, commit, and evaluation.

## Key modules

| Module | File | Responsibility |
|--------|------|---------------|
| API | `Sources/OracleOS/API/IntentAPI.swift` | Runtime intake boundary |
| Orchestration | `Sources/OracleOS/Runtime/RuntimeOrchestrator.swift` | Linear runtime coordination |
| Planning | `Sources/OracleOS/Planning/MainPlanner+Planner.swift` | Intent -> Command planning |
| Execution | `Sources/OracleOS/Execution/VerifiedExecutor.swift` | Policy + routed command execution |
| Routing | `Sources/OracleOS/Execution/Routing/*.swift` | CommandRouter + domain router boundaries |
| Events | `Sources/OracleOS/Events/EventStore.swift` | Append-only event history |
| Commit | `Sources/OracleOS/Events/CommitCoordinator.swift` | Number/append/reduce commit flow |
| Reducers | `Sources/OracleOS/State/Reducers/*.swift` | Pure state derivation |

## Remaining hardening focus

- Keep `AgentLoop` intake-only and free of planning/execution logic.
- Keep all user-facing entrypoints (controller/CLI/MCP/recipes) on the same
  `IntentAPI -> RuntimeOrchestrator` path.
- Continue expanding architecture integrity tests that guard bypass regressions.
