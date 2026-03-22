# ADR 004: Worktree Isolation

## Decision

Oracle is the only canonical worktree owner. Workers return diffs only—they do not commit or push. Each run gets a disposable worktree, ensuring canonical repo protection.

## Reason

Prevents workers from making unreviewed changes. Enables safe experimentation without risk to the main codebase. Allows validation in isolated environment before applying changes.

## Tradeoffs

- **State**: Disposable worktrees limit persistent shared state
- **Performance**: Worktree creation adds overhead per run
- **Collaboration**: Cannot easily share worktree state between workers

## Affected Modules

- `OracleOS/Code/Execution/WorkspaceRunner` - worktree management
- `OracleOS/Code/Execution/WorkspaceScope` - workspace isolation

## Evidence

- [docs/architecture.md:4](../../architecture.md) - control invariants
- [oracle_build_v5_analysis.md:106-110](../oracle_build_v5_analysis.md) - problems addressed

## Source

Oracle Build v5 merge, v4 backend preservation
