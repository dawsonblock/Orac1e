# Architecture

The repository has three spines.

## Execution spine

`issue -> planner -> patcher -> validator -> report`

This path edits only an isolated worktree. It never merges.

## Approval spine

The publish edge is explicit:

- local artifact only
- GitHub issue comment
- GitHub draft PR

It never opens a merge path.

## Reflection / batch spine

The SWE-bench harness reuses the same bounded local pipeline over a manifest of tasks. It is offline and has no live repo write privileges beyond whatever the execution spine already has.

## Sandboxing

Validation uses one of two command runners:

- local subprocess runner
- Docker runner with `--network none`

The Docker runner mounts only the repository root at `/workspace`.
