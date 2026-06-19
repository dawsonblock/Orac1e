# File Purpose Map

## Most important Oracle files

- `Sources/OracleOS/Integration/Orchestration/IntegratedCodingRunService.swift`: main run spine
- `Sources/OracleOS/Integration/Persistence/RunLedger.swift`: run summaries
- `Sources/OracleOS/Integration/Persistence/EventStore.swift`: append-only run history
- `Sources/OracleOS/Integration/Persistence/ApprovalStore.swift`: approval decisions
- `Sources/OracleOS/Integration/Workspace/WorktreeCoordinator.swift`: canonical repo registration and per-run worktrees
- `Sources/OracleOS/Integration/Workspace/PatchApplyService.swift`: checked patch application
- `Sources/OracleOS/Integration/Workspace/ValidationCoordinator.swift`: Oracle-owned validation
- `Sources/OracleOS/Integration/Policy/MutationPolicy.swift`: diff safety and scope limits
- `Sources/OracleOS/Integration/Policy/CommandApprovalPolicy.swift`: allowed validation commands
- `Sources/OracleOS/Integration/Tools/ToolRegistry.swift`: manifest registry
- `Sources/OracleOS/Integration/Tools/ToolRouter.swift`: capability-based tool selection
- `Sources/OracleOS/Integration/Tools/ToolClient.swift`: generic `/invoke` and `/health` client

## Most important Python files

- `integration/shared_py/models.py`: strict request and response models
- `integration/shared_py/diff_utils.py`: diff parsing and unsafe path rejection
- `integration/shared_py/process_utils.py`: single subprocess boundary
- `integration/retrieval_broker/service.py`: broker API entrypoint
- `integration/retrieval_broker/coco_client.py`: cocoindex adapter
- `integration/worker_aider/runner.py`: bounded Aider execution
- `integration/worker_aider/service.py`: Aider API entrypoint
- `integration/worker_hardened/bridge.py`: hardened runtime bridge
- `integration/worker_hardened/service.py`: hardened API entrypoint
- `integration/tool_sdk/base_models.py`: tool manifest and envelope models
- `integration/tool_sdk/registry.py`: tool discovery registry
- `integration/tools/*/tool.json`: live tool declarations

## Most important UI files

- `web/src/App.tsx`: top-level web shell
- `web/src/components/runs/RunList.tsx`: run index
- `web/src/components/runs/RunDetail.tsx`: selected run detail
- `web/src/components/runs/DiffReview.tsx`: diff display
- `web/src/components/runs/ApprovalPanel.tsx`: approve/reject actions
- `web/src/components/runs/WorkerTrace.tsx`: worker warnings and command trace
- `web/src/components/tools/ToolRegistryPanel.tsx`: discovered tool surface
- `web/src/components/tools/ToolHealthTable.tsx`: tool health table
