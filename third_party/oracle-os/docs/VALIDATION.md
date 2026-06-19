# Validation

This repository now has a cleaner execution spine than the earlier Oracle snapshots, but the spine is only credible when it is proven on macOS.

## What CI should prove

The automated validation workflow should establish these facts:

- the Swift package resolves and builds in debug and release
- the test suite passes on macOS
- the controller app bundle can be assembled
- the release tarball can be assembled
- the hardening-specific tests still pass:
  - `RuntimeWiringTests`
  - `PreconditionIntegrationTests`
  - `PostExecutionVerificationTests`
  - `EventReplayTests`

CI does **not** prove live Accessibility-mediated UI automation. GitHub-hosted macOS runners are the wrong place to claim that.

## What must be proven locally on macOS

Run `./scripts/validate-macos-runtime.sh` first. Then complete this manual checklist on a real Mac with Accessibility permissions enabled for the built controller app.

Use `./scripts/prove-local-runtime.sh` to create a timestamped proof workspace before running the local checks. Save all evidence there, then validate the pack with `python3 scripts/check-proof-artifacts.py ProofArtifacts/<timestamp>`.

### 1. UI success path

Prove one UI action goes through:

`intent -> VerifiedExecutor -> CommandRouter -> CommitCoordinator -> OutcomeVerifier`

Recommended case:

- focus Safari
- navigate to a known URL
- verify the URL read-back matches expectation

Record:

- command intent
- emitted events
- committed snapshot before/after
- final verifier report

### 2. Code success path

Recommended case:

- read a file in a disposable repo fixture
- modify the file through the runtime
- verify file read-back changed
- confirm the committed snapshot updated repository state

### 3. System success path

Recommended case:

- open Calculator or TextEdit
- verify process/app focus after execution

If the current system router cannot verify this independently, document that gap rather than claiming success.

### 4. Forced postcondition failure

Recommended case:

- request a file change with an impossible target path or intentionally stale expectation
- verify router-local success cannot override post-execution failure
- final execution status must be `.postconditionFailed`

### 5. Replay determinism

Using a persisted event stream from one successful run:

- rebuild the snapshot from zero
- confirm the final snapshot is identical on repeated replay
- confirm replaying the same batch twice does not double-apply state

## Exit criteria for calling the repo solid

Do not call this repo hardened until all of these are true:

- automated macOS build/test passes are green
- one UI, one code, and one system success path are proven locally
- one forced postcondition failure is proven locally
- replay determinism is proven from persisted events
- no supported action bypasses the live execution spine
