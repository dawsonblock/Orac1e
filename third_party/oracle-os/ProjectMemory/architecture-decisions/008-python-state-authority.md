# ADR 008: Python as Single State Mutation Authority

## Decision

The Python run server is the single authority for run status, approval receipts, promotion receipts, and canonical repository state mutations. Swift UI surfaces submit intents but do not mutate state directly.

## Reason

Centralizes all state mutations for auditability. Simplifies state management by having one writer. Enables unified API surface for all clients (CLI, Controller). Ensures consistent state transitions with idempotency guards.

## Tradeoffs

- **Coupling**: Tight coupling between Python backend and state model
- **Flexibility**: Swift cannot directly manipulate state
- **Latency**: IPC adds overhead for state operations

## Affected Modules

- `scripts/serve_coding_runs.py` - run server
- `scripts/coding_run_promotion.py` - promotion logic
- `Sources/OracleController/ControllerStore` - state presentation

## Evidence

- [oracle_build_v6_implementation_plan.md:71](../oracle_build_v6_implementation_plan.md) - acceptance gate
- [oracle_build_v6_implementation_plan.md:31-39](./python-backend-changes) - implementation tasks
- [docs/release_truth.md:5-8](../../../docs/release_truth.md) - feature status

## Source

Oracle Build v6 implementation plan
