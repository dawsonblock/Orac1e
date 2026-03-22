#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

load_env
ensure_workspace_layout

for dir in \
  "${WORKSPACE_DIR}/worktrees" \
  "${WORKSPACE_DIR}/artifacts" \
  "${WORKSPACE_DIR}/logs" \
  "${WORKSPACE_DIR}/pids"; do
  if [[ -d "${dir}" ]]; then
    find "${dir}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  fi
done

if [[ "${CLEAN_VENVS:-0}" == "1" ]] && [[ -d "${VENV_DIR}" ]]; then
  find "${VENV_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

echo "Workspace cleaned."
