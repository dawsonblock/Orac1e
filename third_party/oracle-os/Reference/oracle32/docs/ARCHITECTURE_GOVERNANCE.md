# Oracle OS Architecture Governance

This document is the operational governance companion to
[GOVERNANCE.md](./GOVERNANCE.md) and [runtime spine](./architecture/runtime_spine.md).

It exists to answer one practical question:

`When can Oracle OS safely grow, and what must stay fixed while it grows?`

## Core Contract

Oracle OS must keep one execution truth path:

`intent -> target resolution -> policy check -> verified execution -> transition recording -> graph / memory update`

Anything that changes the world outside that path is a defect.

## Architecture Boundaries

### Runtime Boundary

`RuntimeOrchestrator` and the verified execution path own real-world change.

Allowed:
- build policy context
- request approval
- execute verified actions
- route post-execution graph and memory updates

Forbidden:
- planners executing directly
- skills mutating directly
- experiments writing durable knowledge without replay through runtime

### Planning Boundary

Planners choose structure only.

Allowed:
- choose workflow vs stable graph path vs candidate edge vs exploration
- choose direct repair vs experiment branch
- compose OS, code, and mixed phases

Forbidden:
- exact UI target selection
- direct file mutation
- direct process execution
- inline recovery mechanics

### Targeting Boundary

Every target-bearing UI action must use:

`semantic query -> candidate extraction -> ranking -> ambiguity check -> selected candidate`

Forbidden:
- `first` candidate fallback
- direct AX / DOM shortcut picks
- silent ambiguity tolerance

### Knowledge Boundary

Oracle OS distinguishes:

- `KnowledgeTier`
  - `exploration`
  - `candidate`
  - `stable`
  - `experiment`
  - `recovery`

- `KnowledgeClass`
  - `reusable`
  - `parameter`
  - `episode`

Rules:
- experiment evidence never promotes directly to stable
- recovery evidence never promotes directly to stable
- episode residue never enters canonical project memory
- workflows promote only from repeated verified multi-episode evidence

### Recovery Boundary

Recovery is a first-class execution mode.

Allowed:
- bounded retry/rerank/refocus/reopen/rebuild strategies
- verified execution of recovery actions
- tagged recovery trace and graph evidence

Forbidden:
- inline unverified recovery hacks
- promoting recovery-only knowledge into nominal stable control knowledge

### Evaluation Boundary

Architecture can expand only when measured capability improves.

Required before merge for high-impact control-flow changes:
- governance coverage
- benchmark coverage
- no regression in `swift test`

## Promotion Rules

### Stable Graph Promotion

Default minimums:
- attempts `>= 5`
- success rate `>= 0.8`
- postcondition consistency `>= 0.9`
- low ambiguity
- not recovery-only evidence

### Workflow Promotion

Default minimums:
- repeated segment count `>= 3`
- evidence spans multiple episodes
- success rate `>= 0.8`
- replay validation `>= 0.66`
- no recovery evidence
- no experiment evidence
- no untyped episode residue

### Canonical Project Memory Promotion

Canonical memory stores only reusable engineering knowledge.

Allowed:
- architecture decisions
- known-good patterns
- open problems
- rejected approaches
- risks

Forbidden:
- temp paths
- sandbox IDs
- one-off trace artifacts
- episode-local literals without parameterization

## Rollout Discipline

Oracle OS should be upgraded in this order:

1. governance freeze
2. runtime spine cleanup
3. execution-truth audit
4. graph hardening
5. graph-first planner rewrite
6. semantic targeting enforcement
7. recovery first-class integration
8. workflow synthesis rewrite
9. memory activation
10. experiment normalization
11. architecture-aware ranking
12. eval hardening
13. controller diagnostics

Do not start higher-order planning, simulation, neural policy, belief-state work,
or distributed-agent work before the lower-stack hardening is benchmark-stable.

## Merge Gate

Before merging a runtime-affecting milestone:
- governance tests pass
- relevant benchmark coverage exists
- `swift test` passes
- no new execution-path bypass exists
- no weak-evidence promotion regression exists

## Review Checklist

Ask these five questions for every milestone:

1. Does this change keep all real-world mutations on the verified runtime path?
2. Does it preserve strict target resolution for target-bearing UI actions?
3. Does it promote only repeated verified evidence into durable knowledge?
4. Does it keep planners choosing structure instead of local action details?
5. Does it improve or at least preserve measured benchmark behavior?
