# Worktree model

Oracle owns canonical repos under `workspace/repos/` and creates one disposable worktree per run under `workspace/worktrees/<run_id>`.

Rules:

1. Workers never edit the canonical repo.
2. A proposal is always generated against a worktree.
3. Apply happens only after Oracle approval.
4. Failed runs keep artifacts; the worktree can then be deleted.
