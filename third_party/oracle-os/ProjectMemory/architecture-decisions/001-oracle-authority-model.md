# ADR 001: Oracle as Sole Authority

## Decision

Oracle OS is the sole authority in the system, owning all critical functions: run creation, worktree lifecycle, validation, event logging, approval storage, and final patch application.

## Reason

Prevents uncontrolled AI coding agents from making unreviewed changes to canonical repositories. Establishes clear ownership and approval boundaries that operators can understand and trust. The v4 backend's worktree/validation/promotion closure was the strongest component and needed preservation.

## Tradeoffs

- **Speed**: Conservative approval process trades development speed for safety
- **Flexibility**: Central authority enables control but may create bottlenecks
- **Operator Overhead**: Manual approval creates latency in development workflows

## Affected Modules

- `OracleOS/Runtime/RuntimeOrchestrator` - run lifecycle
- `OracleOS/Execution/VerifiedExecutor` - validation orchestration
- `OracleOS/Memory/EventMemory` - event logging
- `OracleOS/Integration/Policy/CommandApprovalPolicy` - approval storage

## Evidence

- [GOVERNANCE.md](../../docs/GOVERNANCE.md) - execution boundary rules
- [architecture.md](../../../docs/authority-model) - authority ownership
- [oracle_build_v5_analysis.md](../../../oracle_build_v5_analysis.md) - SWOT analysis

## Source

Oracle Build v5 merge from v4 backend closure + v2 CLI entrypoints
