# ADR 006: Fail-Closed Policy

## Decision

When policy, state, or verification is ambiguous, the runtime fails closed rather than infer success. A command may route successfully and still fail verification.

## Reason

Prevents unsafe assumptions in ambiguous scenarios. Provides conservative safety guarantees. Forces explicit operator decision rather than implicit approval. Aligns with authority model principle of operator control.

## Tradeoffs

- **User Experience**: May block legitimate actions in edge cases
- **Automation**: Limits fully autonomous operation in ambiguous scenarios
- **Debugging**: Failures require operator investigation

## Affected Modules

- `OracleOS/Execution/VerifiedExecutor` - verification decisions
- `OracleOS/Integration/Policy/MutationPolicy` - policy enforcement

## Evidence

- [GOVERNANCE.md:7](../../docs/GOVERNANCE.md) - fail-closed rule
- [oracle_build_v5_analysis.md:114-117](../oracle_build_v5_analysis.md) - design tradeoffs

## Source

Governance contract, safety-first design principle
