# ADR 007: Independent Re-validation

## Decision

Every patch is re-validated by Oracle after worker proposal. Oracle performs independent validation separate from worker self-report to ensure verification truth is not dependent on worker's self-assessment.

## Reason

Prevents false positives from worker self-reporting. Provides defense-in-depth security. Ensures verification is based on actual read-back evidence rather than claimed success. Routers may report what they attempted but may not decide final verification truth.

## Tradeoffs

- **Performance**: Additional validation adds latency
- **Complexity**: Requires maintaining independent verification paths
- **Cost**: Validation resources consumed twice per patch

## Affected Modules

- `OracleOS/Execution/VerifiedExecutor` - independent verification
- `OracleOS/Validation/ValidationCoordinator` - validation orchestration
- [GOVERNANCE.md:4](../../docs/GOVERNANCE.md) - verification rules

## Evidence

- [oracle_build_v5_analysis.md:101](../oracle_build_v5_analysis.md) - control invariants
- [docs/architecture.md:4](../../../docs/architecture.md) - revalidation rule

## Source

Oracle Build v5 defense-in-depth approach
