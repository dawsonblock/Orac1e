#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

load_env
ensure_workspace_layout

require_command "${PYTHON_BIN}"
require_command git

allow_unsupported="${ORACLE_ALLOW_UNSUPPORTED_PYTHON:-0}"
"${PYTHON_BIN}" - "$allow_unsupported" <<'PY'
import shutil
import sys

allow_unsupported = sys.argv[1] == "1"
major, minor = sys.version_info[:2]
if (major, minor) < (3, 11):
    raise SystemExit("Python 3.11+ is required for this workspace")
if (major, minor) >= (3, 13) and not allow_unsupported:
    raise SystemExit("Python 3.13+ is outside the supported Aider range; set ORACLE_PYTHON_BIN to python3.11 or python3.12, or set ORACLE_ALLOW_UNSUPPORTED_PYTHON=1 to force")
if (major, minor) >= (3, 13) and allow_unsupported:
    print(f"Python {major}.{minor} allowed by override")
else:
    print(f"Python {major}.{minor} OK")
if shutil.which(sys.executable) is None:
    raise SystemExit("configured Python interpreter not found in PATH")
PY

if ! "${PYTHON_BIN}" -m venv --help >/dev/null 2>&1; then
  echo "python3 venv module is required" >&2
  exit 1
fi

for path in \
  "${ROOT_DIR}/integration/retrieval_broker/service.py" \
  "${ROOT_DIR}/integration/worker_aider/service.py" \
  "${ROOT_DIR}/integration/worker_hardened/service.py" \
  "${ROOT_DIR}/third_party/oracle-os" \
  "${COCOINDEX_REPO_PATH}" \
  "${CODE_AGENT_REPO_PATH}" \
  "${AIDER_REPO_PATH}"; do
  if [[ ! -e "${path}" ]]; then
    echo "Required path missing: ${path}" >&2
    exit 1
  fi
  echo "Found: ${path}"
done

if command -v swift >/dev/null 2>&1; then
  echo "Found swift: $(swift --version 2>/dev/null | head -n 1)"
else
  warn "swift not found; Python services can still run, but start_oracle.sh will fail until Swift is installed"
fi

echo "Environment looks usable."
