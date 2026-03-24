# Startup order

## 1. Bootstrap

Run:

```bash
scripts/bootstrap_all.sh
```

This creates a single Python virtual environment in `.venv` at the repository root, installs the adapter dependencies, creates the fixture repo, and refreshes the web tool registry.

If your default `python3` is not 3.11 or 3.12, point the bootstrap at a supported interpreter first:

```bash
export ORACLE_PYTHON_BIN=python3.12
scripts/bootstrap_all.sh
```

## 2. Retrieval

Run:

```bash
scripts/start_retrieval.sh
```

Default port: `8787`

Logs: `workspace/logs/retrieval.log`
PID file: `workspace/pids/retrieval.pid`

## 3. Workers

Run:

```bash
scripts/start_workers.sh
```

Defaults:
- Aider adapter: `8788`
- Hardened adapter: `8789`

Logs:
- `workspace/logs/aider.log`
- `workspace/logs/hardened.log`

## 4. Oracle

Run:

```bash
scripts/start_oracle.sh
```

This calls `swift build` and then `swift run oracle` inside `third_party/oracle-os`.

Log: `workspace/logs/oracle.log`
PID file: `workspace/pids/oracle.pid`
