#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

load_env
ensure_workspace_layout

stop_service_by_name retrieval
stop_service_by_name aider
stop_service_by_name hardened
stop_service_by_name run_server
stop_service_by_name oracle

pkill -U "$(id -u)" -f "integration.retrieval_broker.service" >/dev/null 2>&1 || true
pkill -U "$(id -u)" -f "integration.worker_aider.service" >/dev/null 2>&1 || true
pkill -U "$(id -u)" -f "integration.worker_hardened.service" >/dev/null 2>&1 || true
pkill -U "$(id -u)" -f "scripts.serve_coding_runs:app" >/dev/null 2>&1 || true
pkill -U "$(id -u)" -f "swift run oracle" >/dev/null 2>&1 || true

echo "Stopped local services."
