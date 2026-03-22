#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

load_env
ensure_workspace_layout
require_command swift

bash "${ROOT_DIR}/scripts/materialize_repos.sh" >/dev/null
export ORACLE_TOOL_MANIFESTS
oracle_root="${ORACLE_REPO_PATH}"
if [[ ! -f "${oracle_root}/Package.swift" ]]; then
  echo "Oracle package not found at ${oracle_root}" >&2
  exit 1
fi

log_file="$(log_file_for oracle)"
pid_file="$(pid_file_for oracle)"

if [[ -f "${pid_file}" ]]; then
  existing_pid="$(cat "${pid_file}")"
  if [[ -n "${existing_pid}" ]] && is_pid_running "${existing_pid}"; then
    note "oracle already running (pid ${existing_pid})"
    echo "Oracle process already running; log -> ${log_file}"
    exit 0
  fi
  rm -f "${pid_file}"
fi

note "Building Oracle Swift package"
(
  cd "${oracle_root}"
  swift build
) >>"${log_file}" 2>&1

note "Starting Oracle runtime; log -> ${log_file}"
(
  cd "${oracle_root}"
  exec swift run oracle ${ORACLE_RUN_ARGS:-}
) >>"${log_file}" 2>&1 &
oracle_pid=$!
echo "${oracle_pid}" >"${pid_file}"
sleep 2
if ! is_pid_running "${oracle_pid}"; then
  echo "Oracle exited immediately. See ${log_file}" >&2
  exit 1
fi

echo "Oracle started (pid ${oracle_pid})."
echo "Tool manifests: ${ORACLE_TOOL_MANIFESTS}"
