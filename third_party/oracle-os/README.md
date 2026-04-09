# Oracle OS

Oracle OS is a macOS-local operator runtime with three supported product surfaces:

- OracleController app
- MCP server
- `oracle` CLI

This checkout targets macOS 14+ and Swift 6.0. It is not a cross-platform runtime, and it is not presented here as a production-certified autonomous system.

## Supported Shape

The supported main-path execution spine is:

`Surface -> RuntimeOrchestrator -> MainPlanner -> VerifiedExecutor -> CommandRouter -> UIRouter / CodeRouter -> CommitCoordinator`

The MCP surface keeps raw JSON-RPC dictionaries only at ingress and egress. After decode, the supported path uses typed request accessors and typed response export helpers.

Bounded exceptions remain explicitly outside the main runtime contract:

- `oracle setup`
- `oracle doctor`
- optional `vision-sidecar`
- internal sandboxed patch experiments

This checkout does not currently expose a public `oracle_experiment_search` MCP tool.

## Quick Start

```bash
git clone https://github.com/dawsonblock/Oracle-OS.git
cd Oracle-OS
swift build

./.build/debug/oracle setup
./.build/debug/oracle doctor
```

Requirements:

- macOS 14+
- Swift 6.0+
- Accessibility permission
- Screen Recording permission for screenshot-backed flows

## MCP Tool Surface

Oracle OS currently exports 22 public MCP tools under stable `oracle_*` names.

| Category | Tools |
| --- | --- |
| Perception | `oracle_context`, `oracle_state`, `oracle_find`, `oracle_read`, `oracle_inspect`, `oracle_element_at`, `oracle_screenshot` |
| Actions | `oracle_click`, `oracle_type`, `oracle_press`, `oracle_hotkey`, `oracle_scroll`, `oracle_focus`, `oracle_window` |
| Wait | `oracle_wait` |
| Recipes | `oracle_recipes`, `oracle_run`, `oracle_recipe_show`, `oracle_recipe_save`, `oracle_recipe_delete` |
| Vision | `oracle_parse_screen`, `oracle_ground` |

`oracle_screenshot` is a special MCP handler because it returns image content. Vision tools remain optional and experimental.

## Runtime Notes

- OracleController is the interactive local surface.
- OracleControllerHost is bundled support code for the app, not a separate product surface.
- The `oracle` CLI includes explicit tooling exceptions such as setup and doctor; those commands do not define a second runtime.
- Coding and planning features may interact with configured local or remote providers depending on operator configuration. This repository should not be described as guaranteeing local-only reasoning in every deployment.

## Architecture Summary

- `RuntimeOrchestrator` is the main entry point for supported runtime execution.
- `MainPlanner` selects the next command.
- `VerifiedExecutor` is the side-effect trust boundary.
- `CommandRouter` routes to `UIRouter` or `CodeRouter`.
- `CommitCoordinator` is the only committed-state writer.
- Experiment fanout stays isolated in sandbox worktrees and is not part of the guaranteed main-path contract.

See [ARCHITECTURE.md](ARCHITECTURE.md) for a descriptive map and [ARCHITECTURE_RULES.md](ARCHITECTURE_RULES.md) for the normative invariants.

## Development

```bash
swift build
swift test

./.build/debug/oracle setup
./.build/debug/oracle doctor
./.build/debug/oracle mcp
```

macOS-only controller packaging helpers remain under `scripts/`.

## Verification Posture

This repository contains governance and boundary tests, but a Linux container cannot prove the full supported macOS runtime path. Use the status ledger in [docs/STATUS.md](docs/STATUS.md) to distinguish what is structurally enforced from what still requires macOS validation.
