# Oracle Coding System (Build v5-merged-v6-planner)

## ⚠️ Status: Supervised Coding Scaffold (P0 #4)
This repository is currently in a **Supervised Coding Paradigm**. It is not yet an autonomous agent.
Execution requires manual steering through the `scripts/` layer, though the `Planner` layer is now implemented for reliability.

## 🚀 Convergence Highlights
- **Hermetic Packaging**: Aider and other third-party dependencies are installed as editable packages in `.venv`. No `PYTHONPATH` hacks required.
- **Planner Layer**: Enforces structured JSON proposals and rejects empty plans (P0 #3).
- **Single Runtime**: Legacy v4 scripts have been moved to `archive/legacy_runtime/`.

## 🛠️ Usage
1. **Bootstrap**: `./scripts/bootstrap_all.sh` (Requires Python 3.12)
2. **Test**: `./scripts/smoke_test.sh`
3. **Planner Proof**: `./scripts/full_pipeline_test.sh`

## 🏗️ Architecture
- `integration/workers_planner.py`: Reliability and Plan Rejection layer.
- `integration/worker_hardened/`: Deterministic fallback logic.
- `third_party/`: Pinned and vendored components.
