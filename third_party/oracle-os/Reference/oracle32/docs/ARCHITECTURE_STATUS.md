# Oracle OS Architecture Status

The descriptive architecture map is in [runtime spine](architecture/runtime_spine.md). The normative architectural contract is in [GOVERNANCE.md](GOVERNANCE.md).

## Stable

- `OracleOS` Swift package and `oracle` executable naming
- 22-tool MCP surface
- AX-first perception and core action tools
- Recipe replay and CRUD for JSON recipes
- `oracle_ground` vision grounding
- One runtime-managed execution truth path for policy, verified execution, trace, and outcome handling
- Graph trust tiers and promotion guards for experiment/recovery evidence
- Canonical project memory plus episode-residue separation
- Reasoning Layer: Multi-coordinator architecture (Decision, Execution, Learning, Recovery, State Coordinators)

## Partial

- Canonical `Observation` snapshots now fuse AX with conservative Chrome CDP candidates
- Verified execution is active for `oracle_click`, `oracle_type`, `oracle_press`, and `oracle_focus`
- JSONL tracing exists for verified actions
- `oracle_parse_screen` is sidecar-backed, but the runtime still treats it as experimental
- Architecture review emits governance reports, but remains advisory-first
- Eval coverage is present but still fixture-heavy
- **Recipe typed schema**: Recipes support `postconditions` and `constraints` blocks; `RecipeValidator.validateFull()` checks them
- **Experiment evaluator**: `ExperimentEvaluator` scores task outcomes across weighted dimensions (correctness, efficiency, verification, completion)
- **Event bus**: `RuntimeEventBus` provides publish/subscribe for structured runtime events (task, action, artifact, state, evaluation, planner feedback)
- **Vision contract**: `VisionPerceptionContract` defines typed detection frames and `VisionContractValidator` enforces freshness, confidence, and structure
- **Environment reconciliation**: `EnvironmentMonitor` detects world-state mismatches and reconciles postconditions

## Scaffold Only

- Workflow synthesis and reusable workflow promotion
- Neural policy layers
- Distributed execution

## Not Started

- Distributed multi-agent execution
- Neural transition policies
- OpenFst planning
- Full long-horizon autonomous project execution

## Known Failure Modes

- AX traversal can still be slow or sparse in deep browser and Electron trees
- Chrome CDP enrichment currently assumes Chrome remote debugging is available and targets the first debuggable page
- Query-based postconditions still depend on label/value matching when no stable DOM identifier is available
- `oracle_parse_screen` is intentionally treated as experimental until its schema and reliability are hardened
