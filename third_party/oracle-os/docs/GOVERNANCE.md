# Governance Contract

This document defines the repo-level rules that the implementation is expected to satisfy.
It is normative. When code and documentation disagree, the code must be changed or this file must be updated.

## 1. Execution boundary

1. `VerifiedExecutor.execute(_:)` is the only execution boundary allowed to produce runtime side effects.
2. Surfaces such as Controller, MCP, CLI, and recipes may submit intents and query state. They may not execute commands directly.
3. Routers may report what they attempted and what they observed locally. They may not decide final verification truth.

## 2. Committed state

1. `CommitCoordinator.commit(_:)` is the only committed-state write path.
2. Reducers derive committed state from appended events.
3. Live entry points must use the shared default reducer set. Empty reducer arrays are not valid for the controller or MCP runtime.
4. Replay of the same event stream must converge to the same committed snapshot.

## 3. Planning boundary

1. Planners terminate at `Command` generation.
2. Planning code may not import or call execution internals for direct side effects.
3. Runtime orchestration remains linear:
   `Intent -> plan -> execute -> commit -> evaluate`.

## 4. Verification rules

1. Preconditions are checked against committed state before routing execution.
2. Policy gating occurs before execution.
3. Postconditions are determined from independent read-back or other evidence outside the router's self-report.
4. A command may route successfully and still fail verification.

## 5. Repair pipeline honesty

1. Heuristic patch scoring must be labeled as heuristic.
2. Terms such as "compiled" or "tests fixed" are only strong claims when backed by a real harness.
3. Experimental repair code must not be described as verified autonomous program repair.

## 6. Documentation and workflow truth

1. README and architecture docs may only link to files that exist.
2. CI workflow configuration must refer to this repository's project names or clearly marked placeholders.
3. Governance tests must assert behavior or source wiring. Placeholder assertions are not acceptable.

## 7. Failing closed

When policy, state, or verification is ambiguous, the runtime should fail closed rather than infer success.

Related documents:
- [runtime_invariants.md](runtime_invariants.md)
- [ARCHITECTURE.md](../ARCHITECTURE.md)
- [runtime_spine.md](architecture/runtime_spine.md)
