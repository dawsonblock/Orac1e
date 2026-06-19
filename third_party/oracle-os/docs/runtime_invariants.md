# Runtime Invariants

This document records the non-negotiable runtime architecture rules for Oracle-OS.

## Execution and side effects

1. `VerifiedExecutor.execute(_:)` is the only side-effect execution boundary.
2. Runtime entry adapters (controller/MCP/recipes/CLI integrations) must submit
   intents through `IntentAPI`/`RuntimeOrchestrator` instead of executing actions directly.
3. `ExecutionOutcome` must include domain events for both success and failure paths.

## State mutation

1. `CommitCoordinator.commit(_:)` is the only committed-state write path.
2. Reducers are the only components allowed to derive new committed state from events.
3. `WorldStateModel.snapshot` is read-only from outside commit/reducer flow.

## Planning and orchestration

1. Planning terminates at `Command`; planners do not execute.
2. Runtime orchestration follows a linear flow:
   `Intent -> plan -> execute -> commit -> evaluate`.
3. `RuntimeExecutionDriver` is an adapter (`ActionIntent -> Intent`) only.

## Regression policy

Any new code that bypasses these invariants is a correctness bug and should be
blocked by architecture integrity tests.
