#!/usr/bin/env bash
# Common utilities for Orac1e Control Plane scripts

# ============================================================================
# Project root (exported for child scripts)
# ============================================================================
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export ROOT_DIR

# ============================================================================
# Python resolution
# ============================================================================
PYTHON_BIN="${PYTHON_BIN:-python3}"
export PYTHON_BIN

# ============================================================================
# Workspace paths
# ============================================================================
WORKSPACE_DIR="${ROOT_DIR}/workspace"
export WORKSPACE_DIR

FIXTURE_REPO_DIR="${WORKSPACE_DIR}/fixtures/buggy-repo"
export FIXTURE_REPO_DIR

# ============================================================================
# Workspace layout (creates standard directories if missing)
# ============================================================================
ensure_workspace_layout() {
    mkdir -p "${WORKSPACE_DIR}/runs"
    mkdir -p "${WORKSPACE_DIR}/logs"
    mkdir -p "${WORKSPACE_DIR}/pids"
    mkdir -p "${WORKSPACE_DIR}/fixtures"
    mkdir -p "${ROOT_DIR}/.oracle/runs"
    mkdir -p "${ROOT_DIR}/.oracle/logs"
    mkdir -p "${ROOT_DIR}/.oracle/state"
    mkdir -p "${ROOT_DIR}/.oracle/tmp"
}

# ============================================================================
# Environment loading
# ============================================================================

# Load environment files from configs/
load_env() {
    local root="${ROOT_DIR}"

    # Load ports.env if it exists
    if [[ -f "${root}/configs/ports.env" ]]; then
        set -a
        source "${root}/configs/ports.env"
        set +a
    fi

    # Load app.env if it exists
    if [[ -f "${root}/configs/app.env" ]]; then
        set -a
        source "${root}/configs/app.env"
        set +a
    fi
}

# ============================================================================
# HTTP helpers
# ============================================================================

# Wait for HTTP endpoint to return 200 OK
# Usage: wait_for_http_ok <url> [timeout_seconds]
wait_for_http_ok() {
    local url="$1"
    local timeout="${2:-30}"
    local start_time=$(date +%s)

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [[ $elapsed -ge $timeout ]]; then
            return 1
        fi

        if curl -sf -o /dev/null "$url" 2>/dev/null; then
            return 0
        fi

        sleep 1
    done
}

# ============================================================================
# Logging
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
