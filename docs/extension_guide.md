# Extension guide

To add a tool:

1. Create `integration/tools/<tool_name>/tool.json`
2. Add `service.py` with `/health` and `/invoke`
3. Reuse an existing capability tag or add a new one deliberately
4. Run `scripts/tool_harness.py`
5. Start the service and verify `oracle tools`
