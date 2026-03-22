#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

bash "${ROOT_DIR}/scripts/start_retrieval.sh"
bash "${ROOT_DIR}/scripts/start_workers.sh"
bash "${ROOT_DIR}/scripts/start_run_server.sh"
bash "${ROOT_DIR}/scripts/start_oracle.sh"
echo "All services started."
