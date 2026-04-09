# Status

## Proven Invariants

- Package scope is macOS 14+ only.
- Supported product surfaces are OracleController, the MCP server, and the `oracle` CLI.
- Normal runtime execution routes through `RuntimeOrchestrator`, `MainPlanner`, `VerifiedExecutor`, `CommandRouter`, and `CommitCoordinator`.
- MCP ingress decodes raw JSON-RPC arguments into typed values before normal dispatch.
- MCP tool definitions are authored as typed Swift schema values and exported once at the outer seam.
- Runtime boundary results now have typed envelopes for action, trace, code-execution, and recipe-run payloads.
- Controller host mapping now prefers typed runtime envelopes over legacy outer `ToolResult` fallbacks.
- Sandbox experiments now emit isolation metadata including canonical roots, executed commands, candidate paths, and cleanup outcome.
- `oracle setup` and `oracle doctor` now operate on typed Claude config models instead of mutating dictionary trees.

## Bounded Exceptions

- `oracle setup`
- `oracle doctor`
- optional `vision-sidecar`
- internal patch experiments in worktree sandboxes
- `oracle_screenshot` as the explicit MCP image-content exception

This checkout does not currently ship a public `oracle_experiment_search` MCP tool.

## Known Remaining Drift

- Much of the broader runtime still uses historical dictionary conversion helpers in subsystems outside the hardened boundary files.
- Full macOS controller and automation validation cannot be proven from a Linux container.
- The repository still contains historical docs and diagnostics that may describe older architecture slices outside the core contract.

## Verification Posture

- Swift unit tests exist for MCP boundaries, governance invariants, experiments, runtime execution, and controller/shared models.
- Linux can validate a large amount of typing and structural behavior, but not Accessibility, Screen Recording, AppKit control, or other macOS-only runtime effects.
- Hardening status should be described as improved and more internally consistent, not as fully complete or production-certified.
