#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

load_env
ensure_workspace_layout
bash "${ROOT_DIR}/scripts/check_env.sh"
bash "${ROOT_DIR}/scripts/materialize_repos.sh"

ensure_python_venv "${RETRIEVAL_VENV}"
ensure_python_venv "${AIDER_VENV}"
ensure_python_venv "${HARDENED_VENV}"

if [[ "${ORACLE_SKIP_PIP_INSTALL:-0}" == "1" ]]; then
  warn "ORACLE_SKIP_PIP_INSTALL=1 set; skipping pip installs"
else
  note "Installing retrieval adapter dependencies"
  install_adapter_requirements "${RETRIEVAL_VENV}"
  install_requirements_file "${RETRIEVAL_VENV}" "${ROOT_DIR}/integration/retrieval_broker/requirements.txt"
  install_pyproject_dependencies "${RETRIEVAL_VENV}" "${COCOINDEX_REPO_PATH}/pyproject.toml"

  note "Installing Aider adapter dependencies"
  install_adapter_requirements "${AIDER_VENV}"
  install_requirements_file "${AIDER_VENV}" "${ROOT_DIR}/integration/worker_aider/requirements.txt"
  install_requirements_file "${AIDER_VENV}" "${AIDER_REPO_PATH}/requirements.txt"

  note "Installing hardened worker dependencies"
  install_adapter_requirements "${HARDENED_VENV}"
  install_requirements_file "${HARDENED_VENV}" "${ROOT_DIR}/integration/worker_hardened/requirements.txt"
  install_pyproject_dependencies "${HARDENED_VENV}" "${CODE_AGENT_REPO_PATH}/pyproject.toml"
fi

"${PYTHON_BIN}" -m compileall "${ROOT_DIR}/integration" >/dev/null
"${PYTHON_BIN}" -m compileall "${CODE_AGENT_REPO_PATH}" >/dev/null
(
  cd "${CODE_AGENT_REPO_PATH}"
  PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest --collect-only -q >/dev/null
)

"${PYTHON_BIN}" "${ROOT_DIR}/scripts/make_fixture_repo.py"
"${PYTHON_BIN}" "${ROOT_DIR}/scripts/sync_web_tool_registry.py"
echo "Bootstrap complete."
