#!/usr/bin/env bash
# =============================================================================
# bootstrap_all.sh - Single-command deterministic bootstrap
#
# Sets up ONE shared venv under .venv/, installs all runtime deps including
# the three third-party packages, then runs the integration test suite as
# an automated proof of a clean environment.
#
# Usage:
#   bash scripts/bootstrap_all.sh
#
# Idempotent — safe to run again; existing venv is reused.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VENV="${ROOT}/.venv"
PYTHON="${VENV}/bin/python"
PIP="${VENV}/bin/pip"
PYTEST="${VENV}/bin/pytest"

log() { echo "[bootstrap] $*"; }
die() { echo "[bootstrap] ERROR: $*" >&2; exit 1; }

# ── Step 1: create venv ───────────────────────────────────────────────────────
log "1/6  Python venv → ${VENV}"
if [[ ! -f "${VENV}/bin/activate" ]]; then
    python3 -m venv "${VENV}"
    log "     venv created"
else
    log "     venv already exists (reusing)"
fi
source "${VENV}/bin/activate"

# ── Step 2: upgrade pip ───────────────────────────────────────────────────────
log "2/6  Upgrading pip"
"${PIP}" install --upgrade pip --quiet

# ── Step 3: install root deps ─────────────────────────────────────────────────
log "3/6  Installing root requirements"
"${PIP}" install -r "${ROOT}/requirements.txt" --quiet

# ── Step 4: install third-party packages in editable mode ────────────────────
log "4/6  Installing third-party packages (editable)"

AIDER_PATH="${ROOT}/third_party/aider"
HARDENED_PATH="${ROOT}/third_party/code-agent-runtime"
COCOINDEX_PATH="${ROOT}/third_party/cocoindex-code"

for pkg_path in "${AIDER_PATH}" "${HARDENED_PATH}" "${COCOINDEX_PATH}"; do
    name="$(basename "${pkg_path}")"
    if [[ -f "${pkg_path}/pyproject.toml" || -f "${pkg_path}/setup.py" ]]; then
        log "     pip install -e ${name}"
        "${PIP}" install -e "${pkg_path}" --quiet 2>&1 || {
            log "     WARNING: editable install failed for ${name} — checking fallback"
            # Some packages may not support editable mode cleanly; try regular install
            "${PIP}" install "${pkg_path}" --quiet 2>&1 || \
                log "     WARNING: install failed for ${name} — manual setup may be needed"
        }
    else
        log "     SKIP ${name} — no pyproject.toml or setup.py found"
    fi
done

# ── Step 5: add PYTHONPATH for runtime that uses sys.path injection ───────────
export PYTHONPATH="${ROOT}:${ROOT}/third_party/code-agent-runtime:${PYTHONPATH:-}"
export CODE_AGENT_REPO_PATH="${HARDENED_PATH}"

# ── Step 6: smoke test via integration suite ──────────────────────────────────
log "5/6  Running integration test suite"
cd "${ROOT}"
"${PYTEST}" -q tests/integration \
    --tb=short \
    -p no:warnings \
    2>&1 || die "Integration tests failed — environment is not clean"

log "6/6  Freezing environment → requirements.lock.txt"
"${PIP}" freeze > "${ROOT}/requirements.lock.txt"
log "     Written to requirements.lock.txt"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║          BOOTSTRAP COMPLETE ✓                 ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Activate venv : source .venv/bin/activate"
echo "  Start system  : bash scripts/run_local.sh"
echo "  Full e2e      : bash scripts/smoke_e2e.sh"
