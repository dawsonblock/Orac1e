# Parallel execution

Safe parallelism:
- health checks
- retrieval fan-out
- candidate generation on separate worktrees
- validation fan-out where commands do not conflict
- concurrent runs across different repos

Unsafe parallelism:
- two writers in the same worktree
- direct parallel apply to the same target repo
- uncontrolled worker subprocess fan-out
