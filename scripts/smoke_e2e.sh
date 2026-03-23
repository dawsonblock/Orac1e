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

simulate_worker_proposal() {
    local run_id="$1"
    local worktree_path="$2"
    
    # Create a simple code change in the worktree
    local app_file="${worktree_path}/src/parser.py"
    if [[ -f "$app_file" ]]; then
        echo "# Modified by e2e smoke test" >> "$app_file"
        echo "def new_function():" >> "$app_file"
        echo "    pass" >> "$app_file"
    else
        mkdir -p "$(dirname "$app_file")"
        cat > "$app_file" <<EOF
# Modified by e2e smoke test
def new_function():
    pass
EOF
    fi
    
    # Update run status to validating (simulating worker completion)
    local runs_file="${ROOT_DIR}/workspace/runs/runs.json"
    if [[ -f "$runs_file" ]]; then
        "${PYTHON_BIN}" - <<PYTHON
import json
from pathlib import Path

runs_file = Path("${runs_file}")
runs = json.loads(runs_file.read_text())

for run in runs:
    if run.get('id') == '${run_id}':
        run['status'] = 'validating'
        break

runs_file.write_text(json.dumps(runs, indent=2))
PYTHON
    fi
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

# Create worktree and make a change
WORKTREE_PATH="${ROOT_DIR}/workspace/worktrees/${RUN_ID}"
mkdir -p "$(dirname "$WORKTREE_PATH")"

# Create worktree from fixture repo
if [[ -d "${FIXTURE_REPO_DIR}/.git" ]]; then
    git -C "${FIXTURE_REPO_DIR}" worktree add --detach "$WORKTREE_PATH" HEAD 2>/dev/null || true
fi

# Make a code change in worktree
simulate_worker_proposal "$RUN_ID" "$WORKTREE_PATH"

# Step 5: Validation (simulating validation pipeline)
log_step "Running validation"

# Update status to validating then awaiting_approval
"${PYTHON_BIN}" - <<PYTHON
import json
from pathlib import Path

runs_file = Path("${RUNS_DIR}/runs.json")
runs = json.loads(runs_file.read_text())

for run in runs:
    if run.get('id') == '${RUN_ID}':
        run['status'] = 'awaiting_approval'
        run['updatedAt'] = "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        break

runs_file.write_text(json.dumps(runs, indent=2))
PYTHON

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

sleep 2  # Give time for promotion to complete

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