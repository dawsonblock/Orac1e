# ADR 012: Trust Tier System for Knowledge

## Decision

Knowledge is classified into trust tiers: exploration, candidate, stable, experiment, and recovery. Only knowledge that passes critic verification can be promoted between tiers. Stable graph promotion requires replay evidence and trust-tier enforcement.

## Reason

Prevents weak evidence from polluting the knowledge graph. Provides audit trail for knowledge quality. Enables safe experimentation without contaminating stable knowledge. Recovery knowledge is tracked separately from nominal control paths.

## Tradeoffs

- **Flexibility**: Promotion barriers may slow learning
- **Complexity**: Requires tier classification logic
- **Overhead**: Tracking tier transitions adds state management

## Affected Modules

- `OracleOS/Graph/` - knowledge storage
- `OracleOS/TaskGraph/` - task-specific knowledge
- `OracleOS/Learning/` - success probability updates

## Evidence

- [ARCHITECTURE.md:492-508](../../ARCHITECTURE.md) - trust model
- [risk-register.md:5-6](../risk-register.md) - stable graph risk

## Source

Oracle OS knowledge management, governance enforcement
