# Wiring manifest

## Added at workspace root

- `integration/contracts/*`
- `integration/shared_py/*`
- `integration/worker_aider/*`
- `integration/worker_hardened/*`
- `integration/retrieval_broker/*`
- `scripts/*`
- `docs/*`

## Added inside Oracle OS

- `Sources/OracleOS/Integration/Contracts/*`
- `Sources/OracleOS/Integration/Persistence/*`
- `Sources/OracleOS/Integration/Policy/*`
- `Sources/OracleOS/Integration/Retrieval/*`
- `Sources/OracleOS/Integration/Workers/*`
- `Sources/OracleOS/Integration/Workspace/*`
- `Sources/OracleOS/Integration/Orchestration/IntegratedCodingRunService.swift`
- `web/src/components/runs/*`

## No source merge performed

The upstream repos remain intact under `third_party/`. The integration layer wraps them instead of rewriting them.
