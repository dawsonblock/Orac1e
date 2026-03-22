# Runtime Migration Cleanup Notes

This file tracks runtime surfaces removed or intentionally retired during the
runtime-architecture unification effort.

## Removed / retired execution surfaces

- `RuntimeOrchestrator.performAction(...)` direct execution bridge
- `RuntimeExecutionDriver.executeLegacy(...)` split execution route
- `VerifiedActionExecutor` shim path
- Legacy `performAction` call pattern in OracleOS runtime sources

## Current execution boundary

- Side effects must run through:
  `RuntimeOrchestrator.submitIntent(_:) -> VerifiedExecutor.execute(_:)`
- Command dispatch is routed by:
  `CommandRouter -> SystemRouter/UIRouter/CodeRouter`

## Follow-up guardrails

- Keep architecture integrity tests current when adding new runtime features.
- Reject synthetic "success" responses that lack real execution evidence.
- Ensure documentation references `VerifiedExecutor` and `IntentAPI` flow only.
