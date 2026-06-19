# Oracle-OS Runtime Spine

> Updated: post-Wave-1/2 refactor (Wave 1A, 1B complete; 2E-2H governance tests in place)

## The Execution Loop

```
Intent (submitIntent via IntentAPI)
  → RuntimeOrchestrator.decide(intent, planner)
      → Planner.plan(intent, context) → Command
  → RuntimeOrchestrator.execute(command, state)
      → VerifiedExecutor.execute(command, state) ← ONLY side-effect layer
          → PreconditionsValidator.validate
          → SafetyValidator.isSafe
          → CapabilityBinder.bind
          → ToolDispatcher.dispatch ← ONLY tool invocation point
          → PostconditionsValidator.validate
          → ExecutionOutcome { status, observations, artifacts, events }
  → RuntimeOrchestrator.commit(outcome)
      → CommitCoordinator.commit(outcome.events)
          → EventStore.append(events) ← append-only
          → Reducers.apply(events, &state)
          → WorldStateModel updated
  → RuntimeOrchestrator.evaluate(outcome)
      → Critic (post-commit review)
```

## Architecture Rules

| Rule | Enforcement |
|------|------------|
| Planners never execute | `PlannerBoundaryTests` |
| VerifiedExecutor is the only side-effect layer | `ExecutionBoundaryTests`, `NoBypassExecutionTests` |
| Reducers are the only state writers | `StateMutationTests` |
| Controller is a client via IntentAPI | `ControllerBoundaryTests` |
| Every committed change has event ancestry | `EventHistoryInvariantTests` |
| Runtime cycles are replayable | `EventReplayTests` |

## Key Module Map

| Module | File | Responsibility |
|--------|------|---------------|
| **API** | `Sources/OracleOS/API/IntentAPI.swift` | Controller boundary — submitIntent/queryState only |
| **Runtime** | `Sources/OracleOS/Runtime/RuntimeOrchestrator.swift` | Cycle coordinator — decide/execute/commit/evaluate |
| **Execution** | `Sources/OracleOS/Execution/VerifiedExecutor.swift` | Only side-effect layer |
| **Events** | `Sources/OracleOS/Events/EventStore.swift` | Append-only event log |
| **Commit** | `Sources/OracleOS/Events/CommitCoordinator.swift` | State mutation gate |
| **State** | `Sources/OracleOS/State/Reducers/` | Pure state derivation from events |
| **Observability** | `Sources/OracleOS/Observability/` | Timeline, replay, traces from event history |

## Milestone Status

| Milestone | Status | Test |
|-----------|--------|------|
| A — One execution path | ✅ RuntimeOrchestrator delegates to VerifiedExecutor | `ExecutionBoundaryTests` |
| B — One state path | ✅ CommitCoordinator + Reducers | `StateMutationTests`, `EventHistoryInvariantTests` |
| C — One planner authority | ⏳ MainPlanner still god-object | `PlannerBoundaryTests` |
| D — One controller boundary | ⏳ ControllerRuntimeBridge needs audit | `ControllerBoundaryTests` |
| E — Replayable runtime | ✅ EventReplay + TimelineBuilder | `EventReplayTests` |

## Remaining Work (Waves 1C-3D)

- **AgentLoop** (`Execution/Loop/AgentLoop.swift`) — uses legacy spine; needs narrowing to RuntimeOrchestrator
- **RuntimeExecutionDriver** — still calls `performAction()` (legacy shim); needs conversion to intent translator
- **CodeActionGateway** — bypass executor; must be deprecated then deleted
- **ToolDispatcher** — handlers stub; needs bridging to Skills infrastructure
- **MainPlanner** — needs extraction into route-only façade + Strategies/
- **ControllerRuntimeBridge** — needs boundary audit against IntentAPI contract
