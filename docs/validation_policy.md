# Validation policy

Oracle validates every proposal after it returns from a worker.

## Staged Execution

The validation pipeline runs in distinct stages, each producing metadata for receipts:

### Stage 1: Diff Structure & Policy Checks
- Validates patch structure integrity
- Checks against mutation policy rules
- Ensures no forbidden file modifications

### Stage 2: Repository-Local Formatter & Linter
- Language-specific formatting (black, gofmt, rustfmt, etc.)
- Linting with language-appropriate tools
- **Cached** for repeat validations

### Stage 3: Targeted Tests
- Selects relevant tests based on changed files
- Runs only affected test suites
- **Cached** using test selector intelligence

### Stage 4: Full Build/Test Commands (Optional)
- Complete test suite execution
- Build verification
- Skipped for low-risk patches (docs, config, refactoring)

Workers may perform advisory validation, but Oracle remains the final gate.

## allowNoValidation Override

By default, Oracle requires validation commands to be configured for promotion. However, the `allowNoValidation` override allows skipping validation when necessary.

### Enabling via Run Metadata

Set `allowNoValidation: true` in the run metadata:

```json
{
  "runID": "abc-123",
  "validationCommands": [],
  "allowNoValidation": true
}
```

### Enabling via Environment Variable

Set `ORACLE_ALLOW_NO_VALIDATION=1` to enable globally:

```bash
export ORACLE_ALLOW_NO_VALIDATION=1
```

### Behavior

When `allowNoValidation` is enabled:
- Validation is skipped entirely
- Receipt metadata includes `skipped: true` with `skip_reason: "allow_no_validation"`
- Promotion still proceeds to canonical repository

When validation is required but not configured (without override):
- Promotion fails with error: "no validation configured and allowNoValidation is not enabled"
