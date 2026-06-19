# ADR 009: Dual-Worker Architecture

## Decision

The system supports both interactive (Aider) and autonomous bounded (code-agent-runtime-hardened) coding modes. Workers are selected based on task requirements—interactive for pair programming, autonomous for issue resolution.

## Reason

Provides flexibility for different developer workflows. Interactive mode offers human guidance; autonomous mode enables batch processing. Bounded autonomy ensures safety even in automated scenarios. Leverages best-of-breed tools for each mode.

## Tradeoffs

- **Complexity**: Two worker implementations require maintenance
- **Training**: Operators must understand when to use each mode
- **Consistency**: Different workers may produce different quality output

## Affected Modules

- `integration/worker_aider/` - interactive code worker
- `third_party/code-agent-runtime/` - bounded autonomous worker
- `OracleOS/Integration/WorkerRouter` - worker selection

## Evidence

- [oracle_build_v5_analysis.md:20-39](../oracle_build_v5_analysis.md) - component responsibilities
- [build_blueprint.md:53-74](../../../docs/build_blueprint.md) - core flows

## Source

Oracle Build v5 merge from v4 backend + v2 entrypoints
