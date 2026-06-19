# Mac Runbook — Orac1e Control Plane v0.2-alpha

## Requirements

- macOS 14+ (Sonoma or later)
- Python 3.11+
- Swift 6.0+ (for Swift app)
- Xcode Command Line Tools

## Bootstrap

```bash
cd /path/to/Orac1e-main
./scripts/bootstrap_all.sh
```

This creates `.venv`, installs all Python dependencies, and installs local editable packages.

## Preflight

```bash
# After bootstrap — should pass
python3 -m integration.preflight

# Before bootstrap — should fail with honest error
python3 -m integration.preflight
```

## Start Vision Sidecar (Optional)

```bash
cd third_party/oracle-os/vision-sidecar
python3 server.py --port 9876
```

Or use the launcher:

```bash
third_party/oracle-os/vision-sidecar/oracle-vision --port 9876
```

Health check:

```bash
curl http://127.0.0.1:9876/health
```

## Start Services

```bash
bash scripts/run_local.sh
```

Services started:
- Retrieval broker: `http://127.0.0.1:8787`
- Aider worker: `http://127.0.0.1:8788`
- Hardened worker: `http://127.0.0.1:8789`
- Run server: `http://127.0.0.1:8080`

## Smoke Test

```bash
bash scripts/smoke_test.sh
```

## Fixture Repair (E2E)

The fixture repo is at `workspace/fixtures/buggy-repo/` with a known `first_token` bug.

```bash
# Create a run
curl -X POST http://127.0.0.1:8080/runs \
  -H "Content-Type: application/json" \
  -d '{
    "repo_path": "workspace/fixtures/buggy-repo",
    "task": "Fix first_token so empty input returns None",
    "validation_commands": ["pytest -q"]
  }'
```

## Approve a Run

Requires `ORACLE_APPROVAL_TOKEN` environment variable:

```bash
export ORACLE_APPROVAL_TOKEN=your-secret-token

curl -X POST http://127.0.0.1:8080/runs/{run_id}/approve \
  -H "Authorization: Bearer $ORACLE_APPROVAL_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"actor": "operator", "note": "LGTM"}'
```

Without token, returns 401.

## Promote (What Happens After Approval)

When you approve a run, the system automatically:

1. **Validates the worktree** — runs your configured validation commands (e.g., `pytest`) against the worktree
2. **Captures the patch** — diffs the worktree against its parent commit
3. **Applies to canonical** — applies the patch to the canonical repository
4. **Validates canonical** — runs the same validation commands against the canonical repo
5. **Commits** — creates a promotion commit in the canonical repo
6. **Records receipts** — writes approval and promotion receipts to `workspace/runs/`

After promotion, the canonical repo has the fix and all tests pass.

## Reject a Run

```bash
curl -X POST http://127.0.0.1:8080/runs/{run_id}/reject \
  -H "Authorization: Bearer $ORACLE_APPROVAL_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"actor": "operator", "note": "Needs more work"}'
```

## Swift Build

```bash
cd third_party/oracle-os
swift package resolve
swift build
```

Note: `swift test` may fail due to `import Testing` framework compatibility with swift-tools-version 6.0.

## Troubleshooting

### Preflight fails with missing deps

Run `./scripts/bootstrap_all.sh` first.

### Services won't start

Check if ports are in use:

```bash
lsof -i :8787 -i :8788 -i :8789 -i :8080
```

### Vision sidecar won't start

Check if MLX is installed:

```bash
python3 -c "import mlx_vlm; print('OK')"
```

### Approval returns 401

Set the approval token:

```bash
export ORACLE_APPROVAL_TOKEN=your-secret-token
```

### Validation blocked by command policy

Check `configs/command_policy.json` for allowed commands. Only these are permitted:

- `pytest`
- `python -m pytest`
- `python -m compileall`
- `ruff`
- `swift test`
- `swift build`

All other commands are blocked by default.
