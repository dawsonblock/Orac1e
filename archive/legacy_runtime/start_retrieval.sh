#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

load_env
ensure_workspace_layout
bash "${ROOT_DIR}/scripts/materialize_repos.sh" >/dev/null

python_bin="$(python_bin_for_venv "${RETRIEVAL_VENV}")"
if [[ ! -x "${python_bin}" ]]; then
  echo "Retrieval virtualenv missing. Run scripts/bootstrap.sh first." >&2
  exit 1
fi

export PYTHONPATH="${ROOT_DIR}:${COCOINDEX_REPO_PATH}/src${PYTHONPATH:+:${PYTHONPATH}}"
export COCOINDEX_REPO_PATH

start_background_service   retrieval   "${python_bin}" -m uvicorn integration.retrieval_broker.service:app     --host "${ORACLE_HOST}"     --port "${BROKER_PORT}"

wait_for_http_ok "http://${ORACLE_HOST}:${BROKER_PORT}/health" 60
python3 "${ROOT_DIR}/scripts/sync_web_tool_registry.py" || true

echo "Retrieval broker running on http://${ORACLE_HOST}:${BROKER_PORT}"
