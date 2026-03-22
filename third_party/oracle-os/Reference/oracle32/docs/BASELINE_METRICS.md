# Baseline Metrics

Baseline performance metrics recorded before the strategy-as-top-level-control upgrade.

## Task Set

1. **App launch + menu navigation** — Launch an application and navigate to a menu item
2. **Browser login/form flow** — Log into a website and fill a form
3. **Clone repo + run tests** — Clone a repository and execute its test suite
4. **Bounded failing-test repair** — Identify a failing test and generate a fix
5. **Dialog interruption recovery** — Handle an unexpected dialog and resume the task

## Metrics Tracked

| Metric | Description |
|--------|-------------|
| Success rate | Fraction of tasks completed successfully |
| Average steps | Average number of steps per task |
| Wrong-target rate | Fraction of steps that targeted the wrong element |
| Recovery count | Number of times recovery was triggered |
| Workflow reuse rate | Fraction of steps backed by a reusable workflow |
| Patch success rate | Fraction of patch attempts that passed tests |

## Pre-Upgrade Baseline

> **Note:** These metrics should be populated by running the fixed task set
> against the pre-upgrade system. Until then, this file serves as the
> designated location for baseline recording.

| Metric | Value |
|--------|-------|
| Success rate | — |
| Average steps | — |
| Wrong-target rate | — |
| Recovery count | — |
| Workflow reuse rate | — |
| Patch success rate | — |

## Post-Upgrade Comparison

After completing the upgrade, re-run the same task set and record results here.

| Metric | Pre-Upgrade | Post-Upgrade | Delta |
|--------|-------------|--------------|-------|
| Success rate | — | — | — |
| Average steps | — | — | — |
| Wrong-target rate | — | — | — |
| Recovery count | — | — | — |
| Workflow reuse rate | — | — | — |
| Patch success rate | — | — | — |
