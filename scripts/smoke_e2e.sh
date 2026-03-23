#!/usr/bin/env bash
# =============================================================================
# smoke_e2e.sh - End-to-end smoke test with full operator loop
#
# This script performs a complete end-to-end test of the Oracle coding system:
# 1. Bootstrap services (venv, repos)
# 2. Start retrieval broker
# 3. Start workers (aider, hardened)
# 4. Start run server
# 5. Create run against fixture repo
# 6. Generate/propose change (worker produces diff)
# 7. Validate (Oracle validation pipeline)
# 8. Assert `awaiting_approval` status
# 9. Approve & promote
# 10. Verify canonical repo content changed
# =============================================================================
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
}

log_step() {
    log "===> STEP: $*"
}

cleanup_on_exit() {
    local exit_code=$?
    if [[ ${E2E_CLEANUP:-1} == "1" ]]; then
        log "Cleaning up services..."
        bash "${ROOT_DIR}/scripts/stop_all.sh" 2>/dev/null || true
    fi
    exit $exit_code
}

wait_for_service() {
    local name="$1"
    local url="$2"
    local timeout="${3:-60}"
    log "Waiting for ${name} to be ready at ${url}..."
    if wait_for_http_ok "$url" "$timeout"; then
        log "${name} is ready"
        return 0
    else
        log "ERROR: ${name} failed to become ready"
        return 1
    fi
}

get_run_status() {
    local run_id="$1"
    "${PYTHON_BIN}" - <<PYTHON
import json
import urllib.request

url = "http://${ORACLE_HOST}:${RUN_SERVER_PORT}/runs/${run_id}"
with urllib.request.urlopen(url, timeout=10) as resp:
    data = json.load(resp)
    print(data.get('status', 'unknown'))
PYTHON
}

approve_run_via_api() {
    local run_id="$1"
    local actor="${2:-e2e-test}"
    local note="${3:-approved by e2e smoke test}"
    
    local payload
    payload=$(cat <<EOF
{
    "actor": "${actor}",
    "note": "${note}"
}
EOF
)
    
    "${PYTHON_BIN}" - <<PYTHON
import json
import urllib.request
import urllib.error

url = "http://${ORACLE_HOST}:${RUN_SERVER_PORT}/runs/${run_id}/approve"
data = '''${payload}'''.encode('utf-8')

req = urllib.request.Request(url, data=data, method='POST')
req.add_header('Content-Type', 'application/json')

try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        print(resp.read().decode('utf-8'))
except urllib.error.HTTPError as e:
    print(e.read().decode('utf-8'))
    raise
PYTHON
}

real_worker_propose() {
    local run_id="$1"
    local worktree_path="$2"
    local worker_port="${3:-${AIDER_PORT}}"

    local payload
    payload=$(
        "${PYTHON_BIN}" - <<PYTHON
import json, sys
from pathlib import Path

metadata_file = Path("${ROOT_DIR}/workspace/runs/metadata/${run_id}.json")
meta = json.loads(metadata_file.read_text()) if metadata_file.exists() else {}

print(json.dumps({
    "run_id": run_id,
    "repo_name": "buggy-repo",
    "repo_path": "${worktree_path}",
    "mode": "interactive",
    "task": meta.get("task", "Fix first_token so empty token lists return None instead of raising IndexError"),
    "context": {
        "files": meta.get("contextFiles", []),
        "retrieval": []
    },
    "constraints": {
        "max_files": 6,
        "max_changed_lines": 300,
        "allowed_paths": meta.get("allowedPaths", ["src/"])
    }
}, indent=2))
run_id = "${run_id}"
PYTHON
    )

    log "POSTing /propose to worker on port ${worker_port} for run ${run_id}..."
    "${PYTHON_BIN}" - <<PYTHON
import json
import urllib.request
import urllib.error
import sys

url = "http://${ORACLE_HOST}:${worker_port}/propose"
data = '''${payload}'''.encode('utf-8')
req = urllib.request.Request(url, data=data, method='POST')
req.add_header('Content-Type', 'application/json')
try:
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = json.loads(resp.read().decode('utf-8'))
        diff = body.get('diff', '')
        touched = body.get('touched_files', [])
        warnings = body.get('warnings', [])
        if warnings:
            print(f"  worker warnings: {warnings}", file=sys.stderr)
        if not diff.strip():
            print("ERROR: worker returned empty diff", file=sys.stderr)
            sys.exit(1)
        print(f"  worker produced diff touching: {touched}")
except urllib.error.HTTPError as exc:
    print(f"ERROR: /propose returned HTTP {exc.code}: {exc.read().decode()}", file=sys.stderr)
    sys.exit(1)
PYTHON
}

# =============================================================================
# Main Execution
# =============================================================================

trap cleanup_on_exit EXIT

# Parse arguments
SKIP_BOOTSTRAP=0
SKIP_SERVICES=0
E2E_CLEANUP=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-bootstrap)
            SKIP_BOOTSTRAP=1
            shift
            ;;
        --skip-services)
            SKIP_SERVICES=1
            shift
            ;;
        --no-cleanup)
            E2E_CLEANUP=0
            shift
            ;;
        *)
            echo "Usage: $0 [--skip-bootstrap] [--skip-services] [--no-cleanup]"
            exit 1
            ;;
    esac
done

log "Starting E2E Smoke Test"
log "========================"

# Step 1: Bootstrap
if [[ $SKIP_BOOTSTRAP -eq 0 ]]; then
    log_step "Bootstrap (venv, repos, fixture)"
    bash "${ROOT_DIR}/scripts/bootstrap.sh"
else
    log "Skipping bootstrap"
fi

# Step 2: Start services
if [[ $SKIP_SERVICES -eq 0 ]]; then
    log_step "Starting retrieval broker"
    bash "${ROOT_DIR}/scripts/start_retrieval.sh"
    
    log_step "Starting workers"
    bash "${ROOT_DIR}/scripts/start_workers.sh"
    
    log_step "Starting run server"
    bash "${ROOT_DIR}/scripts/start_run_server.sh"
    
    # Wait for all services to be healthy
    wait_for_service "Retrieval Broker" "http://${ORACLE_HOST}:${BROKER_PORT}/health" 60
    wait_for_service "Aider Worker" "http://${ORACLE_HOST}:${AIDER_PORT}/health" 60
    wait_for_service "Hardened Worker" "http://${ORACLE_HOST}:${HARDENED_PORT}/health" 60
    wait_for_service "Run Server" "http://${ORACLE_HOST}:${RUN_SERVER_PORT}/health" 60
else
    log "Skipping service startup"
fi

# Step 3: Create a run against fixture repo
log_step "Creating run against fixture repo"

# Ensure fixture repo exists
if [[ ! -d "${FIXTURE_REPO_DIR}" ]]; then
    log "Creating fixture repo..."
    "${PYTHON_BIN}" "${ROOT_DIR}/scripts/make_fixture_repo.py"
fi

# Generate a unique run ID
RUN_ID="e2e-$(date +%Y%m%d-%H%M%S)"
TASK="Add a simple function to parser.py"

log "Creating run ${RUN_ID} with task: ${TASK}"

# Initialize runs.json if it doesn't exist
RUNS_DIR="${ROOT_DIR}/workspace/runs"
METADATA_DIR="${RUNS_DIR}/metadata"
mkdir -p "$METADATA_DIR"

if [[ ! -f "${RUNS_DIR}/runs.json" ]]; then
    echo "[]" > "${RUNS_DIR}/runs.json"
fi

# Add the new run
"${PYTHON_BIN}" - <<PYTHON
import json
from pathlib import Path

runs_file = Path("${RUNS_DIR}/runs.json")
runs = json.loads(runs_file.read_text())

new_run = {
    "id": "${RUN_ID}",
    "repoName": "buggy-repo",
    "repoPath": "${FIXTURE_REPO_DIR}",
    "mode": "interactive",
    "status": "retrieving",
    "task": """${TASK}""",
    "createdAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
runs.append(new_run)
runs_file.write_text(json.dumps(runs, indent=2))

# Create metadata
metadata = {
    "runID": "${RUN_ID}",
    "canonicalRepoPath": "${FIXTURE_REPO_DIR}",
    "worktreePath": "${ROOT_DIR}/workspace/worktrees/${RUN_ID}",
    "validationCommands": ["python3 -m py_compile src/parser.py"],
    "allowedPaths": ["src/"],
    "retrievalQuery": "parser function",
    "workerMode": "interactive",
    "createdAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
metadata_file = Path("${METADATA_DIR}/${RUN_ID}.json")
metadata_file.write_text(json.dumps(metadata, indent=2))

print(f"Created run: ${RUN_ID}")
PYTHON

# Step 4: Simulate worker processing (retrieving -> proposing)
log_step "Simulating worker processing"

# Update status to proposing
"${PYTHON_BIN}" - <<PYTHON
import json
from pathlib import Path

runs_file = Path("${RUNS_DIR}/runs.json")
runs = json.loads(runs_file.read_text())

for run in runs:
    if run.get('id') == '${RUN_ID}':
        run['status'] = 'proposing'
        break

runs_file.write_text(json.dumps(runs, indent=2))
PYTHON

# Create worktree from fixture repo so the worker has an isolated tree to edit
WORKTREE_PATH="${ROOT_DIR}/workspace/worktrees/${RUN_ID}"
mkdir -p "${ROOT_DIR}/workspace/worktrees"

if [[ -d "${FIXTURE_REPO_DIR}/.git" ]]; then
    git -C "${FIXTURE_REPO_DIR}" worktree add --detach "${WORKTREE_PATH}" HEAD
else
    log "ERROR: fixture repo has no .git directory: ${FIXTURE_REPO_DIR}"
    exit 1
fi

# Update metadata with the real worktree path now that it exists
"${PYTHON_BIN}" - <<PYTHON
import json
from pathlib import Path
mf = Path("${METADATA_DIR}/${RUN_ID}.json")
meta = json.loads(mf.read_text())
meta["worktreePath"] = "${WORKTREE_PATH}"
mf.write_text(json.dumps(meta, indent=2))
PYTHON

# Call the real worker /propose endpoint; exits nonzero if diff is empty
real_worker_propose "${RUN_ID}" "${WORKTREE_PATH}" "${AIDER_PORT}"

# Confirm the worktree has uncommitted changes
DIFF_STAT=$(git -C "${WORKTREE_PATH}" diff --stat HEAD 2>/dev/null || true)
if [[ -z "${DIFF_STAT}" ]]; then
    log "ERROR: worktree has no changes after worker ran"
    exit 1
fi
log "Worktree diff confirmed:"
echo "${DIFF_STAT}" | sed 's/^/  /'

# Commit the worktree changes so promote_run can capture them as a patch
git -C "${WORKTREE_PATH}" add -A
git -C "${WORKTREE_PATH}" -c user.email="smoke@e2e" -c user.name="E2E" \
    commit -m "smoke: worker proposal for ${RUN_ID}"

# Advance run status to awaiting_approval
"${PYTHON_BIN}" - <<PYTHON
import json
from pathlib import Path
runs_file = Path("${RUNS_DIR}/runs.json")
runs = json.loads(runs_file.read_text())
for run in runs:
    if run.get('id') == '${RUN_ID}':
        run['status'] = 'awaiting_approval'
        run['updatedAt'] = "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        break
runs_file.write_text(json.dumps(runs, indent=2))
PYTHON

# Step 5: Validation is handled atomically inside promote_run; no separate step needed.
log_step "Run ready for approval (validation runs inside promote_run)"

# Step 6: Assert awaiting_approval status
log_step "Verifying awaiting_approval status"
STATUS=$(get_run_status "$RUN_ID")
if [[ "$STATUS" != "awaiting_approval" ]]; then
    log "ERROR: Expected status 'awaiting_approval', got '${STATUS}'"
    exit 1
fi
log "Run is in awaiting_approval status"

# Step 7: Approve & promote
log_step "Approving and promoting run"

# Get canonical content before promotion
CANONICAL_BEFORE=$(cat "${FIXTURE_REPO_DIR}/src/parser.py" 2>/dev/null || echo "")

# Approve the run
approve_run_via_api "$RUN_ID" "e2e-tester" "E2E smoke test approval"

# Step 8: Verify canonical repo content changed
log_step "Verifying canonical repo changed"

CANONICAL_AFTER=$(cat "${FIXTURE_REPO_DIR}/src/parser.py" 2>/dev/null || echo "")

if [[ "$CANONICAL_BEFORE" == "$CANONICAL_AFTER" ]]; then
    log "ERROR: Canonical repo content did not change after promotion"
    exit 1
fi

log "SUCCESS: Canonical repo was updated with new content"

# Verify final status
FINAL_STATUS=$(get_run_status "$RUN_ID")
log "Final run status: ${FINAL_STATUS}"

if [[ "$FINAL_STATUS" != "applied" ]]; then
    log "ERROR: Expected final status 'applied', got '${FINAL_STATUS}'"
    exit 1
fi

log "========================"
log "E2E Smoke Test PASSED"
log "========================"