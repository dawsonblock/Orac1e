# Troubleshooting

If `oracle tools` shows no manifests:
- verify `ORACLE_TOOL_MANIFESTS`
- run `scripts/tool_harness.py`
- rerun `scripts/sync_web_tool_registry.py`

If bootstrap fails on Python version:
- set `ORACLE_PYTHON_BIN` to `python3.11` or `python3.12`
- only use `ORACLE_ALLOW_UNSUPPORTED_PYTHON=1` when you deliberately want to force an unsupported interpreter

If workers are unhealthy:
- check adapter ports in `configs/ports.env`
- inspect `workspace/logs/`
- confirm `.venv/` exists and was created by `scripts/bootstrap_all.sh`

If apply fails:
- inspect `workspace/artifacts/<run_id>/proposal.diff`
- rerun validation and policy checks

To stop stale local services:

```bash
scripts/stop_all.sh
```
