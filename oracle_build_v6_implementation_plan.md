# Oracle Build v6 Implementation Plan

## Overview
This document outlines the implementation plan for upgrading from Oracle Build v5 to v6, focusing on restoring the Oracle Controller coding workspace, making the Python run server the single state-mutation authority, and completing all acceptance gates.

## Implementation Categories

### 1. Swift UI Components
**Files to modify/create:**
- `third_party/oracle-os/Sources/OracleController/ControllerStore.swift`
- `third_party/oracle-os/Sources/OracleController/CodingWorkspaceViews.swift` (new)
- `third_party/oracle-os/Sources/OracleController/RootView.swift`
- `third_party/oracle-os/Sources/OracleController/HostProcessClient.swift`
- `third_party/oracle-os/Sources/OracleOS/Integration/Orchestration/OracleCodingRuntime.swift`

**Tasks:**
- [ ] Add `coding` case to `WorkspaceSection` enum in ControllerStore.swift
- [ ] Add coding-related state variables to ControllerStore class
- [ ] Implement host-driven coding methods (loadCodingRuns, loadCodingRunDetail, startCodingRun, approveCodingRun, rejectCodingRun)
- [ ] Create new CodingWorkspaceViews.swift file with SwiftUI interface
- [ ] Update RootView.swift to route to CodingWorkspaceView and add CodingInspectorView
- [ ] Verify HostProcessClient.swift has async wrappers for coding commands
- [ ] Ensure OracleCodingRuntime.swift prefers run server and makes fallback explicitly second-class

### 2. Python Backend Changes
**Files to modify:**
- `scripts/serve_coding_runs.py`
- `scripts/coding_run_promotion.py`

**Tasks:**
- [ ] Normalize read model and mutation responses in serve_coding_runs.py:
  - Update `/health` to return `{"status": "ok"}`
  - Update `/runs` and `/runs/{id}` to return enriched detail with events, approvals, promotions, artifacts
  - Update `/approve` and `/reject` to return updated enriched detail
  - Add idempotency guards before mutation
- [ ] Enhance coding_run_promotion.py:
  - Add explicit no-op/idempotent guard for already-applied runs
  - Ensure normalized status vocabulary (running → awaiting_approval → applied/rejected/failed)

### 3. Test Updates
**Files to modify:**
- `tests/integration/test_broker.py`
- `tests/integration/test_aider_adapter.py`
- `tests/integration/test_hardened_adapter.py`
- `tests/integration/test_tool_invoke.py`

**Tasks:**
- [ ] Replace placeholder assertions with meaningful tests:
  - Test broker returns ranked results with path and score
  - Test aider adapter returns diff and touched paths
  - Test hardened adapter enforces allowed paths
  - Test tool manifest loads from integration tools

### 4. Documentation and Configuration
**Files to modify/create:**
- `README.md`
- `docs/release_truth.md` (new)
- Configuration files in `configs/` (if needed)

**Tasks:**
- [ ] Update README.md title to "Oracle Build v6" and add status section
- [ ] Create docs/release_truth.md with supported/not yet supported features
- [ ] Review configs/ for any needed updates (coding/, retrieval/, workers/ directories)

## Validation and Verification Plan

### Acceptance Gates Verification
1. [ ] Verify `oracle coding run|list|show|approve|reject` works
2. [ ] Verify Oracle Controller has coding section with list/detail/approve/reject
3. [ ] Verify Controller and CLI show the same run state
4. [ ] Verify only Python mutates run status, approval receipts, promotion receipts, and canonical repo state
5. [ ] Verify placeholder tests are gone
6. [ ] Verify `swift build` succeeds on macOS
7. [ ] Verify end-to-end run proves promotion commit lands in canonical repo and rollback leaves it clean on failure

### Validation Sequence
1. [ ] Run syntax checks: `python3 -m compileall scripts integration tests`
2. [ ] Run unit tests: `PYTHONPATH=. pytest -q tests/integration tests/e2e`
3. [ ] Materialize repos: `./scripts/materialize_repos.sh`
4. [ ] Start services in order:
   - `./scripts/start_retrieval.sh`
   - `./scripts/start_workers.sh`
   - `./scripts/start_run_server.sh`
   - `./scripts/start_oracle.sh`
5. [ ] CLI proof:
   - Run: `oracle coding run --repo ./workspace/repos/materialized/example --task "add function foo"`
   - List: `oracle coding list`
   - Show: `oracle coding show <run-id>`
   - Approve: `oracle coding approve <run-id>`
   - Verify updates in workspace/runs/* and canonical repo commit
6. [ ] Controller proof:
   - Launch Oracle Controller
   - Navigate to Coding section
   - Start similar task
   - Select run, inspect diff, approve/reject
   - Verify same updated state in workspace/runs/*

## Rollback and Risk Mitigation Plan

### Risk Identification
1. **Swift UI Compilation Failures**: New SwiftUI components may not compile
2. **Backend API Inconsistencies**: Python changes may break existing clients
3. **Test Failures**: New tests may expose existing issues
4. **State Migration Issues**: Run state format changes may cause problems
5. **Approval Flow Disruptions**: Changes to approval/rejection may break workflows

### Mitigation Strategies
1. **Incremental Implementation**:
   - Implement Swift UI changes one file at a time with verification
   - Keep backward compatibility in Python APIs where possible
   - Run tests frequently during implementation

2. **Feature Flags**:
   - Consider adding temporary flags to enable/disable new coding workspace
   - Allow fallback to v5 behavior if needed

3. **Data Backup**:
   - Backup workspace/runs/ before making changes
   - Ensure promotion scripts have dry-run modes

4. **Rollback Procedures**:
   - Document git commit hashes before changes
   - Have clear steps to revert specific file changes
   - Maintain ability to run v5 services alongside v6 during transition

5. **Verification Checkpoints**:
   - After Swift UI changes: Verify Controller compiles and launches
   - After Python backend changes: Verify health endpoint and basic run listing
   - After test updates: Verify all tests pass
   - After documentation: Verify accuracy against implementation

### Specific Rollback Steps
1. **Swift UI Revert**:
   - Remove `coding` case from WorkspaceSection enum
   - Remove coding state variables from ControllerStore
   - Delete CodingWorkspaceViews.swift
   - Revert RootView.swift changes
   - Revert HostProcessClient.swift changes
   - Revert OracleCodingRuntime.swift changes

2. **Python Backend Revert**:
   - Restore serve_coding_runs.py to previous version
   - Restore coding_run_promotion.py to previous version

3. **Test Revert**:
   - Restore placeholder tests or remove new tests

4. **Documentation Revert**:
   - Revert README.md changes
   - Remove release_truth.md

## Dependencies and Prerequisites
- macOS environment for Swift compilation
- Python 3.11+ for backend services
- Swift 5.9+ for Oracle OS components
- Existing Oracle Build v5 foundation
- Access to third-party repositories (Aider, cocoindex, etc.)

## Estimated Effort (Logical Steps Only)
1. Swift UI implementation (5 sub-tasks)
2. Python backend implementation (2 sub-tasks)
3. Test updates (4 sub-tasks)
4. Documentation updates (2 sub-tasks)
5. Validation and verification (multiple checkpoints)
6. Rollback planning (ongoing throughout)

## Success Criteria
- All acceptance gates pass
- Swift builds successfully on macOS
- All tests pass (no placeholder assertions)
- CLI and Controller show consistent state
- Python is verified as sole mutation authority
- Promotion creates real commits in canonical repo
- Rollback leaves canonical repo clean on failure
- Documentation accurately reflects implementation

## Next Steps
1. Begin implementation with Swift UI components
2. Regularly validate progress against acceptance gates
3. Update this plan as implementation proceeds
4. Schedule review sessions with stakeholders
5. Prepare for final validation and release