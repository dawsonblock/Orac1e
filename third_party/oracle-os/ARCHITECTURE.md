# Oracle OS Architecture

This document describes the current runtime layout in descriptive terms. Normative rules live in [ARCHITECTURE_RULES.md](ARCHITECTURE_RULES.md).

## Supported Surfaces

The supported product surfaces in this checkout are:

- OracleController app
- MCP server
- `oracle` CLI

OracleControllerHost exists to support the controller app. It is not a separate product surface.

## Main Execution Spine

Normal runtime execution flows through one path:

`Surface -> RuntimeOrchestrator -> MainPlanner -> VerifiedExecutor -> CommandRouter -> UIRouter / CodeRouter -> CommitCoordinator`

At a lower level:

1. A surface submits an intent or typed tool request.
2. `RuntimeOrchestrator` constructs the runtime context and planner input.
3. `MainPlanner` chooses a command.
4. `VerifiedExecutor` validates policy, executes through `CommandRouter`, and produces evidence.
5. `CommitCoordinator` applies committed state from verified events.

## MCP Boundary

The MCP server keeps raw `[String: Any]` only at the JSON-RPC compatibility seam. After decode, `MCPBoundary` and `MCPDispatch` use typed request accessors and typed `Encodable` export helpers.

`oracle_screenshot` remains a special MCP handler because it emits image content. Other normal MCP tools follow the typed dispatch and typed export path.

## Controller Mapping

The controller bridge consumes typed runtime envelopes produced by OracleOS types such as `ActionResult`, `TraceResult`, `CodeExecutionResult`, `RecipeRunBoundaryResult`, and `RuntimeBoundaryResult`. The bridge should reflect typed runtime truth rather than reconstructing meaning from partial legacy keys.

## Experiments

Patch experiments remain an isolated exception layer.

- They run in git worktree sandboxes.
- They are not the main execution spine.
- They do not commit through `CommitCoordinator`.
- They do not promote approval state into the main runtime path.
- They now record isolation metadata, executed commands, canonical paths, and cleanup outcomes.

This checkout does not publish a public `oracle_experiment_search` MCP tool. Experiment orchestration is internal.

## Tooling Exceptions

`oracle setup` and `oracle doctor` are explicit tooling commands. They help operators configure the environment and inspect health, but they are not alternate runtime orchestrators.

The optional `vision-sidecar` remains outside the guaranteed main-path contract.

## Platform Scope

This repository is built around macOS-local automation. A non-macOS environment can validate code structure, typing, and many tests, but it cannot prove the full supported runtime path.
