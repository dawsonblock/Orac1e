#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

load_env
ensure_workspace_layout

python_bin="$(python_bin_for_venv "${RETRIEVAL_VENV}")"
if [[ ! -x "${python_bin}" ]]; then
  echo "Retrieval virtualenv missing. Run scripts/bootstrap.sh first." >&2
  exit 1
fi

export PYTHONPATH="${ROOT_DIR}${PYTHONPATH:+:${PYTHONPATH}}"
start_background_service   run_server   "${python_bin}" -m uvicorn scripts.serve_coding_runs:app     --host "${ORACLE_HOST}"     --port "${RUN_SERVER_PORT:-8790}"

wait_for_http_ok "http://${ORACLE_HOST}:${RUN_SERVER_PORT:-8790}/health" 45

echo "Run server running on http://${ORACLE_HOST}:${RUN_SERVER_PORT:-8790}"
