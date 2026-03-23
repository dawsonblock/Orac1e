#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

load_env
ensure_workspace_layout

materialize_repo() {
  local name="$1"
  local src="${ROOT_DIR}/third_party/${name}"
  local dst="${WORKSPACE_DIR}/repos/${name}"

  if [[ ! -d "${src}" ]]; then
    echo "Missing source snapshot: ${src}" >&2
    return 1
  fi

  rm -rf "${dst}"
  mkdir -p "${dst}"
  rsync -a --delete     --exclude '.git'     --exclude '.build'     --exclude '__pycache__'     --exclude '.pytest_cache'     --exclude '.mypy_cache'     --exclude '.ruff_cache'     "${src}/" "${dst}/"

  git -C "${dst}" init -q
  git -C "${dst}" config user.name "Oracle Workspace"
  git -C "${dst}" config user.email "oracle-workspace@example.invalid"
  git -C "${dst}" add -A
  if ! git -C "${dst}" diff --cached --quiet; then
    git -C "${dst}" commit -q -m "Baseline materialized snapshot"
  fi
}

materialize_repo oracle-os
materialize_repo aider
materialize_repo code-agent-runtime
materialize_repo cocoindex-code

echo "Materialized git-backed repos under ${WORKSPACE_DIR}/repos"
