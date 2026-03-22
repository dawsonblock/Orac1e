#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

load_env
ensure_workspace_layout
bash "${ROOT_DIR}/scripts/materialize_repos.sh" >/dev/null

python_aider="$(python_bin_for_venv "${AIDER_VENV}")"
python_hardened="$(python_bin_for_venv "${HARDENED_VENV}")"

if [[ ! -x "${python_aider}" || ! -x "${python_hardened}" ]]; then
  echo "Worker virtualenvs missing. Run scripts/bootstrap.sh first." >&2
  exit 1
fi

export AIDER_BIN="${AIDER_BIN:-${python_aider} -m aider.main}"
export CODE_AGENT_REPO_PATH

export PYTHONPATH="${ROOT_DIR}:${AIDER_REPO_PATH}:${CODE_AGENT_REPO_PATH}${PYTHONPATH:+:${PYTHONPATH}}"
start_background_service   aider   "${python_aider}" -m uvicorn integration.worker_aider.service:app     --host "${ORACLE_HOST}"     --port "${AIDER_PORT}"
wait_for_http_ok "http://${ORACLE_HOST}:${AIDER_PORT}/health" 60

export PYTHONPATH="${ROOT_DIR}:${CODE_AGENT_REPO_PATH}${PYTHONPATH:+:${PYTHONPATH}}"
start_background_service   hardened   "${python_hardened}" -m uvicorn integration.worker_hardened.service:app     --host "${ORACLE_HOST}"     --port "${HARDENED_PORT}"
wait_for_http_ok "http://${ORACLE_HOST}:${HARDENED_PORT}/health" 60

python3 "${ROOT_DIR}/scripts/sync_web_tool_registry.py" || true

echo "Aider worker running on http://${ORACLE_HOST}:${AIDER_PORT}"
echo "Hardened worker running on http://${ORACLE_HOST}:${HARDENED_PORT}"
