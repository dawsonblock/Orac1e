#!/usr/bin/env bash
# Common utilities for Oracle Build scripts

# Load environment files from configs/
load_env() {
    local root="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
    
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
        
        # Try curl with silent mode and follow redirects
        if curl -sf -o /dev/null "$url" 2>/dev/null; then
            return 0
        fi
        
        sleep 1
    done
}

# Log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
