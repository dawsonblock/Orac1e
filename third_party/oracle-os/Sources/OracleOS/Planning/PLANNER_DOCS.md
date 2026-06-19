# MainPlanner Decision Logic Documentation

## Overview

The `MainPlanner` is the central orchestrator for the Oracle OS planning system. It navigates the live `TaskLedger` (task graph) as its primary control substrate to make planning decisions.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        MainPlanner                               │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │  OSPlanner   │    │ CodePlanner  │    │ MixedTask    │      │
│  │              │    │              │    │ Planner      │      │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘      │
│         │                   │                   │               │
│         └───────────────────┼───────────────────┘               │
│                             │                                   │
│                             ▼                                   │
│                    ┌────────────────┐                           │
│                    │ PlanEvaluator  │                           │
│                    └────────┬───────┘                           │
│                             │                                   │
│                             ▼                                   │
│                    ┌────────────────┐                           │
│                    │ PlanSelection  │                           │
│                    └────────┬───────┘                           │
│                             │                                   │
│                             ▼                                   │
│                    ┌────────────────┐                           │
│                    │  PlannerDecision│                          │
│                    └────────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
```

## Planning Cycle

Each planning cycle in `nextStep()` follows these steps:

### 1. Task Graph Update
```swift
let currentTaskRecord = taskGraphStore.updateCurrentNode(worldState: worldState)
```
- Updates the current task-graph node from world state
- The graph is the canonical representation of task position

### 2. Memory Influence
```swift
let _ = MemoryRouter(memoryStore: memoryStore).influence(
    for: MemoryQueryContext(taskContext: taskContext, worldState: worldState)
)
```
- Queries unified memory for relevant context
- Influences decision-making based on past experiences

### 3. Task-Graph Navigation
```swift
let taskGraphDecision = taskGraphNavigatedDecision(
    taskNode: currentTaskRecord,
    taskContext: taskContext,
    worldState: worldState,
    graphStore: graphStore,
    memoryStore: memoryStore,
    selectedStrategy: selectedStrategy
)
```
- Expands candidate edges from the current node
- Evaluates future paths via `LedgerNavigator`
- Selects the best edge based on scoring

### 4. Family Planner Decision
```swift
let familyDecision = familyPlannerDecision(
    taskContext: taskContext,
    worldState: worldState,
    graphStore: graphStore,
    memoryStore: memoryStore,
    selectedStrategy: selectedStrategy
)
```
- Routes to appropriate planner based on `AgentKind`:
  - `.os` → `OSPlanner`
  - `.code` → `CodePlanner`
  - `.mixed` → `MixedTaskPlanner`

### 5. Reasoning Decision
```swift
let reasoning = reasoningDecision(
    taskContext: taskContext,
    worldState: worldState,
    graphStore: graphStore,
    memoryStore: memoryStore,
    fallbackDecision: familyDecision,
    selectedStrategy: selectedStrategy
)
```
- Uses `ReasoningEngine` for complex decision-making
- Considers memory influence and goal state
- Falls back to family decision if reasoning fails

### 6. Plan Selection
```swift
let decision = PlanSelection.selectBest(
    familyDecision: familyDecision,
    reasoningDecision: reasoning,
    taskGraphDecision: taskGraphDecision,
    taskContext: taskContext,
    worldState: worldState,
    memoryStore: memoryStore
)
```
- Selects the best decision from all candidates
- Applies strategy filtering

### 7. Strategy Safety Net
```swift
if let decision {
    let skillName = decision.actionContract.skillName
    let family = operatorFamilyForSkill(skillName)
    if !selectedStrategy.allows(family) {
        return nil
    }
}
```
- Ensures selected decision is allowed by current strategy

## Key Components

### Task Graph (TaskLedgerStore)

The task graph is the canonical representation of task position:

```swift
public let taskGraphStore: TaskLedgerStore
```

- Stores task records with dependencies
- Tracks progress and state transitions
- Enables path planning and evaluation

### Ledger Navigator

Expands and evaluates paths in the task graph:

```swift
private let graphNavigator: LedgerScorer
```

- `expand()`: Generates candidate paths from current node
- Considers goal state and allowed operator families
- Returns paths sorted by cumulative score

### Ledger Scorer

Scores edges and paths in the task graph:

```swift
private let graphScorer: LedgerScorer
```

- `scoreEdgeWithBreakdown()`: Scores individual edges
- Considers memory bias and goal abstract state
- Provides detailed scoring breakdown

### Plan Generator

Generates candidate plans using reasoning:

```swift
self.planGenerator = PlanGenerator(
    reasoningEngine: reasoningEngine,
    planEvaluator: planEvaluator,
    osPlanner: osPlanner,
    codePlanner: codePlanner,
    mixedTaskPlanner: mixedTaskPlanner
)
```

- `bestPlan()`: Finds the highest-scoring plan
- Considers minimum score threshold
- Evaluates simulated outcomes

## Planner Families

### OSPlanner

Handles operating system interactions:
- Window management
- Application switching
- System navigation
- Accessibility operations

### CodePlanner

Handles code-related tasks:
- File editing
- Code generation
- Build operations
- Test execution

### MixedTaskPlanner

Handles tasks requiring both OS and code operations:
- Complex workflows
- Multi-step tasks
- Cross-domain operations

## Decision Structure

A `PlannerDecision` contains:

```swift
PlannerDecision(
    agentKind: AgentKind,           // .os, .code, .mixed
    plannerFamily: PlannerFamily,   // Which planner generated this
    stepPhase: TaskStepPhase,       // Current phase of execution
    actionContract: ActionContract, // The action to execute
    source: PlannerSource,          // Where decision came from
    fallbackReason: String,         // Why fallback was needed
    semanticQuery: String?,         // For retrieval operations
    projectMemoryRefs: [String],    // Related memory entries
    notes: [String],                // Diagnostic notes
    planDiagnostics: PlanDiagnostics?, // Detailed diagnostics
    promptDiagnostics: PromptDiagnostics? // Prompt generation info
)
```

## Scoring and Selection

### Edge Scoring

Edges are scored based on:
- **Goal progress**: How much closer to goal
- **Memory bias**: Influence from past experiences
- **Risk score**: Potential for failure
- **Resource cost**: Computational requirements

### Path Scoring

Paths are scored by:
- **Cumulative score**: Sum of edge scores
- **Terminal state**: Whether path reaches goal
- **Path depth**: Number of edges

### Plan Selection

Plans are selected based on:
- **Score**: Higher is better
- **Source type**: Workflow > Graph > Reasoning
- **Strategy compliance**: Must be allowed by current strategy

## Strategy Filtering

The `SelectedStrategy` controls which operator families are allowed:

```swift
if !selectedStrategy.allows(family) {
    return nil
}
```

This ensures the planner only considers actions appropriate for the current execution mode.

## Memory Integration

### Memory Router

Routes memory queries to appropriate stores:

```swift
MemoryRouter(memoryStore: memoryStore).influence(
    for: MemoryQueryContext(taskContext: taskContext, worldState: worldState)
)
```

### Memory Scorer

Scores memory influence on planning:

```swift
let memoryBias = MemoryScorer.planBias(influence: memoryInfluence)
```

## Error Handling

### Fallback Mechanisms

1. **Graph navigation fails** → Try family planner
2. **Family planner fails** → Try reasoning engine
3. **Reasoning fails** → Return nil (no decision)

### Strategy Violations

If selected decision violates strategy:
- Return nil
- Log violation
- Allow retry with different parameters

## Configuration

### Reasoning Threshold

```swift
private let reasoningThreshold: Double
```

Minimum score for reasoning-selected plans (default: 0.6).

### Goal Matching

```swift
public static func goalMatchScore(state: PlanningState, goal: Goal) -> Double
```

Calculates how well current state matches goal (0.0 to 1.0).

## Usage Example

```swift
let planner = MainPlanner()

// Set goal
let goal = planner.interpretGoal("Open Safari and search for 'Swift programming'")
planner.setGoal(goal)

// Get next step
if let decision = planner.nextStep(
    worldState: currentWorldState,
    graphStore: graphStore,
    selectedStrategy: strategy
) {
    // Execute the action contract
    executeAction(decision.actionContract)
}
```

## Diagnostics

### Plan Diagnostics

```swift
PlanDiagnostics(
    selectedOperatorNames: [String],
    candidatePlans: [ScoredPlanSummary],
    fallbackReason: String
)
```

### Prompt Diagnostics

```swift
PromptDiagnostics(
    // Generated prompt information
)
```

These provide detailed information for debugging and monitoring.
