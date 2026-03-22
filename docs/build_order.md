# Build Order

## Phase 0

Make the workspace bootable:

- `scripts/check_env.sh`
- `scripts/bootstrap.sh`
- `scripts/start_retrieval.sh`
- `scripts/start_workers.sh`
- `scripts/start_oracle.sh`
- `configs/ports.env`

## Phase 1

Lock the Python contracts:

- `integration/shared_py/models.py`
- `integration/shared_py/diff_utils.py`
- `integration/shared_py/process_utils.py`
- `integration/shared_py/path_utils.py`

## Phase 2

Make retrieval real:

- `integration/retrieval_broker/coco_client.py`
- `integration/retrieval_broker/service.py`

## Phase 3

Make Aider usable:

- `integration/worker_aider/prompt_builder.py`
- `integration/worker_aider/normalize_diff.py`
- `integration/worker_aider/runner.py`
- `integration/worker_aider/service.py`

## Phase 4

Make the hardened worker usable:

- `integration/worker_hardened/task_mapper.py`
- `integration/worker_hardened/result_mapper.py`
- `integration/worker_hardened/bridge.py`
- `integration/worker_hardened/service.py`

## Phase 5

Prove the Python side with the fixture repo and smoke tests.

## Phase 6

Define the Swift contract layer:

- `RunModels.swift`
- `WorkerModels.swift`
- `RetrievalModels.swift`
- `ValidationModels.swift`

## Phase 7

Persist truth in Oracle:

- `RunLedger.swift`
- `EventStore.swift`
- `ApprovalStore.swift`

## Phase 8

Make Oracle own worktrees and patch apply:

- `WorktreeCoordinator.swift`
- `PatchApplyService.swift`

## Phase 9

Make Oracle own validation and mutation gates:

- `ValidationCoordinator.swift`
- `MutationPolicy.swift`
- `CommandApprovalPolicy.swift`

## Phase 10

Connect Oracle to retrieval and workers directly.

## Phase 11

Finish `IntegratedCodingRunService.swift`.

## Phase 12

Add CLI commands in `Sources/oracle/main.swift`.

## Phase 13

Land the tool extension layer:

- `integration/tool_sdk/*`
- `integration/tools/*`
- `Sources/OracleOS/Integration/Tools/*`

## Phase 14

Move discovery into the live run path.

## Phase 15

Add controller integration.

## Phase 16

Add web operator surfaces.

## Phase 17

Freeze with end-to-end tests and documentation.
