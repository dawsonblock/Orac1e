#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

resolve_python_bin() {
  if [[ -n "${ORACLE_PYTHON_BIN:-}" ]]; then
    echo "${ORACLE_PYTHON_BIN}"
    return 0
  fi
  local candidate
  for candidate in python3.13 python3.12 python3.11 python3; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      echo "$(command -v "${candidate}")"
      return 0
    fi
  done
  echo "python3"
}

WORKSPACE_DIR="${ROOT_DIR}/workspace"
LOG_DIR="${WORKSPACE_DIR}/logs"
PID_DIR="${WORKSPACE_DIR}/pids"
VENV_DIR="${WORKSPACE_DIR}/venvs"
FIXTURE_REPO_DIR="${WORKSPACE_DIR}/fixtures/buggy-repo"

load_env() {
  if [[ -f "${ROOT_DIR}/configs/app.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/configs/app.env"
    set +a
  fi
  if [[ -f "${ROOT_DIR}/configs/ports.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/configs/ports.env"
    set +a
  fi

  export ROOT_DIR WORKSPACE_DIR LOG_DIR PID_DIR VENV_DIR FIXTURE_REPO_DIR
  export PYTHON_BIN="$(resolve_python_bin)"
  export ORACLE_HOST="${ORACLE_HOST:-127.0.0.1}"
  export ORACLE_PORT="${ORACLE_PORT:-8080}"
  export BROKER_PORT="${BROKER_PORT:-8787}"
  export AIDER_PORT="${AIDER_PORT:-8788}"
  export HARDENED_PORT="${HARDENED_PORT:-8789}"
  export RUN_SERVER_PORT="${RUN_SERVER_PORT:-8790}"
  export ORACLE_TOOL_MANIFESTS="${ORACLE_TOOL_MANIFESTS:-${ROOT_DIR}/integration/tools}"
  export ORACLE_REPO_PATH="${ORACLE_REPO_PATH:-${WORKSPACE_DIR}/repos/oracle-os}"
  export COCOINDEX_REPO_PATH="${COCOINDEX_REPO_PATH:-${WORKSPACE_DIR}/repos/cocoindex-code}"
  export CODE_AGENT_REPO_PATH="${CODE_AGENT_REPO_PATH:-${WORKSPACE_DIR}/repos/code-agent-runtime}"
  export AIDER_REPO_PATH="${AIDER_REPO_PATH:-${WORKSPACE_DIR}/repos/aider}"
  export RETRIEVAL_VENV="${RETRIEVAL_VENV:-${VENV_DIR}/retrieval}"
  export AIDER_VENV="${AIDER_VENV:-${VENV_DIR}/aider}"
  export HARDENED_VENV="${HARDENED_VENV:-${VENV_DIR}/hardened}"
}

ensure_workspace_layout() {
  mkdir -p \
    "${WORKSPACE_DIR}/repos" \
    "${WORKSPACE_DIR}/worktrees" \
    "${WORKSPACE_DIR}/runs" \
    "${WORKSPACE_DIR}/artifacts" \
    "${WORKSPACE_DIR}/cache" \
    "${WORKSPACE_DIR}/fixtures" \
    "${LOG_DIR}" \
    "${PID_DIR}" \
    "${VENV_DIR}"
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Missing required command: ${name}" >&2
    exit 1
  fi
}

warn() {
  echo "WARN: $*" >&2
}

note() {
  echo "==> $*"
}

python_bin_for_venv() {
  local venv_path="$1"
  echo "${venv_path}/bin/python"
}

pip_bin_for_venv() {
  local venv_path="$1"
  echo "${venv_path}/bin/pip"
}

pid_file_for() {
  local name="$1"
  echo "${PID_DIR}/${name}.pid"
}

log_file_for() {
  local name="$1"
  echo "${LOG_DIR}/${name}.log"
}

is_pid_running() {
  local pid="$1"
  kill -0 "$pid" >/dev/null 2>&1
}

stop_service_by_name() {
  local name="$1"
  local pid_file
  pid_file="$(pid_file_for "$name")"

  if [[ -f "${pid_file}" ]]; then
    local pid
    pid="$(cat "${pid_file}")"
    if [[ -n "${pid}" ]] && is_pid_running "${pid}"; then
      note "Stopping ${name} (pid ${pid})"
      kill "${pid}" >/dev/null 2>&1 || true
      for _ in 1 2 3 4 5; do
        if ! is_pid_running "${pid}"; then
          break
        fi
        sleep 1
      done
      if is_pid_running "${pid}"; then
        warn "${name} did not exit cleanly; sending SIGKILL"
        kill -9 "${pid}" >/dev/null 2>&1 || true
      fi
    fi
    rm -f "${pid_file}"
  fi
}

wait_for_http_ok() {
  local url="$1"
  local timeout_seconds="${2:-30}"
  "${PYTHON_BIN}" - "$url" "$timeout_seconds" <<'PY'
import sys
import time
from urllib.error import URLError, HTTPError
from urllib.request import Request, urlopen

url = sys.argv[1]
timeout = float(sys.argv[2])
deadline = time.time() + timeout
last_error = None

while time.time() < deadline:
    req = Request(url, method="GET")
    try:
        with urlopen(req, timeout=2.0) as resp:
            status = getattr(resp, "status", 200)
            if 200 <= status < 300:
                print(f"healthy: {url}")
                sys.exit(0)
            last_error = f"http {status}"
    except (URLError, HTTPError, ValueError) as exc:
        last_error = str(exc)
    time.sleep(1)

print(last_error or "health check timed out", file=sys.stderr)
sys.exit(1)
PY
}

start_background_service() {
  local name="$1"
  shift
  local pid_file log_file pid
  pid_file="$(pid_file_for "$name")"
  log_file="$(log_file_for "$name")"

  if [[ -f "${pid_file}" ]]; then
    pid="$(cat "${pid_file}")"
    if [[ -n "${pid}" ]] && is_pid_running "${pid}"; then
      note "${name} already running (pid ${pid})"
      return 0
    fi
    rm -f "${pid_file}"
  fi

  note "Starting ${name}; log -> ${log_file}"
  (
    cd "${ROOT_DIR}"
    exec "$@"
  ) >>"${log_file}" 2>&1 &
  pid=$!
  echo "${pid}" >"${pid_file}"
  sleep 1
  if ! is_pid_running "${pid}"; then
    echo "${name} exited immediately. See ${log_file}" >&2
    return 1
  fi
}

ensure_python_venv() {
  local venv_path="$1"
  if [[ ! -x "$(python_bin_for_venv "$venv_path")" ]]; then
    note "Creating virtual environment: ${venv_path}"
    "${PYTHON_BIN}" -m venv "${venv_path}"
  fi
}

install_adapter_requirements() {
  local venv_path="$1"
  shift
  local python_bin pip_bin
  python_bin="$(python_bin_for_venv "$venv_path")"
  pip_bin="$(pip_bin_for_venv "$venv_path")"

  "${python_bin}" -m pip install --upgrade pip setuptools wheel
  if [[ $# -gt 0 ]]; then
    "${pip_bin}" install "$@"
  fi
}

install_requirements_file() {
  local venv_path="$1"
  local requirements_file="$2"
  local pip_bin
  pip_bin="$(pip_bin_for_venv "$venv_path")"
  if [[ -f "${requirements_file}" ]]; then
    "${pip_bin}" install -r "${requirements_file}"
  fi
}

install_pyproject_dependencies() {
  local venv_path="$1"
  local pyproject_file="$2"
  local pip_bin
  pip_bin="$(pip_bin_for_venv "$venv_path")"

  if [[ ! -f "${pyproject_file}" ]]; then
    echo "pyproject file not found: ${pyproject_file}" >&2
    return 1
  fi

  local deps_file
  deps_file="$(mktemp)"
  trap 'rm -f "${deps_file}"' RETURN
  "${PYTHON_BIN}" - "${pyproject_file}" >"${deps_file}" <<'PY'
import pathlib
import sys
import tomllib

pyproject = pathlib.Path(sys.argv[1])
with pyproject.open('rb') as handle:
    data = tomllib.load(handle)
for dep in data.get('project', {}).get('dependencies', []):
    print(dep)
PY

  if [[ -s "${deps_file}" ]]; then
    local deps=()
    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      deps+=("${line}")
    done <"${deps_file}"
    if [[ ${#deps[@]} -gt 0 ]]; then
      "${pip_bin}" install "${deps[@]}"
    fi
  fi
  rm -f "${deps_file}"
}
