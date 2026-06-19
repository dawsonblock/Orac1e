# Architecture Rules

This document is the normative invariant set for this checkout.

## Product Surface

Supported runtime surfaces are:

- OracleController app
- MCP server
- `oracle` CLI

`oracle setup`, `oracle doctor`, and the optional `vision-sidecar` are explicit tooling exceptions. They are not alternate runtime spines.

## Main-Path Execution

The supported execution spine is:

`Surface -> RuntimeOrchestrator -> MainPlanner -> VerifiedExecutor -> CommandRouter -> UIRouter / CodeRouter -> CommitCoordinator`

No new direct execution path may bypass this spine.

## MCP Boundary

- Raw `[String: Any]` is allowed only at the JSON-RPC ingress and egress seam.
- After decode, normal MCP dispatch must use typed accessors, `JSONValue`, typed request structs, and typed `Encodable` result payloads.
- Internal MCP dispatch code must not grow new dictionary-shaped transport once the outer seam is decoded.

## Execution Authority

- `VerifiedExecutor` is the side-effect trust boundary for supported runtime execution.
- `CommitCoordinator` is the only committed-state writer.
- No new raw process spawning may be added to normal runtime code outside approved adapter or tooling boundaries.
- No new ambient authority bag or second orchestrator may be introduced.

Approved exception-style boundaries that may spawn subprocesses or operate outside the main runtime loop must stay clearly isolated:

- workspace-scoped command execution adapters already routed under the code execution subsystem
- CLI tooling helpers for setup and doctor
- bounded experiment sandbox helpers
- optional vision tooling

## Controller Mapping

- `ActionResult.swift` is the source of truth for runtime result envelopes that cross runtime boundaries.
- The controller bridge must map from typed runtime results.
- The controller bridge must not depend on legacy payload probing for core truth when the typed source provides that field.

## Experiments

- Experiment execution is a bounded exception, not part of the guaranteed main-path contract.
- Experiment runs must stay sandboxed and must not mutate live committed runtime state.
- Experiment runs must not commit through `CommitCoordinator`.
- Experiment runs must not use approval-store promotion as a path back into the main execution spine.
- Experiment runs must record enough metadata to prove sandbox containment, commands executed, and cleanup outcome.

## Platform Honesty

- Do not claim cross-platform runtime support.
- Do not claim production certification.
- Do not claim local-only reasoning for every deployment when configured providers may be remote.
- Do not claim hardening completion beyond what tests and available validation actually prove.
