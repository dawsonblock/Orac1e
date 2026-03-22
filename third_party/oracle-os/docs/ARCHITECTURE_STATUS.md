# Architecture Status

This file records where the architecture is currently strong and where it is still provisional.

## Strong

- One public runtime submission surface: `RuntimeOrchestrator.submitIntent(_:)`
- One side-effect boundary: `VerifiedExecutor`
- One committed-state writer: `CommitCoordinator`
- Shared reducer bundle for the live controller and MCP paths
- Typed domain events projected into committed state

## Provisional

- Some verification paths still depend on limited evidence rather than full environment re-observation
- Repair/patch ranking is still heuristic
- Some governance coverage is source-wiring based rather than end-to-end behavioral

## Required follow-on work

1. Replace heuristic build/test validation with a real sandbox harness.
2. Strengthen system-command verification.
3. Expand reducer replay tests to cover more event families.
4. Validate the controller path on macOS CI with permissions-aware test coverage.
