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
  # Split ORACLE_RUN_ARGS into an array so flags with spaces are handled correctly.
  IFS=' ' read -ra _oracle_run_args <<< "${ORACLE_RUN_ARGS:-}"
  exec swift run oracle "${_oracle_run_args[@]+"${_oracle_run_args[@]}"}"  
) >>"${log_file}" 2>&1 &
oracle_pid=$!
echo "${oracle_pid}" >"${pid_file}"

# Wait for Oracle process to start (basic check)
sleep 2
if ! is_pid_running "${oracle_pid}"; then
  echo "Oracle exited immediately. See ${log_file}" >&2
  exit 1
fi

# Enhanced readiness check: verify Oracle HTTP health endpoint is responsive
# This ensures the Oracle backend is actually operational, not just running
ORACLE_HEALTH_URL="http://${ORACLE_HOST}:${ORACLE_PORT:-8080}/health"
ORACLE_READY_TIMEOUT="${ORACLE_READY_TIMEOUT:-60}"

note "Waiting for Oracle health endpoint at ${ORACLE_HEALTH_URL}..."
if wait_for_http_ok "${ORACLE_HEALTH_URL}" "${ORACLE_READY_TIMEOUT}"; then
  note "Oracle health check passed - backend is responsive"
else
  echo "Oracle health check failed. Backend may not be fully initialized." >&2
  echo "Check ${log_file} for details" >&2
  # Don't fail immediately - give Oracle more time to start
  note "Retrying health check with extended timeout..."
  if wait_for_http_ok "${ORACLE_HEALTH_URL}" "${ORACLE_READY_RETRY_TIMEOUT:-60}"; then
    note "Oracle eventually became ready"
  else
    echo "Oracle failed to become ready. See ${log_file}" >&2
    exit 1
  fi
fi

# Additional IPC path verification if ORACLE_IPC_PATH is set
if [[ -n "${ORACLE_IPC_PATH:-}" ]]; then
  note "Verifying IPC path: ${ORACLE_IPC_PATH}"
  for i in {1..10}; do
    if [[ -S "${ORACLE_IPC_PATH}" ]]; then
      note "IPC socket is available at ${ORACLE_IPC_PATH}"
      break
    fi
    if [[ $i -eq 10 ]]; then
      warn "IPC socket not found at ${ORACLE_IPC_PATH} after 10 attempts"
      exit 1
    fi
    sleep 1
  done
fi

echo "Oracle started (pid ${oracle_pid})."
echo "Tool manifests: ${ORACLE_TOOL_MANIFESTS}"
echo "Health check: ${ORACLE_HEALTH_URL}"
