# Runtime Baseline 36

Baseline capture for runtime unification work on branch `cursor/runtime-architecture-unification-22a0`.

## Environment

- Date: 2026-03-19
- Host OS: Linux 6.1.147
- Swift version: **unavailable in this environment** (`swift: command not found`)

## Package dependencies

From `Package.swift`:

- Local package:
  - `Vendor/AXorcist` (path dependency)

From `Package.resolved`:

- `swift-argument-parser` (`1.7.0`, revision `c5d11a805e765f52ba34ec7284bd4fcd6ba68615`)

## Build and test baseline

Saved logs:

- Build log: `Diagnostics/runtime_baseline_36_build.log`
- Test log: `Diagnostics/runtime_baseline_36_test.log`

Observed status:

- `swift build`: **failed** (exit code `127`, toolchain missing)
- `swift test`: **failed** (exit code `127`, toolchain missing)
- Total test count: **not measurable in this environment** (tests did not run)

## Runtime entrypoints (current)

- CLI:
  - `Sources/oracle/main.swift`
  - commands include `mcp`, `setup`, `doctor`, `dashboard`, `status`, `version`
- Controller app executable:
  - product target `OracleController`
  - source entrypoint `Sources/OracleController`
- Host process executable:
  - product target `OracleControllerHost`
  - host server in `Sources/OracleControllerHost/ControllerHostServer.swift`
- MCP:
  - `Sources/OracleOS/MCP/MCPServer.swift` (JSON-RPC over stdio)
  - dispatch path currently via `Sources/OracleOS/MCP/MCPDispatch.swift`
- HTTP:
  - no dedicated HTTP runtime server entrypoint identified during baseline scan

## Known legacy / transitional surfaces

- `performAction(...)` runtime bridge surface:
  - present in `Sources/OracleOS/Execution/ActionResult.swift` (RuntimeOrchestrator extension)
  - additional runtime-facing usage in `Sources/OracleOS/Intent/Actions/Actions.swift`
- `executeLegacy(...)`:
  - no source match found in `Sources/`
- Deprecated / legacy runtime initializer surfaces:
  - `RuntimeOrchestrator` still has deprecated context-based initializers
  - `AgentLoop` remains broad (planner/execution/recovery ownership still present)
- `VerifiedActionExecutor` shim:
  - class present in `Sources/OracleOS/Execution/ActionResult.swift`
  - referenced from runtime/action/recipe paths
- `ToolDispatcher` synthetic branches:
  - present in `Sources/OracleOS/Execution/ToolDispatcher.swift`
  - includes synthetic outcomes such as `"no-host: skipped"`, `"opened \(url)"`, `"scrolled"`

## Baseline conclusion

The repository contains both the newer intent-oriented runtime spine and legacy bypass surfaces. Baseline logs are captured before architecture cleanup.
