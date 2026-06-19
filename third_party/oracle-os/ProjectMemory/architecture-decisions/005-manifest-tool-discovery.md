# ADR 005: Manifest-Driven Tool Discovery

## Decision

Tools declare capabilities via `tool.json` manifests. Oracle discovers tools through `ToolRegistry` and routes by capability, not hardcoded names. Direct worker/retrieval clients remain as fallback during migration.

## Reason

Standardizes tool interfaces for consistent invocation. Enables easy extension without modifying Oracle authority. Allows tool versioning and compatibility checking. Provides health monitoring through standardized endpoints.

## Tradeoffs

- **Complexity**: Tool authors must follow manifest schema
- **Migration**: Fallback paths add maintenance burden initially
- **Validation**: Manifest schema must be carefully designed

## Affected Modules

- `integration/tool_sdk/` - tool manifest schema
- `OracleOS/Integration/ToolRegistry` - tool discovery
- `OracleOS/Integration/ToolRouter` - capability-based routing

## Evidence

- [build_blueprint.md:77-86](../../../docs/build_blueprint.md) - tool extension model
- [integration/tool_sdk/manifest.schema.json](../../../../integration/tool_sdk/manifest.schema.json) - schema definition

## Source

Oracle Build v5 tool ecosystem extension
