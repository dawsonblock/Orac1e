# Local proof runbook

This runbook turns the phase 6 validation checklist into a concrete proof pack that can be audited later.

## Before you start

Run:

```bash
./scripts/prove-local-runtime.sh
```

That creates a timestamped `ProofArtifacts/...` directory with one folder per required scenario.

## Required scenarios

### 1. UI success

Target:
- prove a UI command reaches the full runtime spine and survives read-back verification

Recommended case:
- focus Safari
- navigate to a fixed URL
- capture the final URL and window title

Save into `scenarios/ui-success/`:
- command or intent text
- committed snapshot before execution
- emitted events
- post-execution observation
- verifier report
- screenshot or short recording reference
- one `verdict.txt`

### 2. Code success

Target:
- prove a file mutation survives post-execution read-back

Recommended case:
- use a disposable fixture repo
- read one file
- modify the file through the runtime
- capture before and after contents

Save into `scenarios/code-success/`:
- fixture description
- file before and after
- emitted events
- snapshot before and after
- verifier report
- one `verdict.txt`

### 3. System success

Target:
- prove one system command has observed evidence after execution

Recommended case:
- open Calculator or TextEdit
- capture focused app or process evidence

Save into `scenarios/system-success/`:
- command text
- emitted events
- observed evidence
- verifier report
- one `verdict.txt`

### 4. Forced postcondition failure

Target:
- prove router-local success cannot override failed read-back

Recommended case:
- request a file mutation with an impossible or stale expectation
- confirm final status is postcondition failure

Save into `scenarios/forced-postcondition-failure/`:
- command text
- reason it should fail
- router-local result
- post-execution observation
- final verifier report
- one `verdict.txt`

### 5. Replay determinism

Target:
- prove event replay produces the same snapshot every time
- prove duplicate replay does not double-apply state

Save into `scenarios/replay-determinism/`:
- persisted event stream
- snapshot from replay 1
- snapshot from replay 2
- diff or hash comparison
- one `verdict.txt`

## Audit step

After collecting artifacts, run:

```bash
python3 scripts/check-proof-artifacts.py ProofArtifacts/<timestamp>
```

The proof pack is incomplete until the script exits successfully.

## Failure rule

If any scenario is missing, ambiguous, or contradicted by the saved evidence, the repo is still not validated.
