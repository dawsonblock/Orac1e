#!/usr/bin/env bash
# =============================================================================
# run_local.sh - Single-command local system startup
#
# Activates the venv created by bootstrap_all.sh, then starts all four
# services in dependency order with health polling between each step:
#
#   retrieval broker → aider worker → hardened worker → run server
#
# Oracle Swift process (if built) is started last.
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

source "${VENV}/bin/activate"
source "${ROOT}/scripts/common.sh"
load_env

LOG_DIR="${ROOT}/workspace/logs"
PID_DIR="${ROOT}/workspace/pids"
mkdir -p "${LOG_DIR}" "${PID_DIR}"

export PYTHONPATH="${ROOT}:${ROOT}/third_party/code-agent-runtime:${PYTHONPATH:-}"
export CODE_AGENT_REPO_PATH="${ROOT}/third_party/code-agent-runtime"

log() { echo "[run_local] $*"; }

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
    python -m uvicorn "${module}" \
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

start_service "retrieval-broker" \
    "integration.retrieval_broker.service:app" \
    "${BROKER_PORT}"
poll_health "retrieval-broker" "http://${ORACLE_HOST}:${BROKER_PORT}/health"

start_service "worker-aider" \
    "integration.worker_aider.service:app" \
    "${AIDER_PORT}"
poll_health "worker-aider" "http://${ORACLE_HOST}:${AIDER_PORT}/health"

start_service "worker-hardened" \
    "integration.worker_hardened.service:app" \
    "${HARDENED_PORT}"
poll_health "worker-hardened" "http://${ORACLE_HOST}:${HARDENED_PORT}/health"

start_service "run-server" \
    "scripts.serve_coding_runs:app" \
    "${RUN_SERVER_PORT}"
poll_health "run-server" "http://${ORACLE_HOST}:${RUN_SERVER_PORT}/health"

if [[ "${NO_ORACLE}" == "0" ]]; then
    bash "${ROOT}/scripts/start_oracle.sh" || \
        log "WARNING: Oracle Swift process failed to start — Python services are still up"
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  All Python services are running                      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  Retrieval broker : http://${ORACLE_HOST}:${BROKER_PORT}/health"
echo "  Aider worker     : http://${ORACLE_HOST}:${AIDER_PORT}/health"
echo "  Hardened worker  : http://${ORACLE_HOST}:${HARDENED_PORT}/health"
echo "  Run server       : http://${ORACLE_HOST}:${RUN_SERVER_PORT}/health"
echo ""
echo "  Stop all         : bash scripts/stop_all.sh"
