# Oracle Build v5 merge notes

## Goal

Keep the stronger v4 backend and restore the missing operator-facing coding entrypoints from v2.

## What changed

- Restored `oracle coding list|show|run|approve|reject` in `third_party/oracle-os/Sources/oracle/main.swift`.
- Added `OracleCodingRuntime.swift` as the Swift wrapper for coding runs.
- Preserved v4 `IntegratedCodingRunService` as the creation path for new runs.
- Approve/reject now prefer the v4 run server bridge and fall back to the local Python promotion script when the server is unavailable.
- `oracle tools` and tool registry health remained intact.
- README title and status were corrected.

## What is still open

- The Oracle Controller coding workspace from v2 was not fully reintroduced here.
- This archive was not validated with a full macOS `swift build` in the current environment.
- End-to-end proof still depends on a real Oracle macOS runtime with live sidecars.

## Why this shape

This keeps the strongest part of v4 — the worktree/validation/promotion closure — while restoring the highest-value user-facing control path without replacing v4's newer tool-routing work.
