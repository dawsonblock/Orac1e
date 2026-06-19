#!/usr/bin/env bash
# =============================================================================
# run_local.sh - Single-command local system startup
#
# Activates the venv created by bootstrap_all.sh, then starts services that
# are enabled in configs/system.yaml in dependency order:
#
#   retrieval broker → aider worker → hardened worker → run server
#
# Oracle Swift process is started last unless --no-oracle is given or
# oracle.enabled=false in configs/system.yaml.
#
# Usage:
#   bash scripts/run_local.sh [--no-oracle] [--skip-health]
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VENV="${ROOT}/.venv"

NO_ORACLE=0
SKIP_HEALTH=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-oracle)    NO_ORACLE=1; shift ;;
        --skip-health)  SKIP_HEALTH=1; shift ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

if [[ ! -f "${VENV}/bin/activate" ]]; then
    echo "[run_local] ERROR: .venv not found — run scripts/bootstrap_all.sh first" >&2
    exit 1
fi

# ============================================================================
# Consistent venv activation - use explicit paths after this
# ============================================================================
source "${VENV}/bin/activate"

# Use venv Python explicitly for all operations
VENV_PYTHON="${VENV}/bin/python"

# Verify preflight works with activated venv
"$VENV_PYTHON" -c "from integration.preflight import check; check()"

# Load common utilities
source "${ROOT}/scripts/common.sh"
load_env

LOG_DIR="${ROOT}/workspace/logs"
PID_DIR="${ROOT}/workspace/pids"
mkdir -p "${LOG_DIR}" "${PID_DIR}"

export CODE_AGENT_REPO_PATH="${ROOT}/third_party/code-agent-runtime"

log() { echo "[run_local] $*"; }

# Read configs/system.yaml and return 0 (enabled) or 1 (disabled) for a
# dotted key path such as "retrieval.enabled" or "workers.aider.enabled".
# Defaults to enabled when the key is absent or PyYAML is unavailable.
yaml_service_enabled() {
    local key_path="$1"
    "$VENV_PYTHON" - "${ROOT}/configs/system.yaml" "${key_path}" <<'PY'
import sys
from pathlib import Path
try:
    import yaml
except ImportError:
    sys.exit(0)  # default: enabled
cfg_path = Path(sys.argv[1])
if not cfg_path.exists():
    sys.exit(0)  # default: enabled
with cfg_path.open() as fh:
    cfg = yaml.safe_load(fh) or {}
keys = sys.argv[2].split(".")
val = cfg
for k in keys:
    if not isinstance(val, dict) or k not in val:
        sys.exit(0)  # key absent → enabled by default
    val = val[k]
# val may be a bool or a dict with an "enabled" key
if isinstance(val, bool):
    sys.exit(0 if val else 1)
if isinstance(val, dict):
    enabled = val.get("enabled", True)
    sys.exit(0 if enabled else 1)
sys.exit(0)  # unknown shape → enabled by default
PY
}

start_service() {
    local name="$1"
    local module="$2"
    local port="$3"
    local log_file="${LOG_DIR}/${name}.log"
    local pid_file="${PID_DIR}/${name}.pid"

    if [[ -f "${pid_file}" ]]; then
        existing="$(cat "${pid_file}")"
        if kill -0 "${existing}" 2>/dev/null; then
            log "${name} already running (pid ${existing})"
            return 0
        fi
        rm -f "${pid_file}"
    fi

    log "Starting ${name} on port ${port}"
    "$VENV_PYTHON" -m uvicorn "${module}" \
        --host "127.0.0.1" \
        --port "${port}" \
        --log-level info \
        >> "${log_file}" 2>&1 &
    echo $! > "${pid_file}"
    log "${name} pid=$(cat "${pid_file}") → log: ${log_file}"
}

poll_health() {
    local name="$1"
    local url="$2"
    local timeout="${3:-30}"
    if [[ "${SKIP_HEALTH}" == "1" ]]; then return 0; fi
    log "Waiting for ${name} at ${url} ..."
    wait_for_http_ok "${url}" "${timeout}" || {
        echo "[run_local] ERROR: ${name} did not become healthy within ${timeout}s" >&2
        exit 1
    }
    log "${name} is healthy"
}

# ── Services ──────────────────────────────────────────────────────────────────

if yaml_service_enabled "retrieval.broker.enabled"; then
    start_service "retrieval-broker" \
        "integration.retrieval_broker.service:app" \
        "${BROKER_PORT:-8081}"
    poll_health "retrieval-broker" "http://${ORACLE_HOST:-127.0.0.1}:${BROKER_PORT:-8081}/health"
else
    log "SKIP retrieval-broker (disabled in configs/system.yaml)"
fi

if yaml_service_enabled "workers.aider.enabled"; then
    start_service "worker-aider" \
        "integration.worker_aider.service:app" \
        "${AIDER_PORT:-8082}"
    poll_health "worker-aider" "http://${ORACLE_HOST:-127.0.0.1}:${AIDER_PORT:-8082}/health"
else
    log "SKIP worker-aider (disabled in configs/system.yaml)"
fi

if yaml_service_enabled "workers.hardened.enabled"; then
    start_service "worker-hardened" \
        "integration.worker_hardened.service:app" \
        "${HARDENED_PORT:-8083}"
    poll_health "worker-hardened" "http://${ORACLE_HOST:-127.0.0.1}:${HARDENED_PORT:-8083}/health"
else
    log "SKIP worker-hardened (disabled in configs/system.yaml)"
fi

# Start run server
start_service "run-server" \
    "scripts.serve_coding_runs:app" \
    "${RUN_SERVER_PORT:-8080}"
poll_health "run-server" "http://${ORACLE_HOST:-127.0.0.1}:${RUN_SERVER_PORT:-8080}/health"

if [[ "${NO_ORACLE}" == "0" ]] && yaml_service_enabled "oracle.swift_controller.enabled"; then
    if [[ -f "${ROOT}/scripts/start_oracle.sh" ]]; then
        bash "${ROOT}/scripts/start_oracle.sh" || \
            log "WARNING: Oracle Swift process failed to start — Python services are still up"
    else
        log "WARNING: start_oracle.sh not found — skipping Oracle Swift"
    fi
elif [[ "${NO_ORACLE}" == "1" ]]; then
    log "SKIP oracle (--no-oracle flag)"
else
    log "SKIP oracle (disabled in configs/system.yaml)"
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  All Python services are running                      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  Run server       : http://${ORACLE_HOST:-127.0.0.1}:${RUN_SERVER_PORT:-8080}/health"
echo "  Run server ready : http://${ORACLE_HOST:-127.0.0.1}:${RUN_SERVER_PORT:-8080}/ready"
echo "  Run endpoint     : http://${ORACLE_HOST:-127.0.0.1}:${RUN_SERVER_PORT:-8080}/run"
echo ""
echo "  Stop all         : bash scripts/stop_all.sh"
