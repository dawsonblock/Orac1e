#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${ROOT}/ProofArtifacts/${STAMP}"
LOG_DIR="${OUT_DIR}/logs"
META_DIR="${OUT_DIR}/meta"
SCENARIO_DIR="${OUT_DIR}/scenarios"

mkdir -p \
  "${LOG_DIR}" \
  "${META_DIR}" \
  "${SCENARIO_DIR}/ui-success" \
  "${SCENARIO_DIR}/code-success" \
  "${SCENARIO_DIR}/system-success" \
  "${SCENARIO_DIR}/forced-postcondition-failure" \
  "${SCENARIO_DIR}/replay-determinism"

record_optional() {
  local label="$1"
  shift
  if "$@" > "${META_DIR}/${label}.txt" 2>&1; then
    return 0
  fi
  echo "unavailable" > "${META_DIR}/${label}.txt"
}

record_optional git-rev-parse git rev-parse HEAD
record_optional git-status git status --short
record_optional swift-version swift --version
record_optional package-describe swift package describe
record_optional xcodebuild-version xcodebuild -version
record_optional uname uname -a

cat > "${META_DIR}/artifact-index.txt" <<INDEX
Proof artifact root: ${OUT_DIR}
Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Required scenario folders:
- scenarios/ui-success
- scenarios/code-success
- scenarios/system-success
- scenarios/forced-postcondition-failure
- scenarios/replay-determinism
INDEX

VALIDATION_LOG="${LOG_DIR}/validate-macos-runtime.log"
if [[ -x "${ROOT}/scripts/validate-macos-runtime.sh" ]]; then
  echo "[phase7] running validate-macos-runtime.sh"
  if "${ROOT}/scripts/validate-macos-runtime.sh" > "${VALIDATION_LOG}" 2>&1; then
    echo "[phase7] validation script completed"
  else
    echo "[phase7] validation script failed; see ${VALIDATION_LOG}" >&2
  fi
else
  echo "validate-macos-runtime.sh not executable or missing" > "${VALIDATION_LOG}"
fi

cat > "${SCENARIO_DIR}/ui-success/README.md" <<'EOF_UI'
# UI success proof

Collect:
- intent or command text
- pre-execution committed snapshot
- emitted events
- post-execution observation
- verifier report
- screenshot or screen recording reference
- short verdict
EOF_UI

cat > "${SCENARIO_DIR}/code-success/README.md" <<'EOF_CODE'
# Code success proof

Collect:
- target fixture repo path
- file before/after
- emitted events
- committed snapshot before/after
- verifier report
- short verdict
EOF_CODE

cat > "${SCENARIO_DIR}/system-success/README.md" <<'EOF_SYS'
# System success proof

Collect:
- command intent
- emitted events
- observed app or process evidence
- verifier report
- short verdict
EOF_SYS

cat > "${SCENARIO_DIR}/forced-postcondition-failure/README.md" <<'EOF_FAIL'
# Forced postcondition failure proof

Collect:
- original command
- reason the expectation should fail
- router-local result
- post-execution observation
- final execution outcome showing postcondition failure
- short verdict
EOF_FAIL

cat > "${SCENARIO_DIR}/replay-determinism/README.md" <<'EOF_REPLAY'
# Replay determinism proof

Collect:
- persisted event stream
- snapshot after first replay
- snapshot after second replay
- hash or diff comparison
- verdict showing no double-apply drift
EOF_REPLAY

cat > "${OUT_DIR}/NEXT_STEPS.txt" <<'EOF_STEPS'
1. Open docs/LOCAL_PROOF_RUNBOOK.md and execute all five scenarios on a real Mac.
2. Save raw logs, snapshots, verifier reports, and screenshots into the matching scenario folders.
3. Run:
   python3 scripts/check-proof-artifacts.py ProofArtifacts/<timestamp>
4. Treat any missing artifact or failed verdict as an open validation blocker.
EOF_STEPS

echo "Created proof workspace: ${OUT_DIR}"
echo "Next: fill the scenario folders, then run scripts/check-proof-artifacts.py ${OUT_DIR}"
