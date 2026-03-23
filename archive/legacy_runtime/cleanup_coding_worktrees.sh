#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

load_env
ensure_workspace_layout

for repo in oracle-os aider code-agent-runtime cocoindex-code; do
  repo_path="${WORKSPACE_DIR}/repos/${repo}"
  [[ -d "${repo_path}/.git" ]] || continue
  git -C "${repo_path}" worktree prune >/dev/null 2>&1 || true
done

rm -rf "${WORKSPACE_DIR}/worktrees"/*
echo "Cleaned ${WORKSPACE_DIR}/worktrees"
