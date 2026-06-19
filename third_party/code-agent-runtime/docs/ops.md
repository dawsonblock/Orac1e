# Operational notes

## Dry-run mode

Set `GITHUB_DRY_RUN=true` to exercise GitHub App code paths without live network mutations.

## Workspace cleanup

`apps.run_github_issue` retains worktrees in dry-run mode and removes them after live runs.

## Docker fallback

If `SANDBOX_MODE=docker` but Docker is not installed, validation falls back to local execution.
