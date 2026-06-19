# ADR 002: VerifiedExecutor as Single Execution Boundary

## Decision

`VerifiedExecutor.execute(_:)` is the only execution boundary allowed to produce runtime side effects. All surfaces (Controller, MCP, CLI, recipes) may submit intents and query state but may not execute commands directly.

## Reason

Establishes a single, auditable point where all side effects occur. Enables policy validation before execution and postcondition verification after execution. Prevents bypasses through alternative execution paths that could circumvent safety checks.

## Tradeoffs

- **Complexity**: Single execution path adds coordination overhead
- **Flexibility**: Cannot execute actions directly from UI or CLI surfaces
- **Performance**: Additional verification layers may add latency

## Affected Modules

- `OracleOS/Execution/VerifiedExecutor` - execution gate
- `OracleOS/Runtime/RuntimeOrchestrator` - intent coordination
- `OracleOS/Execution/CommandRouter` - command dispatch

## Evidence

- [GOVERNANCE.md:1](../../docs/GOVERNANCE.md) - execution boundary rule
- [runtime_invariants.md:1](../../docs/runtime_invariants.md) - invariant documentation
- [migration_cleanup.md](../../docs/migration_cleanup.md) - removed legacy surfaces

## Source

Runtime architecture unification, phase 3+ cleanup
