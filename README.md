# Orac1e Control Plane v0.2-alpha

A supervised local coding-agent control plane for macOS.

**This is not autonomous. It is not an OS. It requires operator approval for promotion.**

## What It Does

Orac1e manages coding runs: a worker proposes a patch, validation runs, an operator approves, and the patch is promoted to the canonical repository. Optionally, a vision sidecar provides screen grounding via VLM.

## Quick Start

```bash
# Bootstrap (creates .venv, installs deps)
./scripts/bootstrap_all.sh

# Preflight check (verifies deps are installed)
python3 -m integration.preflight

# Start services
bash scripts/run_local.sh

# Run smoke test
bash scripts/smoke_test.sh
```

## Architecture

- `integration/` — Core services: lifecycle, orchestrator, preflight, workers
- `scripts/` — Operational tooling: run server, promotion logic, smoke tests
- `oracle_runtime/` — Approval store and runtime components
- `configs/` — Policy files: command, mutation, approval, tool, validation profiles
- `third_party/oracle-os/` — Swift macOS app and vision sidecar
- `workspace/` — Runtime data: runs, fixtures, artifacts

## Security

- **Approval auth**: Promotion endpoints require `ORACLE_APPROVAL_TOKEN` Bearer token
- **Command policy**: Validation commands are filtered against allow/deny lists before execution
- **Validation required**: No-validation promotion is blocked by default (unsafe override exists)
- **Path blocking**: Modifications to `.git/`, `.github/`, `secrets/`, `infra/`, `deploy/` are blocked

## Version

- Python control plane: 0.2.0
- Vision sidecar: 2.2.0
- Swift app: See `third_party/oracle-os/Package.swift`
