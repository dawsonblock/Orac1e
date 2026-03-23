#!/usr/bin/env bash
# =============================================================================
# common.sh - Shared shell functions for Oracle scripts
# =============================================================================

# Load environment variables from ports.env if it exists
load_env() {
    local root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
    local ports_env="${root_dir}/configs/ports.env"

    # Default values
    export ORACLE_HOST="${ORACLE_HOST:-127.0.0.1}"
    export BROKER_PORT="${BROKER_PORT:-8001}"
    export AIDER_PORT="${AIDER_PORT:-8002}"
    export HARDENED_PORT="${HARDENED_PORT:-8003}"
    export RUN_SERVER_PORT="${RUN_SERVER_PORT:-8004}"

    # Override with ports.env if present
    if [[ -f "${ports_env}" ]]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" || "$key" =~ ^# ]] && continue
            export "$key=$value"
        done < "${ports_env}"
    fi
}

# Wait for HTTP endpoint to become available
wait_for_http_ok() {
    local url="$1"
    local timeout="${2:-30}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if curl -sf "${url}" > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
        ((elapsed++))
    done
    return 1
}
