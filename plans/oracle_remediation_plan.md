# Oracle Remediation Plan

## Overview

This document outlines the remediation plan for the Oracle coding workspace based on comprehensive code review. The issues are organized into priority passes, with Pass 1 being critical trust-boundary repairs that must be addressed first.

## Critical Issues Summary (P0)

| Issue | Location | Impact |
|-------|----------|--------|
| **Promotion idempotency broken** | `scripts/coding_run_promotion.py:299` | Second promotion after cleanup fails instead of returning existing receipt |
| **Empty validation passes silently** | `ValidationCoordinator.swift:77`, `coding_run_promotion.py:229` | Repos can reach approval/promotion with zero validation checks |
| **Empty validation profiles** | `configs/validation_profiles/*.json` | JS/TS/default repos have no validation commands |
| **Stale e2e tests** | `test_promotion_flow.py:190-223` | Tests expect `running->applied/rejected` which violates P0 rules |
| **Bad test assertion** | `test_interactive_run.py:57` | Asserts "updated" but content is "interactive update" |

---

## Pass 1 — Critical Trust-Boundary Repairs

### 1.1 Fix Idempotent Promotion Ordering

**File:** `scripts/coding_run_promotion.py`

**Problem:** In `promote_run()`, the worktree existence check happens before the already-applied check, breaking idempotent second promotion after cleanup.

**Current logic (lines 297-300):**
```python
if not canonical_repo.exists():
    raise PromotionError(f"canonical repo missing: {canonical_repo}")
if not worktree_repo.exists():
    raise PromotionError(f"worktree missing: {worktree_repo}")

# Normalized status vocabulary check
current_status = run.get("status")
if current_status == "applied":
```

**Fix:** Move the `status == "applied"` check before worktree existence check.

---

### 1.2 Add Fail-Closed Guard for Empty Validation (Swift)

**File:** `third_party/oracle-os/Sources/OracleOS/Integration/Workspace/ValidationCoordinator.swift`

**Problem:** `validate()` returns `ok: true` when stages and commands are empty.

**Location:** Lines 76-84, after the stage iteration loop.

**Fix:** Add guard before returning success:
```swift
// After line 75, before line 77
if plan.stages.isEmpty && plan.resolvedCommands.isEmpty {
    return CodingValidationResult(
        ok: false,
        steps: steps,
        profileName: plan.profileName,
        stageCount: 0,
        resolvedCommands: [],
        errorCategory: "validation_unconfigured"
    )
}
```

**Note:** Requires extending `CodingValidationResult` with `errorCategory` field.

---

### 1.3 Add Fail-Closed Guard for Empty Validation (Python)

**File:** `scripts/coding_run_promotion.py`

**Problem:** `_run_validation(repo, [])` returns success when no commands provided.

**Location:** Function `_run_validation()` at line 229.

**Fix:** Add at start of function:
```python
def _run_validation(repo: Path, commands: list[str]) -> dict[str, Any]:
    if not commands:
        return {
            "ok": False,
            "steps": [],
            "environment": _capture_environment(repo),
            "error_category": "validation_unconfigured",
            "summary": "Validation configuration missing"
        }
    # ... rest of function
```

---

### 1.4 Add Real Validation Profiles

**Files:**
- `configs/validation_profiles/default.json`
- `configs/validation_profiles/javascript.json`
- `configs/validation_profiles/typescript.json`

**Current state:** All have `"commands": [], "stages": []`

**Fix — default.json:**
```json
{
  "profile": "default",
  "language": "default",
  "description": "Fallback validation profile",
  "stages": [
    {
      "id": "repo_sanity",
      "name": "Repository sanity",
      "commands": ["git status --short"]
    }
  ]
}
```

**Fix — javascript.json:**
```json
{
  "profile": "javascript",
  "language": "javascript",
  "description": "Validation profile for JavaScript repositories",
  "stages": [
    {
      "id": "install_check",
      "name": "Dependency manifest check",
      "commands": ["test -f package.json"]
    },
    {
      "id": "lint",
      "name": "Lint",
      "commands": ["npm run lint --if-present"]
    },
    {
      "id": "test",
      "name": "Tests",
      "commands": ["npm test --if-present -- --runInBand"]
    }
  ]
}
```

**Fix — typescript.json:**
```json
{
  "profile": "typescript",
  "language": "typescript",
  "description": "Validation profile for TypeScript repositories",
  "stages": [
    {
      "id": "install_check",
      "name": "Dependency manifest check",
      "commands": ["test -f package.json"]
    },
    {
      "id": "typecheck",
      "name": "Type check",
      "commands": ["npm run typecheck --if-present"]
    },
    {
      "id": "lint",
      "name": "Lint",
      "commands": ["npm run lint --if-present"]
    },
    {
      "id": "test",
      "name": "Tests",
      "commands": ["npm test --if-present -- --runInBand"]
    }
  ]
}
```

---

### 1.5 Update Stale E2E Tests

**File:** `tests/e2e/test_promotion_flow.py`

**Problem:** Tests at lines 190-223 expect `running -> applied/rejected` transitions, which violate the tightened P0 rules requiring `awaiting_approval` status.

**Tests to fix:**
- `test_status_running_to_applied` (line 190)
- `test_status_running_to_rejected` (line 209)

**Fix options:**
1. Remove these tests entirely (they test invalid transitions)
2. Rewrite to expect `PromotionError` when attempting to promote/reject from `running` status

**Recommended:** Option 2 — rewrite to verify the P0 contract is enforced.

---

### 1.6 Fix Bad Test Assertion

**File:** `tests/e2e/test_interactive_run.py`

**Problem:** Line 57 asserts `"updated" in canonical_content`, but the actual content written is `"interactive update"`.

**Current:**
```python
assert "updated" in canonical_content, \
    "Canonical repo should contain the promoted content"
```

**Fix:**
```python
assert "interactive update" in canonical_content, \
    "Canonical repo should contain the promoted content"
```

---

## Pass 2 — Swift Validation Runner Hardening

### 2.1 Refactor runShell() for Non-Blocking Pipe Draining

**File:** `third_party/oracle-os/Sources/OracleOS/Integration/Workspace/ValidationCoordinator.swift`

**Problem:** Current implementation uses `waitUntilExit()` then `readDataToEndOfFile()`, which can deadlock on noisy commands that fill pipe buffers.

**Current (lines 243-287):**
```swift
private func runShell(...) async -> CodingValidationStep {
    // ... setup process and pipes ...
    try process.run()
    process.waitUntilExit()
    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), ...)
    // ...
}
```

**Fix:** Use `readabilityHandler` for concurrent draining:
```swift
private func runShell(...) async -> CodingValidationStep {
    let process = Process()
    // ... setup ...
    
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    
    var stdoutData = Data()
    var stderrData = Data()
    
    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        if !chunk.isEmpty { stdoutData.append(chunk) }
    }
    
    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        if !chunk.isEmpty { stderrData.append(chunk) }
    }
    
    try process.run()
    process.waitUntilExit()
    
    // Clear handlers
    stdoutPipe.fileHandleForReading.readabilityHandler = nil
    stderrPipe.fileHandleForReading.readabilityHandler = nil
    
    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
    // ... return step ...
}
```

---

### 2.2 Add Per-Command Timeout Handling

**File:** `third_party/oracle-os/Sources/OracleOS/Integration/Workspace/ValidationCoordinator.swift`

**Problem:** No timeout exists for validation commands; hung tests can stall indefinitely.

**Fix:** Add timeout using `DispatchWorkItem` or `withTimeout`:
```swift
private func runShell(
    command: String,
    cwd: String,
    stageID: String,
    stageName: String,
    profileName: String,
    timeoutSeconds: TimeInterval = 300  // 5 minutes default
) async -> CodingValidationStep {
    // ... setup process ...
    
    let startTime = Date()
    var timedOut = false
    
    // Use Timer or DispatchSource to enforce timeout
    let timeoutWorkItem = DispatchWorkItem {
        timedOut = true
        process.terminate()
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWorkItem)
    
    try process.run()
    process.waitUntilExit()
    
    timeoutWorkItem.cancel()
    let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
    
    // Return step with timeout info and duration
    return CodingValidationStep(
        name: command,
        ok: !timedOut && process.terminationStatus == 0,
        stdout: stdout,
        stderr: stderr,
        exitCode: timedOut ? -1 : process.terminationStatus,
        stageID: stageID,
        stageName: stageName,
        profileName: profileName,
        timedOut: timedOut,
        durationMs: durationMs,
        failureCategory: timedOut ? "timeout" : (process.terminationStatus == 0 ? nil : "exit_failure")
    )
}
```

---

### 2.3 Extend CodingValidationStep and CodingValidationResult

**File:** `third_party/oracle-os/Sources/OracleOS/Integration/Contracts/ValidationModels.swift`

**Extend CodingValidationStep:**
```swift
public struct CodingValidationStep: Codable, Sendable, Identifiable {
    // ... existing fields ...
    public let timedOut: Bool
    public let durationMs: Int
    public let failureCategory: String?
    
    public init(
        name: String,
        ok: Bool,
        stdout: String,
        stderr: String,
        exitCode: Int32,
        stageID: String? = nil,
        stageName: String? = nil,
        profileName: String? = nil,
        timedOut: Bool = false,
        durationMs: Int = 0,
        failureCategory: String? = nil
    ) {
        // ... existing assignments ...
        self.timedOut = timedOut
        self.durationMs = durationMs
        self.failureCategory = failureCategory
    }
}
```

**Extend CodingValidationResult:**
```swift
public struct CodingValidationResult: Codable, Sendable {
    // ... existing fields ...
    public let errorCategory: String?
    
    public init(
        ok: Bool,
        steps: [CodingValidationStep],
        profileName: String? = nil,
        stageCount: Int = 0,
        resolvedCommands: [String] = [],
        errorCategory: String? = nil
    ) {
        self.ok = ok
        self.steps = steps
        self.profileName = profileName
        self.stageCount = stageCount
        self.resolvedCommands = resolvedCommands
        self.errorCategory = errorCategory
    }
}
```

---

## Pass 3 — Stage Persistence & Promotion Integration

### 3.1 Persist Resolved Validation Stages in Metadata

**Problem:** Only `validationCommands` (flat list) is persisted, losing stage structure before promotion.

**Files affected:**
- Swift: `IntegratedCodingRunService.swift` or run creation code
- Python: `scripts/coding_run_promotion.py` metadata handling

**Required metadata schema extension:**
```json
{
  "validationProfileName": "python",
  "validationProfileVersion": 1,
  "validationStages": [
    {
      "id": "compile",
      "name": "Compile",
      "commands": ["python -m compileall src"]
    },
    {
      "id": "tests",
      "name": "Tests",
      "commands": ["pytest -q tests"]
    }
  ],
  "validationCommands": [
    "python -m compileall src",
    "pytest -q tests"
  ],
  "allowNoValidation": false
}
```

---

### 3.2 Update ValidationCoordinator to Return Stage Metadata

**File:** `third_party/oracle-os/Sources/OracleOS/Integration/Workspace/ValidationCoordinator.swift`

**Change:** The `validate()` method should return stage-level details in the result, not just a flat step list.

**Option:** Return steps with stage attribution (already partially done via `stageID`/`stageName` in `CodingValidationStep`), but also return the plan structure.

---

### 3.3 Teach Promotion to Consume Stage Plans

**File:** `scripts/coding_run_promotion.py`

**Change:** Update `_run_validation()` and promotion flow to:
1. Check for `validationStages` in metadata first
2. Fall back to `validationCommands` for backward compatibility
3. Execute commands in stage groups for reporting
4. Include stage structure in promotion receipts

---

## Pass 4 — Profile Override & Environment Hardening

### 4.1 Add Explicit Validation Profile Override Support

**Problem:** Inference is too weak for polyglot repos.

**Files:**
- Swift: `ValidationCoordinator.swift` — add override check
- Run creation DTOs — add `preferredValidationProfile` field
- Python: promotion handling — respect override

**Precedence:**
1. Explicit run override (`preferredValidationProfile`)
2. Repo-local `.oracle-validation.json`
3. Inferred profile from file detection
4. Fallback `default`

---

### 4.2 Harden Environment Fingerprinting

**File:** `scripts/coding_run_promotion.py` — `_capture_environment()` at line 184

**Problem:** Uses `hash()` which is not stable across Python runs, and doesn't use SHA-256.

**Fix:** Replace with SHA-256 over sorted lockfile contents:
```python
import hashlib

def _capture_environment(repo: Path) -> dict[str, str]:
    env = {}
    
    # Capture version strings
    # ... existing version capture ...
    
    # SHA-256 over lockfiles
    lock_files = [
        "requirements.txt",
        "requirements-dev.txt",
        "poetry.lock",
        "pyproject.toml",
        "package-lock.json",
        "pnpm-lock.yaml",
        "yarn.lock",
        "package.json",
        "Package.resolved",
        "Package.swift",
        ".oracle-validation.json"
    ]
    
    hasher = hashlib.sha256()
    for lock in sorted(lock_files):
        lock_path = repo / lock
        if lock_path.exists():
            hasher.update(f"{lock}:".encode())
            hasher.update(lock_path.read_bytes())
            hasher.update(b"\n")
    
    env["dependencies_hash"] = hasher.hexdigest()
    return env
```

---

### 4.3 Pin Python Integration Dependencies

**Files:**
- `integration/retrieval_broker/requirements.txt`
- `integration/worker_aider/requirements.txt`
- `integration/worker_hardened/requirements.txt`
- Any other requirements files in `integration/`

**Change:** Replace open ranges with exact pins:
```
fastapi==0.115.12
uvicorn==0.30.6
pydantic==2.8.2
```

---

### 4.4 Document Swift Dependency Resolution Strategy

**Files:**
- `README.md`
- `docs/build_status.md`

**Action:** Choose and document one:
- **Option A:** Fully vendor all Swift dependencies (including AXorcist's remote deps)
- **Option B:** Accept online resolution and document that first build requires network

Current state is hybrid (vendored AXorcist but it has remote deps), which is confusing.

---

## Pass 5 — Operational Proof & Testing

### 5.1 Build Real End-to-End Smoke Harness

**File:** Add `scripts/smoke_e2e.sh`

**Problem:** Current `smoke_test.sh` only checks file presence and port health, not the actual operator loop.

**Real smoke harness should:**
1. Bootstrap services
2. Start retrieval broker
3. Start workers
4. Start run server
5. Start Oracle / invoke runtime
6. Create run against fixture repo
7. Retrieve context
8. Generate/propose change
9. Validate
10. Assert `awaiting_approval` status
11. Approve
12. Promote
13. Verify canonical repo content changed
14. Verify receipt and status ledger

---

### 5.2 Add Oracle Readiness Checking

**File:** `scripts/start_oracle.sh`

**Problem:** Only checks if process is alive after 2 seconds.

**Fix options:**
- Add `--self-check` CLI flag to Oracle that exits 0 if ready
- Or expose health endpoint and poll it
- Or verify IPC path is responsive

---

### 5.3 Add Regression Tests for Empty-Validation Failure

**Files:**
- `tests/integration/...`
- `tests/e2e/...`

**Tests to add:**
1. Inferred empty/default profile now fails
2. Explicit empty command list now fails  
3. Explicit override (`allowNoValidation: true`) allows no-validation mode
4. Stage metadata persists and is visible in receipts

---

### 5.4 Strip Cache Residue Before Release

**Packaging script:** Add to build/release process

**Exclude:**
- `__pycache__/`
- `*.pyc`
- `.pytest_cache/`
- `.mypy_cache/`

---

## Pass 6 — Documentation Alignment

### 6.1 Audit and Update README

**File:** `README.md`

**Problem:** README claims features not implemented:
- Preflight/lint/targeted tests/full tests pipeline
- Caching
- Parallel execution

**Fix:** Either implement or remove claims.

---

### 6.2 Update Validation Pipeline Documentation

**Files:**
- `docs/validation_policy.md`
- `docs/validation_v5.md`

**Update to reflect:**
- Profile resolution precedence
- Staged serial execution (not parallel)
- Halt-on-failure behavior
- Empty validation fails by default

---

### 6.3 Document allowNoValidation Override

**File:** `docs/validation_policy.md`

**Add:** Documentation for explicit bypass mechanism:
- Env var: `ORACLE_ALLOW_EMPTY_VALIDATION=1`
- Metadata flag: `allowNoValidation: true`
- When it's appropriate to use (emergency fixes, trusted repos)

---

## Acceptance Checklist

The repo is materially upgraded when:

- [ ] Second promotion on an applied run returns the existing receipt
- [ ] Empty validation fails by default (no silent success)
- [ ] JS/TS/default profiles run real validation checks
- [ ] Noisy validation commands do not deadlock
- [ ] Hung validation commands time out with distinct error
- [ ] Stage plans persist into promotion metadata
- [ ] Stale e2e tests pass with corrected assertions
- [ ] One real smoke script proves the full operator loop
- [ ] Oracle readiness check verifies actual functionality, not just process existence
- [ ] Docs match actual runtime behavior
- [ ] Release zips exclude cache artifacts

---

## Recommended Execution Order

### Pass 1 (Critical — Do First)
1. Fix promotion idempotency ordering
2. Add fail-closed validation guards (Swift + Python)
3. Add real JS/TS/default profiles
4. Update stale e2e tests
5. Fix interactive test assertion

### Pass 2 (Operational Safety)
6. Make Swift validation non-blocking
7. Add timeouts
8. Extend validation result types

### Pass 3 (Data Integrity)
9. Persist stage plans
10. Teach promotion to consume stage plans

### Pass 4 (Control & Hardening)
11. Add profile override support
12. Harden environment fingerprinting
13. Pin Python dependencies
14. Document Swift dependency strategy

### Pass 5 (Operational Proof)
15. Build real smoke harness
16. Add Oracle readiness checks
17. Add regression tests
18. Strip cache residue

### Pass 6 (Documentation)
19. Audit README
20. Update validation docs
21. Document override mechanism

---

## Priority Call

**The first two fixes matter more than everything else:**
1. **Idempotent applied promotion** — without this, the system cannot reliably handle re-promotion scenarios
2. **Fail-closed validation** — without this, repos can pass through the pipeline with zero verification

These are trust-boundary issues. After these, the next most critical is the Swift validation runner hardening — a validation layer that can silently hang is not operational.

---

*Plan created based on comprehensive code review of Orac1e-main repository.*
