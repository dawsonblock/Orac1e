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

# ── Resolve a Python >=3.11 interpreter ──────────────────────────────────────
_resolve_python311() {
    for candidate in python3.12 python3.11; do
        if command -v "${candidate}" >/dev/null 2>&1; then
            local ver
            ver=$("${candidate}" -c 'import sys; print(sys.version_info[:2])')
            # Accept (3,11), (3,12), (3,13)...
            if "${candidate}" -c 'import sys; assert sys.version_info >= (3,11)' 2>/dev/null; then
                echo "$(command -v "${candidate}")"
                return 0
            fi
        fi
    done
    return 1
}

PYTHON_BIN="$(_resolve_python311 || true)"
if [[ -z "${PYTHON_BIN}" ]]; then
    die "Python 3.11+ is required but not found. Install it with: brew install python@3.11"
fi
log "     Using ${PYTHON_BIN} ($(${PYTHON_BIN} --version 2>&1))"

# ── Step 1: create venv ───────────────────────────────────────────────────────
log "1/6  Python venv → ${VENV}"
if [[ ! -f "${VENV}/bin/activate" ]]; then
    "${PYTHON_BIN}" -m venv "${VENV}"
    log "     venv created"
else
    # Verify the existing venv is also >=3.11; wipe it if not
    existing_ver=$("${VENV}/bin/python" -c 'import sys; print(sys.version_info[:2])' 2>/dev/null || echo "(0, 0)")
    if ! "${VENV}/bin/python" -c 'import sys; assert sys.version_info >= (3,11)' 2>/dev/null; then
        log "     Existing venv is ${existing_ver} (< 3.11) — recreating with ${PYTHON_BIN}"
        rm -rf "${VENV}"
        "${PYTHON_BIN}" -m venv "${VENV}"
        log "     venv recreated"
    else
        log "     venv already exists and is ${existing_ver} (reusing)"
    fi
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
# Purge any stale egg-info / dist-info left by previous failed installs.
# Without this, pip's resolver sees those registrations in every Python
# environment on the machine (they leak out of the venv via PYTHONPATH).
find "${ROOT}/third_party" \
    \( -name "*.egg-info" -o -name "*.dist-info" \) \
    -maxdepth 4 -type d \
    -exec rm -rf {} + 2>/dev/null || true
# Vendored packages live in third_party/ which has no per-package .git history.
# setuptools-scm / hatch-vcs detect the *parent* repo root but can't infer an
# individual package version. Pin a pretend version so the build succeeds.
#   SETUPTOOLS_SCM_PRETEND_VERSION_FOR_*  — used by setuptools-scm (aider-chat)
#   HATCH_VCS_PRETEND_VERSION             — used by hatch-vcs (cocoindex-code)
export SETUPTOOLS_SCM_PRETEND_VERSION_FOR_AIDER_CHAT="0.0.0"
export SETUPTOOLS_SCM_PRETEND_VERSION_FOR_COCOINDEX_CODE="0.0.0"
export HATCH_VCS_PRETEND_VERSION="0.0.0"

# Pre-install build backends so --no-build-isolation works as a fallback
"${PIP}" install --quiet hatchling hatch-vcs setuptools-scm wheel

AIDER_PATH="${ROOT}/third_party/aider"
HARDENED_PATH="${ROOT}/third_party/code-agent-runtime"
COCOINDEX_PATH="${ROOT}/third_party/cocoindex-code"

for pkg_path in "${HARDENED_PATH}" "${COCOINDEX_PATH}"; do
    name="$(basename "${pkg_path}")"
    if [[ -f "${pkg_path}/pyproject.toml" || -f "${pkg_path}/setup.py" ]]; then
        log "     pip install -e ${name}"
        "${PIP}" install -e "${pkg_path}" --quiet 2>&1 || {
            log "     WARNING: editable install failed for ${name} — trying --no-build-isolation"
            "${PIP}" install -e "${pkg_path}" --no-build-isolation --quiet 2>&1 || {
                log "     WARNING: --no-build-isolation also failed for ${name} — using PYTHONPATH fallback"
            }
        }
    else
        log "     SKIP ${name} — no pyproject.toml or setup.py found"
    fi
done
# aider: skip pip install entirely — it pins hundreds of exact-version deps
# that conflict with our services. PYTHONPATH (set in step 5) provides import.
log "     SKIP aider pip-install (PYTHONPATH-only; avoids resolver conflicts)"

# ── Step 5: add PYTHONPATH for runtime that uses sys.path injection ───────────
# Always include src/ layouts; makes imports work even if pip install failed.
export PYTHONPATH="${ROOT}:${ROOT}/third_party/code-agent-runtime:${ROOT}/third_party/cocoindex-code/src:${ROOT}/third_party/aider:${PYTHONPATH:-}"
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
