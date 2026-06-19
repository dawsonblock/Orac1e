#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

load_env
ensure_workspace_layout

repo="${FIXTURE_REPO_DIR}"
test -d "${repo}"
test -d "${repo}/.git"
test -f "${repo}/src/parser.py"
test -f "${ROOT_DIR}/integration/tools/aider/tool.json"
test -f "${ROOT_DIR}/integration/tools/hardened/tool.json"
test -f "${ROOT_DIR}/integration/tools/cocoindex/tool.json"
"${PYTHON_BIN}" "${ROOT_DIR}/scripts/tool_harness.py" >/dev/null

wait_for_http_ok "http://${ORACLE_HOST}:${BROKER_PORT}/health" 10
wait_for_http_ok "http://${ORACLE_HOST}:${AIDER_PORT}/health" 10
wait_for_http_ok "http://${ORACLE_HOST}:${HARDENED_PORT}/health" 10
wait_for_http_ok "http://${ORACLE_HOST}:${RUN_SERVER_PORT}/health" 10

"${PYTHON_BIN}" "${ROOT_DIR}/scripts/sync_web_tool_registry.py" >/dev/null || true

echo "Smoke test completed."
