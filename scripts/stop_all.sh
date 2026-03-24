#!/usr/bin/env bash
# Stop all Oracle Build services
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PID_DIR="${ROOT}/workspace/pids"

log() { echo "[stop_all] $*"; }

# Stop services in reverse order
services=("run-server" "worker-hardened" "worker-aider" "retrieval-broker")

for service in "${services[@]}"; do
    pid_file="${PID_DIR}/${service}.pid"
    if [[ -f "${pid_file}" ]]; then
        pid=$(cat "${pid_file}")
        if kill -0 "${pid}" 2>/dev/null; then
            log "Stopping ${service} (pid ${pid})..."
            kill "${pid}" 2>/dev/null || true
            # Wait for process to terminate
            for i in {1..10}; do
                if ! kill -0 "${pid}" 2>/dev/null; then
                    break
                fi
                sleep 0.5
            done
            # Force kill if still running
            if kill -0 "${pid}" 2>/dev/null; then
                log "Force stopping ${service}..."
                kill -9 "${pid}" 2>/dev/null || true
            fi
        fi
        rm -f "${pid_file}"
        log "${service} stopped"
    fi
done

log "All services stopped"
