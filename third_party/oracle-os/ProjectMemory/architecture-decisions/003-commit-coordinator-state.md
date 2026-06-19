# ADR 003: CommitCoordinator as Sole State Writer

## Decision

`CommitCoordinator.commit(_:)` is the only committed-state write path. Reducers derive new committed state from appended events. Replay of the same event stream must converge to the same committed snapshot.

## Reason

Ensures deterministic state management. Enables replay debugging and auditability. Prevents state corruption through multiple write paths. All state changes are traceable to events.

## Tradeoffs

- **Performance**: Event append + reducer derivation adds overhead vs direct writes
- **Complexity**: Requires understanding event-driven state model
- **Debugging**: State changes are indirect, requiring event reconstruction

## Affected Modules

- `OracleOS/Events/CommitCoordinator` - commit flow
- `OracleOS/State/Reducers/*` - event-to-state derivation
- `OracleOS/Events/EventStore` - append-only event history

## Evidence

- [GOVERNANCE.md:2](../../docs/GOVERNANCE.md) - committed state rules
- [runtime_invariants.md:2](../../docs/runtime_invariants.md) - state mutation invariant
- [REPLAY_DETERMINISM.md](../../docs/REPLAY_DETERMINISM.md) - determinism requirements

## Source

Runtime architecture unification, deterministic state management
