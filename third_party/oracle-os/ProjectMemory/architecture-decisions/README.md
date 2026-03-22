# Architecture Decisions

Accepted and draft engineering decisions live here.

Each record should capture:
- decision
- reason
- tradeoffs
- affected modules
- evidence refs
- source trace IDs

## Accepted Decisions

| ADR | Title | Source |
|-----|-------|--------|
| 001 | [Oracle as Sole Authority](001-oracle-authority-model.md) | v5 merge |
| 002 | [VerifiedExecutor as Single Execution Boundary](002-verified-executor-boundary.md) | Runtime unification |
| 003 | [CommitCoordinator as Sole State Writer](003-commit-coordinator-state.md) | Runtime unification |
| 004 | [Worktree Isolation](004-worktree-isolation.md) | v5 merge |
| 005 | [Manifest-Driven Tool Discovery](005-manifest-tool-discovery.md) | v5 tool ecosystem |
| 006 | [Fail-Closed Policy](006-fail-closed.md) | Governance contract |
| 007 | [Independent Re-validation](007-independent-revalidation.md) | v5 defense-in-depth |
| 008 | [Python as Single State Mutation Authority](008-python-state-authority.md) | v6 implementation |
| 009 | [Dual-Worker Architecture](009-dual-worker-mode.md) | v5 merge |
| 010 | [Semantic Retrieval First](010-semantic-retrieval-first.md) | v5 context improvement |
| 011 | [Critic-Driven Self-Evaluation](011-critic-self-evaluation.md) | Oracle OS runtime |
| 012 | [Trust Tier System for Knowledge](012-trust-tier-knowledge.md) | Oracle OS knowledge management |
