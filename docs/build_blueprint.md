# Build Blueprint

## Product

This workspace is a local supervised coding runtime built from four core components:

- Oracle OS as the only authority and control plane
- Aider as the interactive code worker
- code-agent-runtime-hardened as the bounded autonomous code worker
- cocoindex as the code retrieval engine

The system accepts coding tasks, retrieves relevant code context, routes work to the right worker, validates proposed patches in isolated worktrees, and requires Oracle-owned approval before applying changes.

## Authority model

Oracle owns:

- run creation
- event logging
- worktree lifecycle
- tool discovery
- worker routing
- mutation policy
- validation orchestration
- approval state
- final patch apply
- UI and CLI operator surfaces

Workers only propose. Retrieval only retrieves. Tools do not own state.

## Current shape

```text
user
  -> Oracle OS
      -> Run Ledger
      -> Event Store
      -> Approval Store
      -> Worktree Coordinator
      -> Mutation Policy
      -> Validation Coordinator
      -> Tool Registry
      -> Tool Router
      -> Tool Client
          -> Aider tool
          -> Hardened tool
          -> Cocoindex tool
      -> UI / CLI / Controller
```

## Core flows

### Interactive flow

1. Oracle creates a run
2. Oracle creates a worktree
3. Oracle retrieves code context through cocoindex
4. Oracle routes to Aider
5. Aider returns a proposal diff
6. Oracle enforces mutation policy
7. Oracle validates
8. Oracle persists artifacts and moves to `awaiting_approval`
9. Oracle applies only after approval

### Autonomous bounded flow

1. Oracle creates a run
2. Oracle creates a worktree
3. Oracle retrieves code context through cocoindex
4. Oracle routes to the hardened worker
5. Hardened worker returns a proposal diff and notes
6. Oracle re-validates independently
7. Oracle persists artifacts and moves to `awaiting_approval`
8. Oracle applies only after approval

## Tool extension model

The workspace now supports manifest-driven tools:

- each tool declares a `tool.json`
- each tool exposes `GET /health` and `POST /invoke`
- Oracle discovers tools from `integration/tools/`
- Oracle routes by capability, not only by hardcoded tool name
- direct worker and retrieval clients remain as fallback during migration

This makes future additions cheap without changing Oracle authority.

## Definition of done

The build is complete when:

1. Oracle discovers tools from manifests at startup
2. `oracle tools` reports live health state
3. Oracle creates a run from CLI or UI
4. Oracle creates a clean worktree
5. Oracle retrieves code context through the broker or tool layer
6. Oracle routes to the chosen worker through `/invoke`
7. Oracle receives a normalized proposal
8. Oracle enforces mutation policy
9. Oracle validates and stores artifacts
10. Oracle records `awaiting_approval`
11. approval applies only through Oracle
12. run state and event history persist across restart
13. both interactive and autonomous modes work end to end
