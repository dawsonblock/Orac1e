# Phase 6 status

Phase 6 is the first validation-focused pass. It does not claim that Oracle OS is fully validated. It adds the machinery and checklist needed to prove or falsify that claim on macOS.

## Added in this phase

- `scripts/validate-macos-runtime.sh`
- `.github/workflows/runtime-validation.yml`
- `docs/VALIDATION.md`

## What this phase is for

- move from structural plausibility to platform proof
- capture build, test, packaging, and targeted hardening logs in one run
- separate what CI can prove from what only local macOS execution can prove

## Remaining gaps after this phase

- no hosted CI runner can honestly prove Accessibility-mediated UI automation
- system-command verification is still thinner than UI and file verification
- build/test result validation still depends on the current runtime surfaces rather than a fully isolated harness
